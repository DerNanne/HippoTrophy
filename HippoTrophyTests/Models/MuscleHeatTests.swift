import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The heat map's period and shading, on a fixed calendar and a fixed "now":
/// 15 October 2026, noon.
@MainActor
struct MuscleHeatTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var now: Date { day(2026, 10, 15, hour: 12) }

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func log(_ name: String, sets: Int, on date: Date, in context: ModelContext) {
        let session = WorkoutSession(date: date)
        context.insert(session)
        let entry = ExerciseEntry(name: name, orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
        context.insert(entry)
        for number in 1...sets {
            let set = SetEntry(setNumber: number, exercise: entry)
            context.insert(set)
            context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 0, numberValue: 8, set: set))
        }
    }

    private func history(in context: ModelContext) throws -> MuscleGroupHistory {
        MuscleGroupHistory(
            entries: try context.fetch(FetchDescriptor<ExerciseEntry>()),
            definitions: try context.fetch(FetchDescriptor<ExerciseDefinition>())
        )
    }

    @Test func theSliderRunsFromAllOnTheLeftToTheLastMonthOnTheRight() {
        #expect(HeatMapPeriod.allCases == [.all, .year, .sixMonths, .threeMonths, .month])
    }

    @Test func aPeriodStartsOnTheSameDaySoManyMonthsAgoFromItsStart() {
        let first = day(2025, 3, 2, hour: 18)
        #expect(HeatMapPeriod.month.start(now: now, firstWorkout: first, calendar: calendar) == day(2026, 9, 15))
        #expect(HeatMapPeriod.threeMonths.start(now: now, firstWorkout: first, calendar: calendar) == day(2026, 7, 15))
        #expect(HeatMapPeriod.sixMonths.start(now: now, firstWorkout: first, calendar: calendar) == day(2026, 4, 15))
        #expect(HeatMapPeriod.year.start(now: now, firstWorkout: first, calendar: calendar) == day(2025, 10, 15))
    }

    @Test func allBeginsOnTheDayOfTheFirstWorkoutOrNowhere() {
        #expect(HeatMapPeriod.all.start(now: now, firstWorkout: day(2025, 3, 2, hour: 18), calendar: calendar) == day(2025, 3, 2))
        #expect(HeatMapPeriod.all.start(now: now, firstWorkout: nil, calendar: calendar) == nil)
    }

    @Test func onlyTheSetsInThePeriodCount() throws {
        let context = try context()
        context.insert(ExerciseDefinition(name: "Bench Press", orderIndex: 0, muscleGroupNames: ["chest", "triceps"]))
        log("Bench Press", sets: 3, on: day(2026, 10, 1), in: context)
        log("Bench Press", sets: 5, on: day(2026, 9, 14), in: context)

        let history = try history(in: context)
        let month = MuscleHeat(history: history, period: .month, now: now, calendar: calendar)
        #expect(month.sets(for: .chest) == 3)
        #expect(month.sets(for: .triceps) == 3)

        let all = MuscleHeat(history: history, period: .all, now: now, calendar: calendar)
        #expect(all.sets(for: .chest) == 8)
        #expect(all.start == day(2026, 9, 14))
    }

    @Test func eachMuscleIsShadedAgainstTheMostTrainedOne() throws {
        let context = try context()
        context.insert(ExerciseDefinition(name: "Squat", orderIndex: 0, muscleGroupNames: ["quads"]))
        context.insert(ExerciseDefinition(name: "Curl", orderIndex: 1, muscleGroupNames: ["biceps"]))
        context.insert(ExerciseDefinition(name: "Calf Raise", orderIndex: 2, muscleGroupNames: ["calves"]))
        log("Squat", sets: 20, on: day(2026, 10, 10), in: context)
        log("Curl", sets: 9, on: day(2026, 10, 10), in: context)
        log("Calf Raise", sets: 2, on: day(2026, 10, 10), in: context)

        let heat = MuscleHeat(history: try history(in: context), period: .month, now: now, calendar: calendar)
        #expect(heat.level(for: .quads) == 4)
        #expect(heat.level(for: .biceps) == 2)
        #expect(heat.level(for: .calves) == 1)
        #expect(heat.level(for: .chest) == 0)

        #expect(heat.share(for: .quads) == 1)
        #expect(heat.share(for: .biceps) == 0.45)
        #expect(heat.share(for: .calves) == 0.1)
        #expect(heat.share(for: .chest) == 0)
    }

    @Test func nothingTrainedIsNoShareAnywhere() throws {
        let heat = MuscleHeat(history: try history(in: try context()), period: .all, now: now, calendar: calendar)
        #expect(MuscleGroup.allCases.allSatisfy { heat.share(for: $0) == 0 })
    }

    @Test func quartilesAreTheActivityGridsRule() {
        #expect(QuartileLevel.level(0, highestCount: 10) == 0)
        #expect(QuartileLevel.level(1, highestCount: 1) == 4)
        #expect(QuartileLevel.level(2, highestCount: 10) == 1)
        #expect(QuartileLevel.level(5, highestCount: 10) == 3)
        #expect(QuartileLevel.level(10, highestCount: 10) == 4)
    }
}
