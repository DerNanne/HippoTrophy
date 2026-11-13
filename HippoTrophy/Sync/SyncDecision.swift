import CryptoKit
import Foundation
import SwiftData

/// What the sync remembers between runs. Not a setting: it describes the
/// server, and turning sync off forgets it.
nonisolated struct SyncState: Codable, Equatable {
    /// The content of the last backup that arrived — see `SyncUpload`.
    var lastFingerprint: String?
    /// The etag of `backup.zip` right after this device wrote it.
    var lastETag: String?
    var lastUpload: Date?
    /// What went wrong the last time, gone with the next success.
    var lastError: String?
    var lastErrorAt: Date?
    /// The backup on the server is not this device's: nothing is written
    /// until the user decides.
    var foreignBackupOnServer = false
}

/// How a sync came about.
nonisolated enum SyncTrigger: Equatable {
    /// A workout ended, the app went away, or it came back with an upload
    /// still owed: only if something changed.
    case automatic
    /// Sync Now: even if nothing changed.
    case manual
    /// The user decided this device's data counts: written over whatever is
    /// on the server.
    case replaceServer
}

/// The decisions of a sync, apart from carrying them out.
nonisolated enum SyncDecision {
    enum Before: Equatable {
        case upload
        case unchanged
        /// Never while a workout is being trained: half a workout is not a
        /// state anyone should read.
        case workoutRunning
        case waitingForDecision
    }

    static func before(trigger: SyncTrigger, fingerprint: String, state: SyncState, workoutRunning: Bool) -> Before {
        if workoutRunning { return .workoutRunning }
        if state.foreignBackupOnServer, trigger != .replaceServer { return .waitingForDecision }
        if trigger == .automatic, fingerprint == state.lastFingerprint { return .unchanged }
        return .upload
    }

    /// Whether the backup on the server may be written over: there is none,
    /// or it is still the one this device wrote last.
    static func serverIsOurs(currentETag: String?, knownETag: String?) -> Bool {
        guard let currentETag else { return true }
        return currentETag == knownETag
    }
}

/// The bytes that go up, and what they say regardless of when they were made.
nonisolated struct SyncUpload: Sendable {
    let data: Data
    let fingerprint: String

    /// Always a ZIP, so the server keeps one name. The fingerprint is taken
    /// from the same package with its export date fixed: two backups of the
    /// same data an hour apart have the same one.
    init(_ package: BackupPackage) throws {
        data = try package.encoded(alwaysZip: true)
        var timeless = package
        timeless.file.exportedAt = Date(timeIntervalSinceReferenceDate: 0)
        fingerprint = SHA256.hash(data: try timeless.encoded(alwaysZip: true))
            .map { String(format: "%02x", $0) }.joined()
    }
}

extension BackupExporter {
    /// Everything the store holds, with photos: what a backup with every
    /// switch on carries.
    static func everything(in context: ModelContext, at date: Date = .now) throws -> BackupPackage {
        let sessions = try context.fetch(FetchDescriptor(
            predicate: WorkoutSession.trained, sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
        let templates = try context.fetch(FetchDescriptor(
            predicate: WorkoutSession.templates, sortBy: [SortDescriptor(\.templateOrder)]
        ))
        let definitions = try context.fetch(FetchDescriptor(sortBy: [SortDescriptor(\ExerciseDefinition.orderIndex)]))
        let gyms = try context.fetch(FetchDescriptor<Gym>())
        let machines = try context.fetch(FetchDescriptor<Machine>())
        return package(
            definitions: definitions, sessions: sessions, templates: templates,
            gyms: gyms, machines: machines, includingPhotos: true, at: date
        )
    }
}
