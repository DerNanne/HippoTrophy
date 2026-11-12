import Foundation
import SwiftData

/// One logged value in a set. It carries the label and type it was logged
/// with, so a set still renders correctly after its definition was renamed or
/// deleted, and so the backup can round-trip without reaching for the
/// definition.
@Model
final class FieldValue {
    var id: UUID
    var fieldKey: String
    var label: String
    var typeRawValue: String
    var orderIndex: Int
    /// Where a `.text` value lives; nil when the field was left empty.
    var textValue: String?
    /// Where every other kind lives; nil when the field was left empty, which
    /// is different from holding 0. A weight is kilograms, and so is the help
    /// logged in its place; a duration whole
    /// seconds (8:30 is 510), reps a whole number. One `Double` column serves
    /// them all, so history can sort, filter and sum on it — and stays exact
    /// far beyond anything a workout can hold.
    var numberValue: Double?
    var set: SetEntry?

    init(
        fieldKey: String,
        label: String,
        typeRawValue: String,
        orderIndex: Int,
        textValue: String? = nil,
        numberValue: Double? = nil,
        set: SetEntry? = nil
    ) {
        self.id = UUID()
        self.fieldKey = fieldKey
        self.label = label
        self.typeRawValue = typeRawValue
        self.orderIndex = orderIndex
        self.textValue = textValue
        self.numberValue = numberValue
        self.set = set
    }

    var type: FieldType {
        get { FieldType(rawValue: typeRawValue) ?? .number }
        set { typeRawValue = newValue.rawValue }
    }

    /// Whole seconds of a `.time` value, in the `Int` the picker and the
    /// formatter work in.
    var durationSeconds: Int? {
        get { numberValue.map { Int($0) } }
        set { numberValue = newValue.map(Double.init) }
    }

    /// True when the field was left unfilled.
    var isEmpty: Bool {
        Self.isEmpty(textValue: textValue, numberValue: numberValue)
    }

    /// The one rule for "nothing logged here", for values that are not rows.
    static func isEmpty(textValue: String?, numberValue: Double?) -> Bool {
        numberValue == nil
            && (textValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// The value as it appears in a text field: the weight in `unit`, a locale
    /// decimal separator for numbers, `m:ss` for durations, empty when nothing
    /// is logged.
    func editText(unit: WeightUnit) -> String {
        switch type {
        case .text:
            return textValue ?? ""
        case .weight, .assistance:
            guard let numberValue else { return "" }
            return unit.number(fromKilograms: numberValue)
        case .reps:
            guard let numberValue else { return "" }
            return String(Int(numberValue))
        case .number:
            guard let numberValue else { return "" }
            return FieldType.canonicalText(for: numberValue)
                .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
        case .time:
            guard let durationSeconds else { return "" }
            return DurationFormat.text(forSeconds: durationSeconds)
        }
    }

    var editText: String { editText(unit: .current) }

    /// The value for read-only rows, unit included for a weight; an empty
    /// field reads as an em dash.
    func displayText(unit: WeightUnit) -> String {
        guard !isEmpty else { return "—" }
        switch type {
        case .weight, .assistance: return unit.formatted(kilograms: numberValue ?? 0)
        default: return editText(unit: unit)
        }
    }

    /// Writes what the user typed into the right column, storing nil when the
    /// input holds no value. A weight arrives in `unit` and is stored in
    /// kilograms. Durations come through the picker, never as typed text.
    func applyInput(_ input: String, unit: WeightUnit) {
        switch type {
        case .text:
            let stored: String? = input.isEmpty ? nil : input
            if textValue != stored { textValue = stored }
        case .weight, .assistance:
            let parsed = FieldType.number(fromInput: input).map(unit.kilograms(from:))
            // Only a real edit is written back. The field shows two fraction
            // digits, so anything closer than half a step is the stored weight
            // rendered, not a new one — writing it back would turn 60 kg into
            // 60.001 the moment the row is shown in pounds.
            if let parsed, let numberValue, abs(parsed - numberValue) <= unit.storageTolerance { return }
            if numberValue != parsed { numberValue = parsed }
        case .reps:
            let parsed = FieldType.wholeNumber(fromInput: input).map(Double.init)
            if numberValue != parsed { numberValue = parsed }
        case .number:
            let parsed = FieldType.number(fromInput: input)
            if numberValue != parsed { numberValue = parsed }
        case .time:
            break
        }
    }

    /// What this value would hold as `type`, and whether the conversion drops it.
    /// Reading is kept apart from writing so the editor can count what a type
    /// change costs with exactly the rules the change then applies.
    ///
    /// Nothing readable becomes nil, never 0: an empty field means nothing was
    /// logged, which is a different thing from having measured zero.
    func converting(to type: FieldType) -> (textValue: String?, numberValue: Double?, lost: Bool) {
        Self.converting(textValue: textValue, numberValue: numberValue, from: self.type, to: type)
    }

    /// The conversion itself, on plain values — so `FieldChangeImpact` can
    /// count losses without a store.
    static func converting(
        textValue: String?,
        numberValue: Double?,
        from source: FieldType,
        to type: FieldType
    ) -> (textValue: String?, numberValue: Double?, lost: Bool) {
        guard !isEmpty(textValue: textValue, numberValue: numberValue), type != source else {
            return (textValue, numberValue, false)
        }
        let durationSeconds = numberValue.map { Int($0) }

        switch (source, type) {
        case (.time, .text):
            return (durationSeconds.map { DurationFormat.text(forSeconds: $0) }, nil, false)
        case (_, .text):
            return (numberValue.map { FieldType.canonicalText(for: $0) }, nil, false)
        case (.text, .time):
            // "8:30" is 510 seconds; see the reader for what a bare number means.
            let parsed = DurationFormat.seconds(fromFreeText: textValue ?? "")
            return (nil, parsed.map(Double.init), parsed == nil)
        case (.text, _):
            let parsed = FieldType.number(fromInput: textValue ?? "")
            return (nil, parsed, parsed == nil)
        case (_, .time):
            // Every numeric kind lives in `numberValue`, so the number itself
            // carries over — as the whole seconds a duration is stored in.
            let seconds = numberValue.map { min(max(Int($0.rounded()), 0), DurationFormat.maxSeconds) }
            return (nil, seconds.map(Double.init), false)
        case (_, .reps):
            return (nil, numberValue.map { $0.rounded() }, false)
        default:
            return (nil, numberValue, false)
        }
    }

    /// Rewrites this value for a field whose type changed.
    func convert(to type: FieldType) {
        let converted = converting(to: type)
        textValue = converted.textValue
        numberValue = converted.numberValue
        self.type = type
    }
}
