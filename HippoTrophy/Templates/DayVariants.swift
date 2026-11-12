import Foundation

/// A day variant is a template adjusted for one day: a copy, changed for a
/// single workout while the template stays as it is, and marked by
/// `plannedFor`. It goes once a workout is saved from it; one not used
/// stays a week and is then put away — archived, or deleted when the
/// setting says so.
enum DayVariants {
    /// How many days an unused variant stays on the shelf, its own day
    /// included.
    static let daysOnShelf = 7

    /// A variant of `template` for the day of `date`: everything it plans,
    /// under its name. Not inserted, and not on the shelf yet.
    static func variant(of template: WorkoutSession, on date: Date, calendar: Calendar = .current) -> WorkoutSession {
        let variant = template.templateCopy(named: template.name)
        variant.plannedFor = calendar.startOfDay(for: date)
        return variant
    }

    /// The variants on the shelf whose week is over on `date`.
    static func expired(on shelf: TemplateShelf, at date: Date, calendar: Calendar = .current) -> [WorkoutSession] {
        shelf.templates.filter { template in
            guard let day = template.plannedFor else { return false }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: date)).day ?? 0
            return days >= daysOnShelf
        }
    }

    /// What a variant's badge says: Today, Yesterday, or its day.
    static func label(for day: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        // The year only once it is not this one.
        if calendar.isDate(day, equalTo: now, toGranularity: .year) {
            style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        }
        return day.formatted(style)
    }
}
