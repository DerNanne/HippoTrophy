import Foundation

/// How an exercise will look in a workout, made up out of its fields, so the
/// editor can show what a choice means instead of explaining it.
struct ExercisePreview: Equatable {
    struct Cell: Equatable {
        /// What the value is; `nil` where the value says so itself.
        var title: String?
        var value: String
    }

    struct Row: Equatable {
        /// The set's number; `nil` for an exercise without sets.
        var number: Int?
        var cells: [Cell]
    }

    /// Three sets for an exercise with sets, because one numbered row does not
    /// yet read as a list; a single row without a number for one without.
    /// Nothing at all without a field to show.
    let rows: [Row]

    init(fields: [(label: String, type: FieldType)], tracksSets: Bool, weightSymbol: String) {
        guard !fields.isEmpty else {
            rows = []
            return
        }
        func row(_ index: Int) -> [Cell] {
            fields.map { Self.cell(label: $0.label, type: $0.type, set: index, weightSymbol: weightSymbol) }
        }
        rows = tracksSets
            ? (0..<3).map { Row(number: $0 + 1, cells: row($0)) }
            : [Row(number: nil, cells: row(0))]
    }

    /// Made-up values, the last set a little different the way a last set is.
    private static func cell(label: String, type: FieldType, set: Int, weightSymbol: String) -> Cell {
        func pick(_ values: [String]) -> String { values[set] }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? type.displayName : trimmed
        switch type {
        case .weight, .assistance:
            return Cell(title: nil, value: "\(pick(["80", "80", "75"])) \(weightSymbol)")
        case .reps:
            return Cell(title: nil, value: "\(pick(["8", "8", "10"])) reps")
        case .number:
            return Cell(title: title, value: pick(["12", "12", "10"]))
        case .time:
            return Cell(title: title, value: pick(["1:30", "1:30", "1:15"]))
        case .text:
            return Cell(title: title, value: "Text")
        }
    }
}
