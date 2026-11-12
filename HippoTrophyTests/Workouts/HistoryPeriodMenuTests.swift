import Foundation
import Testing
@testable import HippoTrophy

/// The title a saved custom range gets in the history filter.
@MainActor
struct HistoryPeriodMenuTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func title(_ start: Date?, _ end: Date?) -> String? {
        HistoryPeriodMenu.rangeTitle(start: start, end: end, now: day(2026, 9, 14), calendar: calendar, locale: locale)
    }

    @Test func noSavedStartHasNoTitle() {
        #expect(title(nil, day(2026, 9, 1)) == nil)
    }

    @Test func aRangeRunningUpToTodayReadsSince() {
        #expect(title(day(2026, 9, 1), day(2026, 9, 14)) == "Since Sep 1")
        #expect(title(day(2026, 9, 1), nil) == "Since Sep 1")
    }

    @Test func aClosedRangeNamesBothEnds() {
        #expect(title(day(2026, 8, 3), day(2026, 8, 9)) == "Aug 3 – Aug 9")
    }

    @Test func aSingleDayIsNamedOnce() {
        #expect(title(day(2026, 8, 3), day(2026, 8, 3)) == "Aug 3")
    }

    @Test func anotherYearKeepsItsYear() {
        #expect(title(day(2025, 12, 30), day(2026, 1, 2)) == "Dec 30, 2025 – Jan 2")
    }
}
