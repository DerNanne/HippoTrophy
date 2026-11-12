import Foundation

/// What deleting workouts takes with it, said the same way wherever a workout
/// goes: swiped away in the list, or discarded while it is being trained.
nonisolated enum WorkoutDeletion {
    /// "3 logged sets are deleted with it. This cannot be undone."
    static func message(setCount: Int, workoutCount: Int = 1) -> String {
        let owner = workoutCount == 1 ? "it" : "them"
        let logged = switch setCount {
        case 0: "Nothing was logged in \(owner)."
        case 1: "1 logged set is deleted with \(owner)."
        default: "\(setCount) logged sets are deleted with \(owner)."
        }
        return "\(logged) This cannot be undone."
    }
}
