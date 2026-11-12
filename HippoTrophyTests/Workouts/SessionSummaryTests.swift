import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// What the app counts in a session — its sets and exercises, and the line
/// under a workout built from them — and the line the editor shows under an
/// exercise name.
///
/// Both need real relationships, so these run against an in-memory store rather
/// than loose objects.
@MainActor
struct SessionSummaryTests {
    private func context() throws -> ModelContext {
        ModelContext(
            try ModelContainer(
                for: Schema(AppSchema.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }

    @discardableResult
    private func session(in context: ModelContext, date: Date = .now) -> WorkoutSession {
        let session = WorkoutSession(name: "Session", date: date)
        context.insert(session)
        return session
    }

    private func entry(_ name: String, in context: ModelContext, session: WorkoutSession?) -> ExerciseEntry {
        let entry = ExerciseEntry(name: name, orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
        context.insert(entry)
        return entry
    }

    /// A set of weight training: the two standard fields, filled.
    @discardableResult
    private func weightSet(_ number: Int, reps: Int, weightKg: Double, in context: ModelContext, of entry: ExerciseEntry) -> SetEntry {
        let set = SetEntry(setNumber: number, exercise: entry)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "weight", label: "Weight", typeRawValue: "weight", orderIndex: 0, numberValue: weightKg == 0 ? nil : weightKg, set: set))
        context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 1, numberValue: reps == 0 ? nil : Double(reps), set: set))
        return set
    }

    // MARK: - setCount and exerciseCount

    @Test func everyLoggedSetCounts() throws {
        let context = try context()
        let session = session(in: context)
        let squat = entry("Squat", in: context, session: session)
        for number in 1...3 {
            weightSet(number, reps: 5, weightKg: 60, in: context, of: squat)
        }

        #expect(session.setCount == 3)
        #expect(session.exerciseCount == 1)
    }

    /// An exercise that logs once per workout has one set, and counts as one —
    /// but only once something was actually logged in it.
    @Test func aOncePerWorkoutExerciseCountsAsOne() throws {
        let context = try context()
        let session = session(in: context)
        let rowing = entry("Rowing Machine", in: context, session: session)
        let set = SetEntry(setNumber: 1, exercise: rowing)
        context.insert(set)
        let time = FieldValue(fieldKey: "f1", label: "Time", typeRawValue: "time", orderIndex: 0, set: set)
        context.insert(time)
        #expect(session.setCount == 0)
        #expect(session.exerciseCount == 0)

        time.numberValue = 480
        #expect(session.setCount == 1)
        #expect(session.exerciseCount == 1)
    }

    @Test func anEmptySetDoesNotCount() throws {
        let context = try context()
        let session = session(in: context)
        let squat = entry("Squat", in: context, session: session)
        weightSet(1, reps: 5, weightKg: 60, in: context, of: squat)
        weightSet(2, reps: 0, weightKg: 0, in: context, of: squat)

        #expect(session.setCount == 1)
    }

    /// Added and forgotten, or skipped with a note: still on the workout's page,
    /// but not an exercise trained.
    @Test func anExerciseWithoutASetThatCountsIsNoExercise() throws {
        let context = try context()
        let session = session(in: context)
        let squat = entry("Squat", in: context, session: session)
        weightSet(1, reps: 5, weightKg: 60, in: context, of: squat)
        _ = entry("Lat Pulldown", in: context, session: session)
        let bench = entry("Bench Press", in: context, session: session)
        weightSet(1, reps: 0, weightKg: 0, in: context, of: bench)
        let row = entry("Row", in: context, session: session)
        row.notes = "skipped, shoulder"

        #expect(session.exercises.count == 4)
        #expect(session.exerciseCount == 1)
        #expect(session.setCount == 1)
    }

    @Test func anEmptySessionIsWorthNothing() throws {
        let context = try context()
        #expect(session(in: context).setCount == 0)
        #expect(session(in: context).exerciseCount == 0)
    }

    // MARK: - summary

    @Test func theSummaryCountsOneInTheSingular() throws {
        let context = try context()
        let session = session(in: context)
        let squat = entry("Squat", in: context, session: session)
        weightSet(1, reps: 5, weightKg: 60, in: context, of: squat)

        #expect(session.summary == "1 exercise • 1 set")
    }

    @Test func theSummaryCountsSeveralInThePlural() throws {
        let context = try context()
        let session = session(in: context)
        let squat = entry("Squat", in: context, session: session)
        let bench = entry("Bench Press", in: context, session: session)
        for number in 1...3 {
            weightSet(number, reps: 5, weightKg: 60, in: context, of: squat)
        }
        weightSet(1, reps: 5, weightKg: 40, in: context, of: bench)

        #expect(session.summary == "2 exercises • 4 sets")
    }

    /// The workout from 1 October 2026 that showed "4 sets" in the list and
    /// "5 sets" in the grid: the run's one row is a set in both now.
    @Test func theSummaryCountsARunAsOneSet() throws {
        let context = try context()
        let session = session(in: context)
        let bench = entry("Bench Press", in: context, session: session)
        weightSet(1, reps: 5, weightKg: 60, in: context, of: bench)
        let squat = entry("Squat", in: context, session: session)
        for number in 1...3 {
            weightSet(number, reps: 5, weightKg: 80, in: context, of: squat)
        }
        let running = entry("Running", in: context, session: session)
        let row = SetEntry(setNumber: 1, exercise: running)
        context.insert(row)
        context.insert(FieldValue(fieldKey: "f1", label: "Distance", typeRawValue: "number", orderIndex: 0, numberValue: 5, set: row))

        #expect(session.summary == "3 exercises • 5 sets")
    }

