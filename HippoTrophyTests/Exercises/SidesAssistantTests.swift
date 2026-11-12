import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// Sorting the own exercises into bilateral and unilateral, and what that
/// does to what was logged.
@MainActor
struct SidesAssistantTests {
    private func entry(_ mode: UnilateralMode) -> SidesAssistant.Entry {
        SidesAssistant.Entry(id: UUID(), mode: mode, date: .now, workout: "", sets: 3)
    }

    private func exercise(_ modes: [UnilateralMode], named name: String = "Curl") -> SidesAssistant.Exercise {
        SidesAssistant.Exercise(id: UUID(), name: name, muscleGroupNames: ["biceps"], entries: modes.map(entry))
    }

    /// Same Weight and left/right are one way of training: one side at a time.
    @Test func mixedMeansBilateralTogetherWithOneSided() {
        #expect(!exercise([.bilateral, .bilateral]).isMixed)
        #expect(!exercise([.oneSided, .perSide]).isMixed)
        #expect(!exercise([]).isMixed)
        #expect(exercise([.bilateral, .oneSided]).isMixed)
        #expect(exercise([.bilateral, .perSide]).isMixed)
    }

    @Test func theHistorySaysHowItWasLogged() {
        #expect(exercise([.bilateral, .perSide, .perSide]).history == "1× Bilateral, 2× L/R")
        #expect(exercise([]).history == "Never logged")
    }

    /// The mixed ones start decided, entry by entry as logged; the others
    /// wait for a swipe.
    @Test func doneWaitsForEveryExerciseLoggedOneWayAndEveryMixedOneOpened() {
        let uniform = exercise([.bilateral])
        let mixed = exercise([.bilateral, .perSide], named: "Row")
        var assistant = SidesAssistant(exercises: [uniform, mixed])
        #expect(!assistant.isComplete)
        assistant.choices[uniform.id] = .one
        #expect(!assistant.isComplete)
        assistant.markOpened(mixed)
        #expect(assistant.isComplete)
    }

    /// Deleted entries go with all their sets and leave the split to the
    /// rest: with the left/right entry gone, nothing moves.
    @Test func aDeletedEntryIsLeftOutAndSaysSo() throws {
        let row = exercise([.bilateral, .perSide], named: "Row")
        var assistant = SidesAssistant(exercises: [row])
        let tried = row.entries[1]
        assistant.toggleDeleted(tried)
        let outcome = try #require(assistant.outcome(for: row))
        #expect(outcome.deletions == [tried.id])
        #expect(outcome.split.isEmpty)
        #expect(outcome.sides == .both)
        #expect(SidesAssistant.summary(of: outcome, name: "Row").contains { $0.isWarning && $0.text.contains("deleted") })
        #expect(assistant.isChanged(row))
        assistant.resetAsLogged(row)
        #expect(assistant.deleted.isEmpty)
    }

    /// A Bulgarian Split Squat of one's own, logged "normal": unilateral, and
    /// its entries Same Weight.
    @Test func unilateralTurnsBilateralEntriesIntoSameWeight() throws {
        let squats = exercise([.bilateral, .bilateral], named: "Split Squat")
        var assistant = SidesAssistant(exercises: [squats])
        assistant.choices[squats.id] = .one
        let outcome = try #require(assistant.outcome(for: squats))
        #expect(outcome.sides == .one)
        #expect(Set(outcome.modes.values) == [.oneSided])
        #expect(outcome.split.isEmpty)
    }

    @Test func bilateralMergesLeftAndRightAndSaysSo() throws {
        let curl = exercise([.perSide, .oneSided])
        var assistant = SidesAssistant(exercises: [curl])
        assistant.choices[curl.id] = .both
        let outcome = try #require(assistant.outcome(for: curl))
        #expect(outcome.sides == .both)
        #expect(outcome.mergedLeftRight == 1)
        let summary = SidesAssistant.summary(of: outcome, name: curl.name)
        #expect(summary.contains { $0.isWarning && $0.text.contains("merged") })
        #expect(summary.contains { !$0.isWarning && $0.text == "1 entry becomes Bilateral." })
    }

    /// Left as logged, a mixed exercise splits: the bilateral entries keep
    /// the name, the others go to a new unilateral one.
    @Test func aMixedExerciseSplitsAsLogged() throws {
        let row = exercise([.bilateral, .perSide, .oneSided], named: "Row")
        let assistant = SidesAssistant(exercises: [row])
        let outcome = try #require(assistant.outcome(for: row))
        #expect(outcome.sides == .both)
        #expect(outcome.split == Set(row.entries.dropFirst().map(\.id)))
        #expect(outcome.modes.isEmpty)
        #expect(SidesAssistant.summary(of: outcome, name: "Row").map(\.text) == ["2 entries move to Row (Unilateral)."])
    }

