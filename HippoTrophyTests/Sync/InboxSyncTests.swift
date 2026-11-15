import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The inbox in a whole run against a server in memory: what Desk left is
/// taken before the upload, written as an import writes it, and gone from
/// the inbox — or moved aside when it cannot apply.
@MainActor
struct InboxSyncTests {
    private let server = FakeWebDAV()
    private let defaults: UserDefaults
    private let context: ModelContext
    private let bench: ExerciseDefinition

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "InboxSyncTests-\(UUID().uuidString)"))
        context = ModelContext(try ModelContainer(
            for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
        bench = ExerciseDefinition.insertPlainSetsAndReps(name: "Bench", orderIndex: 0, in: context)
        context.insert(WorkoutSession(name: "Chest", date: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        try context.save()
    }

    private func center(running: Bool = false) -> SyncCenter {
        let kept = Locked<String?>(nil)
        return SyncCenter(
            defaults: defaults,
            secrets: SyncSecrets(read: { kept.value }, write: { kept.value = $0; return true }),
            session: server.session,
            workoutRunning: { running },
            now: { Date(timeIntervalSinceReferenceDate: 815_000_000) }
        )
    }

    private func connected(running: Bool = false) async throws -> SyncCenter {
        let center = center(running: running)
        #expect(await center.connect(address: server.address, user: server.user, password: server.password) == nil)
        return center
    }

    private func template(_ name: String, id: UUID = UUID(), notes: String = "", weight: Double = 60) -> SyncTemplate {
        SyncTemplate(id: id, name: name, notes: notes, archived: false, plannedFor: nil, gym: nil, exercises: [
            SyncEntry(
                exercise: "Bench", catalogKey: nil, notes: "", instructions: "", mode: "bilateral",
                assistance: "unassisted", effortScale: "off", supersetGroup: nil, machine: nil, startSide: nil,
                sets: [SyncSet(side: "both", effort: nil, supersetPosition: nil, sideOrder: nil, done: false, values: [
                    SyncValue(key: "weight", label: "Weight", type: "weight", text: nil, number: weight),
                    SyncValue(key: "reps", label: "Reps", type: "reps", text: nil, number: 8),
                ])]
            ),
        ])
    }

    private func leave(_ name: String, _ operations: SyncOperation...) throws {
        let file = InboxFile(syncFormat: 1, createdAt: .now, operations: operations)
        server.place(try SyncFormat.encoder.encode(file), at: "/dav/HippoTrophy/inbox/\(name)")
    }

    private func templates() throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor(predicate: WorkoutSession.templates, sortBy: [SortDescriptor(\.templateOrder)]))
    }

    @Test func takesANewTemplateAndUploadsIt() async throws {
        let center = try await connected()
        let push = template("Push")
        try leave("2026-11-15T10-00-00.json", .putTemplate(template: push, base: nil))

        #expect(await center.sync(.automatic, in: context) == .uploaded)

        let made = try #require(try templates().first)
        #expect(made.id == push.id && made.name == "Push")
        // Its entry hangs on the exercise here; none is made up.
        #expect(made.exercises.first?.definitionID == bench.id)
        #expect(try context.fetch(FetchDescriptor<ExerciseDefinition>()).count == 1)
        #expect(made.exercises.first?.sortedSets.first?.weightKg == 60)
        #expect(server.files["/dav/HippoTrophy/inbox/2026-11-15T10-00-00.json"] == nil)
        let uploaded = try BackupPackage.read(from: try #require(server.files["/dav/HippoTrophy/backup.zip"]).data)
        #expect(uploaded.file.templates?.map(\.id) == [push.id])
        #expect(center.inboxNotice?.changes == [.added("Push")])
    }

    @Test func aChangedTemplateKeepsItsPlace() async throws {
        let center = try await connected()
        let a = template("A"), b = template("B")
        try leave("1.json", .putTemplate(template: b, base: nil), .putTemplate(template: a, base: nil))
        await center.sync(.automatic, in: context)
        #expect(try templates().map(\.name) == ["A", "B"])

        let seen = try #require(try InboxApplier.state(in: context).templates[b.id])
        var heavier = seen
        heavier.exercises[0].sets[0].values[0].number = 70
        try leave("2.json", .putTemplate(template: heavier, base: seen))
        await center.sync(.automatic, in: context)

        #expect(try templates().map(\.name) == ["A", "B"])
        #expect(try templates().last?.exercises.first?.sortedSets.first?.weightKg == 70)
    }

    @Test func movesAChangeOnAnOldStateAsideForDesk() async throws {
        let center = try await connected()
        let push = template("Push")
        try leave("1.json", .putTemplate(template: push, base: nil))
        await center.sync(.automatic, in: context)
        try templates().first?.notes = "Changed on the phone"
        try context.save()

        var desk = push
        desk.notes = "Changed in Desk"
        try leave("2.json", .putTemplate(template: desk, base: push))
        await center.sync(.automatic, in: context)

        #expect(try templates().first?.notes == "Changed on the phone")
        #expect(server.files["/dav/HippoTrophy/inbox/2.json"] == nil)
        #expect(server.files["/dav/HippoTrophy/inbox/conflicts/2.json"] != nil)
        #expect(center.inboxNotice?.conflicts == [.changedHere("Push")])
    }

    @Test func takesNothingDuringAWorkout() async throws {
        let center = try await connected(running: true)
        try leave("1.json", .putTemplate(template: template("Push"), base: nil))
        #expect(await center.sync(.automatic, in: context) == .workoutRunning)
        #expect(try templates().isEmpty)
        #expect(server.files["/dav/HippoTrophy/inbox/1.json"] != nil)
    }

    @Test func takesNothingOverABackupThatIsNotThisDevices() async throws {
        server.place(Data("theirs".utf8), at: "/dav/HippoTrophy/backup.zip")
        let center = try await connected()
        try leave("1.json", .putTemplate(template: template("Push"), base: nil))
        #expect(await center.sync(.automatic, in: context) == .waitingForDecision)
        #expect(try templates().isEmpty)
        #expect(server.files["/dav/HippoTrophy/inbox/1.json"] != nil)
    }

    @Test func leavesAFileFromANewerDeskAndSaysSo() async throws {
        let center = try await connected()
        server.place(Data(#"{"syncFormat": 2, "createdAt": "2026-11-15T10:00:00Z", "operations": []}"#.utf8), at: "/dav/HippoTrophy/inbox/1.json")
        await center.sync(.automatic, in: context)
        #expect(server.files["/dav/HippoTrophy/inbox/1.json"] != nil)
        #expect(center.inboxNotice?.needsUpdate == true)
    }

    @Test func undoPutsBackWhatDeskChangedAndKeepsWhatChangedHere() async throws {
        let center = try await connected()
        let push = template("Push")
        let legs = template("Legs")
        try leave("1.json", .putTemplate(template: push, base: nil), .putTemplate(template: legs, base: nil))
        await center.sync(.automatic, in: context)
        center.dismissInboxNotice()

        let seen = try InboxApplier.state(in: context)
        var heavier = try #require(seen.templates[push.id])
        heavier.exercises[0].sets[0].values[0].number = 80
        let added = template("Arms")
        try leave("2.json",
                  .putTemplate(template: heavier, base: seen.templates[push.id]),
                  .deleteTemplate(id: legs.id, base: try #require(seen.templates[legs.id])),
                  .putTemplate(template: added, base: nil))
        await center.sync(.automatic, in: context)
        #expect(try templates().map(\.name).sorted() == ["Arms", "Push"])

        center.undoInbox(in: context)

        #expect(center.inboxNotice == nil)
        #expect(try templates().map(\.name).sorted() == ["Legs", "Push"])
        let pushNow = try #require(try templates().first { $0.id == push.id })
        #expect(pushNow.exercises.first?.sortedSets.first?.weightKg == 60)
    }
}
