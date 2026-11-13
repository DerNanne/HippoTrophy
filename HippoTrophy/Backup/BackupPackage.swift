import Foundation

/// A backup as it travels. Without photos it is `BackupFile` as plain JSON;
/// with photos it is a ZIP of that same JSON as `backup.json` beside the
/// pictures, which the records name by their path in `photos/`. So there is
/// one format in two wrappings, and one type that reads it.
nonisolated struct BackupPackage {
    static let fileName = "backup.json"
    static let photoFolder = "photos/"

    var file: BackupFile
    /// The pictures by the name the records give them.
    var photos: [String: Data] = [:]

    var isZip: Bool { !photos.isEmpty }

    /// How many photos the file names that are not here: all of them, if only
    /// the JSON out of a package was picked.
    var missingPhotoCount: Int {
        file.photoNames.filter { photos[$0] == nil }.count
    }

    /// The file as it is written: the JSON alone without photos, unless
    /// `alwaysZip` asks for the ZIP anyway — the sync keeps one name on the
    /// server whatever the backup holds.
    func encoded(alwaysZip: Bool = false) throws -> Data {
        let json = try BackupCoding.encoder.encode(file)
        guard isZip || alwaysZip else { return json }
        let pictures = photos.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        return try BackupZip.write(
            [BackupZip.Entry(name: Self.fileName, data: json)] + pictures.map { BackupZip.Entry(name: $0.key, data: $0.value) },
            modified: file.exportedAt
        )
    }

    /// The one way in, whatever the file is called: its first bytes say which
    /// wrapping it is.
    static func read(from data: Data) throws -> BackupPackage {
        guard BackupZip.isZip(data) else {
            return BackupPackage(file: try BackupCoding.readBackup(from: data))
        }
        let contents = try BackupZip.read(data)
        guard let json = contents[fileName] else { throw BackupReadError.notABackup }
        return BackupPackage(
            file: try BackupCoding.readBackup(from: json),
            photos: contents.filter { $0.key.hasPrefix(photoFolder) }
        )
    }
}
