import Foundation
import UIKit

/// The kinds of value a field of an exercise can hold. The type decides which
/// column of `FieldValue` a value lives in — `.text` in `textValue`, every
/// other kind in `numberValue` — and drives input, formatting and the keyboard.
///
/// `weight` and `reps` are the two standard fields: fixed in name and type,
/// switched on or off per exercise rather than configured. Everything that
/// knows what a set of weight training is — volume, "3×8 @ 60 kg", the report
/// — looks for exactly these two.
///
/// `assistance` is no field of an exercise: it is what the weight field logs
/// in an assisted entry — see `Assistance`. It is kilograms like a weight,
/// and it is not one, so nothing that adds up weight counts it.
enum FieldType: String, CaseIterable, Codable {
    case weight
    case reps
    case assistance
    case text
    case number
    case time

    /// The two fields a plain sets-and-reps exercise consists of, in the order
    /// a set row shows them.
    static let standard: [FieldType] = [.weight, .reps]

    /// The kinds a user configures freely, with a title of their own.
    static let custom: [FieldType] = [.text, .number, .time]

    var isStandard: Bool { Self.standard.contains(self) }

    /// The field a value of this kind was logged for: the weight for help
    /// logged in its place, itself for everything else.
    nonisolated var fieldType: FieldType {
        self == .assistance ? .weight : self
    }

    // `displayName` and `standardKey` are fixed text, read by drafts built off
    // the main actor; `placeholder` reads the weight unit and stays isolated.
    nonisolated var displayName: String {
        switch self {
        case .weight: return "Weight"
        case .reps: return "Reps"
        case .assistance: return "Assist"
        case .text: return "Text"
        case .number: return "Number"
        // "Time" invited a clock reading; the field measures how long something
        // took. The raw value stays `time`, because that is what is persisted.
        case .time: return "Duration"
        }
    }

    /// The `fN` key a standard field is stored under, so the two are found by
    /// key on every definition alike.
    nonisolated var standardKey: String? {
        switch self {
        case .weight: return "weight"
        case .reps: return "reps"
        default: return nil
        }
    }

    var placeholder: String {
        switch self {
        case .weight, .assistance: return WeightUnit.current.symbol
        case .reps: return "reps"
        case .text: return "text"
        case .number: return "0"
        case .time: return "0:00"
        }
    }

    var keyboardType: UIKeyboardType {
        switch self {
        case .weight, .assistance, .number: return .decimalPad
        case .reps: return .numberPad
        case .text: return .default
        case .time: return .numbersAndPunctuation
        }
    }

    /// Parses typed input into the stored number, accepting either decimal
    /// separator and a unit or stray mark behind the number. Nil when no number
    /// can be read — an empty field, not a zero — and when digits stand apart:
    /// "12-15" says two things, and joining them would store 1215.
    static func number(fromInput input: String) -> Double? {
        numberPart(of: input, allowsFraction: true)
            .flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    /// The same for a count, which has no fraction: "1.5" is not 15 reps.
    static func wholeNumber(fromInput input: String) -> Int? {
        numberPart(of: input, allowsFraction: false).flatMap { Int($0) }
    }

    /// What a field shows after `input` replaced `previous`. Input with no
    /// number to read — pasted, or from a hardware keyboard — is refused, so
    /// the field never shows a value that was not stored.
    ///
    /// A mark behind a number stays while typing: dropped at once, it would
    /// let the next digits join the number, and "12-15" typed key by key would
    /// become 1215. Kept, it makes them stand apart, and they are refused.
    /// `settledInput` takes it away once the field is left.
    func acceptedInput(_ input: String, replacing previous: String) -> String {
        guard !input.isEmpty, let allowsFraction else { return input }
        return Self.numberPart(of: input, allowsFraction: allowsFraction) == nil ? previous : input
    }

    /// What a field shows once it is left: the number it stores, without the
    /// mark `acceptedInput` let stand behind it.
    func settledInput(_ input: String) -> String {
        guard let allowsFraction else { return input }
        return Self.numberPart(of: input, allowsFraction: allowsFraction) ?? input
    }

    /// Whether the field takes a number with a fraction; nil when it does not
    /// take a number at all.
    private var allowsFraction: Bool? {
        switch self {
        case .text, .time: return nil
        case .reps: return false
        case .weight, .assistance, .number: return true
        }
    }

    /// The number `input` starts with, as typed. Nil when it does not start
    /// with one, or when more digits follow what is not part of it.
    private static func numberPart(of input: String, allowsFraction: Bool) -> String? {
        var rest = Substring(input.trimmingCharacters(in: .whitespaces))
        var part = ""
        var hasSeparator = false
        while let character = rest.first {
            if character.isASCII && character.isNumber {
                part.append(character)
            } else if allowsFraction, !hasSeparator, character == "." || character == "," {
                hasSeparator = true
                part.append(character)
            } else {
                break
            }
            rest = rest.dropFirst()
        }
        guard !part.isEmpty, !rest.contains(where: \.isNumber) else { return nil }
        return part
    }

    /// A stored number written the way the backup file spells it: a dot as the
    /// separator, and no fraction when there is none — `142`, not `142.0`.
    static func canonicalText(for number: Double) -> String {
        if let whole = Int(exactly: number.rounded()), number == number.rounded() {
            return String(whole)
        }
        return String(number)
    }
}