    /// All on one side, nothing splits.
    @Test func decidingAllOfAMixedExerciseOneWayDoesNotSplit() throws {
        let row = exercise([.bilateral, .perSide], named: "Row")
        var assistant = SidesAssistant(exercises: [row])
        assistant.decideAll(of: row, as: .one)
        let outcome = try #require(assistant.outcome(for: row))
        #expect(outcome.sides == .one)
        #expect(outcome.split.isEmpty)
        #expect(outcome.modes == [row.entries[0].id: .oneSided])
    }

    /// Changed entry by entry, then reset: back where it started.
    @Test func resettingPutsEveryEntryBackAsLogged() {
        let row = exercise([.bilateral, .perSide], named: "Row")
        var assistant = SidesAssistant(exercises: [row])
        let start = assistant.entrySides
        #expect(!assistant.isChanged(row))
        assistant.decideAll(of: row, as: .both)
        #expect(assistant.isChanged(row))
        assistant.resetAsLogged(row)
        #expect(assistant.entrySides == start)
        #expect(!assistant.isChanged(row))
    }

    @Test func aNeverLoggedExerciseTakesTheSidePicked() throws {
        let fresh = exercise([])
        var assistant = SidesAssistant(exercises: [fresh])
        #expect(assistant.outcome(for: fresh) == nil)
        assistant.choices[fresh.id] = .one
        #expect(try #require(assistant.outcome(for: fresh)).sides == .one)
    }

    /// The backup saved from the assistant keeps an undecided exercise
    /// undecided; imported into a store again, the assistant asks again.
    @Test func aBackupFromBeforeDecidingAsksAgainWhenImported() throws {
        let schema = Schema(AppSchema.models)
        let before = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let row = ExerciseDefinition.insertPlainSetsAndReps(name: "Hebel Row", orderIndex: 0, muscleGroupNames: ["back"], in: before)
        row.sides = .either
        try before.save()

        let file = BackupExporter.file(definitions: [row], sessions: [])
        #expect(file.exercises?.first?.sides == ExerciseSides.either.rawValue)

        let after = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let plan = ImportPlanner.plan(file: file, existing: [], knownWorkoutIDs: [])
        _ = BackupImporter(context: after).apply(plan, decisions: ImportDecisions(), selection: ImportSelection())
        try after.save()
        #expect(SidesAssistant.isNeeded(in: after))
    }

    @Test func applyingDeletesTheMarkedEntries() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let row = ExerciseDefinition.insertPlainSetsAndReps(name: "Row", orderIndex: 0, muscleGroupNames: ["back"], in: context)
        row.sides = .either
        let session = WorkoutSession(name: "Back")
        context.insert(session)
        let kept = ExerciseEntry(name: "Row", orderIndex: 0, definitionID: row.id, effortScale: .levels, session: session)
        let tried = ExerciseEntry(name: "Row", orderIndex: 1, definitionID: row.id, effortScale: .levels, session: session)
        tried.unilateralMode = .perSide
        context.insert(kept)
        context.insert(tried)
        kept.notes = "real"
        tried.notes = "only tried"
        try context.save()

        var assistant = SidesAssistant.load(in: context)
        let mixed = try #require(assistant.mixed.first)
        assistant.toggleDeleted(try #require(mixed.entries.first { $0.id == tried.id }))
        assistant.markOpened(mixed)
        try assistant.apply(in: context)

        #expect(try context.fetch(FetchDescriptor<ExerciseEntry>()).map(\.id) == [kept.id])
        #expect(row.sides == .both)
        #expect(!(try context.fetch(FetchDescriptor<ExerciseDefinition>()).contains { $0.name.contains("Unilateral") }))
    }

    @Test func applyingASplitCopiesTheExerciseUnderAFreeName() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let row = ExerciseDefinition.insertPlainSetsAndReps(name: "Row", orderIndex: 0, muscleGroupNames: ["back"], in: context)
        row.sides = .either
        // The name the split would take is someone else's already.
        ExerciseDefinition.insertPlainSetsAndReps(name: "Row (Unilateral)", orderIndex: 1, in: context)
        let session = WorkoutSession(name: "Back")
        context.insert(session)
        let both = ExerciseEntry(name: "Row", orderIndex: 0, definitionID: row.id, effortScale: .levels, session: session)
        let one = ExerciseEntry(name: "Row", orderIndex: 1, definitionID: row.id, effortScale: .levels, session: session)
        one.unilateralMode = .perSide
        context.insert(both)
        context.insert(one)
        try context.save()

        let assistant = SidesAssistant.load(in: context)
        #expect(assistant.mixed.map(\.name) == ["Row"])
        try assistant.apply(in: context)

        #expect(row.sides == .both)
        let split = try #require(try context.fetch(FetchDescriptor<ExerciseDefinition>()).first { $0.name == "Row (Unilateral) 2" })
        #expect(split.sides == .one)
        #expect(split.muscleGroupNames == ["back"])
        #expect(split.isPlainSetsAndReps)
        #expect(one.definitionID == split.id)
        #expect(one.name == "Row (Unilateral) 2")
        #expect(one.unilateralMode == .perSide)
        #expect(both.definitionID == row.id)
        #expect(!SidesAssistant.isNeeded(in: context))
    }
}
