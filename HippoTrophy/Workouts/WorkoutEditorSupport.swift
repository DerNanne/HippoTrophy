import SwiftUI

/// An alert rather than a confirmation dialog: from a toolbar button the dialog
/// becomes a popover, and that drops Keep Editing.
struct DiscardChangesConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    /// The logged sets of a workout being trained, for which Discard deletes
    /// the whole workout: its sets were saved as they were ticked, so
    /// "unsaved changes" would undersell what goes.
    var trainedSetCount: Int?
    let onDiscard: () -> Void

    func body(content: Content) -> some View {
        if let trainedSetCount {
            content.alert("Discard Workout?", isPresented: $isPresented) {
                Button("Keep Training", role: .cancel) {}
                Button("Discard Workout", role: .destructive, action: onDiscard)
            } message: {
                Text(WorkoutDeletion.message(setCount: trainedSetCount))
            }
        } else {
            content.alert("Discard Changes?", isPresented: $isPresented) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard Changes", role: .destructive, action: onDiscard)
            } message: {
                Text("You have unsaved changes. If you cancel now, your changes will be discarded.")
            }
        }
    }
}

/// A switch away from the split log, held until it is confirmed. Once left and
/// right are one list, nothing says which set came from which side any more.
struct PendingModeChange: Identifiable {
    let id = UUID()
    let exerciseID: UUID
    let mode: UnilateralMode
}

/// A switch to another effort scale, held until it is confirmed: the entry's
/// ratings do not carry over and are dropped.
struct PendingEffortScaleChange: Identifiable {
    let id = UUID()
    let exerciseID: UUID
    let scale: EffortScale
    let discarded: Int

    /// The warning, with the count it is about. Earlier workouts are named
    /// because "the ratings" alone could be read as all of them.
    var message: String {
        let ratings = discarded == 1 ? "The rating of 1 set" : "The ratings of \(discarded) sets"
        return "⚠️ \(ratings) in this exercise will be discarded — a rating does not carry over to another scale. Earlier workouts keep theirs."
    }
}

enum ExerciseSide: String, CaseIterable {
    case left
    case right

    /// The side its sets are logged on.
    var setSide: SetSide {
        switch self {
        case .left: return .left
        case .right: return .right
        }
    }

    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}
