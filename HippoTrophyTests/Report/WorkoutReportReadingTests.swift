import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// How the report reads a workout out of the store: only the sets that count
/// make it in, so the report counts and prints what the rest of the app counts.
@MainActor
struct WorkoutReportReadingTests {
    private func context() throws -> ModelContext {
        ModelContext(
            try ModelContainer(
                for: Schema(AppSchema.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }

    private func entry(_ name: String, at index: Int, superset: UUID? = nil, in context: ModelContext, session: WorkoutSession) -> ExerciseEntry {
        let entry = ExerciseEntry(name: name, orderIndex: index, definitionID: UUID(), supersetID: superset, effortScale: .off, session: session)
        context.insert(entry)
        return entry
    }

    /// A set of weight training; `nil` leaves both fields standing but empty.
    private func weightSet(_ number: Int, _ weightAndReps: (Double, Double)?, position: Int? = nil, in context: ModelContext, of entry: ExerciseEntry) {
        let set = SetEntry(setNumber: number, supersetPosition: position, exercise: entry)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "weight", label: "Weight", typeRawValue: "weight", orderIndex: 0, numberValue: weightAndReps?.0, set: set))
        context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 1, numberValue: weightAndReps?.1, set: set))
    }

    /// "Push B" from the coverage backup: a bench press with an empty fourth
    /// set, and a lat pulldown added and forgotten.
    @Test func anEmptySetIsNeitherPrintedNorCounted() throws {
        let context = try context()
        let session = WorkoutSession(name: "Push B")
        context.insert(session)
        let bench = entry("Bench Press", at: 0, in: context, session: session)
        weightSet(1, (80, 8), in: context, of: bench)
        weightSet(2, (80, 8), in: context, of: bench)
        weightSet(3, (80, 7), in: context, of: bench)
        weightSet(4, nil, in: context, of: bench)
        _ = entry("Lat Pulldown", at: 1, in: context, session: session)

        let data = WorkoutReportData(session: session, unit: .kilograms)
        #expect(data.exercises.map(\.name) == ["Bench Press"])
        #expect(data.exercises[0].sets.map(\.number) == [1, 2, 3])
        #expect(data.exerciseCount == session.exerciseCount)
        #expect(data.setCount == session.setCount)
        #expect(data.skippedNames.isEmpty)
    }

    /// An exercise whose sets are all empty is not trained, even with the
    /// fields of weight training standing in them.
    @Test func anExerciseWithOnlyEmptySetsIsLeftOut() throws {
        let context = try context()
        let session = WorkoutSession(name: "Push")
        context.insert(session)
        let bench = entry("Bench Press", at: 0, in: context, session: session)
        weightSet(1, nil, in: context, of: bench)
        weightSet(2, nil, in: context, of: bench)

        let data = WorkoutReportData(session: session, unit: .kilograms)
        #expect(data.exercises.isEmpty)
        #expect(data.exerciseCount == 0)
        #expect(data.setCount == 0)
    }

    @Test func aSupersetReadsInTheOrderItWasDone() throws {
        let context = try context()
        let session = WorkoutSession(name: "Push")
        context.insert(session)
        let pair = UUID()
        let curl = entry("Curl", at: 0, superset: pair, in: context, session: session)
        let pushdown = entry("Pushdown", at: 1, superset: pair, in: context, session: session)
        weightSet(1, (10, 10), position: 1, in: context, of: curl)
        weightSet(1, (20, 12), position: 2, in: context, of: pushdown)
        weightSet(2, (20, 12), position: 3, in: context, of: pushdown)
        weightSet(2, (10, 8), position: 4, in: context, of: curl)

        let data = WorkoutReportData(session: session, unit: .kilograms)
        guard case .superset(let superset) = try #require(data.items.first) else {
            Issue.record("expected a superset")
            return
        }
        #expect(superset.rows.map(\.label) == ["A1", "B1", "B2", "A2"])
    }

    /// Sets paired before positions were written read as rounds, A then B,
    /// as `SupersetPair` reads them for the editor.
    @Test func setsPairedWithoutPositionsReadAsRounds() throws {
        let context = try context()
        let session = WorkoutSession(name: "Push")
        context.insert(session)
        let pair = UUID()
        let curl = entry("Curl", at: 0, superset: pair, in: context, session: session)
        let pushdown = entry("Pushdown", at: 1, superset: pair, in: context, session: session)
        weightSet(1, (10, 10), in: context, of: curl)
        weightSet(2, (10, 8), in: context, of: curl)
        weightSet(3, (10, 6), in: context, of: curl)
        weightSet(1, (20, 12), in: context, of: pushdown)

        let data = WorkoutReportData(session: session, unit: .kilograms)
        guard case .superset(let superset) = try #require(data.items.first) else {
            Issue.record("expected a superset")
            return
        }
        #expect(superset.rows.map(\.label) == ["A1", "B1", "A2", "A3"])
    }

    /// "Push A" from the coverage backup, imported as a tester would: both
    /// of its supersets, one printed whole, one with a partner that logs
    /// only reps.
    @Test func pushAFromTheCoverageBackup() throws {
        let context = try context()
        try CoverageBackup.importFile(try CoverageBackup.read(), into: context)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        let session = try #require(sessions.first { $0.name == "Push A" })

        let data = WorkoutReportData(session: session, unit: .kilograms)
        let items = data.items.map { item -> String in
            switch item {
            case .exercise(let exercise):
                exercise.name + (exercise.supersetPartner.map { " (with \($0))" } ?? "")
            case .superset(let superset):
                "\(superset.a.name) + \(superset.b.name): " + superset.rows.map(\.label).joined(separator: " ")
            }
        }
        #expect(items == [
            "Barbell Bench Press",
            "Pull-Up + Cable Fly: A1 B1 A2 A3 B2",
            "Dumbbell Row (with Push-Up)",
        ])
        #expect(data.skippedNames == ["Push-Up", "Farmer's Carry", "Rowing Erg"])
    }
}
