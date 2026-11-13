import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The whole run against a server in memory: what lands where, what is left
/// alone, and when nothing is sent at all.
@MainActor
struct SyncCenterTests {
    private let server = FakeWebDAV()
    private let defaults: UserDefaults
    private let context: ModelContext

    init() throws {
        let suite = "SyncCenterTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        context = ModelContext(try ModelContainer(
            for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
        context.insert(WorkoutSession(name: "Legs", date: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        try context.save()
    }

    /// A center with its own defaults and a password store in memory.
    private func center(now: Date = Date(timeIntervalSinceReferenceDate: 815_000_000), running: Bool = false) -> SyncCenter {
        let kept = Locked<String?>(nil)
        return SyncCenter(
            defaults: defaults,
            secrets: SyncSecrets(read: { kept.value }, write: { kept.value = $0; return true }),
            session: server.session,
            workoutRunning: { running },
            now: { now }
        )
    }

    private func connected(_ center: SyncCenter) async throws {
        let problem = await center.connect(address: server.address, user: server.user, password: server.password)
        #expect(problem == nil)
    }

    // MARK: - Connecting

    @Test func connectingMakesTheFolderAndLeavesNothingBehind() async throws {
        let center = center()
        try await connected(center)
        #expect(center.isOn)
        #expect(server.files.isEmpty)
        #expect(server.log.contains("MKCOL /dav/HippoTrophy"))
        #expect(server.log.contains("PUT /dav/HippoTrophy/backup.zip.write-test"))
        #expect(!center.state.foreignBackupOnServer)
    }

    @Test func connectingIsKeptOnlyIfItWorked() async throws {
        let center = center()
        let problem = await center.connect(address: server.address, user: server.user, password: "wrong")
        #expect(problem == .credentials)
        #expect(!center.isOn)
        #expect(defaults.string(forKey: SettingsKey.syncServer) == nil)
    }

    @Test func connectingRefusesAnAddressOverHTTP() async {
        let problem = await center().connect(address: "http://\(server.host)/dav/", user: server.user, password: server.password)
        #expect(problem == .address(.notHTTPS))
        #expect(server.log.isEmpty)
    }

    @Test func comesBackConnectedAfterALaunch() async throws {
        try await connected(center())
        let relaunched = center()
        #expect(relaunched.connection?.layout.server.absoluteString == server.address)
        #expect(relaunched.connection?.user == server.user)
    }

    @Test func turningOffForgetsTheServerAndLeavesItAlone() async throws {
        let center = center()
        try await connected(center)
        await center.sync(.manual, in: context)
        server.clearLog()
        center.disconnect()
        #expect(!center.isOn)
        #expect(center.state == SyncState())
        #expect(server.log.isEmpty)
        #expect(server.files["/dav/HippoTrophy/backup.zip"] != nil)
        #expect(await center.sync(.manual, in: context) == .off)
    }

    // MARK: - Uploading

    @Test func putsTheBackupAndTheDaysCopyOnTheServer() async throws {
        let center = center()
        try await connected(center)
        #expect(await center.sync(.automatic, in: context) == .uploaded)

        let backup = try #require(server.files["/dav/HippoTrophy/backup.zip"])
        #expect(try BackupPackage.read(from: backup.data).file.workouts?.map(\.name) == ["Legs"])
        #expect(server.files["/dav/HippoTrophy/backup.zip.uploading"] == nil)
        let day = SyncLayout.historyName(for: Date(timeIntervalSinceReferenceDate: 815_000_000))
        #expect(server.files["/dav/HippoTrophy/history/\(day)"]?.data == backup.data)
        #expect(center.state.lastETag == backup.etag)
        #expect(center.state.lastError == nil)
        #expect(center.state.lastUpload != nil)
    }

    @Test func writesTheNewBackupOverTheOldInOneMove() async throws {
        let center = center()
        try await connected(center)
        server.clearLog()
        await center.sync(.automatic, in: context)
        let writes = server.log.filter { !$0.hasPrefix("PROPFIND") && !$0.hasPrefix("MKCOL") }
        #expect(Array(writes.prefix(2)) == ["PUT /dav/HippoTrophy/backup.zip.uploading", "MOVE /dav/HippoTrophy/backup.zip.uploading"])
    }

    @Test func sendsNothingWhenNothingChanged() async throws {
        let center = center()
        try await connected(center)
        await center.sync(.automatic, in: context)
        server.clearLog()
        #expect(await center.sync(.automatic, in: context) == .unchanged)
        #expect(server.log.isEmpty)
    }

    @Test func knowsItsOwnBackupWhenTheServerMarksTheEtagWeak() async throws {
        server.weakRightAfterWrite = true
        let center = center()
        try await connected(center)
        #expect(await center.sync(.automatic, in: context) == .uploaded)
        #expect(center.state.lastETag?.hasPrefix("W/") == true)
        #expect(await center.sync(.manual, in: context) == .uploaded)
        #expect(!center.state.foreignBackupOnServer)
    }

    @Test func uploadsWhatChanged() async throws {
        let center = center()
        try await connected(center)
        await center.sync(.automatic, in: context)
        context.insert(WorkoutSession(name: "Pull", date: Date(timeIntervalSinceReferenceDate: 810_000_000)))
        try context.save()
        #expect(await center.sync(.automatic, in: context) == .uploaded)
        let backup = try #require(server.files["/dav/HippoTrophy/backup.zip"])
        #expect(try BackupPackage.read(from: backup.data).file.workouts?.count == 2)
    }

    @Test func sendsNothingDuringAWorkout() async throws {
        let center = center(running: true)
        try await connected(center)
        server.clearLog()
        #expect(await center.sync(.manual, in: context) == .workoutRunning)
        #expect(server.log.isEmpty)
    }

    @Test func keepsTheNewestFourteenDaysAndLeavesTheRestOfTheFolderAlone() async throws {
        for day in 1...20 {
            server.place(Data("old".utf8), at: String(format: "/dav/HippoTrophy/history/2026-10-%02d.zip", day))
        }
        server.place(Data("mine".utf8), at: "/dav/HippoTrophy/history/notes.txt")
        server.place(Data("later".utf8), at: "/dav/HippoTrophy/inbox/template.json")
        let center = center()
        try await connected(center)
        await center.sync(.manual, in: context)

        let history = server.files.keys.filter { $0.hasPrefix("/dav/HippoTrophy/history/") }
        #expect(history.filter { SyncLayout.isHistoryName(($0 as NSString).lastPathComponent) }.count == SyncLayout.historyKept)
        #expect(history.contains("/dav/HippoTrophy/history/notes.txt"))
        #expect(!history.contains("/dav/HippoTrophy/history/2026-10-07.zip"))
        #expect(history.contains("/dav/HippoTrophy/history/2026-10-08.zip"))
        #expect(server.files["/dav/HippoTrophy/inbox/template.json"] != nil)
    }

    // MARK: - Someone else's backup

    @Test func waitsWhenTheServerAlreadyHasABackup() async throws {
        server.place(Data("theirs".utf8), at: "/dav/HippoTrophy/backup.zip")
        let center = center()
        try await connected(center)
        #expect(center.state.foreignBackupOnServer)
        server.clearLog()
        #expect(await center.sync(.automatic, in: context) == .waitingForDecision)
        #expect(server.log.isEmpty)
        #expect(server.files["/dav/HippoTrophy/backup.zip"]?.data == Data("theirs".utf8))
    }

    @Test func stopsWhenAnotherDeviceWroteSinceTheLastUpload() async throws {
        let center = center()
        try await connected(center)
        await center.sync(.automatic, in: context)
        server.place(Data("theirs".utf8), at: "/dav/HippoTrophy/backup.zip")
        context.insert(WorkoutSession(name: "Push", date: .now))
        try context.save()

        #expect(await center.sync(.automatic, in: context) == .failed(.foreignBackup))
        #expect(server.files["/dav/HippoTrophy/backup.zip"]?.data == Data("theirs".utf8))
        #expect(server.files["/dav/HippoTrophy/backup.zip.uploading"] == nil)
        #expect(center.state.foreignBackupOnServer)
        #expect(!center.owesUpload)
    }

    @Test func replacesTheirBackupWhenTheUserSaysSo() async throws {
        server.place(Data("theirs".utf8), at: "/dav/HippoTrophy/backup.zip")
        let center = center()
        try await connected(center)
        #expect(await center.sync(.replaceServer, in: context) == .uploaded)
        let backup = try #require(server.files["/dav/HippoTrophy/backup.zip"])
        #expect(try BackupPackage.read(from: backup.data).file.workouts?.map(\.name) == ["Legs"])
        #expect(!center.state.foreignBackupOnServer)
        #expect(await center.sync(.automatic, in: context) == .unchanged)
    }

    // MARK: - Bringing it in

    @Test func downloadsTheBackupOnTheServerAndChangesNothing() async throws {
        server.place(Data("theirs".utf8), at: "/dav/HippoTrophy/backup.zip")
        let center = center()
        try await connected(center)
        let before = center.state
        server.clearLog()
        let backup = try await center.downloadBackup().get()
        #expect(backup.data == Data("theirs".utf8))
        #expect(backup.etag == server.files["/dav/HippoTrophy/backup.zip"]?.etag)
        #expect(server.log.allSatisfy { $0.hasPrefix("PROPFIND") || $0.hasPrefix("GET") })
        #expect(center.state == before)
    }

    @Test func saysSoWhenTheServerHasNoBackup() async throws {
        let center = center()
        try await connected(center)
        #expect(await center.downloadBackup() == .failure(.noBackupOnServer))
    }

    @Test func writesOverTheBackupItBroughtIn() async throws {
        server.place(Data("theirs".utf8), at: "/dav/HippoTrophy/backup.zip")
        let center = center()
        try await connected(center)
        let backup = try await center.downloadBackup().get()
        center.adoptServerBackup(etag: backup.etag)
        #expect(!center.state.foreignBackupOnServer)
        #expect(await center.sync(.automatic, in: context) == .uploaded)
        #expect(server.files["/dav/HippoTrophy/backup.zip"]?.data != Data("theirs".utf8))
    }

    @Test func stillStopsWhenAnotherDeviceWroteAfterTheDownload() async throws {
        server.place(Data("theirs".utf8), at: "/dav/HippoTrophy/backup.zip")
        let center = center()
        try await connected(center)
        let backup = try await center.downloadBackup().get()
        server.place(Data("newer".utf8), at: "/dav/HippoTrophy/backup.zip")
        center.adoptServerBackup(etag: backup.etag)
        #expect(await center.sync(.automatic, in: context) == .failed(.foreignBackup))
        #expect(server.files["/dav/HippoTrophy/backup.zip"]?.data == Data("newer".utf8))
    }

    // MARK: - Failing

    @Test func remembersAFailureAndOwesTheUpload() async throws {
        let center = center()
        try await connected(center)
        server.forcedStatus = 503
        #expect(await center.sync(.automatic, in: context) == .failed(.server(503)))
        #expect(center.state.lastError != nil)
        #expect(center.owesUpload)

        server.forcedStatus = nil
        #expect(await center.sync(.automatic, in: context) == .uploaded)
        #expect(center.state.lastError == nil)
        #expect(!center.owesUpload)
    }
}

/// A value closures on several threads can share.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
