import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The one step after the update: unused own exercises go, the rest that log
/// sets wait for the assistant.
@MainActor
struct SidesSettlementTests {
    private func exercise(
        catalog: Bool = false, tracksSets: Bool = true, cardio: Bool = false, used: Bool = true
    ) -> SidesSettlement.Exercise {
        SidesSettlement.Exercise(id: UUID(), isCatalog: catalog, tracksSets: tracksSets, isCardio: cardio, isUsed: used)
    }

    @Test func anOwnExerciseNeverUsedGoes() {
        let unused = exercise(used: false)
        #expect(SidesSettlement.plan([unused]).deletions == [unused.id])
    }

    @Test func aCatalogExerciseIsNeverTouched() {
        let catalog = exercise(catalog: true, used: false)
        #expect(SidesSettlement.plan([catalog]) == SidesSettlement.Plan())
    }

    /// Strength, Mobility, an own category: all asked, whatever the old
    /// switch said.
    @Test func everyUsedOwnExerciseWithSetsIsAsked() {
        let used = exercise()
        #expect(SidesSettlement.plan([used]).undecided == [used.id])
    }

    /// Not asked, and not left as they were either: an old switch left on
    /// would read as undecided and bring them into the assistant after all —
    /// the update test from build 20 found a plank there.
    @Test func cardioAndOncePerWorkoutAreBilateralWithoutAsking() {
        let cardio = exercise(cardio: true)
        let once = exercise(tracksSets: false)
        let plan = SidesSettlement.plan([cardio, once])
        #expect(plan.undecided.isEmpty)
        #expect(plan.bilateral == [cardio.id, once.id])
    }

    @Test func anOwnExerciseAlreadyOneSidedIsLeftAlone() {
        let made = SidesSettlement.Exercise(id: UUID(), isCatalog: false, tracksSets: true, isCardio: false, isOneSided: true, isUsed: true)
        #expect(SidesSettlement.plan([made]) == SidesSettlement.Plan())
    }

    /// After the first launch only the undecided ones never used go: there is
    /// nothing to ask about them.
    @Test func aLeftoverIsUndecidedOwnAndUnused() {
        let leftover = SidesSettlement.Exercise(id: UUID(), isCatalog: false, tracksSets: true, isCardio: false, isUndecided: true, isUsed: false)
        let usedUndecided = SidesSettlement.Exercise(id: UUID(), isCatalog: false, tracksSets: true, isCardio: false, isUndecided: true, isUsed: true)
        let decided = exercise(used: false)
        #expect(SidesSettlement.leftovers([leftover, usedUndecided, decided]) == [leftover.id])
    }

    /// The overhead extension from the list build 20 shipped turned up in the
    /// assistant on a phone settled long before, "Never logged".
    @Test func droppingLeftoversRunsEveryTimeAndKeepsTheRest() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let leftover = ExerciseDefinition.insertPlainSetsAndReps(name: "Overhead Triceps Extension", orderIndex: 0, in: context)
        leftover.sides = .either
        let asked = ExerciseDefinition.insertPlainSetsAndReps(name: "Split Squat", orderIndex: 1, in: context)
        asked.sides = .either
        let typed = ExerciseDefinition.insertPlainSetsAndReps(name: "Typed Once", orderIndex: 2, in: context)
        typed.sides = .both
        let session = WorkoutSession(name: "Arms")
        context.insert(session)
        let empty = ExerciseEntry(name: "Overhead Triceps Extension", orderIndex: 0, definitionID: leftover.id, effortScale: .levels, session: session)
        let noted = ExerciseEntry(name: "Split Squat", orderIndex: 1, definitionID: asked.id, effortScale: .levels, session: session)
        context.insert(empty)
        context.insert(noted)
        noted.notes = "left first"
        try context.save()

        try SidesSettlement.dropLeftovers(in: context)

        let names = try context.fetch(FetchDescriptor<ExerciseDefinition>()).map(\.name)
        #expect(Set(names) == ["Split Squat", "Typed Once"])
        #expect(try context.fetch(FetchDescriptor<ExerciseEntry>()).map(\.name) == ["Split Squat"])
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).count == 1)
    }

    /// With build 22, whatever its side; the catalog's stay.
    @Test func everyOwnExerciseNeverUsedIsUnused() {
        let oneSided = SidesSettlement.Exercise(id: UUID(), isCatalog: false, tracksSets: true, isCardio: false, isOneSided: true, isUsed: false)
        let bilateral = exercise(used: false)
        let used = exercise()
        let catalog = exercise(catalog: true, used: false)
        #expect(SidesSettlement.unused([oneSided, bilateral, used, catalog]) == [oneSided.id, bilateral.id])
    }

    /// Once: an exercise made after it is wanted, if not yet trained.
    @Test func droppingTheUnusedRunsOnce() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let decided = ExerciseDefinition.insertPlainSetsAndReps(name: "Overhead Triceps Extension", orderIndex: 0, in: context)
        decided.sides = .one
        try context.save()
        let defaults = scratchDefaults()

        try SidesSettlement.dropUnusedOnce(in: context, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<ExerciseDefinition>()).isEmpty)

        _ = ExerciseDefinition.insertPlainSetsAndReps(name: "Cable Shrug", orderIndex: 1, in: context)
        try context.save()
        try SidesSettlement.dropUnusedOnce(in: context, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<ExerciseDefinition>()).map(\.name) == ["Cable Shrug"])
    }

    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SidesSettlementTests-\(UUID().uuidString)")!
    }

    @Test func runningItDeletesTheUnusedAndMarksTheRestOnce() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let unused = ExerciseDefinition.insertPlainSetsAndReps(name: "Typed Once", orderIndex: 0, in: context)
        let used = ExerciseDefinition.insertPlainSetsAndReps(name: "Split Squat", orderIndex: 1, in: context)
        used.sides = .both
        let session = WorkoutSession(name: "Legs")
        context.insert(session)

        // An empty entry of the unused one, paired with the used one.
        let supersetID = UUID()
        let empty = ExerciseEntry(name: "Typed Once", orderIndex: 0, definitionID: unused.id, supersetID: supersetID, effortScale: .levels, session: session)
        let logged = ExerciseEntry(name: "Split Squat", orderIndex: 1, definitionID: used.id, supersetID: supersetID, effortScale: .levels, session: session)
        context.insert(empty)
        context.insert(logged)
        logged.notes = "felt good"
        try context.save()

        let defaults = scratchDefaults()
        try SidesSettlement.runOnce(in: context, defaults: defaults)

        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        #expect(definitions.map(\.name) == ["Split Squat"])
        #expect(used.sides == .either)
        #expect(try context.fetch(FetchDescriptor<ExerciseEntry>()).map(\.name) == ["Split Squat"])
        #expect(logged.supersetID == nil)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).count == 1)

        // Once: a later run leaves a decision alone.
        used.sides = .one
        try SidesSettlement.runOnce(in: context, defaults: defaults)
        #expect(used.sides == .one)
    }
}
