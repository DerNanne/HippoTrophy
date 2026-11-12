import Foundation

/// One day in the grid. `setCount` is the sum of that day's workouts, each
/// counted as `WorkoutSession.setCount` counts it.
struct ActivityDay: Identifiable, Equatable {
    let date: Date
    let setCount: Int
    let isToday: Bool
    let isFuture: Bool

    var id: Date { date }
}

struct ActivityWeek: Identifiable {
    let start: Date
    let days: [ActivityDay]
    /// Set on the first week that falls into a new month, unless that would
    /// crowd the previous label.
    let monthLabel: String?

    var id: Date { start }
}

/// Buckets the workout history into weeks of days, and holds the busiest day so
/// the shading can be relative to how much this person actually trains.
struct ActivityGrid {
    let weeks: [ActivityWeek]
    let maxCount: Int

    /// Reads what each workout is worth — see `WorkoutSession.setCount`.
    init(
        sessions: [WorkoutSession],
        weeks weekCount: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.init(
            activity: sessions.map { (date: $0.date, count: $0.setCount) },
            weeks: weekCount,
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    /// - Parameters:
    ///   - activity: what each workout is worth, by when it happened. Workouts
    ///     on the same day add up.
    ///   - weekCount: columns, the last one being the week of `now`, starting
    ///     on the calendar's first weekday.
    init(
        activity: [(date: Date, count: Int)],
        weeks weekCount: Int,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) {
        let today = calendar.startOfDay(for: now)

        var counts: [Date: Int] = [:]
        for workout in activity {
            let day = calendar.startOfDay(for: workout.date)
            counts[day, default: 0] += workout.count
        }

        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let firstWeekStart = calendar.date(
                  byAdding: .weekOfYear,
                  value: -(weekCount - 1),
                  to: thisWeekStart
              )
        else {
            self.weeks = []
            self.maxCount = 0
            return
        }

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.locale = locale
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")

        var builtWeeks: [ActivityWeek] = []
        var highest = 0
        var lastLabelledMonth: Int?
        var weeksSinceLabel = Int.max

        for weekIndex in 0..<weekCount {
            guard let weekStart = calendar.date(
                byAdding: .weekOfYear,
                value: weekIndex,
                to: firstWeekStart
            ) else { continue }

            var days: [ActivityDay] = []
            for dayIndex in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: dayIndex, to: weekStart) else { continue }
                let day = calendar.startOfDay(for: date)
                let count = counts[day] ?? 0
                highest = max(highest, count)
                days.append(
                    ActivityDay(
                        date: day,
                        setCount: count,
                        isToday: day == today,
                        isFuture: day > today
                    )
                )
            }

            // Label the week the month changes in, keeping three columns of air
            // so two labels never overlap.
            let month = calendar.component(.month, from: weekStart)
            var label: String?
            if month != lastLabelledMonth, weeksSinceLabel >= 3 {
                label = monthFormatter.string(from: weekStart)
                lastLabelledMonth = month
                weeksSinceLabel = 0
            } else {
                // A month whose first week comes too soon after the previous
                // label keeps its turn; it gets labelled a column later.
                weeksSinceLabel = weeksSinceLabel == .max ? .max : weeksSinceLabel + 1
            }

            builtWeeks.append(ActivityWeek(start: weekStart, days: days, monthLabel: label))
        }

        self.weeks = builtWeeks
        self.maxCount = highest
    }

    /// The day whose `date` is `date`, as this grid has it, or nil once the
    /// grid no longer reaches it. A selection holds on to the date rather than
    /// the day, so a count that changed since it was tapped is read fresh.
    func day(on date: Date) -> ActivityDay? {
        weeks.lazy.flatMap(\.days).first { $0.date == date }
    }

    /// Shaded against the busiest day in the grid — see `QuartileLevel`.
    func level(for count: Int) -> Int {
        QuartileLevel.level(count, highestCount: maxCount)
    }
}
