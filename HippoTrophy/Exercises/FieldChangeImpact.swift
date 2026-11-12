import Foundation

/// A field being configured in the exercise editor. It only reaches a
/// `FieldDefinition` on Save.
struct FieldDraft: Identifiable {
    let id = UUID()
    var key: String
    var label: String = ""
    var type: FieldType = .number
    /// The stored field this came from; `nil` for a field added in this editor.
    var storedID: UUID?
    /// The type this field had when the editor opened — what a logged value would
    /// be converted from.
    var originalType: FieldType?
    /// Marked for deletion, and still on screen until Save.
    var isRemoved = false

    // Built while a `View.init` runs, which is not on the main actor.
    nonisolated init(key: String) {
        self.key = key
    }

    /// A standard field: title and kind are fixed, only its presence is chosen.
    nonisolated init(standard type: FieldType) {
        self.key = type.standardKey ?? type.rawValue
        self.label = type.displayName
        self.type = type
    }

    nonisolated init(stored: FieldDefinition) {
        self.key = stored.key
        self.label = stored.label
        self.type = stored.type
        self.storedID = stored.id
        self.originalType = stored.type
    }

    /// A field as it was stored, without a store — what the tests build.
    init(key: String, label: String, type: FieldType, storedID: UUID?, originalType: FieldType?, isRemoved: Bool = false) {
        self.key = key
        self.label = label
        self.type = type
        self.storedID = storedID
        self.originalType = originalType
        self.isRemoved = isRemoved
    }
}

/// What saving an edited exercise does to what is already logged from it.
///
/// Decided here, applied by `ExerciseEditorView`: the editor hands over the
/// drafts and the logged values as plain values and shows the lines this
/// returns — under each field, and together in the confirmation before Save.
/// A retitled or reordered field costs nothing and gets no line.
struct FieldChangeImpact {
    /// One logged value, read out of the store.
    struct LoggedValue {
        var fieldKey: String
        var label: String
        var type: FieldType
        var textValue: String?
        var numberValue: Double?
        /// The workout it was logged in, for counting workouts rather than values.
        var workoutID: UUID?

        var isEmpty: Bool {
            FieldValue.isEmpty(textValue: textValue, numberValue: numberValue)
        }
    }

    struct Line: Equatable {
        /// The draft the line belongs to; `nil` for a line about no field on
        /// screen — a leftover key, the split.
        var fieldID: UUID?
        var label: String
        var text: String
        var isDestructive: Bool
    }

    let lines: [Line]

    /// - Parameters:
    ///   - fields: the drafts, in the order the form shows them.
    ///   - loggedValues: every value logged from the exercise, in history order.
    ///   - loggedWorkoutCount: the workouts that logged the exercise at all —
    ///     with or without a value — which a new field is added empty to.
    ///   - splitWorkoutCount: the workouts whose sets turning "Track Sets" off
    ///     splits; 0 when it stays on or nothing needs splitting.
    init(fields: [FieldDraft], loggedValues: [LoggedValue], loggedWorkoutCount: Int, splitWorkoutCount: Int = 0) {
        let filled = loggedValues.filter { !$0.isEmpty }
        var lines = fields.compactMap { field -> Line? in
            guard let (text, isDestructive) = Self.impact(of: field, filled: filled, loggedWorkoutCount: loggedWorkoutCount) else {
                return nil
            }
            return Line(fieldID: field.id, label: Self.title(field.label), text: text, isDestructive: isDestructive)
        }
        lines += Self.leftovers(coveredKeys: Set(fields.map(\.key)), filled: filled)
        if let split = Self.splitText(workouts: splitWorkoutCount) {
            lines.append(Line(fieldID: nil, label: "No sets", text: split, isDestructive: false))
        }
        self.lines = lines
    }

    var isEmpty: Bool { lines.isEmpty }

    var losesData: Bool { lines.contains(where: \.isDestructive) }

    /// The confirmation text before Save, one paragraph per line.
    var message: String {
        lines.map { "\($0.label): \($0.text)" }.joined(separator: "\n\n")
    }

    func line(for field: FieldDraft) -> Line? {
        lines.first { $0.fieldID == field.id }
    }

    /// Turning "Track Sets" off splits several sets into one entry each —
    /// nothing is lost, but it is worth saying.
    static func splitText(workouts: Int) -> String? {
        guard workouts > 0 else { return nil }
        let subject = CountFormat.text(workouts, "workout holds", "workouts hold")
        return "\(subject) several sets of this exercise. Each set becomes an entry of its own, in the same order."
    }

    // MARK: - Rules

    private static func impact(of field: FieldDraft, filled: [LoggedValue], loggedWorkoutCount: Int) -> (String, Bool)? {
        if field.isRemoved {
            let values = filled.filter { $0.fieldKey == field.key }
            guard !values.isEmpty else {
                return ("Will be deleted. Nothing logged it yet.", false)
            }
            return ("Will be deleted, and with it \(CountFormat.text(values.count, "logged value", "logged values")) in \(CountFormat.text(workouts(of: values), "workout", "workouts")).", true)
        }

        if field.storedID == nil {
            guard loggedWorkoutCount > 0 else { return ("New field.", false) }
            return ("New. Added empty to \(CountFormat.text(loggedWorkoutCount, "logged workout", "logged workouts")) — nothing was measured there.", false)
        }

        guard let original = field.originalType, original != field.type else { return nil }

        let change = "\(original.displayName) → \(field.type.displayName)."
        let values = filled.filter { $0.fieldKey == field.key }
        guard !values.isEmpty else { return (change, false) }

        let lost = values.filter {
            FieldValue.converting(textValue: $0.textValue, numberValue: $0.numberValue, from: $0.type, to: field.type).lost
        }.count
        let converted = "\(change) \(CountFormat.text(values.count, "logged value", "logged values")) converted"
        guard lost > 0 else { return ("\(converted).", false) }
        return ("\(converted), \(lost) of them cannot be read and will be cleared.", true)
    }

    /// Values logged under a key no field covers any more — not even one
    /// marked for removal, which has its own line already.
    ///
    /// Saving deletes them: the editor drops every value whose key is not in
    /// the definition. They get there through an import, which writes what
    /// the file logged without asking the definition, so the keys are real and
    /// so is the deletion.
    private static func leftovers(coveredKeys: Set<String>, filled: [LoggedValue]) -> [Line] {
        var seen = Set<String>()
        return filled.compactMap { value in
            guard !coveredKeys.contains(value.fieldKey), seen.insert(value.fieldKey).inserted else { return nil }
            let values = filled.filter { $0.fieldKey == value.fieldKey }
            return Line(
                fieldID: nil,
                label: title(value.label),
                text: "Logged in your history but not a field of this exercise any more. "
                    + "Saving deletes \(CountFormat.text(values.count, "logged value", "logged values")) "
                    + "in \(CountFormat.text(workouts(of: values), "workout", "workouts")).",
                isDestructive: true
            )
        }
    }

    private static func title(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled field" : trimmed
    }

    private static func workouts(of values: [LoggedValue]) -> Int {
        Set(values.compactMap(\.workoutID)).count
    }
}
