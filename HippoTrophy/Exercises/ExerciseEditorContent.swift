import Foundation

/// What the exercise editor holds, as far as it would be saved. Two of these
/// are equal when Cancel would lose nothing between them — a field's draft has
/// an identity of its own, which says nothing about what it holds.
struct ExerciseEditorContent: Equatable {
    struct Field: Equatable {
        let key: String
        let label: String
        let type: FieldType
    }

    let name: String
    let categoryName: String
    let muscles: MuscleSelection
    let tracksSets: Bool
    let sides: ExerciseSides
    let offersAssistance: Bool
    let kind: ExerciseLogKind
    let fields: [Field]
    let photo: PhotoDraft?

    init(
        name: String,
        categoryName: String,
        muscles: MuscleSelection,
        tracksSets: Bool,
        sides: ExerciseSides,
        offersAssistance: Bool,
        kind: ExerciseLogKind,
        drafts: ExerciseFieldDrafts,
        photo: PhotoDraft?
    ) {
        self.name = name
        self.categoryName = categoryName
        self.muscles = muscles
        self.tracksSets = tracksSets
        self.sides = sides
        self.offersAssistance = offersAssistance
        self.kind = kind
        fields = drafts.active.map { Field(key: $0.key, label: $0.label, type: $0.type) }
        self.photo = photo
    }
}
