import Foundation

/// The unit weights are entered and shown in.
///
/// Storage stays kilograms everywhere — `SetEntry.weightKg` — so volumes,
/// comparisons and backups keep working on one comparable number. The unit is an
/// input and display concern and is converted at that edge only; nothing that
/// adds weights up ever has to ask which unit a set was logged in.
enum WeightUnit: String, CaseIterable, Identifiable {
    case kilograms = "kg"
    case pounds = "lb"

    var id: String { rawValue }

    /// The exact international definition, so pounds survive a round trip
    /// through kilograms: 135 lb comes back as 135 lb, not 134.9.
    private static let kilogramsPerPound = 0.45359237

    /// The smallest step the app shows, in the unit itself. Two fraction
    /// digits, so a quarter step — 11.25 kg, a 1.25 kg plate a side — reads as
    /// what was logged rather than rounded to 11.2.
    private static let displayStep = 0.01

    var symbol: String {
        switch self {
        case .kilograms: "kg"
        case .pounds: "lb"
        }
    }

    /// For the settings picker, where an abbreviation alone reads like jargon.
    var name: String {
        switch self {
        case .kilograms: "Kilograms (kg)"
        case .pounds: "Pounds (lb)"
        }
    }

    /// Spelled out for VoiceOver, which would otherwise read "kg" as letters.
    var spokenName: String {
        switch self {
        case .kilograms: "kilograms"
        case .pounds: "pounds"
        }
    }

    /// A stored weight as the user sees it.
    func value(fromKilograms kilograms: Double) -> Double {
        switch self {
        case .kilograms: kilograms
        case .pounds: kilograms / Self.kilogramsPerPound
        }
    }

    /// A weight the user typed, on its way into storage.
    func kilograms(from value: Double) -> Double {
        switch self {
        case .kilograms: value
        case .pounds: value * Self.kilogramsPerPound
        }
    }

    /// The one way a weight is written, everywhere it appears: the workout and
    /// history rows, "Last time", the editor and the report.
    ///
    /// Weights read the way they were entered — `60`, not `60.0`, but `62,5`
    /// keeps its half and `11,25` its quarter — with the device's decimal
    /// separator, like every other number in the app. No group separator: the
    /// editor shows this text and reads it back, and `1,000` would come back
    /// as one.
    func number(fromKilograms kilograms: Double, locale: Locale = .current) -> String {
        value(fromKilograms: kilograms).formatted(
            .number
                .precision(.fractionLength(0...Self.fractionDigits))
                .grouping(.never)
                .locale(locale)
        )
    }

    /// `60 kg`, `62,5 kg` — `number(fromKilograms:)` with the unit.
    func formatted(kilograms: Double, locale: Locale = .current) -> String {
        number(fromKilograms: kilograms, locale: locale) + " " + symbol
    }

    private static let fractionDigits = 2

    /// Half a display step, expressed in kilograms.
    ///
    /// The editor compares a typed weight against the stored one across a
    /// conversion, where neither side is exact. Anything closer than this is the
    /// same weight rendered twice, not an edit — without the slack, merely
    /// showing 60 kg as 132.28 lb would write 60.001 kg back into the set.
    var storageTolerance: Double {
        kilograms(from: Self.displayStep / 2)
    }

    /// The stored preference, for the places that format a weight outside a view
    /// and so cannot read `@AppStorage` — the report renderer, above all.
    /// `UserDefaults` is safe to read from any thread, so this is not tied to
    /// the main actor the way the views that write it are.
    nonisolated static var current: WeightUnit {
        UserDefaults.standard.string(forKey: SettingsKey.weightUnit)
            .flatMap(WeightUnit.init(rawValue:)) ?? .kilograms
    }
}
