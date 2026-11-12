import SwiftUI

/// The period filter beside the "History" header: the presets, the last
/// custom range when there is one, and the way back into picking a range.
struct HistoryPeriodMenu: View {
    @Binding var period: HistoryPeriod
    let customStart: Date?
    let customEnd: Date?
    /// "Custom Range…" — the caller shows the picker.
    let onPickRange: () -> Void

    var body: some View {
        Menu {
            ForEach(HistoryPeriod.presets) { preset in
                Button {
                    period = preset
                } label: {
                    menuLabel(preset.menuTitle, checked: period == preset)
                }
            }

            Divider()

            // The saved range and the editor are two different things: one
            // re-applies what was last picked, the other goes back to picking.
            // Sharing a row made "All" look as if a range were still armed.
            if let title = rangeTitle {
                Button {
                    period = .custom
                } label: {
                    menuLabel(title, checked: period == .custom)
                }
            }

            Button(action: onPickRange) {
                Text(HistoryPeriod.custom.menuTitle)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: period == .all
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
                Text(buttonTitle)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .textCase(nil)
        }
        // A menu inside a section header would otherwise inherit the header's
        // uppercasing and muted colour and stop reading as a control.
        .textCase(nil)
    }

    private var rangeTitle: String? {
        Self.rangeTitle(start: customStart, end: customEnd)
    }

    private var buttonTitle: String {
        guard period == .custom, let rangeTitle else { return period.buttonTitle }
        return rangeTitle
    }

    private func menuLabel(_ title: String, checked: Bool) -> some View {
        Group {
            if checked {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    /// A range that still runs up to today reads as "Since …"; once it closes
    /// in the past both ends have to be named. `nil` without a saved start.
    static func rangeTitle(
        start: Date?,
        end: Date?,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let start else { return nil }
        func short(_ date: Date) -> String { shortDate(date, now: now, calendar: calendar, locale: locale) }
        guard let end, !calendar.isDate(end, inSameDayAs: now) else {
            return "Since \(short(start))"
        }
        if calendar.isDate(start, inSameDayAs: end) {
            return short(start)
        }
        return "\(short(start)) – \(short(end))"
    }

    /// The year is dropped in the current year, so a two-ended range still fits
    /// beside the section title.
    private static func shortDate(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.month(.abbreviated).day()
        } else {
            style = style.year().month(.abbreviated).day()
        }
        return date.formatted(style)
    }
}
