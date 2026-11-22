import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// Merging an own exercise from Desk: the planner moves its entries as the
/// iPhone's Merge Exercises does, waits when either exercise changed here,
/// and refuses two that cannot be one.
struct InboxPlannerMergeTests {
    private func exercise(_ name: String, sides: String = "both", fields: [SyncField]) -> SyncExercise {
        SyncExercise(
            name: name, category: "Strength", muscleGroupNames: ["back"], secondaryMuscleGroupNames: [],
            tracksSets: true, sides: sides, offersAssistance: false, fields: fields, restSeconds: nil
        )
    }

    private let weight = SyncField(key: "weight", label: "Weight", type: "weight")
    private let reps = SyncField(key: "reps", label: "Reps", type: "reps")

    private var rowing: SyncExercise { exercise("Rowing", fields: [weight, SyncField(key: "f1", label: "Strokes", type: "reps")]) }
    private var row: SyncExercise { exercise("Row", fields: [reps, weight, SyncField(key: "f1", label: "Grip", type: "text")]) }

    private func file(_ operations: SyncOperation...) -> InboxPlanner.File {
        InboxPlanner.File(name: "1.json", content: .success(InboxFile(syncFormat: 1, createdAt: .now, operations: operations)))
    }

    private func workout(_ entries: SyncEntry...) -> SyncWorkout {
        SyncWorkout(id: UUID(), name: "Pull", date: .now, notes: "", durationSeconds: nil, gym: nil, exercises: entries)
    }

    private func entry(_ name: String, catalogKey: String? = nil, values: [SyncValue]) -> SyncEntry {
        SyncEntry(
            exercise: name, catalogKey: catalogKey, notes: "", instructions: "", mode: "bilateral", assistance: "unassisted",
            effortScale: "off", supersetGroup: nil, machine: nil, startSide: nil,
            sets: [SyncSet(side: "both", effort: nil, supersetPosition: nil, sideOrder: nil, done: true, values: values)]
        )
    }

    private func merge(_ base: SyncExercise, into target: SyncExercise, catalogKey: String? = nil, _ moves: [String: String?]) -> SyncOperation {
        .mergeExercise(
            base: base, into: SyncMergeTarget(catalogKey: catalogKey, exercise: target),
            fields: moves.sorted { $0.key < $1.key }.map { SyncFieldMove(from: $0.key, to: $0.value) }
        )
    }

