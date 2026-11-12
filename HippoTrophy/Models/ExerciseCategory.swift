import SwiftUI
import UIKit

/// What an exercise counts as. They live in code, not in the store, so nothing
/// has to seed them on a first launch. Exercises store the plain name.
///
/// In the order they are offered: strength first, because the app is made for it.
/// Isometrics is strength too, held rather than moved, and kept apart so a
/// plank or a hold on the leg extension can be told from sets and reps.
enum ExerciseCategory: String, CaseIterable, Identifiable {
    case strength
    case cardio
    case mobility
    case isometrics

    var id: String { rawValue }

    nonisolated var name: String {
        switch self {
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        case .mobility: return "Mobility"
        case .isometrics: return "Isometrics"
        }
    }

    var symbolName: String {
        switch self {
        case .strength: return "dumbbell"
        case .cardio: return "figure.run"
        case .mobility: return "figure.cooldown"
        case .isometrics: return "figure.core.training"
        }
    }

    /// The badge reads this, and the chips and the activity graph.
    var tint: Color {
        switch self {
        case .strength: return .green
        case .cardio: return .blue
        case .mobility: return .orange
        case .isometrics: return .purple
        }
    }

    /// The symbol in the category's colour, as an image of its own: a menu or
    /// a picker draws a plain symbol in its text colour, but keeps the colours
    /// an image brings. Chips and the badge tint `symbolName` themselves.
    var coloredSymbol: Image {
        guard let symbol = UIImage(systemName: symbolName) else { return Image(systemName: symbolName) }
        return Image(uiImage: symbol.withTintColor(UIColor(tint), renderingMode: .alwaysOriginal))
    }

    /// The category of a stored name, however it is spelled. `nil` for a blank
    /// name, which is how "no category" is stored, and for any other.
    static func resolve(_ name: String) -> ExerciseCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

/// The capsule that marks an exercise's category, shared by the settings list
/// and the exercise picker so the two cannot drift apart.
struct ExerciseCategoryBadge: View {
    let category: ExerciseCategory

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbolName)
            Text(category.name)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(category.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(category.tint.opacity(0.14)))
        .accessibilityLabel("Category: \(category.name)")
    }
}