    /// Nothing logged reads as zero of each, in the plural.
    @Test func aWorkoutWithNothingLoggedSummarisesAsZero() throws {
        let context = try context()
        let session = session(in: context)
        let rowing = entry("Rowing Machine", in: context, session: session)
        context.insert(SetEntry(setNumber: 1, exercise: rowing))

        #expect(session.summary == "0 exercises • 0 sets")
    }

    // MARK: - LastPerformance

    private func performance(daysAgo: Int, in context: ModelContext) throws -> LastPerformance {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let session = session(in: context, date: date)
        let squat = entry("Squat", in: context, session: session)
        weightSet(1, reps: 5, weightKg: 60, in: context, of: squat)
        return try #require(LastPerformance(entry: squat))
    }

    @Test func theAgeReadsInDaysNearTheBoundaries() throws {
        let context = try context()
        #expect(try performance(daysAgo: 0, in: context).age(now: .now) == "today")
        #expect(try performance(daysAgo: 1, in: context).age(now: .now) == "yesterday")
        #expect(try performance(daysAgo: 2, in: context).age(now: .now) == "2 days ago")
        #expect(try performance(daysAgo: 13, in: context).age(now: .now) == "13 days ago")
    }

    @Test func pastTwoWeeksItCountsInWeeks() throws {
        let context = try context()
        #expect(try performance(daysAgo: 14, in: context).age(now: .now) == "2 weeks ago")
        #expect(try performance(daysAgo: 62, in: context).age(now: .now) == "8 weeks ago")
    }

    /// Past a couple of months the distance stops meaning anything, so the line
    /// hands over to the date — which no longer contains the word "ago".
    @Test func pastTwoMonthsItShowsTheDate() throws {
        let context = try context()
        let old = try performance(daysAgo: 63, in: context).age(now: .now)
        #expect(!old.contains("ago"))
        #expect(!old.isEmpty)
    }

    /// A set list that is all empty reads as "not logged", not as a session at
    /// zero kilograms.
    @Test func anEmptySetListIsNoPerformanceAtAll() throws {
        let context = try context()
        let session = session(in: context)
        let squat = entry("Squat", in: context, session: session)
        weightSet(1, reps: 0, weightKg: 0, in: context, of: squat)

        #expect(LastPerformance(entry: squat) == nil)
    }

    @Test func anEntryWithoutASessionHasNoPerformance() throws {
        let context = try context()
        let squat = entry("Squat", in: context, session: nil)
        weightSet(1, reps: 5, weightKg: 60, in: context, of: squat)

        #expect(LastPerformance(entry: squat) == nil)
    }

    @Test func weightTrainingReadsAsSets() throws {
        let context = try context()
        let session = session(in: context)
        let squat = entry("Squat", in: context, session: session)
        for number in 1...3 {
            weightSet(number, reps: 8, weightKg: 60, in: context, of: squat)
        }
        let performance = try #require(LastPerformance(entry: squat))
        #expect(performance.summary(unit: .kilograms).hasSuffix("3×8 @ 60 kg"))
    }

    /// VoiceOver says the sets in words, so a single one has to read as one.
    @Test func theSpokenLineCountsOneSetInTheSingular() throws {
        let context = try context()
        let session = session(in: context)
        let squat = entry("Squat", in: context, session: session)
        weightSet(1, reps: 8, weightKg: 60, in: context, of: squat)
        weightSet(2, reps: 6, weightKg: 60, in: context, of: squat)
        weightSet(3, reps: 6, weightKg: 60, in: context, of: squat)

        let performance = try #require(LastPerformance(entry: squat))
        #expect(performance.spokenSummary(unit: .kilograms).hasSuffix(
            "1 set of 8 at 60 kilograms, 2 sets of 6 at 60 kilograms"
        ))
    }

    /// An exercise without weight and reps gets its line from the fields that
    /// were actually filled in.
    @Test func otherFieldsReadAsValues() throws {
        let context = try context()
        let session = session(in: context)
        let rowing = entry("Rowing Machine", in: context, session: session)
        let set = SetEntry(setNumber: 1, exercise: rowing)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "time", label: "Time", typeRawValue: "time", orderIndex: 0, numberValue: 480, set: set))
        context.insert(FieldValue(fieldKey: "dist", label: "Distance", typeRawValue: "number", orderIndex: 1, set: set))

        let performance = try #require(LastPerformance(entry: rowing))
        #expect(performance.sets.isEmpty)
        #expect(performance.fields == [LastPerformance.Field(label: "Time", text: "8:00")])
    }

    private func assistedSet(_ number: Int, reps: Int, assistanceKg: Double, in context: ModelContext, of entry: ExerciseEntry) {
        let set = SetEntry(setNumber: number, exercise: entry)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "weight", label: "Assist", typeRawValue: "assistance", orderIndex: 0, numberValue: assistanceKg, set: set))
        context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 1, numberValue: Double(reps), set: set))
    }

    @Test func assistedSetsReadAsSetsWithTheirHelp() throws {
        let context = try context()
        let session = session(in: context)
        let pullUp = entry("Pull-Up", in: context, session: session)
        pullUp.assistance = .machine
        assistedSet(1, reps: 8, assistanceKg: 25, in: context, of: pullUp)
        assistedSet(2, reps: 8, assistanceKg: 25, in: context, of: pullUp)
        assistedSet(3, reps: 6, assistanceKg: 20, in: context, of: pullUp)

        let performance = try #require(LastPerformance(entry: pullUp))
        #expect(performance.performance(unit: .kilograms) == "2×8 @ 25 kg assist · 1×6 @ 20 kg assist")
        #expect(performance.spokenPerformance(unit: .kilograms) == "2 sets of 8 with 25 kilograms of assistance, 1 set of 6 with 20 kilograms of assistance")
    }
}
