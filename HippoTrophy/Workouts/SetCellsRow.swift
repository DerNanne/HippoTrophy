import SwiftUI

/// One set with each value above its label, three to a line, the way the
/// editor lays out its fields. For a table too wide for the screen, and for a
/// set inside a superset, where the sets of two exercises take turns and no
/// table can line them up.
///
/// Every cell reads alike: the bare value over what it is. A weight goes
/// without its unit, which is its label — `60` over `kg` — and reps without
/// the `x`, over `Reps`. A text, whose length nobody knows, gets a line of its
/// own beneath.
///
/// Under a `SetCellsHeader` that names the columns once, the labels go and
/// a weight takes its unit back: `60 kg` under Weight.
struct SetCellsRow: View {
    let set: SetEntry
    let columns: [SetValuesColumn]
    let unit: WeightUnit
    var showsNumber = true
    var weightText: ((SetEntry) -> String?)?
    /// The sets to mark as the personal record — the history's.
    var recordSetIDs: Set<UUID> = []
    /// Off under a `SetCellsHeader`.
    var showsLabels = true
    @ScaledMetric(relativeTo: .body) private var cellWidth: CGFloat = SetCellsHeader.defaultCellWidth
    /// The height of a line of body text, which the gauge centres on so it
    /// sits beside the values rather than above them.
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 22

    private var cellLines: [[SetValuesColumn]] {
        let cells = columns.filter { $0.type != .text }
        let perLine = SetValuesLayout.cellsPerLine
        return stride(from: 0, to: cells.count, by: perLine).map {
            Array(cells[$0..<min($0 + perLine, cells.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                SetLabel(set: set, showsNumber: showsNumber, isRecord: recordSetIDs.contains(set.id))
                Spacer(minLength: 0)
                // Unrated sets keep the gauge's place, so the cells of an
                // entry's sets stay in columns.
                EffortIndicator(scale: set.exercise?.effortScale ?? .off, effort: set.effort)
                    .opacity(set.effort == nil ? 0 : 1)
                    .frame(height: lineHeight)
                if set.hasValues {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(cellLines.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: 6) {
                                ForEach(cellLines[index]) { column in
                                    cell(column)
                                }
                            }
                        }
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            ForEach(columns.filter { $0.type == .text }) { column in
                if let value = column.value(in: set) {
                    Text("\(Text(column.label).foregroundStyle(.secondary)) \(value.displayText(unit: unit))")
                        .font(.subheadline)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            SetValuesColumn.spokenText(for: set, columns: columns, unit: unit, weightText: weightText?(set), showsNumber: showsNumber)
        )
        .plannedSet(set)
    }

    private func cell(_ column: SetValuesColumn) -> some View {
        VStack(spacing: 0) {
            // An empty field keeps its slot, so the cells of an entry's sets
            // stay in columns.
            Text(column.value(in: set).map(bareText) ?? " ")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if showsLabels {
                Text(column.type == .weight ? unit.symbol : column.type == .assistance ? "\(unit.symbol) assist" : column.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: cellWidth)
    }

    /// The value as typed into the editor — no unit, no `x` — unless the
    /// caller has a weight of its own to show. Without a label beneath, a
    /// weight says its unit itself.
    private func bareText(_ value: FieldValue) -> String {
        if value.type == .weight, let weightText = weightText?(set) {
            return weightText
        }
        if !showsLabels, value.type == .weight || value.type == .assistance {
            return unit.formatted(kilograms: value.numberValue ?? 0)
        }
        return value.editText(unit: unit)
    }
}

/// The labels of a superset's columns, once above its sets, in the cells'
/// own widths so each label stands over its values. The text columns are left
/// out: each keeps its label on its own line beneath its set.
struct SetCellsHeader: View {
    let columns: [SetValuesColumn]
    @ScaledMetric(relativeTo: .body) private var cellWidth: CGFloat = Self.defaultCellWidth

    static let defaultCellWidth: CGFloat = 72

    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(columns.filter { $0.type != .text }) { column in
                Text(column.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: cellWidth)
            }
        }
        // Each set reads its labels out with its values.
        .accessibilityHidden(true)
    }
}
