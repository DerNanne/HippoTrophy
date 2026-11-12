import SwiftUI
import UniformTypeIdentifiers

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .zip] }

    var package: BackupPackage

    init(package: BackupPackage) {
        self.package = package
    }

    /// What the save dialog saves it as; the package says which wrapping.
    var contentType: UTType {
        package.isZip ? .zip : .json
    }

    /// `hippotrophy-backup-2026-10-22`: the name the save dialog suggests.
    static func defaultFilename(on date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "hippotrophy-backup-\(formatter.string(from: date))"
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        package = try BackupPackage.read(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: try package.encoded())
    }
}
