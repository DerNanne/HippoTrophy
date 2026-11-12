import Foundation
import Testing
@testable import HippoTrophy

struct BackupZipTests {
    private let entries = [
        BackupZip.Entry(name: "backup.json", data: Data("{\"a\":1}".utf8)),
        BackupZip.Entry(name: "photos/1.jpg", data: Data((0..<2000).map { UInt8($0 % 251) })),
        BackupZip.Entry(name: "photos/leer.jpg", data: Data())
    ]

    private func written() throws -> Data {
        try BackupZip.write(entries, modified: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func whatIsWrittenReadsBack() throws {
        let files = try BackupZip.read(written())
        #expect(files.count == entries.count)
        for entry in entries {
            #expect(files[entry.name] == entry.data)
        }
    }

    /// CRC-32's published check value.
    @Test func theChecksumIsTheStandardOne() {
        #expect(BackupZip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func itKnowsAZipByItsFirstBytes() throws {
        #expect(BackupZip.isZip(try written()))
        #expect(!BackupZip.isZip(Data("{}".utf8)))
        #expect(!BackupZip.isZip(Data()))
    }

    @Test func aChangedByteIsNoticed() throws {
        var data = try written()
        // In the middle of the picture, which only the checksum can notice.
        data[data.startIndex + 200] ^= 0xFF
        #expect(throws: BackupZip.Failure.damaged) { try BackupZip.read(data) }
    }

    @Test func aFileCutShortIsDamagedNotACrash() throws {
        let data = try written()
        for length in [0, 3, 21, 22, 100, data.count - 1] {
            #expect(throws: BackupZip.Failure.self) { try BackupZip.read(data.prefix(length)) }
        }
    }

    @Test func noiseIsDamagedNotACrash() {
        let noise = Data((0..<4096).map { UInt8(($0 * 37) % 256) })
        #expect(throws: BackupZip.Failure.damaged) { try BackupZip.read(noise) }
    }

    @Test func aDirectoryPointingNowhereIsDamagedNotACrash() throws {
        var data = try written()
        let count = data.count
        // The directory's offset, the last four bytes before the comment length.
        data.replaceSubrange((count - 6)..<(count - 2), with: [0xFE, 0xFF, 0xFF, 0x7F])
        #expect(throws: BackupZip.Failure.damaged) { try BackupZip.read(data) }
    }

    @Test func anEncryptedEntryIsSaidToBeUnsupported() throws {
        var data = try written()
        let directory = try #require(data.range(of: Data([0x50, 0x4B, 0x01, 0x02])))
        data[directory.lowerBound + 8] |= 0x01
        #expect(throws: BackupZip.Failure.unsupported) { try BackupZip.read(data) }
    }

    @Test func aFileWithATrailingCommentStillReads() throws {
        var data = try written()
        // The comment length is the last field, so a comment simply follows it.
        data[data.endIndex - 2] = 5
        data.append(contentsOf: Array("hello".utf8))
        #expect(try BackupZip.read(data).count == entries.count)
    }
}
