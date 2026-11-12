import SwiftUI

extension View {
    /// A set that was planned and not done, as the read-only lists show it:
    /// greyed out, its values still there — so a workout keeps what was meant
    /// and not trained — and said to be not done.
    func plannedSet(_ set: SetEntry) -> some View {
        opacity(set.isDone ? 1 : 0.4)
            .accessibilityValue(set.isDone ? "" : "Not done")
    }
}