    @Test func movesTheEntriesUnderTheTargetsKeysAndFields() {
        let rowingID = UUID(), rowID = UUID()
        let logged = workout(entry("rowing", values: [
            SyncValue(key: "weight", label: "Weight", type: "weight", text: nil, number: 50),
            SyncValue(key: "f1", label: "Strokes", type: "reps", text: nil, number: 12),
        ]))
        let state = InboxState(workouts: [logged], exercises: [rowingID: rowing, rowID: row])
        let plan = InboxPlanner.plan([file(merge(rowing, into: row, ["weight": "weight", "f1": "reps"]))], on: state)

        #expect(plan.changes == [.exerciseMerged("Rowing", into: "Row")])
        #expect(plan.result.exercises[rowingID] == nil)
        #expect(plan.result.exercises[rowID] == row)
        #expect(plan.result.photoHandovers == [rowingID: rowID])
        let moved = plan.result.workouts[logged.id]?.exercises.first
        #expect(moved?.exercise == "Row" && moved?.catalogKey == nil)
        #expect(moved?.sets.first?.values == [
            SyncValue(key: "reps", label: "Reps", type: "reps", text: nil, number: 12),
            SyncValue(key: "weight", label: "Weight", type: "weight", text: nil, number: 50),
            SyncValue(key: "f1", label: "Grip", type: "text", text: nil, number: nil),
        ])
    }

    @Test func aFieldWithoutCounterpartGoesOverAsANewOne() {
        let rowingID = UUID(), rowID = UUID()
        let plan = InboxPlanner.plan(
            [file(merge(rowing, into: row, ["weight": "weight", "f1": nil]))],
            on: InboxState(exercises: [rowingID: rowing, rowID: row])
        )
        // "f1" is the target's Grip already, so Strokes moves to the next free key.
        #expect(plan.result.exercises[rowID]?.fields.map(\.label) == ["Reps", "Weight", "Grip", "Strokes"])
        #expect(plan.result.exercises[rowID]?.fields.last?.key == "f4")
    }

    @Test func intoACatalogExerciseTheEntriesBecomeTheCatalogs() {
        let pullUp = exercise("Pull-Up", fields: [reps, weight])
        let own = exercise("Pull-Up", fields: [reps])
        let logged = workout(entry("Pull-Up", values: [SyncValue(key: "reps", label: "Reps", type: "reps", text: nil, number: 8)]))
        let state = InboxState(workouts: [logged], exercises: [UUID(): own], catalog: ["pull-up": pullUp])
        let plan = InboxPlanner.plan([file(merge(own, into: pullUp, catalogKey: "pull-up", ["reps": "reps"]))], on: state)
        #expect(plan.changes == [.exerciseMerged("Pull-Up", into: "Pull-Up")])
        #expect(plan.result.exercises.isEmpty)
        #expect(plan.result.photoHandovers.isEmpty)
        let moved = plan.result.workouts[logged.id]?.exercises.first
        #expect(moved?.catalogKey == "pull-up")
        #expect(moved?.sets.first?.values.map(\.key) == ["reps", "weight"])
        // Taken a second time, the own exercise is gone and nothing is logged with it.
        #expect(InboxPlanner.plan([file(merge(own, into: pullUp, catalogKey: "pull-up", ["reps": "reps"]))], on: plan.result).outcomes.map(\.outcome) == [.apply([])])
    }

    @Test func aCatalogExerciseTakesNoNewField() {
        let pullUp = exercise("Pull-Up", fields: [reps])
        let state = InboxState(exercises: [UUID(): rowing], catalog: ["pull-up": pullUp])
        let plan = InboxPlanner.plan([file(merge(rowing, into: pullUp, catalogKey: "pull-up", ["weight": nil, "f1": "reps"]))], on: state)
        #expect(plan.conflicts == [.exerciseCannotMerge("Rowing", into: "Pull-Up")])
    }

    @Test func refusesWhatCannotBeOne() {
        let unilateral = exercise("Row", sides: "one", fields: [reps, weight])
        let state = InboxState(exercises: [UUID(): rowing, UUID(): unilateral])
        #expect(InboxPlanner.plan([file(merge(rowing, into: unilateral, ["weight": "weight", "f1": "reps"]))], on: state).conflicts
            == [.exerciseCannotMerge("Rowing", into: "Row")])
        // A mapping that leaves a field nowhere.
        let both = InboxState(exercises: [UUID(): rowing, UUID(): row])
        #expect(InboxPlanner.plan([file(merge(rowing, into: row, ["weight": "weight"]))], on: both).conflicts
            == [.exerciseCannotMerge("Rowing", into: "Row")])
    }

    @Test func waitsWhenEitherChangedOrWentHere() {
        var renamed = row
        renamed.name = "Cable Row"
        let changedTarget = InboxState(exercises: [UUID(): rowing, UUID(): renamed])
        #expect(InboxPlanner.plan([file(merge(rowing, into: row, ["weight": "weight", "f1": "reps"]))], on: changedTarget).conflicts
            == [.exerciseDeletedHere("Row")])
        var refiled = row
        refiled.category = "Cardio"
        #expect(InboxPlanner.plan([file(merge(rowing, into: row, ["weight": "weight", "f1": "reps"]))], on: InboxState(exercises: [UUID(): rowing, UUID(): refiled])).conflicts
            == [.exerciseChangedHere("Row")])
        var changedSource = rowing
        changedSource.restSeconds = 60
        #expect(InboxPlanner.plan([file(merge(rowing, into: row, ["weight": "weight", "f1": "reps"]))], on: InboxState(exercises: [UUID(): changedSource, UUID(): row])).conflicts
            == [.exerciseChangedHere("Rowing")])
        let used = InboxState(workouts: [workout(entry("Rowing", values: []))], exercises: [UUID(): row])
        #expect(InboxPlanner.plan([file(merge(rowing, into: row, ["weight": "weight", "f1": "reps"]))], on: used).conflicts
            == [.exerciseDeletedHere("Rowing")])
    }

    @Test func readsBackWhatItWrites() throws {
        let operation = merge(rowing, into: row, ["weight": "weight", "f1": nil])
        let data = try SyncFormat.encoder.encode(InboxFile(syncFormat: 1, createdAt: Date(timeIntervalSince1970: 0), operations: [operation]))
        #expect(try InboxFile.read(from: data).get().operations == [operation])
    }
}

/// The same merges on a whole store: what the planner foresees is what the
/// iPhone's own merge writes, and a run takes it, hands the photo on and
/// undoes it.
@MainActor
struct InboxMergeStoreTests {
    /// For every case Desk is checked against, the store after the iPhone's
    /// `ExerciseMerging` reads as the planner said it would.
    @Test(arguments: DeskExport.mergeCases.indices)
    func thePlannerForeseesWhatTheIPhonesMergeWrites(_ index: Int) throws {
        let (sourceName, targetName, catalogKey) = DeskExport.mergeCases[index]
        let context = try DeskExport.store()
        let before = try InboxApplier.state(in: context)
        let operation = try DeskExport.mergeOperation(sourceName, into: targetName, catalogKey: catalogKey, on: before)
        let file = InboxPlanner.File(name: "1.json", content: .success(InboxFile(syncFormat: 1, createdAt: .now, operations: [operation])))
        let foreseen = InboxPlanner.plan([file], on: before)
        #expect(foreseen.conflicts.isEmpty)
        #expect(foreseen.result.workoutsByDate != before.workoutsByDate, "the case moves something")

        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let source = try #require(definitions.first { $0.catalogKey == nil && $0.name == sourceName })
        let target = try #require(definitions.first { catalogKey == nil ? ($0.catalogKey == nil && $0.name == targetName) : $0.catalogKey == catalogKey })
        guard case .mergeExercise(_, _, let moves) = operation else { Issue.record(); return }
        try ExerciseMerging.merge(source, into: target, mapping: FieldMapping(moves), in: context)
        try context.save()

        let merged = try InboxApplier.state(in: context)
        #expect(merged.exercises == foreseen.result.exercises)
        #expect(merged.workoutsByDate == foreseen.result.workoutsByDate)
        #expect(merged.inOrder == foreseen.result.inOrder)
    }

