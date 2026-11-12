import Foundation

/// How the sets of one entry are rated for effort. Chosen per entry, never per
/// set: an entry rates all of its sets on one scale or none, so two scales can
/// never meet in one exercise of one workout. Changing it never reaches back
/// into earlier workouts — the history says how it was rated at the time.
///
/// A set stores its rating as a bare number, and only this type says what the
/// number means. That is the one definition of it: the views, the report and
/// the backup all ask here. There is no conversion between scales — "hard" is
/// not some number of reps in reserve.
nonisolated enum EffortScale: String, CaseIterable, Identifiable, Codable {
    /// Nothing is rated; the sets show no effort at all.
    case off
    /// Easy, normal or hard.
    case levels
    /// Reps in reserve: how many more reps the set had left, 0 to 10 in
    /// halves. 0 is a set taken to failure.
    case rir

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: return "Off"
        case .levels: return "Easy, Normal, Hard"
        case .rir: return "Reps in Reserve (RIR)"
        }
    }

    /// The scale a newly added entry starts with while the settings say
    /// nothing: three steps cost one tap, and a rating can be ignored.
    static let defaultForNewEntries = EffortScale.levels

    /// The scale a newly added entry starts with, from the settings.
    static var forNewEntries: EffortScale {
        UserDefaults.standard.string(forKey: SettingsKey.effortScale)
            .flatMap(EffortScale.init(rawValue:)) ?? defaultForNewEntries
    }

    /// The range of reps in reserve, and its step.
    static let rirRange: ClosedRange<Double> = 0...10
    static let rirStep = 0.5

    /// What a stored value means on this scale. `nil` for a set that was not
    /// rated, and for a value this scale cannot hold — there is nothing to
    /// guess it from.
    func effort(storedAs value: Double?) -> SetEffort? {
        guard let value else { return nil }
        switch self {
        case .off:
            return nil
        case .levels:
            return Int(exactly: value).flatMap(EffortLevel.init(rawValue:)).map(SetEffort.level)
        case .rir:
            let steps = value / Self.rirStep
            guard Self.rirRange.contains(value), steps == steps.rounded() else { return nil }
            return .rir(value)
        }
    }

    /// The ratings this scale offers at a tap, in the order they are offered.
    /// For reps in reserve that is one per band, hardest first; any other
    /// value in range is reached by stepping.
    var choices: [SetEffort] {
        switch self {
        case .off: return []
        case .levels: return EffortLevel.allCases.map(SetEffort.level)
        case .rir: return RIRBand.allCases.map { .rir($0.preset) }
        }
    }
}

/// The three steps of `EffortScale.levels`. The raw value is what a set
/// stores, and also how far up the gauge the step reaches.
nonisolated enum EffortLevel: Int, CaseIterable {
    case easy
    case normal
    case hard

    var label: String {
        switch self {
        case .easy: return "Easy"
        case .normal: return "Normal"
        case .hard: return "Hard"
        }
    }
}

/// Reps in reserve in bands, so a glance down a workout tells how hard it ran
/// without reading every number. Coarse where estimating is coarse — nobody
/// reliably tells 5 reps left from 7, so everything from 4 up is one band —
/// and fine near failure, where 0, 0.5 and 1 change the training.
///
/// Each band has a preset, the value a single tap logs. A value stepped to in
/// between belongs to the band it falls in.
nonisolated enum RIRBand: CaseIterable {
    case failure
    case halfRep
    case oneRep
    case twoReps
    case threeReps
    case fourOrMore

    /// The band a value falls in: from its preset up to the next band's.
    static func containing(_ rir: Double) -> RIRBand {
        switch rir {
        case ..<0.5: return .failure
        case ..<1: return .halfRep
        case ..<2: return .oneRep
        case ..<3: return .twoReps
        case ..<4: return .threeReps
        default: return .fourOrMore
        }
    }

    var preset: Double {
        switch self {
        case .failure: return 0
        case .halfRep: return 0.5
        case .oneRep: return 1
        case .twoReps: return 2
        case .threeReps: return 3
        case .fourOrMore: return 4
        }
    }

    /// What the preset is called on its button. "4+" logs a plain 4: the
    /// floor it stands for, a number like any other.
    var presetLabel: String {
        self == .fourOrMore ? "4+" : RIRBand.format(preset)
    }

    /// What the band means, in words.
    var meaning: String {
        switch self {
        case .failure: return "Failure — nothing left"
        case .halfRep: return "Half a rep left, at most"
        case .oneRep: return "One more rep"
        case .twoReps: return "Two more reps"
        case .threeReps: return "Three more reps"
        case .fourOrMore: return "Four or more — easy"
        }
    }

    /// A value of reps in reserve as the app shows it: no trailing zero, the
    /// half in the user's decimal style.
    static func format(_ rir: Double) -> String {
        rir.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// One set's rating, read through its entry's scale. A set that was not rated
/// has none — there is no default rating, so a set nobody touched never looks
/// like one somebody judged.
nonisolated enum SetEffort: Hashable {
    case level(EffortLevel)
    case rir(Double)

    /// The scale this rating belongs to.
    var scale: EffortScale {
        switch self {
        case .level: return .levels
        case .rir: return .rir
        }
    }

    /// The number a set keeps for this rating.
    var storedValue: Double {
        switch self {
        case .level(let level): return Double(level.rawValue)
        case .rir(let rir): return rir
        }
    }

    var label: String {
        switch self {
        case .level(let level): return level.label
        case .rir(let rir): return "RIR \(RIRBand.format(rir))"
        }
    }
}
