import SwiftUI

/// A logged value as the read-only lists print it under its label: a weight
/// or help as `40 kg`, reps as `10`, anything else as it was entered. The
/// label — Weight, Reps, Assist — is the caller's, which is why reps need no
/// `x` and help no "assist".
struct LoggedValueText: View {
    let value: FieldValue
    let unit: WeightUnit
    /// Replaces the weight as printed — the history's per-side reading.
    var weightText: String?

    var body: some View {
        switch value.type {
        case .weight:
            Text(weightText ?? unit.formatted(kilograms: value.numberValue ?? 0))
        case .assistance:
            Text(unit.formatted(kilograms: value.numberValue ?? 0))
        case .reps:
            Text("\(Int(value.numberValue ?? 0))")
        case .text, .number, .time:
            Text(value.displayText(unit: unit))
        }
    }
}
