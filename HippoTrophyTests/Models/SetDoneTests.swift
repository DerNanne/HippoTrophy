import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// A set is done or only planned. A planned set keeps its values, so a
/// workout shows what was meant; no count, history, "last time" or progress
/// reads it.
@MainActor
struct SetDoneTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @discardableResult
    private func set(
        _ number: Int, weight: Double?, reps: Double?, done: Bool, on entry: ExerciseEntry, in context: ModelContext
    ) -> SetEntry {
        let set = SetEntry(setNumber: number, isDone: done, exercise: entry)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "weight", label: "Weight", typeRawValue: "weight", orderIndex: 0, numberValue: weight, set: set))
        context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 1, numberValue: reps, set: set))
        return set
    }

    private func bench(on date: Date, in context: ModelContext) -> ExerciseEntry {
        let workout = WorkoutSession(name: "Push", date: date)
        context.insert(workout)
        let entry = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: workout)
        context.insert(entry)
        return entry
    }

    @Test func aPlannedSetShowsItsValuesButCountsNowhere() throws {
        let context = try context()
        let entry = bench(on: .now, in: context)
        let planned = set(1, weight: 80, reps: 8, done: false, on: entry, in: context)
        set(2, weight: 80, reps: 6, done: true, on: entry, in: context)

        #expect(planned.hasValues)
        #expect(!planned.hasLoggedData)
        #expect(entry.setCount == 1)
        #expect(entry.session?.setCount == 1)
        #expect(entry.doneSets.map(\.setNumber) == [2])
    }

    @Test func anExerciseWithOnlyPlannedSetsWasNotTrained() throws {
        let context = try context()
        let entry = bench(on: .now, in: context)
        set(1, weight: 80, reps: 8, done: false, on: entry, in: context)

        #expect(!entry.hasLoggedData)
        #expect(!entry.belongsInHistory)
        #expect(entry.session?.exerciseCount == 0)
        #expect(ExerciseHistory.fetch(in: context).identitiesWithHistory.isEmpty)
        #expect(LastPerformance(entry: entry) == nil)
    }

    @Test func lastTimeAndProgressReadOnlyTheSetsDone() throws {
        let context = try context()
        let entry = bench(on: .now, in: context)
        set(1, weight: 80, reps: 8, done: true, on: entry, in: context)
        set(2, weight: 100, reps: 8, done: false, on: entry, in: context)

        #expect(LastPerformance(entry: entry)?.sets.map(\.weightKg) == [80])
        #expect(ExerciseProgress(entries: [entry]).points(for: .maxWeight).map(\.value) == [80])
    }

    /// Nothing of a copy — from a template, or of a workout — was trained
    /// yet; its values are where the sets start.
    @Test func aCopiedWorkoutsSetsArePlanned() throws {
        let context = try context()
        let entry = bench(on: .distantPast, in: context)
        set(1, weight: 80, reps: 8, done: true, on: entry, in: context)
        let copy = try #require(entry.session).copy(dated: .now)
        context.insert(copy)

        let copied = try #require(copy.exercises.first?.sets.first)
        #expect(!copied.isDone)
        #expect(copied.weightKg == 80)
        #expect(copy.plannedSets.count == 1)
    }

    /// A set added in the editor waits for a value or a tick; one copied
    /// there is where the next set starts.
    @Test func aSetAddedOrCopiedInTheEditorIsPlanned() throws {
        let context = try context()
        let entry = bench(on: .now, in: context)
        let done = set(1, weight: 80, reps: 8, done: true, on: entry, in: context)

        #expect(!entry.addSet(on: .both, definition: nil, in: context).isDone)
        #expect(!entry.copySet(done, in: context).isDone)
    }

    @Test func plannedSetsComeInTheWorkoutsOrder() throws {
        let context = try context()
        let workout = WorkoutSession()
        context.insert(workout)
        let second = ExerciseEntry(name: "Row", orderIndex: 1, definitionID: UUID(), effortScale: .off, session: workout)
        let first = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: workout)
        context.insert(second)
        context.insert(first)
        set(2, weight: 1, reps: 1, done: false, on: first, in: context)
        set(1, weight: 1, reps: 1, done: true, on: first, in: context)
        set(1, weight: 1, reps: 1, done: false, on: second, in: context)

        #expect(workout.plannedSets.map { "\($0.exercise?.name ?? "") \($0.setNumber)" } == ["Bench 2", "Row 1"])
    }
}
