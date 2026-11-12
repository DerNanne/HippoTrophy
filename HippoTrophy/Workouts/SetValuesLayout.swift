import Foundation

/// How a read-only list shows what one exercise entry logged — the workout
/// page and the exercise history.
///
/// The labels go on top of a table, once, and each set's values line up
/// beneath them — weight and reps as much as any other field, so a set reads
/// `40 kg` and `10` under Weight and Reps rather than `40 kg x10`. Only so
/// many columns fit beside the set number, and past that each value carries
/// its own label instead. An entry logged once per workout has no sets to line
/// up and lists its fields.
enum SetValuesLayout: Equatable {
    /// The labels once on top, each set's values in columns beneath. With no
    /// columns — nothing logged in any set — each set reads as a dash.
    case table([SetValuesColumn])
    /// Each value with its label underneath, three to a line, the way the
    /// editor lays out its fields.
    case cells([SetValuesColumn])
    /// A line per field, label on the left and value on the right.
    case list([SetValuesColumn])

    /// How many columns fit beside "Set 1" and the effort on the narrowest
    /// phone. A table that is still too wide — long values, large text — falls
    /// back to cells where it is drawn.
    static let maxTableColumns = 3

    /// How many labelled cells stand on one line, the way the editor lays out
    /// its fields.
    static let cellsPerLine = 3

    /// - Parameters:
    ///   - sets: the sets the list shows, in their order.
    ///   - tracksSets: whether the exercise logs sets; one that does not holds
    ///     exactly one.
    init(sets: [SetEntry], tracksSets: Bool) {
        let columns = SetValuesColumn.columns(of: sets)
        if !tracksSets && sets.count <= 1 && !columns.isEmpty {
            self = .list(columns)
        } else if columns.count <= Self.maxTableColumns {
            self = .table(columns)
        } else {
            self = .cells(columns)
        }
    }

    var columns: [SetValuesColumn] {
        switch self {
        case .table(let columns), .cells(let columns), .list(let columns): columns
        }
    }
}

/// One field of an entry as the read-only lists show it: the key its values
/// are stored under, the label on top, and the type that decides how a value
/// reads.
struct SetValuesColumn: Equatable, Identifiable {
    let key: String
    let label: String
    let type: FieldType

    var id: String { key }

    /// The fields the sets logged something in, in the exercise's order. A
    /// field left empty in every set has nothing to show and gets no column;
    /// one filled in a single set is a column for all of them.
    static func columns(of sets: [SetEntry]) -> [SetValuesColumn] {
        var found: [String: (order: Int, column: SetValuesColumn)] = [:]
        for value in sets.flatMap(\.sortedValues) where !value.isEmpty {
            if let known = found[value.fieldKey], known.order <= value.orderIndex { continue }
            found[value.fieldKey] = (value.orderIndex, SetValuesColumn(key: value.fieldKey, label: value.label, type: value.type))
        }
        return found.values
            .sorted { ($0.order, $0.column.key) < ($1.order, $1.column.key) }
            .map(\.column)
    }

    /// The columns one header can name for the sets of a superset, which take
    /// turns between two exercises: the columns of the one that logs more,
    /// when the other logs nothing it lacks — a pull-up's reps under a row's
    /// weight and reps. Nil when each logs something of its own, since a
    /// header half of whose columns are blank in every other set explains
    /// nothing, and when they do not fit on one line of cells; then every
    /// value keeps its own label. A text gets a line of its own beneath its
    /// set and is not counted.
    static func shared(by a: [SetValuesColumn], and b: [SetValuesColumn]) -> [SetValuesColumn]? {
        let (more, fewer) = a.count >= b.count ? (a, b) : (b, a)
        guard fewer.allSatisfy(more.contains),
              more.filter({ $0.type != .text }).count <= SetValuesLayout.cellsPerLine
        else { return nil }
        return more
    }

    /// This field's value in `set`, when something was logged in it.
    func value(in set: SetEntry) -> FieldValue? {
        set.values.first { $0.fieldKey == key && !$0.isEmpty }
    }

    /// What VoiceOver reads for one set: its number, each logged value after
    /// its label, then the effort — one sentence instead of a walk across the
    /// columns, which a table reads in no useful order.
    static func spokenText(
        for set: SetEntry,
        columns: [SetValuesColumn],
        unit: WeightUnit,
        weightText: String? = nil,
        showsNumber: Bool
    ) -> String {
        var parts: [String] = []
        if showsNumber {
            parts.append("Set \(set.setNumber)")
        }
        for column in columns {
            guard let value = column.value(in: set) else { continue }
            let text = column.type == .weight ? weightText ?? value.displayText(unit: unit) : value.displayText(unit: unit)
            parts.append("\(column.label) \(text)")
        }
        if !set.hasValues {
            parts.append("Nothing logged")
        }
        if let effort = set.effort {
            parts.append("Effort \(effort.label)")
        }
        return parts.joined(separator: ", ")
    }
}

/// The sets of an entry as the read-only lists show them: one run for an
/// entry logged on both sides at once, a run per side under its title for
/// one logged per side.
///
/// The workout page shows every set, a planned one greyed out: it tells what
/// that workout was meant to be. An exercise's history shows only the sets
/// done — `doneOnly` — since it follows what was trained, like the graph
/// above it. A side left without a set done drops out with its title.
struct SetGroup: Identifiable {
    let title: String?
    let sets: [SetEntry]

    var id: String { title ?? "" }

    static func groups(of entry: ExerciseEntry, doneOnly: Bool = false) -> [SetGroup] {
        let sorted = doneOnly ? entry.doneSets : entry.sortedSets
        guard entry.unilateralMode == .perSide else {
            return [SetGroup(title: nil, sets: sorted.filter { $0.side == .both })]
        }
        return [(SetSide.left, "Left"), (.right, "Right")].compactMap { side, title in
            let sets = sorted.filter { $0.side == side }
            return sets.isEmpty ? nil : SetGroup(title: title, sets: sets)
        }
    }
}
