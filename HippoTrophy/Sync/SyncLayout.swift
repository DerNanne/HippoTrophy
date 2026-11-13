import Foundation

/// Where the sync puts things on the server, and nothing else: one folder,
/// the newest backup in it under a name that never changes, and a copy a day
/// beside it. Everything else in the folder belongs to someone else — a later
/// step of the sync, the web app, the user — and is left alone.
nonisolated struct SyncLayout: Equatable {
    static let folderName = "HippoTrophy"
    static let backupName = "backup.zip"
    /// Written first, then moved over `backupName`: whoever reads the folder
    /// sees the old backup or the new one, never half of one.
    static let uploadingName = "backup.zip.uploading"
    /// Put down and taken away again by the connection test.
    static let writeTestName = "backup.zip.write-test"
    static let historyFolderName = "history"
    /// How many daily copies stay.
    static let historyKept = 14

    /// The server address as the user gave it, cleaned up.
    let server: URL

    /// The folder the sync owns, ending in a slash.
    var folder: URL { server.appending(path: Self.folderName, directoryHint: .isDirectory) }
    var backup: URL { folder.appending(path: Self.backupName, directoryHint: .notDirectory) }
    var uploading: URL { folder.appending(path: Self.uploadingName, directoryHint: .notDirectory) }
    var writeTest: URL { folder.appending(path: Self.writeTestName, directoryHint: .notDirectory) }
    var history: URL { folder.appending(path: Self.historyFolderName, directoryHint: .isDirectory) }

    func historyFile(for date: Date, calendar: Calendar = .current) -> URL {
        history.appending(path: Self.historyName(for: date, calendar: calendar), directoryHint: .notDirectory)
    }

    /// `2026-11-13.zip`: the day in the user's own calendar, so the copy of
    /// an evening workout carries the evening's date.
    static func historyName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d.zip", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The daily copies to delete: all but the newest `historyKept`. A name
    /// that is not a daily copy is not the sync's and is never on the list.
    static func historyToDelete(among names: [String]) -> [String] {
        let copies = names.filter(isHistoryName).sorted(by: >)
        return Array(copies.dropFirst(historyKept))
    }

    static func isHistoryName(_ name: String) -> Bool {
        name.wholeMatch(of: /\d{4}-\d{2}-\d{2}\.zip/) != nil
    }

    // MARK: - The address

    enum AddressProblem: Error, Equatable {
        case empty
        case notHTTPS
        case invalid
    }

    /// The address the user typed. Without a scheme it is taken as HTTPS;
    /// with `http` it is refused, because the password would cross the
    /// network as it is.
    static func parse(_ text: String) -> Result<SyncLayout, AddressProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var parts = URLComponents(string: withScheme), let scheme = parts.scheme?.lowercased() else {
            return .failure(.invalid)
        }
        guard scheme == "https" else { return .failure(.notHTTPS) }
        guard let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil
        else { return .failure(.invalid) }
        parts.scheme = "https"
        // One trailing slash, so the folder is appended inside the path the
        // user gave and not beside its last part.
        if !parts.path.hasSuffix("/") { parts.path += "/" }
        guard let url = parts.url else { return .failure(.invalid) }
        return .success(SyncLayout(server: url))
    }
}

extension SyncLayout.AddressProblem: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty: "Enter the address of your WebDAV folder."
        case .notHTTPS: "The address has to start with https://. Over plain http, your password would cross the network unprotected."
        case .invalid: "This is not an address the app can use. It looks like https://cloud.example.com/remote.php/dav/files/alex/."
        }
    }
}