    /// And the applier, writing the planner's state, arrives at the same.
    @Test(arguments: DeskExport.mergeCases.indices)
    func theApplierWritesWhatThePlannerForesaw(_ index: Int) throws {
        let (sourceName, targetName, catalogKey) = DeskExport.mergeCases[index]
        let context = try DeskExport.store()
        let before = try InboxApplier.state(in: context)
        let operation = try DeskExport.mergeOperation(sourceName, into: targetName, catalogKey: catalogKey, on: before)
        let file = InboxPlanner.File(name: "1.json", content: .success(InboxFile(syncFormat: 1, createdAt: .now, operations: [operation])))
        let plan = InboxPlanner.plan([file], on: before)
        try InboxApplier.make(plan.result, from: before, in: context)
        try context.save()

        let after = try InboxApplier.state(in: context)
        #expect(after.exercises == plan.result.exercises)
        #expect(after.workoutsByDate == plan.result.workoutsByDate)
        #expect(after.inOrder == plan.result.inOrder)
        // Every entry hangs on a definition that is there.
        let ids = Set(try context.fetch(FetchDescriptor<ExerciseDefinition>()).map(\.id))
        let entries = try context.fetch(FetchDescriptor<ExerciseEntry>())
        #expect(entries.filter { $0.name == targetName }.allSatisfy { ids.contains($0.definitionID) })
    }
}

/// A merge in a whole run against a server in memory.
@MainActor
struct InboxMergeSyncTests {
    private let server = FakeWebDAV()
    private let defaults: UserDefaults
    private let context: ModelContext
    private let rowing: ExerciseDefinition
    private let row: ExerciseDefinition

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "InboxMergeSyncTests-\(UUID().uuidString)"))
        context = ModelContext(try ModelContainer(
            for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
        rowing = ExerciseDefinition.insertPlainSetsAndReps(name: "Rowing", orderIndex: 0, in: context)
        row = ExerciseDefinition.insertPlainSetsAndReps(name: "Row", orderIndex: 1, in: context)
        rowing.setPhoto(Data([1, 2, 3]), in: context)
        let session = WorkoutSession(name: "Pull", date: Date(timeIntervalSinceReferenceDate: 800_000_000))
        context.insert(session)
        let entry = ExerciseEntry(name: "Rowing", orderIndex: 0, definitionID: rowing.id, effortScale: .off, session: session)
        context.insert(entry)
        session.exercises.append(entry)
        try context.save()
    }

    private func connected() async throws -> SyncCenter {
        let kept = Locked<String?>(nil)
        let center = SyncCenter(
            defaults: defaults,
            secrets: SyncSecrets(read: { kept.value }, write: { kept.value = $0; return true }),
            session: server.session,
            workoutRunning: { false },
            now: { Date(timeIntervalSinceReferenceDate: 815_000_000) }
        )
        #expect(await center.connect(address: server.address, user: server.user, password: server.password) == nil)
        return center
    }

    private func definitions() throws -> [ExerciseDefinition] {
        try context.fetch(FetchDescriptor<ExerciseDefinition>(sortBy: [SortDescriptor(\.name)]))
    }

    private func entries() throws -> [ExerciseEntry] {
        try context.fetch(FetchDescriptor<ExerciseEntry>())
    }

    @Test func takesAMergeHandsThePhotoOnAndUndoesIt() async throws {
        let center = try await connected()
        let seen = try InboxApplier.state(in: context)
        let base = try #require(seen.exercises[rowing.id])
        let into = try #require(seen.exercises[row.id])
        let operation = SyncOperation.mergeExercise(
            base: base, into: SyncMergeTarget(catalogKey: nil, exercise: into),
            fields: [SyncFieldMove(from: "weight", to: "weight"), SyncFieldMove(from: "reps", to: "reps")]
        )
        let file = InboxFile(syncFormat: 1, createdAt: .now, operations: [operation])
        server.place(try SyncFormat.encoder.encode(file), at: "/dav/HippoTrophy/inbox/1.json")
        let rowID = row.id
        let rowingID = rowing.id
        await center.sync(.automatic, in: context)

        #expect(center.inboxNotice?.changes == [.exerciseMerged("Rowing", into: "Row")])
        #expect(try definitions().map(\.name) == ["Row"])
        let moved = try #require(try entries().first)
        #expect(moved.name == "Row" && moved.definitionID == rowID)
        #expect(try definitions().first?.ownPhoto?.data == Data([1, 2, 3]))
        #expect(server.files["/dav/HippoTrophy/inbox/1.json"] == nil)

        center.undoInbox(in: context)
        #expect(try definitions().map(\.name) == ["Row", "Rowing"])
        let back = try #require(try entries().first)
        #expect(back.name == "Rowing" && back.definitionID == rowingID)
    }
}
