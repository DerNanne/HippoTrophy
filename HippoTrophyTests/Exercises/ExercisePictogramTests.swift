import Foundation
import Testing
import UIKit
@testable import HippoTrophy

/// Every catalog exercise has its picture, and nothing else does.
struct ExercisePictogramTests {
    @Test func everyCatalogExerciseHasAPictogram() {
        #expect(!Catalog.exercises.isEmpty)
        let missing = Catalog.exercises.map(\.key).filter {
            UIImage(named: ExercisePictogram.imageName(for: $0)) == nil
        }
        #expect(missing.isEmpty)
    }

    @Test func anOwnExerciseHasNone() {
        let own = ExerciseDefinition(name: "Back Squat", orderIndex: 0)
        #expect(ExercisePictogram.image(for: own) == nil)
    }
}
