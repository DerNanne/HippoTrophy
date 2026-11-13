import Foundation
import Observation
import SwiftData
import UIKit

/// The sync to the user's own WebDAV server, for the whole app: whether it is
/// on, what happened last, and the one run at a time that puts the backup
/// there. Off, it does nothing at all — no request, no work at a workout's
/// end or when the app goes away.
@MainActor
@Observable
final class SyncCenter {
    static let shared = SyncCenter(defaults: .standard, secrets: .keychain)

    struct Connection: Equatable {
        let layout: SyncLayout
        let user: String
    }

    /// What a run came to, for Sync Now to say.
    enum Outcome: Equatable {
        case uploaded
        case unchanged
        case workoutRunning
        case waitingForDecision
        case failed(SyncProblem)
        case off
    }

    private(set) var connection: Connection?
    private(set) var state: SyncState {
        didSet { persistState() }
    }
    private(set) var isSyncing = false

    var isOn: Bool { connection != nil }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: SyncSecrets
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let workoutRunning: @MainActor () -> Bool
    @ObservationIgnored private let now: () -> Date
    /// A run asked for while one was going: done once that one is through.
    @ObservationIgnored private var owedTrigger: (SyncTrigger, ModelContext)?

    /// Not a `SettingsKey`: this is state, not a setting.
    static let stateKey = "syncState"

