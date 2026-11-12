import SwiftUI

/// The capsule that marks how an exercise was trained. Shared by the editor, the
/// workout detail and the history so one-sided work reads the same everywhere,
/// and so the editor's tappable version and the read-only ones cannot drift.
struct UnilateralModeBadge: View {
    let mode: UnilateralMode

    private var isPlain: Bool { mode == .bilateral }

    var body: some View {
        Text(mode.shortTitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isPlain ? Color.secondary : Color.blue)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((isPlain ? Color.secondary : Color.blue).opacity(0.14))
            )
            .accessibilityLabel("Trained: \(mode.title)")
    }
}
