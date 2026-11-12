import Compression
import Foundation

/// The little of ZIP a backup needs; iOS has no API for it. Writes without
/// compressing, because JPEGs do not shrink and the JSON is small beside them.
/// Reads that, and what a computer writes when a package is zipped by hand:
/// deflated entries, data descriptors, folder entries. Nothing is ever written
/// to disk under a name from the file, so a name cannot escape anywhere.
nonisolated enum BackupZip {
    struct Entry: Equatable {
        var name: String
        var data: Data
    }

    enum Failure: LocalizedError, Equatable {
        case damaged
        case unsupported
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .damaged: "⚠️ This ZIP file is damaged and cannot be read."
            case .unsupported: "⚠️ This ZIP file was packed in a way the app cannot read. Zip the backup again without encryption."
            case .tooLarge: "⚠️ This backup is too large for a ZIP file."
            }
        }
    }

    /// No entry this big is a backup's: the limit is what stops a small file
    /// from claiming to unpack into all of the memory there is.
    private static let largestEntry = 256 * 1024 * 1024

    private static let localHeader: UInt32 = 0x0403_4B50
    private static let centralHeader: UInt32 = 0x0201_4B50
    private static let endOfDirectory: UInt32 = 0x0605_4B50
    /// General purpose bit 11: names are UTF-8.
    private static let utf8Names: UInt16 = 0x0800
    private static let encrypted: UInt16 = 0x0001
    private static let stored: UInt16 = 0
    private static let deflated: UInt16 = 8

    static func isZip(_ data: Data) -> Bool {
        data.starts(with: [0x50, 0x4B, 0x03, 0x04])
    }

    // MARK: - Writing

    static func write(_ entries: [Entry], modified: Date) throws -> Data {
        let (time, date) = dosTimestamp(modified)
        var output = Data()
        var directory = Data()

        for entry in entries {
            let name = Data(entry.name.utf8)
            guard let offset = UInt32(exactly: output.count),
                  let size = UInt32(exactly: entry.data.count),
                  let nameLength = UInt16(exactly: name.count)
            else { throw Failure.tooLarge }
            let crc = crc32(entry.data)

            output.append(localHeader)
            output.append(UInt16(20)) // version needed
            output.append(utf8Names)
            output.append(stored)
            output.append(time)
            output.append(date)
            output.append(crc)
            output.append(size)
            output.append(size)
            output.append(nameLength)
            output.append(UInt16(0)) // extra
            output.append(name)
            output.append(entry.data)

            directory.append(centralHeader)
            directory.append(UInt16(20)) // version made by
            directory.append(UInt16(20)) // version needed
            directory.append(utf8Names)
            directory.append(stored)
            directory.append(time)
            directory.append(date)
            directory.append(crc)
            directory.append(size)
            directory.append(size)
            directory.append(nameLength)
            directory.append(UInt16(0)) // extra
            directory.append(UInt16(0)) // comment
            directory.append(UInt16(0)) // disk
            directory.append(UInt16(0)) // internal attributes
            directory.append(UInt32(0)) // external attributes
            directory.append(offset)
            directory.append(name)
        }

        guard let directoryOffset = UInt32(exactly: output.count),
              let directorySize = UInt32(exactly: directory.count),
              let count = UInt16(exactly: entries.count)
        else { throw Failure.tooLarge }
        output.append(directory)
        output.append(endOfDirectory)
        output.append(UInt16(0)) // this disk
        output.append(UInt16(0)) // disk with the directory
        output.append(count)
        output.append(count)
        output.append(directorySize)
        output.append(directoryOffset)
        output.append(UInt16(0)) // comment
        return output
    }

    /// ZIP's own clock: local time, two-second steps, from 1980.
    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max((parts.year ?? 1980) - 1980, 0)
        let time = (parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2
        let day = year << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1)
        return (UInt16(truncatingIfNeeded: time), UInt16(truncatingIfNeeded: day))
    }

    // MARK: - Reading

    /// Every file in the archive by its name; folders are left out. The
    /// central directory is what counts, as it is for every other tool: it
    /// alone knows the sizes when a writer put them behind the data.
    static func read(_ data: Data) throws -> [String: Data] {
        let reader = Reader(data: data)
        let end = try reader.endOfDirectoryOffset()
        let count = try reader.u16(end + 10)
        let directorySize = try reader.u32(end + 12)
        let directoryOffset = try reader.u32(end + 16)
        // ZIP64 announces itself with the largest values that fit.
        guard count != .max, directorySize != .max, directoryOffset != .max else { throw Failure.unsupported }

        var files: [String: Data] = [:]
        var offset = Int(directoryOffset)
        for _ in 0..<count {
            guard try reader.u32(offset) == centralHeader else { throw Failure.damaged }
            let flags = try reader.u16(offset + 8)
            let method = try reader.u16(offset + 10)
            let crc = try reader.u32(offset + 16)
            let packedSize = try reader.u32(offset + 20)
            let size = try reader.u32(offset + 24)
            let nameLength = Int(try reader.u16(offset + 28))
            let extraLength = Int(try reader.u16(offset + 30))
            let commentLength = Int(try reader.u16(offset + 32))
            let localOffset = try reader.u32(offset + 42)
            let name = String(decoding: try reader.bytes(offset + 46, nameLength), as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength

            if name.hasSuffix("/") { continue }
            guard flags & encrypted == 0, packedSize != .max, size != .max, localOffset != .max else {
                throw Failure.unsupported
            }
            guard Int(size) <= largestEntry else { throw Failure.tooLarge }

            let local = Int(localOffset)
            guard try reader.u32(local) == localHeader else { throw Failure.damaged }
            let start = local + 30 + Int(try reader.u16(local + 26)) + Int(try reader.u16(local + 28))
            let packed = try reader.bytes(start, Int(packedSize))

            let contents: Data
            switch method {
            case stored:
                guard packedSize == size else { throw Failure.damaged }
                contents = packed
            case deflated:
                contents = try inflate(packed, to: Int(size))
            default:
                throw Failure.unsupported
            }
            guard crc32(contents) == crc else { throw Failure.damaged }
            files[name] = contents
        }
        return files
    }

    private static func inflate(_ packed: Data, to size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { target in
            packed.withUnsafeBytes { source in
                // `COMPRESSION_ZLIB` is raw DEFLATE, which is what ZIP holds.
                compression_decode_buffer(
                    target.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, packed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw Failure.damaged }
        return output
    }

    /// Bounds-checked little-endian reads, so a damaged file fails by saying
    /// so rather than by reading past its end.
    private struct Reader {
        let data: Data

        /// From the end: only a comment may stand behind the record.
        func endOfDirectoryOffset() throws -> Int {
            let last = data.count - 22
            guard last >= 0 else { throw Failure.damaged }
            for offset in stride(from: last, through: max(0, last - Int(UInt16.max)), by: -1) {
                if try u32(offset) == endOfDirectory {
                    return offset
                }
            }
            throw Failure.damaged
        }

        func u16(_ offset: Int) throws -> UInt16 {
            let bytes = try slice(offset, 2)
            return bytes.reduce(into: (value: UInt16(0), shift: UInt16(0))) { result, byte in
                result.value |= UInt16(byte) << result.shift
                result.shift += 8
            }.value
        }

        func u32(_ offset: Int) throws -> UInt32 {
            let bytes = try slice(offset, 4)
            return bytes.reduce(into: (value: UInt32(0), shift: UInt32(0))) { result, byte in
                result.value |= UInt32(byte) << result.shift
                result.shift += 8
            }.value
        }

        func bytes(_ offset: Int, _ count: Int) throws -> Data {
            Data(try slice(offset, count))
        }

        private func slice(_ offset: Int, _ count: Int) throws -> Data.SubSequence {
            let start = data.startIndex + offset
            guard offset >= 0, count >= 0, start + count <= data.endIndex else { throw Failure.damaged }
            return data[start..<(start + count)]
        }
    }

    // MARK: - Checksum

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in
            value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in
            crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
    }
}

private extension Data {
    nonisolated mutating func append(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    nonisolated mutating func append(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