    init(
        defaults: UserDefaults,
        secrets: SyncSecrets,
        session: URLSession = .shared,
        workoutRunning: @escaping @MainActor () -> Bool = { RunningWorkoutCenter.shared.running != nil },
        now: @escaping () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.secrets = secrets
        self.session = session
        self.workoutRunning = workoutRunning
        self.now = now
        state = defaults.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) } ?? SyncState()
        if let address = defaults.string(forKey: SettingsKey.syncServer),
           let user = defaults.string(forKey: SettingsKey.syncUser),
           case .success(let layout) = SyncLayout.parse(address) {
            connection = Connection(layout: layout, user: user)
        }
    }

    // MARK: - Connecting

    /// Tries the server before anything is kept: signs in, makes the folder,
    /// writes a file and takes it away again. Kept only if all of that
    /// worked. A backup already there is not this device's until the user
    /// says so.
    func connect(address: String, user: String, password: String) async -> SyncProblem? {
        let layout: SyncLayout
        switch SyncLayout.parse(address) {
        case .success(let parsed): layout = parsed
        case .failure(let problem): return .address(problem)
        }
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = WebDAVClient(user: user, password: password, session: session)
        let existing: String?
        do {
            try await client.makeFolder(layout.folder)
            try await client.put(Data("HippoTrophy checks it can write here.".utf8), to: layout.writeTest)
            try await client.delete(layout.writeTest)
            existing = try await client.etag(of: layout.backup)
        } catch {
            return SyncProblem.from(error)
        }
        guard secrets.write(password) else {
            return .other("The password could not be kept in the keychain.")
        }
        defaults.set(layout.server.absoluteString, forKey: SettingsKey.syncServer)
        defaults.set(user, forKey: SettingsKey.syncUser)
        state = SyncState(foreignBackupOnServer: existing != nil)
        connection = Connection(layout: layout, user: user)
        return nil
    }

    /// Forgets the server: the address, the password and what the sync
    /// remembers. What is on the server stays there.
    func disconnect() {
        _ = secrets.write(nil)
        defaults.removeObject(forKey: SettingsKey.syncServer)
        defaults.removeObject(forKey: SettingsKey.syncUser)
        state = SyncState()
        connection = nil
    }

    // MARK: - Syncing

    /// Whether an upload failed and is still owed: the app tries again when
    /// it comes back.
    var owesUpload: Bool {
        isOn && state.lastError != nil && !state.foreignBackupOnServer
    }

    /// A run the app goes on with for a while after it leaves the screen, so
    /// an upload started as it goes away gets to its end.
    func syncInBackground(_ trigger: SyncTrigger, in context: ModelContext) {
        guard isOn else { return }
        let application = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = application.beginBackgroundTask(withName: "HippoTrophy sync") {
            application.endBackgroundTask(task)
            task = .invalid
        }
        Task {
            _ = await sync(trigger, in: context)
            if task != .invalid { application.endBackgroundTask(task) }
        }
    }

    @discardableResult
    func sync(_ trigger: SyncTrigger, in context: ModelContext) async -> Outcome {
        guard let connection else { return .off }
        guard !isSyncing else {
            owedTrigger = (trigger, context)
            return .unchanged
        }
        isSyncing = true
        defer {
            isSyncing = false
            if let (owed, owedContext) = owedTrigger {
                owedTrigger = nil
                Task { await sync(owed, in: owedContext) }
            }
        }
        if workoutRunning() { return .workoutRunning }

        let upload: SyncUpload
        do {
            let package = try BackupExporter.everything(in: context, at: now())
            upload = try await Task.detached(priority: .utility) { try SyncUpload(package) }.value
        } catch {
            return fail(SyncProblem.from(error))
        }
        switch SyncDecision.before(trigger: trigger, fingerprint: upload.fingerprint, state: state, workoutRunning: workoutRunning()) {
        case .upload: break
        case .unchanged: return .unchanged
        case .workoutRunning: return .workoutRunning
        case .waitingForDecision: return .waitingForDecision
        }
        guard let password = secrets.read() else { return fail(.credentials) }
        let client = WebDAVClient(user: connection.user, password: password, session: session)
        let layout = connection.layout

        do {
            try await client.makeFolder(layout.folder)
            try await client.put(upload.data, to: layout.uploading)
            if trigger != .replaceServer {
                let current = try await client.etag(of: layout.backup)
                guard SyncDecision.serverIsOurs(currentETag: current, knownETag: state.lastETag) else {
                    try? await client.delete(layout.uploading)
                    state.foreignBackupOnServer = true
                    return fail(.foreignBackup)
                }
            }
            try await client.move(layout.uploading, to: layout.backup)
            let etag = try await client.etag(of: layout.backup)
            state = SyncState(lastFingerprint: upload.fingerprint, lastETag: etag, lastUpload: now())
        } catch {
            return fail(SyncProblem.from(error))
        }

        // The backup is up; a copy for the day that fails does not undo it.
        do {
            try await client.makeFolder(layout.history)
            try await client.copy(layout.backup, to: layout.historyFile(for: now()))
            let names = try await client.list(layout.history).filter { !$0.isCollection }.map(\.name)
            for name in SyncLayout.historyToDelete(among: names) {
                try await client.delete(layout.history.appending(path: name, directoryHint: .notDirectory))
            }
        } catch {
            state.lastError = "The backup is on the server, but its copy for today in history/ failed. \(SyncProblem.from(error).localizedDescription)"
            state.lastErrorAt = now()
        }
        return .uploaded
    }

    // MARK: - Bringing the server's backup in

    /// The backup on the server as it is now, and the etag it had when it
    /// was read.
    struct ServerBackup: Equatable {
        let data: Data
        let etag: String?
    }

    /// Fetches `backup.zip` for the import. Changes nothing, here or there:
    /// the import is the user's to go through or to cancel.
    func downloadBackup() async -> Result<ServerBackup, SyncProblem> {
        guard let connection, let password = secrets.read() else { return .failure(.credentials) }
        let client = WebDAVClient(user: connection.user, password: password, session: session)
        do {
            // The etag first: a backup written between the two reads is
            // then taken for another one at the next upload, never the other
            // way round.
            let etag = try await client.etag(of: connection.layout.backup)
            guard let data = try await client.get(connection.layout.backup) else { return .failure(.noBackupOnServer) }
            return .success(ServerBackup(data: data, etag: etag))
        } catch {
            return .failure(SyncProblem.from(error))
        }
    }

    /// The server's backup has been brought in: this device now holds what
    /// it held, and from here on writes over it. A wait for the user's
    /// decision is over; the next run uploads, changed or not.
    func adoptServerBackup(etag: String?) {
        state.lastETag = etag
        state.lastFingerprint = nil
        state.foreignBackupOnServer = false
        state.lastError = nil
        state.lastErrorAt = nil
    }

    private func fail(_ problem: SyncProblem) -> Outcome {
        state.lastError = problem.localizedDescription
        state.lastErrorAt = now()
        return .failed(problem)
    }

    private func persistState() {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.stateKey)
    }
}
