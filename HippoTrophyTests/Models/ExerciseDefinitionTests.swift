import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// What makes an exercise "plain" decides which face the editor shows, so it
/// has to name every choice the plain face leaves out.
@MainActor
struct ExerciseDefinitionTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func aQuickAddedExerciseIsPlain() throws {
        let context = try context()
        let definition = ExerciseDefinition.insertPlainSetsAndReps(name: "Bench Press", orderIndex: 0, in: context)

        #expect(definition.isPlainSetsAndReps)
        #expect(definition.sortedFields.map(\.type) == [.weight, .reps])
        #expect(definition.fieldSummary == nil)
    }

    /// Every one of these is a choice the plain editor does not show, so an
    /// exercise that differs in it must not be shown as plain.
    @Test func anythingThePlainFaceHidesMakesItCustom() throws {
        let context = try context()

        let cardio = ExerciseDefinition.insertPlainSetsAndReps(name: "Rowing", orderIndex: 0, in: context)
        cardio.categoryName = ExerciseCategory.cardio.name
        #expect(!cardio.isPlainSetsAndReps)

        let once = ExerciseDefinition.insertPlainSetsAndReps(name: "Plank", orderIndex: 1, in: context)
        once.tracksSets = false
        #expect(!once.isPlainSetsAndReps)

        // How it is trained is a choice of its own, shown for plain
        // exercises too: a two-sided one is as plain as any.
        let twoSided = ExerciseDefinition.insertPlainSetsAndReps(name: "Crunch", orderIndex: 2, in: context)
        twoSided.sides = .both
        #expect(twoSided.isPlainSetsAndReps)

        let extra = ExerciseDefinition.insertPlainSetsAndReps(name: "Farmer Carry", orderIndex: 3, in: context)
        let field = FieldDefinition(key: "f1", label: "Distance", typeRawValue: "number", orderIndex: 2, definition: extra)
        context.insert(field)
        extra.fields.append(field)
        #expect(!extra.isPlainSetsAndReps)
        #expect(extra.fieldSummary == "Sets of Weight, Reps, Distance")
    }


    /// Two stored switches, three ways: the first says whether sides are on
    /// offer, the second whether they are all there is.
    @Test func sidesAreStoredInTwoSwitches() throws {
        let definition = ExerciseDefinition.insertPlainSetsAndReps(name: "Lunge", orderIndex: 0, in: try context())
        #expect(definition.sides == .both)
        for sides in ExerciseSides.allCases {
            definition.sides = sides
            #expect(definition.sides == sides)
        }
        definition.sides = .one
        #expect(definition.allowsSides && definition.onlyOneSided)
        definition.sides = .both
        #expect(!definition.allowsSides && !definition.onlyOneSided)
    }
}
