import Foundation

/// Whether an entry's sets were helped up, and by what — a dip or pull-up
/// machine whose counterweight pushes from below. Stored on the entry;
/// `ExerciseEntry.assistance` is the way in. Whether an exercise offers it at
/// all is the definition's `offersAssistance`.
///
/// Help and weight exclude each other: an assisted set logs the help in the
/// place of the weight, under the weight field's key, as a value of type
/// `assistance`. Everything that adds up weight — volume, the one-rep max —
/// looks for `.weight` and so passes it by; only the progress graph reads it
/// on purpose, below zero. A band is a kind of help still to come.
nonisolated enum Assistance: String, CaseIterable, Codable {
    case unassisted
    case machine

    var title: String {
        switch self {
        case .unassisted: return "Unassisted"
        case .machine: return "Machine Assisted"
        }
    }

    /// The short form for the capsule next to an exercise name.
    var shortTitle: String {
        switch self {
        case .unassisted: return "Unassisted"
        case .machine: return "Assisted"
        }
    }

    var isAssisted: Bool { self != .unassisted }

    /// What a set of an entry with this help logs for a field of `type`: the
    /// help in place of the weight, everything else as it is.
    func loggedType(for type: FieldType) -> FieldType {
        isAssisted && type == .weight ? .assistance : type
    }

    /// The title a value of a field logged this way carries.
    func loggedLabel(for type: FieldType, label: String) -> String {
        loggedType(for: type) == type ? label : FieldType.assistance.displayName
    }

    /// The help a new entry starts with: what the exercise was logged with
    /// last time, so one always done on the machine does not have to be
    /// switched over every workout — as long as the exercise still offers it.
    static func start(offered: Bool, lastLogged: Assistance?) -> Assistance {
        guard offered else { return .unassisted }
        return lastLogged ?? .unassisted
    }

    /// The choices an entry's menu offers: none on an exercise without help,
    /// unless the entry already has some — what is written down stays
    /// reachable, so it can be switched back.
    static func choices(offered: Bool, current: Assistance) -> [Assistance] {
        offered || current.isAssisted ? allCases : []
    }
}
