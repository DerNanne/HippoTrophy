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

        // What Desk changed comes in first, so the upload after carries it.
        // Not over a backup that is not this device's: Desk's changes rest on
        // that one.
        if !state.foreignBackupOnServer {
            if let problem = await takeInbox(in: context, connection: connection) { return fail(problem) }
        }

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

    // MARK: - What Desk sends

    /// What came from Desk, until the user closes it: the changes, what had
    /// to wait, and the templates before them, for Undo.
    struct InboxNotice: Equatable {
        var changes: [InboxPlanner.Change] = []
        var conflicts: [InboxPlanner.Conflict] = []
        /// A file from a newer Desk waits for an update of this app.
        var needsUpdate = false
        var before: InboxState
        /// The templates the changes touched.
        var touched: Set<UUID> = []
        /// The workouts the changes touched.
        var touchedWorkouts: Set<UUID> = []
        /// The own exercises the changes touched.
        var touchedExercises: Set<UUID> = []
        var reordered = false

        /// Whether Undo has anything to put back.
        var canUndo: Bool { !touched.isEmpty || !touchedWorkouts.isEmpty || !touchedExercises.isEmpty || reordered }
    }

    private(set) var inboxNotice: InboxNotice?

    /// Whether Desk left anything: a look at the inbox, nothing taken. When
    /// the app comes back, a sync runs only if there is.
    func syncIfInboxHasMail(in context: ModelContext) {
        guard let connection, !state.foreignBackupOnServer, !workoutRunning(), let password = secrets.read() else { return }
        let client = WebDAVClient(user: connection.user, password: password, session: session)
        Task {
            let names = (try? await client.list(connection.layout.inbox))?.filter { !$0.isCollection }.map(\.name) ?? []
            if names.contains(where: SyncLayout.isInboxName) {
                syncInBackground(.automatic, in: context)
            }
        }
    }

    /// Takes the inbox: plans every file on the templates here, writes what
    /// applies in one save, then deletes those files and moves the ones in
    /// conflict aside for Desk. A file from a newer Desk, or one that cannot
    /// be read, stays where it is.
    private func takeInbox(in context: ModelContext, connection: Connection) async -> SyncProblem? {
        guard let password = secrets.read() else { return .credentials }
        let client = WebDAVClient(user: connection.user, password: password, session: session)
        let layout = connection.layout
        do {
            let names = try await client.list(layout.inbox)
                .filter { !$0.isCollection && SyncLayout.isInboxName($0.name) }
                .map(\.name)
            guard !names.isEmpty else { return nil }
            var files: [InboxPlanner.File] = []
            for name in names {
                guard let data = try await client.get(layout.inbox.appending(path: name, directoryHint: .notDirectory)) else { continue }
                files.append(InboxPlanner.File(name: name, content: InboxFile.read(from: data)))
            }

            let before = try InboxApplier.state(in: context)
            let plan = InboxPlanner.plan(files, on: before)
            if plan.result != before {
                do {
                    try InboxApplier.make(plan.result, from: before, in: context)
                    try context.save()
                } catch {
                    context.rollback()
                    return .other("What Desk sent could not be saved: \(error.localizedDescription)")
                }
            }

            for (name, outcome) in plan.outcomes {
                let file = layout.inbox.appending(path: name, directoryHint: .notDirectory)
                switch outcome {
                case .apply:
                    try await client.delete(file)
                case .conflict:
                    try await client.makeFolder(layout.conflicts)
                    try await client.move(file, to: layout.conflicts.appending(path: name, directoryHint: .notDirectory))
                case .tooNew, .unreadable:
                    break
                }
            }
            note(plan, before: before)
            return nil
        } catch {
            return SyncProblem.from(error)
        }
    }

    /// Adds what a run took to the notice still open, so one Undo goes back
    /// to before the first of them.
    private func note(_ plan: InboxPlanner.Plan, before: InboxState) {
        let needsUpdate = plan.outcomes.contains { if case .tooNew = $0.outcome { true } else { false } }
        guard !plan.changes.isEmpty || !plan.conflicts.isEmpty || needsUpdate else { return }
        var notice = inboxNotice ?? InboxNotice(before: before)
        notice.changes += plan.changes
        notice.conflicts += plan.conflicts
        notice.needsUpdate = notice.needsUpdate || needsUpdate
        let ids = Set(before.templates.keys).union(plan.result.templates.keys)
        notice.touched.formUnion(ids.filter { before.templates[$0] != plan.result.templates[$0] })
        let workoutIDs = Set(before.workouts.keys).union(plan.result.workouts.keys)
        notice.touchedWorkouts.formUnion(workoutIDs.filter { before.workouts[$0] != plan.result.workouts[$0] })
        let exerciseIDs = Set(before.exercises.keys).union(plan.result.exercises.keys)
        notice.touchedExercises.formUnion(exerciseIDs.filter { before.exercises[$0] != plan.result.exercises[$0] })
        notice.reordered = notice.reordered || before.order != plan.result.order
        inboxNotice = notice
    }

    func dismissInboxNotice() {
        inboxNotice = nil
    }

    /// Puts back what Desk changed: the templates, workouts and own exercises
    /// it touched as they were, and the templates' order if it moved them. What was changed here since stays.
    /// The upload after carries it to the server and to Desk.
    func undoInbox(in context: ModelContext) {
        guard let notice = inboxNotice else { return }
        inboxNotice = nil
        do {
            let current = try InboxApplier.state(in: context)
            var target = current
            for id in notice.touched {
                target.templates[id] = notice.before.templates[id]
            }
            for id in notice.touchedWorkouts {
                target.workouts[id] = notice.before.workouts[id]
            }
            for id in notice.touchedExercises {
                target.exercises[id] = notice.before.exercises[id]
            }
            let kept = target.templates.keys
            if notice.reordered {
                let earlier = notice.before.order.filter { kept.contains($0) }
                target.order = current.order.filter { !earlier.contains($0) && kept.contains($0) } + earlier
            } else {
                target.order = current.order.filter { kept.contains($0) }
                    + notice.before.order.filter { kept.contains($0) && !current.order.contains($0) }
            }
            try InboxApplier.make(target, from: current, in: context)
            try context.save()
        } catch {
            context.rollback()
            state.lastError = "Undo failed: \(error.localizedDescription)"
            state.lastErrorAt = now()
            return
        }
        syncInBackground(.automatic, in: context)
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
