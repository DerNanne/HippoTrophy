import SwiftUI
import UIKit

/// The picture of a catalog exercise: start and end of the movement side by
/// side, 3 : 2, named after the exercise's key. The pictograms are generated
/// SVGs; the generator is not part of this repository. An exercise of the
/// user's own has none, but can have a photo — see `ExercisePhotoTile`.
struct ExercisePictogram: View {
    static let aspectRatio: CGFloat = 3 / 2

    /// The asset of a catalog exercise, by its key.
    static func imageName(for catalogKey: String) -> String {
        "pictogram-\(catalogKey)"
    }

    static func image(for definition: ExerciseDefinition) -> UIImage? {
        definition.catalogKey.flatMap { UIImage(named: imageName(for: $0)) }
    }

    let definition: ExerciseDefinition

    var body: some View {
        // Drawn for a light ground, so the tile stays light in dark mode.
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(white: 0.96))
            .overlay {
                if let image = Self.image(for: definition) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A small figure that says what an option means before the words do: a
/// barbell squat for bilateral, a Bulgarian split squat for unilateral, a
/// pull-up kneeling on a pad, with an arrow up, for assisted. Drawn as
/// templates, so they take the colour of the text beside them.
struct LinePictogram: View {
    let name: String
    @ScaledMetric private var size: CGFloat

    init(name: String, size: CGFloat = 20) {
        self.name = name
        _size = ScaledMetric(wrappedValue: size, relativeTo: .footnote)
    }

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
