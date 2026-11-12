import SwiftUI

/// Says which of the two an exercise is while it is being edited: plain weight
/// training, or one that logs something of its own. It follows the draft, not
/// the store, so a change shows what it makes of the exercise before saving.
struct ExerciseShapeBadge: View {
    let isPlain: Bool

    var body: some View {
        Text(isPlain ? "Weight & Reps" : "Custom Fields")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isPlain ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isPlain
                               ? AnyShapeStyle(Color(.tertiarySystemFill))
                               : AnyShapeStyle(Color.accentColor.opacity(0.14)))
            )
            .accessibilityLabel(isPlain ? "Weight and reps exercise" : "Exercise with custom fields")
    }
}
