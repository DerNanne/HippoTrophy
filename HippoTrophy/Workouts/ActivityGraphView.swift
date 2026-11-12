import SwiftUI

/// A GitHub-style contribution grid: one cell per day for the last twelve
/// months, columns are weeks, rows are weekdays. A cell is shaded by how many
/// sets of one category were logged that day, relative to the busiest day in
/// the range, in the category's colour. Turning to another graph is left to
/// whoever shows this one: `headerGesture` is laid on the header,
/// `accessory` sits at its end.
struct ActivityGraphView<Accessory: View, HeaderGesture: Gesture>: View {
    let category: CategoryFilter.Option
    /// What each workout is worth in `category` — see `ActivityGrid.activity`.
    let activity: [(date: Date, count: Int)]
    /// Whether any of the graph can be seen. Going out of view puts the grid
    /// back on the current month and lets go of a tapped day, so a graph
    /// turned back to starts as it would afresh — out of sight, where the
    /// jump does not show.
    let isInView: Bool
    let headerGesture: HeaderGesture
    /// The adjustable action's turn, for VoiceOver: 1 for the next graph, -1
    /// for the one before.
    let onTurn: (Int) -> Void
    @ViewBuilder let accessory: Accessory

    @AppStorage(SettingsKey.showActivityWeekdays) private var showWeekdays = true
    @AppStorage(SettingsKey.showActivityLegend) private var showLegend = false
    /// Only the date: the day itself is looked up in the current grid, so
    /// deleting a workout shows in the header as it does in the cell.
    @State private var selectedDate: Date?
    @State private var scrollPosition = ScrollPosition(edge: .trailing)

    private static var cellSize: CGFloat { 12 }
    private static var cellSpacing: CGFloat { 3 }
    private static var weekWidth: CGFloat { cellSize + cellSpacing }
    private static var weeksShown: Int { 53 }
    /// Height of the month label row plus the spacing below it, so the weekday
    /// column starts level with the first row of cells.
    private static var monthLabelHeight: CGFloat { 16 }

    private var grid: ActivityGrid {
        ActivityGrid(activity: activity, weeks: Self.weeksShown, now: .now, calendar: .current, locale: .current)
    }

    /// Built-in categories bring their own colour; a custom one and "No
    /// Category" are grey, as their badge is.
    private var tint: Color {
        category?.tint ?? .secondary
    }

    var body: some View {
        let grid = self.grid
        let selectedDay = selectedDate.flatMap(grid.day(on:))

        VStack(alignment: .leading, spacing: 8) {
            header(for: selectedDay)
            // The weekday column stays put outside the scroller; only the grid
            // scrolls sideways.
            HStack(alignment: .top, spacing: 6) {
                if showWeekdays {
                    weekdayLabels
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        monthLabels(for: grid)
                        HStack(alignment: .top, spacing: Self.cellSpacing) {
                            ForEach(grid.weeks) { week in
                                VStack(spacing: Self.cellSpacing) {
                                    ForEach(week.days) { day in
                                        cell(for: day, in: grid)
                                    }
                                }
                            }
                        }
                    }
                    // Month names sit above the first week of their month and are
                    // allowed to run past that column, so the row needs the slack.
                    .padding(.trailing, 28)
                }
                .scrollPosition($scrollPosition)
                .defaultScrollAnchor(.trailing)
            }
            if showLegend {
                legend
            }
        }
        .padding(.vertical, 4)
        // A date the grid has moved past stays unselected, rather than coming
        // back if it ever reappears.
        .onChange(of: selectedDay) { _, day in
            if day == nil { selectedDate = nil }
        }
        .onChange(of: isInView) { _, inView in
            guard !inView else { return }
            selectedDate = nil
            scrollPosition.scrollTo(edge: .trailing)
        }
    }

    /// The title with its detail a step fainter, laid out as one line of text
    /// rather than two concatenated `Text`s, which iOS 26 retired.
    private func headerLine(_ title: String, detail: String) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .foregroundStyle(.primary)
            Text(" · \(detail)")
                .foregroundStyle(.secondary)
        }
    }

    /// The category's symbol, then the title or the tapped day. The whole
    /// row takes the drag that turns to the next graph: the grid below
    /// already scrolls sideways through the year.
    private func header(for selectedDay: ActivityDay?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: CategoryFilter.symbolName(of: category))
                .foregroundStyle(tint)
            Group {
                if let selectedDay {
                    headerLine(
                        selectedDay.date.formatted(date: .abbreviated, time: .omitted),
                        detail: CountFormat.text(selectedDay.setCount, "set", "sets")
                    )
                } else {
                    headerLine("\(CategoryFilter.name(of: category)) — last 12 months", detail: "by sets")
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .font(.caption.weight(.medium))
        .contentShape(Rectangle())
        .gesture(headerGesture)
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onTurn(1)
            case .decrement: onTurn(-1)
            @unknown default: break
            }
        }
    }

    /// The weekday names in the same order the cells are stacked, which starts
    /// at the locale's first weekday rather than a fixed Monday.
    private static var weekdayNames: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % symbols.count] }
    }

    private var weekdayLabels: some View {
        VStack(spacing: Self.cellSpacing) {
            ForEach(Self.weekdayNames, id: \.self) { name in
                Text(name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(height: Self.cellSize)
            }
        }
        .padding(.top, Self.monthLabelHeight)
        .accessibilityHidden(true)
    }

    private func monthLabels(for grid: ActivityGrid) -> some View {
        HStack(alignment: .bottom, spacing: Self.cellSpacing) {
            ForEach(grid.weeks) { week in
                Text(week.monthLabel ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: Self.cellSize, alignment: .leading)
            }
        }
        // A fixed height like the cells and the weekday names: grown with the
        // text size, the row pushed the cells down past the weekday column,
        // and Saturday read as Sunday.
        .frame(height: Self.monthLabelHeight - 4, alignment: .bottom)
    }

    private func cell(for day: ActivityDay, in grid: ActivityGrid) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(for: day, in: grid))
            .frame(width: Self.cellSize, height: Self.cellSize)
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(tint, lineWidth: 1.5)
                }
            }
            .opacity(day.isFuture ? 0.35 : 1)
            .onTapGesture {
                guard !day.isFuture else { return }
                selectedDate = selectedDate == day.date ? nil : day.date
            }
            .accessibilityLabel(
                "\(day.date.formatted(date: .abbreviated, time: .omitted)), \(CountFormat.text(day.setCount, "set", "sets"))"
            )
    }

    private func color(for day: ActivityDay, in grid: ActivityGrid) -> Color {
        color(forLevel: grid.level(for: day.setCount))
    }

    private func color(forLevel level: Int) -> Color {
        switch level {
        case 1: return tint.opacity(0.25)
        case 2: return tint.opacity(0.45)
        case 3: return tint.opacity(0.7)
        case 4: return tint
        default: return Color(.tertiarySystemFill)
        }
    }

    private var legend: some View {
        HStack(spacing: Self.cellSpacing) {
            Spacer()
            Text("Less")
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(forLevel: level))
                    .frame(width: Self.cellSize, height: Self.cellSize)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
