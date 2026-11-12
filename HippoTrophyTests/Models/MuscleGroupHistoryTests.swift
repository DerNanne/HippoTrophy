import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// A muscle group's history, on a fixed calendar: weeks start on Monday, and
/// day 0 is Monday, 1 January 2001 — the reference date.
@MainActor
struct MuscleGroupHistoryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func date(_ day: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(day) * 86_400 + 3_600)
    }

    private func session(on day: Int, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(date: date(day))
        context.insert(session)
        return session
    }

    @discardableResult
    private func definition(
        _ name: String, _ muscles: [MuscleGroup], secondary: [MuscleGroup] = [], category: String = "Strength", in context: ModelContext
    ) -> ExerciseDefinition {
        let definition = ExerciseDefinition(
            name: name, orderIndex: 0, categoryName: category,
            muscleGroupNames: muscles.map(\.rawValue), secondaryMuscleGroupNames: secondary.map(\.rawValue)
        )
        context.insert(definition)
        return definition
    }

    @discardableResult
    private func entry(
        _ name: String,
        in session: WorkoutSession,
        order: Int = 0,
        sets reps: [Double?] = [8],
        notes: String = "",
        context: ModelContext
    ) -> ExerciseEntry {
        let entry = ExerciseEntry(name: name, notes: notes, orderIndex: order, definitionID: UUID(), effortScale: .off, session: session)
        context.insert(entry)
        for (index, value) in reps.enumerated() {
            let set = SetEntry(setNumber: index + 1, exercise: entry)
            context.insert(set)
            context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 0, numberValue: value, set: set))
        }
        return entry
    }

    private func history(in context: ModelContext, categories: CategoryFilter? = nil) throws -> MuscleGroupHistory {
        MuscleGroupHistory(
            entries: try context.fetch(FetchDescriptor<ExerciseEntry>()),
            definitions: try context.fetch(FetchDescriptor<ExerciseDefinition>()),
            categories: categories
        )
    }

    @Test func aSetCountsInFullForEveryMuscleItsExerciseTrains() throws {
        let context = try context()
        definition("Deadlift", [.back, .hamstrings, .glutes], in: context)
        entry("Deadlift", in: session(on: 0, in: context), sets: [5, 5, 5], context: context)

        let history = try history(in: context)
        for muscle in [MuscleGroup.back, .hamstrings, .glutes] {
            #expect(history.setsThisWeek(training: muscle, now: date(2), calendar: calendar) == 3)
        }
        #expect(history.setsThisWeek(training: .chest, now: date(2), calendar: calendar) == 0)
    }

    /// A template's sets are a plan, not training: no muscle counts them.
    @Test func aTemplateTrainsNoMuscle() throws {
        let context = try context()
        definition("Deadlift", [.back], in: context)
        let template = session(on: 0, in: context)
        template.isTemplate = true
        entry("Deadlift", in: template, sets: [5, 5, 5], context: context)

        let history = try history(in: context)
        #expect(history.setsThisWeek(training: .back, now: date(2), calendar: calendar) == 0)
        #expect(history.setCount(training: .back, since: nil) == .zero)
        #expect(history.workouts(training: .back).isEmpty)
    }

    /// Three sets of squats: three main sets for Quads and Glutes, three
    /// secondary ones for Adductors — in the week, in the period, and in the
    /// workout's figure. Weighed, the secondary ones are worth one and a half.
    @Test func aSetCountsAsSecondaryForAMuscleItOnlyHelps() throws {
        let context = try context()
        definition("Squat", [.quads, .glutes], secondary: [.adductors], in: context)
        entry("Squat", in: session(on: 0, in: context), sets: [5, 5, 5], context: context)

        let history = try history(in: context)
        let secondary = MuscleSets(main: 0, secondary: 3)
        #expect(history.setsThisWeek(training: .quads, now: date(2), calendar: calendar) == 3)
        #expect(history.setsThisWeek(training: .adductors, now: date(2), calendar: calendar) == secondary)
        #expect(history.setCount(training: .adductors, since: nil) == secondary)
        #expect(history.setCount(training: .adductors, since: nil).weighted == 1.5)
        #expect(history.workouts(training: .adductors).map(\.sets) == [secondary])
        #expect(history.muscles(of: try #require(context.fetch(FetchDescriptor<ExerciseEntry>()).first)) == [.quads, .glutes, .adductors])
        #expect(history.unfiledNames.isEmpty)
    }

    @Test func aCategoryFilterLeavesOutWhatItDoesNotPick() throws {
        let context = try context()
        definition("Squat", [.quads], in: context)
        definition("Bike Ergometer", [.quads, .calves], category: "Cardio", in: context)
        definition("Plank", [.core], category: "", in: context)
        let workout = session(on: 0, in: context)
        entry("Squat", in: workout, order: 0, sets: [5, 5, 5], context: context)
        entry("Bike Ergometer", in: workout, order: 1, sets: [1], context: context)
        entry("Plank", in: workout, order: 2, sets: [1], context: context)
        entry("Lunge", in: workout, order: 3, sets: [8], context: context)

        let strength = try history(in: context, categories: .standard)
        #expect(strength.setCount(training: .quads, since: nil) == 3)
        #expect(strength.setCount(training: .calves, since: nil) == 0)
        #expect(strength.unfiledNames.isEmpty)

        var withCardioAndNone = CategoryFilter.standard
        withCardioAndNone.toggle(.cardio)
        withCardioAndNone.toggle(nil)
        let wider = try history(in: context, categories: withCardioAndNone)
        #expect(wider.setCount(training: .quads, since: nil) == 4)
        #expect(wider.setCount(training: .core, since: nil) == 1)
        #expect(wider.unfiledNames == ["Lunge"])

        #expect(try history(in: context).setCount(training: .quads, since: nil) == 4)
    }

    @Test func musclesAreReadFromTheExerciseByNameWhateverTheCase() throws {
        let context = try context()
        definition("Bench Press", [.chest, .triceps], in: context)
        let logged = entry(" bench press", in: session(on: 0, in: context), context: context)

        let history = try history(in: context)
        #expect(history.muscles(of: logged) == [.chest, .triceps])
        #expect(history.workouts(training: .triceps).count == 1)
    }

    @Test func workoutsComeNewestFirstWithOnlyTheirEntriesForTheMuscleInOrder() throws {
        let context = try context()
        definition("Bench Press", [.chest], in: context)
        definition("Fly", [.chest], in: context)
        definition("Squat", [.quads], in: context)

        let old = session(on: 0, in: context)
        entry("Bench Press", in: old, context: context)
        let new = session(on: 3, in: context)
        let fly = entry("Fly", in: new, order: 2, context: context)
        entry("Squat", in: new, order: 1, context: context)
        let bench = entry("Bench Press", in: new, order: 0, context: context)

        let workouts = try history(in: context).workouts(training: .chest)
        #expect(workouts.map(\.id) == [new.id, old.id])
        #expect(workouts.first?.entries.map(\.id) == [bench.id, fly.id])
    }

    @Test func aNoteKeepsAWorkoutInTheListButIsNotATrainedMuscle() throws {
        let context = try context()
        definition("Row", [.back], in: context)
        entry("Row", in: session(on: 0, in: context), sets: [10], context: context)
        let skipped = session(on: 4, in: context)
        entry("Row", in: skipped, sets: [nil], notes: "skipped, back hurt", context: context)
        entry("Row", in: session(on: 5, in: context), sets: [nil], context: context)

        let history = try history(in: context)
        #expect(history.workouts(training: .back).map(\.id).first == skipped.id)
        #expect(history.workouts(training: .back).count == 2)
        #expect(history.lastTrained(.back) == date(0))
        #expect(history.workouts(training: .back).first?.sets == 0)
    }

    @Test func weeksRunOldestFirstToThisWeekWithEmptyWeeksAsZero() throws {
        let context = try context()
        definition("Curl", [.biceps], in: context)
        entry("Curl", in: session(on: 1, in: context), sets: [10, 10], context: context)
        entry("Curl", in: session(on: 6, in: context), sets: [10], context: context)
        entry("Curl", in: session(on: 15, in: context), sets: [8, 8, 8, 8], context: context)

        let weeks = try history(in: context).weeks(training: .biceps, count: 4, now: date(16), calendar: calendar)
        #expect(weeks.map(\.sets) == [0, 3, 0, 4])
        #expect(weeks.last?.start == calendar.startOfDay(for: date(14)))
    }

    @Test func emptySetsAreNotCounted() throws {
        let context = try context()
        definition("Curl", [.biceps], in: context)
        entry("Curl", in: session(on: 0, in: context), sets: [10, nil], context: context)

        #expect(try history(in: context).setsThisWeek(training: .biceps, now: date(0), calendar: calendar) == 1)
    }

    @Test func exercisesWithoutMusclesOrWithoutADefinitionAreNamedAsUnfiled() throws {
        let context = try context()
        definition("Plank", [], in: context)
        definition("Squat", [.quads], in: context)
        entry("plank", in: session(on: 0, in: context), context: context)
        entry("Plank", in: session(on: 2, in: context), context: context)
        entry("Arm Circles", in: session(on: 1, in: context), context: context)
        entry("Squat", in: session(on: 1, in: context), context: context)
        entry("Forgotten", in: session(on: 1, in: context), sets: [nil], context: context)

        #expect(try history(in: context).unfiledNames == ["Arm Circles", "Plank"])
    }
}
