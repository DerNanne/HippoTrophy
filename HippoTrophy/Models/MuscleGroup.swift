import Foundation

/// A muscle a catalogue exercise trains. Fixed in code rather than stored: the
/// set is small, shared by every user, and nothing about it is worth carrying in
/// a backup — an exercise stores the raw values, so an unknown one read from a
/// file survives as text instead of being dropped.
///
/// Deliberately separate from `ExerciseCategory`, which answers a different
/// question (Cardio/Mobility/Strength) about a different thing (custom
/// exercises). An exercise is both a strength exercise and a chest exercise, so
/// folding the two into one list would make the choices mutually exclusive when
/// they are not.
nonisolated enum MuscleGroup: String, CaseIterable, Identifiable, Hashable {
    case chest
    case back
    case traps
    case shoulders
    case biceps
    case triceps
    case forearms
    case core
    case glutes
    case quads
    case hamstrings
    case adductors
    case abductors
    case calves

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .traps: return "Traps"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .core: return "Core"
        case .glutes: return "Glutes"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .adductors: return "Adductors"
        case .abductors: return "Abductors"
        case .calves: return "Calves"
        }
    }

    /// Reads a stored or imported raw value, tolerating the spelling and casing
    /// a hand-edited file might carry.
    static func from(raw: String) -> MuscleGroup? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return allCases.first { $0.rawValue.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// Reads a list off a file. Duplicates collapse and the order survives,
    /// because the first entry is the main muscle. The set is ours to define, so
    /// a name that is not in it is a mistake in the file rather than a category
    /// to invent — it is dropped, and handed back so the import can say which.
    static func read(_ raw: [String]) -> (muscles: [String], unknown: [String]) {
        var seen = Set<MuscleGroup>()
        var muscles: [String] = []
        var unknownKeys = Set<String>()
        var unknown: [String] = []

        for name in raw {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let muscle = from(raw: trimmed) else {
                // Reported in the spelling the file used, but only once however
                // often — and however cased — it appears.
                if unknownKeys.insert(trimmed.localizedLowercase).inserted {
                    unknown.append(trimmed)
                }
                continue
            }
            if seen.insert(muscle).inserted {
                muscles.append(muscle.rawValue)
            }
        }
        return (muscles, unknown)
    }
}

/// A coarse bundle of muscles, used only to offer "show me everything for my
/// legs" without making the user tick four boxes. Derived at runtime and never
/// stored: an exercise records muscles, never a region, so regrouping later
/// costs no migration.
///
/// The bundles deliberately overlap — the arm muscles are in both `upperBody`
/// and `arms`. They are shortcuts for a filter, not drawers each muscle belongs
/// to exactly once.
nonisolated enum MuscleRegion: String, CaseIterable, Identifiable, Hashable {
    case upperBody
    case arms
    case legs
    case core

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .upperBody: return "Upper Body"
        case .arms: return "Arms"
        case .legs: return "Legs"
        case .core: return "Core"
        }
    }

    var muscles: [MuscleGroup] {
        switch self {
        case .upperBody: return [.chest, .back, .traps, .shoulders, .biceps, .triceps, .forearms]
        case .arms: return [.biceps, .triceps, .forearms]
        case .legs: return [.quads, .hamstrings, .glutes, .adductors, .abductors, .calves]
        case .core: return [.core]
        }
    }
}
