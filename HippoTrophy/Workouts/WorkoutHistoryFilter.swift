import Foundation

/// The period the history list is narrowed to. Stored raw in `UserDefaults`, so
/// the cases carry stable string values that survive a rename.
enum HistoryPeriod: String, CaseIterable, Identifiable {
    case all
    case lastWeek
    case lastMonth
    case custom

    var id: String { rawValue }

    /// Presets offered before the custom entry; `custom` is reached through its
    /// own menu item because it needs a date first.
    static let presets: [HistoryPeriod] = [.all, .lastWeek, .lastMonth]

    var menuTitle: String {
        switch self {
        case .all: "All"
        case .lastWeek: "Last Week"
        case .lastMonth: "Last Month"
        case .custom: "Custom Range…"
        }
    }

    /// Shown next to the filter icon, so the active period is readable without
    /// opening the menu.
    var buttonTitle: String {
        switch self {
        case .all: "All"
        case .lastWeek: "Last Week"
        case .lastMonth: "Last Month"
        case .custom: "Custom"
        }
    }

    /// How the visible entries are divided up. A longer list needs the coarser
    /// grouping to stay readable, which is why a month range groups by month.
    var grouping: HistoryGrouping {
        switch self {
        case .all: .none
        case .lastWeek: .week
        case .lastMonth, .custom: .month
        }
    }
}

/// The calendar unit the visible entries are divided by.
enum HistoryGrouping {
    case none
    case week
    case month
}

/// The half-open span of dates a period covers. `nil` on either side means the
/// list is not bounded there, which is what keeps "All" the unfiltered list it
/// has always been.
struct HistoryBounds {
    let start: Date?
    /// Exclusive, so a chosen end day counts in full without needing 23:59:59.
    let endExclusive: Date?

    func contains(_ date: Date) -> Bool {
        if let start, date < start { return false }
        if let endExclusive, date >= endExclusive { return false }
        return true
    }
}

/// Turns a period into the dates still shown. Everything here works on
/// `Calendar.current`: the activity graph already lays its weeks out by the
/// device's first weekday, and a second week definition on the same screen
/// would put the grouping at odds with the graph above it.
enum HistoryPeriodRange {
    /// A week or month range covers *at least* the past week or month and is
    /// then widened to the start of the oldest calendar unit it touches, so the
    /// first group is never a stump of a few days. Only a custom range closes
    /// at the top; the presets always run up to now.
    static func bounds(
        for period: HistoryPeriod,
        customStart: Date?,
        customEnd: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HistoryBounds {
        switch period {
        case .all:
            return HistoryBounds(start: nil, endExclusive: nil)
        case .lastWeek:
            // Today plus the six days before it, then back to the week's start.
            guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: now) else {
                return HistoryBounds(start: nil, endExclusive: nil)
            }
            let start = calendar.dateInterval(of: .weekOfYear, for: sevenDaysAgo)?.start
                ?? calendar.startOfDay(for: sevenDaysAgo)
            return HistoryBounds(start: start, endExclusive: nil)
        case .lastMonth:
            guard let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) else {
                return HistoryBounds(start: nil, endExclusive: nil)
            }
            let start = calendar.dateInterval(of: .month, for: monthAgo)?.start
                ?? calendar.startOfDay(for: monthAgo)
            return HistoryBounds(start: start, endExclusive: nil)
        case .custom:
            // The chosen days count in full: the range opens at the start day's
            // midnight and closes at the midnight after the end day.
            let start = customStart.map { calendar.startOfDay(for: $0) }
            let endExclusive = customEnd.flatMap {
                calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
            }
            return HistoryBounds(start: start, endExclusive: endExclusive)
        }
    }
}

/// One run of sessions that share a calendar week or month.
struct HistoryGroup: Identifiable {
    /// The start of the group's calendar unit, which also orders the groups.
    let id: Date
    /// `nil` while the list is ungrouped, so the rows render without a header.
    let title: String?
    let sessions: [WorkoutSession]
}

enum HistoryGrouper {
    /// Splits already date-sorted sessions into groups. Sessions keep their
    /// incoming order, so a newest-first list stays newest-first.
    static func groups(
        for sessions: [WorkoutSession],
        grouping: HistoryGrouping,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HistoryGroup] {
        guard grouping != .none, !sessions.isEmpty else {
            return [HistoryGroup(id: .distantPast, title: nil, sessions: sessions)]
        }

        let component: Calendar.Component = grouping == .week ? .weekOfYear : .month
        var groups: [HistoryGroup] = []

        for session in sessions {
            let start = calendar.dateInterval(of: component, for: session.date)?.start
                ?? calendar.startOfDay(for: session.date)

            if let last = groups.last, last.id == start {
                groups[groups.count - 1] = HistoryGroup(
                    id: start,
                    title: last.title,
                    sessions: last.sessions + [session]
                )
            } else {
                groups.append(
                    HistoryGroup(
                        id: start,
                        title: title(forGroupStarting: start, grouping: grouping, now: now, calendar: calendar),
                        sessions: [session]
                    )
                )
            }
        }

        return groups
    }

    private static func title(
        forGroupStarting start: Date,
        grouping: HistoryGrouping,
        now: Date,
        calendar: Calendar
    ) -> String {
        switch grouping {
        case .none:
            return ""
        case .week:
            if calendar.isDate(start, equalTo: now, toGranularity: .weekOfYear) {
                return "This Week"
            }
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return "\(start.formatted(day)) – \(end.formatted(day))"
        case .month:
            if calendar.isDate(start, equalTo: now, toGranularity: .year) {
                return start.formatted(.dateTime.month(.wide))
            }
            return start.formatted(.dateTime.month(.wide).year())
        }
    }
}
