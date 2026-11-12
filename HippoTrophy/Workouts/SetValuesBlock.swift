import SwiftUI

/// An entry's sets in one list row: a table under the field labels, labelled
/// cells when the table does not fit, or a line per field for an entry logged
/// once per workout. `SetValuesLayout` decides which.
///
/// One row rather than a row per set, because a table's columns only line up
/// inside one view; the row draws the separators the list would have.
struct SetValuesBlock: View {
    let layout: SetValuesLayout
    let groups: [SetGroup]
    let unit: WeightUnit
    let effortScale: EffortScale
    /// Hidden for an exercise that logs once per workout.
    var showsNumber = true
    /// The weight as printed, when the caller has something to add to it —
    /// the history's per-side reading.
    var weightText: ((SetEntry) -> String?)?
    /// The sets to mark as the personal record — the history's.
    var recordSetIDs: Set<UUID> = []

    /// The natural width of every cell of the table, by column and line, so
    /// each column is as wide as its widest cell. Measured rather than left to
    /// `Grid`, which either leaves the table at its narrowest or shares the
    /// row's spare width out over every column, pushing the values apart.
    @State private var cellWidths: [CellKey: CGFloat] = [:]
    /// The row's width, and the width the table needs at its narrowest. Until
    /// both are known the table is assumed to fit.
    @State private var rowWidth: CGFloat?
    @State private var tableWidth: CGFloat?

    private static let spacing: CGFloat = 8

    var body: some View {
        switch layout {
        case .table(let columns):
            // A long value or large text can push a table past the screen's
            // edge; then every value takes its label along instead. The table
            // is measured out of sight to know, and the row by a container
            // that keeps the width it is offered — measured on the table
            // itself, a table too wide would widen the row with it.
            OfferedWidth {
                if tableFits {
                    table(columns)
                } else {
                    cells(columns)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .background {
                table(columns)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tableWidth = $0 }
            }
        case .cells(let columns):
            cells(columns)
        case .list(let columns):
            list(columns)
        }
    }

    private var showsEffort: Bool {
        effortScale != .off
    }

    private var tableFits: Bool {
        guard let rowWidth, let tableWidth else { return true }
        return tableWidth <= rowWidth
    }

    // MARK: - Table

    /// A cell of the table: its column — `nil` for the effort's — and its
    /// line, a set's id or the header.
    private struct CellKey: Hashable {
        let column: String?
        let line: String
    }

    private func width(of column: String?) -> CGFloat? {
        cellWidths.filter { $0.key.column == column }.values.max()
    }

    /// Lays `content` out at its natural width, records that width, and gives
    /// it the column's.
    private func cell(_ column: String?, line: String, @ViewBuilder content: () -> some View) -> some View {
        content()
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                cellWidths[CellKey(column: column, line: line)] = width
            }
            .frame(width: width(of: column), alignment: .trailing)
    }

    private func table(_ columns: [SetValuesColumn]) -> some View {
        VStack(spacing: 0) {
            // Sets with nothing logged leave nothing to label.
            if !columns.isEmpty {
                HStack(spacing: Self.spacing) {
                    Spacer(minLength: 0)
                    if showsEffort {
                        Color.clear
                            .frame(width: width(of: nil) ?? 0, height: 0)
                    }
                    ForEach(columns) { column in
                        cell(column.key, line: "header") {
                            Text(column.label)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 12)
                // Each set reads its labels out with its values.
                .accessibilityHidden(true)
            }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Divider()
                }
                switch line {
                case .title(let title):
                    sideTitle(title)
                case .set(let set):
                    tableRow(set, columns: columns)
                }
            }
        }
    }

    private func tableRow(_ set: SetEntry, columns: [SetValuesColumn]) -> some View {
        let line = set.id.uuidString
        return HStack(spacing: Self.spacing) {
            SetLabel(set: set, showsNumber: showsNumber, isRecord: recordSetIDs.contains(set.id))
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsEffort {
                cell(nil, line: line) {
                    // Unrated sets keep the gauge's place, so the columns hold.
                    EffortIndicator(scale: effortScale, effort: set.effort)
                        .opacity(set.effort == nil ? 0 : 1)
                }
            }
            if set.hasValues {
                ForEach(columns) { column in
                    if let value = column.value(in: set) {
                        cell(column.key, line: line) {
                            LoggedValueText(value: value, unit: unit, weightText: weightText?(set))
                        }
                    } else {
                        Color.clear
                            .frame(width: width(of: column.key) ?? 0, height: 0)
                    }
                }
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText(for: set, columns: columns) + (recordSetIDs.contains(set.id) ? ", Personal record" : ""))
        .plannedSet(set)
    }

    // MARK: - Cells

    private func cells(_ columns: [SetValuesColumn]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Divider()
                }
                switch line {
                case .title(let title):
                    sideTitle(title)
                case .set(let set):
                    SetCellsRow(set: set, columns: columns, unit: unit, showsNumber: showsNumber, weightText: weightText, recordSetIDs: recordSetIDs)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - List

    /// The one set of an entry logged once per workout, a line per field. The
    /// effort, when rated, is the last line.
    @ViewBuilder
    private func list(_ columns: [SetValuesColumn]) -> some View {
        if let set = groups.flatMap(\.sets).first {
            VStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    if index > 0 {
                        Divider()
                    }
                    if let value = column.value(in: set) {
                        // A number never breaks; when space runs out, its
                        // label does. A text may break, and its label holds.
                        let isText = value.type == .text
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(column.label)
                                .foregroundStyle(.secondary)
                                .layoutPriority(isText ? 1 : 0)
                            Spacer(minLength: 0)
                            LoggedValueText(value: value, unit: unit, weightText: weightText?(set))
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: !isText, vertical: false)
                        }
                        .padding(.vertical, 11)
                        .accessibilityElement(children: .combine)
                    }
                }
                if let effort = set.effort {
                    Divider()
                    HStack {
                        Text("Effort")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        EffortIndicator(scale: effortScale, effort: effort)
                    }
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Effort \(effort.label)")
                }
            }
        }
    }

    // MARK: - Shared

    /// The groups as one run of lines: each side's title, then its sets.
    private var lines: [Line] {
        groups.flatMap { group in
            (group.title.map { [Line.title($0)] } ?? []) + group.sets.map(Line.set)
        }
    }

    private enum Line: Identifiable {
        case title(String)
        case set(SetEntry)

        var id: String {
            switch self {
            case .title(let title): "title-\(title)"
            case .set(let set): set.id.uuidString
            }
        }
    }

    private func sideTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }

    private func spokenText(for set: SetEntry, columns: [SetValuesColumn]) -> String {
        SetValuesColumn.spokenText(for: set, columns: columns, unit: unit, weightText: weightText?(set), showsNumber: showsNumber)
    }
}

/// As wide as it is offered, whatever its content asks for. A stack or a
/// frame grows with content wider than the row; this keeps the row's width
/// measurable while the content is still too wide for it.
private struct OfferedWidth: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
