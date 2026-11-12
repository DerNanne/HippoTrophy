import Foundation
import Testing
@testable import HippoTrophy

/// Calendar logic, pinned to a fixed calendar and a fixed "now" — the app reads
/// `Calendar.current`, so a test that did the same would pass or fail by the
/// machine it ran on.
struct HistoryRangeTests {
    /// Monday-first, UTC, so week starts are the same everywhere.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // 2026-09-10 is a Thursday.
    private var now: Date { date(2026, 9, 10) }

    @Test func allIsUnbounded() {
        let bounds = HistoryPeriodRange.bounds(
            for: .all, customStart: nil, customEnd: nil, now: now, calendar: calendar
        )
        #expect(bounds.start == nil)
        #expect(bounds.endExclusive == nil)
        #expect(bounds.contains(date(1999, 1, 1)))
    }

    /// Today plus six days back is 2026-09-04 (Friday), widened to that week's
    /// Monday — so the first group is a whole week rather than a stump.
    @Test func lastWeekOpensAtAWeekStart() {
        let bounds = HistoryPeriodRange.bounds(
            for: .lastWeek, customStart: nil, customEnd: nil, now: now, calendar: calendar
        )
        #expect(bounds.start == date(2026, 8, 31, 0))
        #expect(bounds.endExclusive == nil)
        #expect(bounds.contains(now))
        #expect(bounds.contains(date(2026, 12, 24)))
        #expect(!bounds.contains(date(2026, 8, 30)))
    }

    @Test func lastMonthOpensAtAMonthStart() {
        let bounds = HistoryPeriodRange.bounds(
            for: .lastMonth, customStart: nil, customEnd: nil, now: now, calendar: calendar
        )
        #expect(bounds.start == date(2026, 8, 1, 0))
        #expect(bounds.endExclusive == nil)
    }

    /// Both chosen days count in full: the range opens at the start day's
    /// midnight and closes at the midnight after the end day.
    @Test func aCustomRangeCountsBothEndDaysWhole() {
        let bounds = HistoryPeriodRange.bounds(
            for: .custom,
            customStart: date(2026, 9, 1, 18),
            customEnd: date(2026, 9, 3, 6),
            now: now,
            calendar: calendar
        )
        #expect(bounds.start == date(2026, 9, 1, 0))
        #expect(bounds.endExclusive == date(2026, 9, 4, 0))
        #expect(bounds.contains(date(2026, 9, 1, 0)))
        #expect(bounds.contains(date(2026, 9, 3, 23)))
        #expect(!bounds.contains(date(2026, 8, 31, 23)))
        #expect(!bounds.contains(date(2026, 9, 4, 0)))
    }

    @Test func aHalfOpenCustomRangeStaysOpenOnThatSide() {
        let onlyStart = HistoryPeriodRange.bounds(
            for: .custom, customStart: date(2026, 9, 1), customEnd: nil, now: now, calendar: calendar
        )
        #expect(onlyStart.endExclusive == nil)
        #expect(onlyStart.contains(date(2030, 1, 1)))

        let onlyEnd = HistoryPeriodRange.bounds(
            for: .custom, customStart: nil, customEnd: date(2026, 9, 1), now: now, calendar: calendar
        )
        #expect(onlyEnd.start == nil)
        #expect(onlyEnd.contains(date(1999, 1, 1)))
    }

    // MARK: - Grouping

    private func session(_ day: Date) -> WorkoutSession {
        WorkoutSession(name: "Session", date: day)
    }

    @Test func ungroupedKeepsOneHeaderlessRun() {
        let sessions = [session(now), session(date(2026, 8, 1))]
        let groups = HistoryGrouper.groups(
            for: sessions, grouping: .none, now: now, calendar: calendar
        )
        #expect(groups.count == 1)
        #expect(groups[0].title == nil)
        #expect(groups[0].sessions.count == 2)
    }

    @Test func anEmptyListStaysOneHeaderlessRun() {
        let groups = HistoryGrouper.groups(
            for: [], grouping: .week, now: now, calendar: calendar
        )
        #expect(groups.count == 1)
        #expect(groups[0].title == nil)
        #expect(groups[0].sessions.isEmpty)
    }

    @Test func sessionsInOneWeekShareAGroup() {
        let sessions = [
            session(date(2026, 9, 10)),  // Thu
            session(date(2026, 9, 7)),   // Mon, same week
            session(date(2026, 9, 6))    // Sun, the week before
        ]
        let groups = HistoryGrouper.groups(
            for: sessions, grouping: .week, now: now, calendar: calendar
        )
        #expect(groups.count == 2)
        #expect(groups[0].sessions.count == 2)
        #expect(groups[0].id == date(2026, 9, 7, 0))
        #expect(groups[1].sessions.count == 1)
        #expect(groups[1].id == date(2026, 8, 31, 0))
    }

    @Test func monthGroupingSplitsAtTheMonthBoundary() {
        let sessions = [
            session(date(2026, 9, 2)),
            session(date(2026, 8, 30)),
            session(date(2026, 8, 1))
        ]
        let groups = HistoryGrouper.groups(
            for: sessions, grouping: .month, now: now, calendar: calendar
        )
        #expect(groups.count == 2)
        #expect(groups[0].sessions.count == 1)
        #expect(groups[1].sessions.count == 2)
    }

    /// A newest-first list stays newest-first, inside the groups as well.
    @Test func groupingKeepsTheIncomingOrder() {
        let newest = session(date(2026, 9, 10))
        let older = session(date(2026, 9, 8))
        let groups = HistoryGrouper.groups(
            for: [newest, older], grouping: .week, now: now, calendar: calendar
        )
        #expect(groups[0].sessions.first?.date == newest.date)
        #expect(groups[0].sessions.last?.date == older.date)
    }
}
