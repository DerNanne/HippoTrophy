import Foundation

/// The muscles picked in the exercise editor, main and secondary, as raw
/// names in the order they were picked. A muscle is one or the other or
/// neither, never both: picking one level takes it out of the other, and
/// picking the level it has takes it out altogether.
nonisolated struct MuscleSelection: Equatable {
    enum Level: Equatable {
        case none, primary, secondary
    }

    var primary: [String]
    var secondary: [String]

    /// Whether saving asks first. A Strength exercise is what the muscle views
    /// count by default, so one filed under nothing goes missing there without
    /// a word; other categories have no such promise to break.
    func asksBeforeSaving(categoryName: String) -> Bool {
        primary.isEmpty && secondary.isEmpty && ExerciseCategory.resolve(categoryName) == .strength
    }

    func level(of muscle: MuscleGroup) -> Level {
        if primary.contains(muscle.rawValue) { return .primary }
        if secondary.contains(muscle.rawValue) { return .secondary }
        return .none
    }

    mutating func toggle(_ muscle: MuscleGroup, _ picked: Level) {
        let current = level(of: muscle)
        primary.removeAll { $0 == muscle.rawValue }
        secondary.removeAll { $0 == muscle.rawValue }
        guard picked != current else { return }
        switch picked {
        case .primary: primary.append(muscle.rawValue)
        case .secondary: secondary.append(muscle.rawValue)
        case .none: break
        }
    }
}
