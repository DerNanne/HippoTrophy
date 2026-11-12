import SwiftUI

/// The day a variant is for, on its card and in the archive.
struct DayVariantBadge: View {
    let day: Date

    var body: some View {
        Label(DayVariants.label(for: day), systemImage: "calendar")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.15), in: .capsule)
            .accessibilityLabel("Variant for \(DayVariants.label(for: day))")
    }
}
