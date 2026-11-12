import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The rules behind the activity grid on the start screen, on a fixed calendar
/// and a fixed "now": Monday, 14 September 2026, weeks starting on Monday.
@MainActor
struct ActivityGridTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var now: Date { day(2026, 9, 14, hour: 12) }

    private func grid(_ activity: [(date: Date, count: Int)] = []) -> ActivityGrid {
        ActivityGrid(activity: activity, weeks: 53, now: now, calendar: calendar, locale: locale)
    }

    @Test func fiftyThreeWeeksOfSevenDaysEndingInThisWeek() throws {
        let weeks = grid().weeks
        #expect(weeks.count == 53)
        #expect(weeks.allSatisfy { $0.days.count == 7 })
        #expect(weeks.last?.start == day(2026, 9, 14))
        #expect(weeks.first?.start == day(2025, 9, 15))
        #expect(weeks.allSatisfy { calendar.component(.weekday, from: $0.start) == 2 })
    }

    @Test func todayIsMarkedAndTheRestOfTheWeekIsFuture() throws {
        let days = try #require(grid().weeks.last?.days)
        #expect(days.map(\.isToday) == [true, false, false, false, false, false, false])
        #expect(days.map(\.isFuture) == [false, true, true, true, true, true, true])
    }

    @Test func workoutsOnOneDayAddUp() throws {
        let data = grid([
            (date: day(2026, 9, 8, hour: 7), count: 3),
            (date: day(2026, 9, 8, hour: 18), count: 2),
            (date: day(2026, 9, 9), count: 1),
        ])
        let week = try #require(data.weeks.first { $0.start == day(2026, 9, 7) })
        #expect(week.days.map(\.setCount) == [0, 5, 1, 0, 0, 0, 0])
        #expect(data.maxCount == 5)
    }

    @Test func aDayIsLookedUpWithTheCountItHasNow() {
        // The only workout on Sep 8 is deleted: the day is still there, empty.
        let before = grid([(date: day(2026, 9, 8, hour: 7), count: 1)])
        let after = grid()
        #expect(before.day(on: day(2026, 9, 8))?.setCount == 1)
        #expect(after.day(on: day(2026, 9, 8))?.setCount == 0)
    }

    @Test func aDateOutsideTheGridFindsNoDay() {
        // The first column is the week of Sep 15, 2025; a week on, it is gone.
        let nextWeek = ActivityGrid(activity: [], weeks: 53, now: day(2026, 9, 21, hour: 12), calendar: calendar, locale: locale)
        #expect(grid().day(on: day(2025, 9, 15)) != nil)
        #expect(nextWeek.day(on: day(2025, 9, 15)) == nil)
        #expect(grid().day(on: day(2026, 9, 21)) == nil)
    }

    @Test func monthLabelsKeepThreeColumnsApartAndSkipNoMonth() {
        let weeks = grid().weeks
        let labelled = weeks.enumerated().compactMap { index, week in
            week.monthLabel.map { (index: index, start: week.start, label: $0) }
        }

        #expect(labelled.first?.index == 0)
        #expect(labelled.first?.label == "Sep")
        for (previous, next) in zip(labelled, labelled.dropFirst()) {
            #expect(next.index - previous.index >= 4)
            let months = calendar.dateComponents([.month], from: calendar.startOfMonth(previous.start), to: calendar.startOfMonth(next.start)).month
            #expect(months == 1)
        }
        // Every label names the month its column starts in.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        #expect(labelled.allSatisfy { formatter.string(from: $0.start) == $0.label })
    }

    @Test func aMonthStartingTooSoonAfterALabelWaitsAColumn() throws {
        // Sep 15 is labelled; October's first Monday, Oct 6, is only three
        // columns on, so "Oct" lands on Oct 13.
        let weeks = grid().weeks
        #expect(weeks[3].start == day(2025, 10, 6))
        #expect(weeks[3].monthLabel == nil)
        #expect(weeks[4].monthLabel == "Oct")
    }

    @Test func shadingIsInQuartersOfTheBusiestDay() {
        let data = grid([(date: day(2026, 9, 1), count: 8)])
        #expect([0, 1, 2, 3, 4, 5, 6, 8].map(data.level(for:)) == [0, 1, 2, 2, 3, 3, 4, 4])
    }

    @Test func withOneSetAsTheBusiestDayAnyActivityIsFull() {
        let data = grid([(date: day(2026, 9, 1), count: 1)])
        #expect(data.level(for: 1) == 4)
        #expect(data.level(for: 0) == 0)
    }

    @Test func aDayWithAFieldExerciseCountsOne() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let session = WorkoutSession(date: day(2026, 9, 10))
        context.insert(session)
        let run = ExerciseEntry(name: "Run", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
        context.insert(run)
        let set = SetEntry(setNumber: 1, exercise: run)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "f1", label: "Distance", typeRawValue: "number", orderIndex: 0, numberValue: 5, set: set))
        let skipped = ExerciseEntry(name: "Squat", notes: "skipped", orderIndex: 1, definitionID: UUID(), effortScale: .off, session: session)
        context.insert(skipped)
        context.insert(SetEntry(setNumber: 1, exercise: skipped))

        let data = ActivityGrid(sessions: [session], weeks: 53, now: now, calendar: calendar, locale: locale)
        let week = try #require(data.weeks.first { $0.start == day(2026, 9, 7) })
        #expect(week.days[3].setCount == 1)
    }

    /// The grid and the list count alike: a day is the sum of what its
    /// workouts say under their names, whatever they hold — a once-per-workout
    /// row, an empty set, an exercise added and forgotten.
    @Test func aDayIsTheSumOfItsWorkouts() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        func entry(_ name: String, in session: WorkoutSession, values: [Double?]) {
            let entry = ExerciseEntry(name: name, orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
            context.insert(entry)
            for (index, value) in values.enumerated() {
                let set = SetEntry(setNumber: index + 1, exercise: entry)
                context.insert(set)
                context.insert(FieldValue(fieldKey: "f1", label: "Reps", typeRawValue: "reps", orderIndex: 0, numberValue: value, set: set))
            }
        }
        let morning = WorkoutSession(date: day(2026, 9, 10, hour: 7))
        let evening = WorkoutSession(date: day(2026, 9, 10, hour: 18))
        context.insert(morning)
        context.insert(evening)
        entry("Squat", in: morning, values: [5, 5, 5])
        entry("Running", in: morning, values: [30])
        entry("Bench Press", in: evening, values: [8, 8, nil])
        entry("Lat Pulldown", in: evening, values: [])

        let data = ActivityGrid(sessions: [morning, evening], weeks: 53, now: now, calendar: calendar, locale: locale)
        let week = try #require(data.weeks.first { $0.start == day(2026, 9, 7) })
        #expect(morning.summary == "2 exercises • 4 sets")
        #expect(evening.summary == "1 exercise • 2 sets")
        #expect(week.days[3].setCount == morning.setCount + evening.setCount)
    }
}

private extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))!
    }
}
