import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The one place that answers "what has been logged": by identity for history
/// and "last time" — a catalog exercise's key, an own exercise's name — by
/// definition for sync and merging.
@MainActor
struct ExerciseHistoryTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @discardableResult
    private func entry(
        _ name: String,
        on day: Int,
        reps: Double? = nil,
        notes: String = "",
        mode: UnilateralMode = .bilateral,
        definitionID: UUID = UUID(),
        catalogKey: String? = nil,
        in context: ModelContext
    ) -> ExerciseEntry {
        let session = WorkoutSession(date: Date(timeIntervalSinceReferenceDate: Double(day) * 86_400))
        context.insert(session)
        let entry = ExerciseEntry(name: name, notes: notes, orderIndex: 0, definitionID: definitionID, effortScale: .off, catalogKey: catalogKey, session: session)
        entry.unilateralMode = mode
        context.insert(entry)
        let set = SetEntry(setNumber: 1, exercise: entry)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 0, numberValue: reps, set: set))
        return entry
    }

    @Test func identitiesWithHistoryCountAValueOrANoteButNotAnEmptyEntry() throws {
        let context = try context()
        entry("Squat", on: 1, reps: 5, in: context)
        entry("Plank", on: 1, notes: "skipped, back hurt", in: context)
        entry("Curl", on: 1, in: context)

        #expect(ExerciseHistory.fetch(in: context).identitiesWithHistory == [.own("squat"), .own("plank")])
    }

    @Test func theWorkoutOnScreenIsNotItsOwnHistory() throws {
        let context = try context()
        let today = entry("Squat", on: 2, reps: 5, in: context)

        let history = ExerciseHistory.fetch(in: context, excludingSession: today.session?.id)
        #expect(history.identitiesWithHistory.isEmpty)
        #expect(history.lastPerformances.isEmpty)
    }

    /// A template holds values to start from, not a performance: it opens no
    /// history and is never "last time" — but whatever happens to its
    /// exercise reaches it, so it is among the entries of its definition.
    @Test func aTemplateIsNoHistoryButFollowsItsExercise() throws {
        let context = try context()
        let definitionID = UUID()
        let planned = entry("Squat", on: 9, reps: 5, definitionID: definitionID, in: context)
        planned.session?.isTemplate = true
        let trained = entry("Squat", on: 1, reps: 3, definitionID: definitionID, in: context)

        let history = ExerciseHistory.fetch(in: context)
        #expect(history.entries(of: .own("squat")).map(\.id) == [trained.id])
        #expect(history.lastLogged(of: .own("squat"))?.id == trained.id)
        #expect(Set(history.entries(loggedFrom: definitionID).map(\.id)) == [trained.id, planned.id])
        #expect(history.entries(loggedFrom: definitionID).trainedWorkoutCount == 1)

        trained.session.map(context.delete)
        try context.save()
        #expect(ExerciseHistory.fetch(in: context).identitiesWithHistory.isEmpty)
    }

    @Test func historyFollowsTheNameWhateverTheCaseNewestFirst() throws {
        let context = try context()
        let old = entry("Bench Press", on: 1, reps: 5, in: context)
        let new = entry("bench press ", on: 3, notes: "light", in: context)
        entry("Bench Press", on: 2, in: context)
        entry("Incline Bench Press", on: 4, reps: 5, in: context)

        let entries = ExerciseHistory.fetch(in: context).entries(of: ExerciseIdentity(name: "BENCH PRESS", catalogKey: nil))
        #expect(entries.map(\.id) == [new.id, old.id])
    }

    @Test func lastTimeIsTheNewestMeasuredEntryNotANote() throws {
        let context = try context()
        entry("Row", on: 1, reps: 10, mode: .bilateral, in: context)
        let measured = entry("Row", on: 2, reps: 8, mode: .perSide, in: context)
        entry("Row", on: 3, notes: "only a note", in: context)

        let history = ExerciseHistory.fetch(in: context)
        #expect(history.lastLogged(of: .own("row"))?.id == measured.id)
        #expect(history.lastPerformances[.own("row")]?.date == measured.session?.date)
        #expect(history.lastPerformances[.own("row")]?.mode == .perSide)
    }

    /// A catalog exercise is its key: the name it was logged under, in
    /// whatever language or spelling the catalog had then, does not split it.
    @Test func aCatalogExercisesHistoryFollowsTheKeyNotTheName() throws {
        let context = try context()
        let english = entry("Barbell Bench Press", on: 1, reps: 5, catalogKey: "barbell-bench-press", in: context)
        let german = entry("Bankdrücken (Langhantel)", on: 2, reps: 6, catalogKey: "barbell-bench-press", in: context)

        let history = ExerciseHistory.fetch(in: context)
        #expect(history.entries(of: .catalog("barbell-bench-press")).map(\.id) == [german.id, english.id])
        #expect(history.lastPerformances[.catalog("barbell-bench-press")]?.date == german.session?.date)
    }

    /// The other way round: an own exercise that happens to carry a catalog
    /// exercise's name is not that catalog exercise.
    @Test func anOwnExerciseUnderACatalogNameIsNotTheCatalogExercise() throws {
        let context = try context()
        let catalog = entry("Barbell Bench Press", on: 1, reps: 5, catalogKey: "barbell-bench-press", in: context)
        let own = entry("Barbell Bench Press", on: 2, reps: 5, in: context)

        let history = ExerciseHistory.fetch(in: context)
        #expect(history.entries(of: .catalog("barbell-bench-press")).map(\.id) == [catalog.id])
        #expect(history.entries(of: .own("barbell bench press")).map(\.id) == [own.id])
    }

    @Test func aDefinitionsEntriesAreFoundByIdEvenUnderAnotherName() throws {
        let context = try context()
        let definitionID = UUID()
        let renamed = entry("Old Name", on: 1, definitionID: definitionID, in: context)
        entry("Old Name", on: 2, in: context)

        #expect(ExerciseHistory.fetch(in: context).entries(loggedFrom: definitionID).map(\.id) == [renamed.id])
    }

    @Test func aFailedSaveMessageLeadsWithWhatWasBeingDone() {
        struct Failure: LocalizedError { var errorDescription: String? { "disk full" } }
        #expect(ModelContext.failureMessage("Could not add set.", Failure()) == "Could not add set.\n\ndisk full")
    }
}
