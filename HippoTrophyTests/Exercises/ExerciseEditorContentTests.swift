import Foundation
import Testing
@testable import HippoTrophy

/// Whether Cancel in the exercise editor would lose anything.
struct ExerciseEditorContentTests {
    @Test func theSameContentIsNoChange() {
        #expect(content() == content())
    }

    /// Drafts built twice have different ids and hold the same.
    @Test func aDraftsOwnIdentityIsNoChange() {
        #expect(content(drafts: standardDrafts()) == content(drafts: standardDrafts()))
    }

    @Test func aNameIsAChange() {
        #expect(content(name: "Rowing") != content())
    }

    @Test func aMuscleIsAChange() {
        #expect(content(muscles: MuscleSelection(primary: ["Back"], secondary: [])) != content())
    }

    @Test func aPhotoIsAChange() {
        #expect(content(photo: PhotoDraft(data: Data([1]))) != content())
        #expect(content(photo: PhotoDraft(data: Data([1]), framing: PhotoFraming(x: 0.2, y: 0.5, zoom: 1))) != content(photo: PhotoDraft(data: Data([1]))))
    }

    @Test func aRemovedFieldIsAChange() {
        let removed = ExerciseFieldDrafts(
            [FieldDraft(key: "weight", label: "Weight", type: .weight, storedID: nil, originalType: nil, isRemoved: true),
             FieldDraft(standard: .reps)],
            keysInUse: []
        )
        #expect(content(drafts: removed) != content())
    }

    private func standardDrafts() -> ExerciseFieldDrafts {
        ExerciseFieldDrafts(FieldType.standard.map(FieldDraft.init(standard:)), keysInUse: [])
    }

    private func content(
        name: String = "",
        muscles: MuscleSelection = MuscleSelection(primary: [], secondary: []),
        drafts: ExerciseFieldDrafts? = nil,
        photo: PhotoDraft? = nil
    ) -> ExerciseEditorContent {
        ExerciseEditorContent(
            name: name,
            categoryName: "Strength",
            muscles: muscles,
            tracksSets: true,
            sides: .both,
            offersAssistance: false,
            kind: .weightAndReps,
            drafts: drafts ?? standardDrafts(),
            photo: photo
        )
    }
}
