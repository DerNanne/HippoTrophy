import SwiftUI

/// Marks every exercise of the user's own; the catalog's are the ones without.
/// A signal rather than a warning: the user should know an exercise is off
/// the catalog, where the heat map and the graphs rely on it being set up
/// right — and it tells two of one name apart.
struct UserDefinedBadge: View {
    var body: some View {
        Text("User defined")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.yellow.opacity(0.22)))
            // A capsule in two lines is no capsule: when the row runs short,
            // the name beside it wraps instead.
            .fixedSize()
            .accessibilityLabel("User defined")
    }
}

extension ExerciseDefinition {
    /// An exercise of the user's own, as against the catalog's.
    var isUserDefined: Bool { catalogKey == nil }
}

extension ExerciseEntry {
    /// The same for what was logged.
    var isUserDefined: Bool { catalogKey == nil }
}
