import Foundation
import SwiftData

/// The store as the first build outside the owner's hands wrote it, frozen
/// when `SchemaV2` added `catalogKey` to `ExerciseDefinition`.
///
/// Only the stored shape lives here — properties, relationships, delete rules.
/// Behaviour stays on the live types; nothing outside the migration plan ever
/// holds one of these. Never edit: `StoreFixtureTests` compares this against
/// `SchemaV1.store`.
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WorkoutSession.self,
            ExerciseEntry.self,
            SetEntry.self,
            ExerciseDefinition.self,
            CustomExerciseCategory.self,
            FieldDefinition.self,
            FieldValue.self
        ]
    }

    @Model
    final class WorkoutSession {
        var id: UUID
        var name: String
        var date: Date
        var notes: String
        @Relationship(deleteRule: .cascade, inverse: \ExerciseEntry.session)
        var exercises: [ExerciseEntry]

        init(id: UUID, name: String, date: Date, notes: String, exercises: [ExerciseEntry]) {
            self.id = id
            self.name = name
            self.date = date
            self.notes = notes
            self.exercises = exercises
        }
    }

    @Model
    final class ExerciseEntry {
        var id: UUID
        var name: String
        var notes: String
        var orderIndex: Int
        var definitionID: UUID
        var supersetID: UUID?
        var tracksUnilateral: Bool
        var logsSidesSeparately: Bool
        var effortScaleRawValue: String
        @Relationship(deleteRule: .cascade, inverse: \SetEntry.exercise)
        var sets: [SetEntry]
        var session: WorkoutSession?

        init(
            id: UUID, name: String, notes: String, orderIndex: Int, definitionID: UUID,
            supersetID: UUID?, tracksUnilateral: Bool, logsSidesSeparately: Bool,
            effortScaleRawValue: String, sets: [SetEntry], session: WorkoutSession?
        ) {
            self.id = id
            self.name = name
            self.notes = notes
            self.orderIndex = orderIndex
            self.definitionID = definitionID
            self.supersetID = supersetID
            self.tracksUnilateral = tracksUnilateral
            self.logsSidesSeparately = logsSidesSeparately
            self.effortScaleRawValue = effortScaleRawValue
            self.sets = sets
            self.session = session
        }
    }

    @Model
    final class SetEntry {
        var id: UUID
        var setNumber: Int
        var sideRawValue: String
        var effortValue: Double?
        var supersetPosition: Int?
        @Relationship(deleteRule: .cascade, inverse: \FieldValue.set)
        var values: [FieldValue]
        var exercise: ExerciseEntry?

        init(
            id: UUID, setNumber: Int, sideRawValue: String, effortValue: Double?,
            supersetPosition: Int?, values: [FieldValue], exercise: ExerciseEntry?
        ) {
            self.id = id
            self.setNumber = setNumber
            self.sideRawValue = sideRawValue
            self.effortValue = effortValue
            self.supersetPosition = supersetPosition
            self.values = values
            self.exercise = exercise
        }
    }

    @Model
    final class ExerciseDefinition {
        var id: UUID
        var name: String
        var orderIndex: Int
        var categoryName: String
        var muscleGroupNames: [String]
        var tracksSets: Bool
        var allowsSides: Bool
        @Relationship(deleteRule: .cascade, inverse: \FieldDefinition.definition)
        var fields: [FieldDefinition]

        init(
            id: UUID, name: String, orderIndex: Int, categoryName: String,
            muscleGroupNames: [String], tracksSets: Bool, allowsSides: Bool, fields: [FieldDefinition]
        ) {
            self.id = id
            self.name = name
            self.orderIndex = orderIndex
            self.categoryName = categoryName
            self.muscleGroupNames = muscleGroupNames
            self.tracksSets = tracksSets
            self.allowsSides = allowsSides
            self.fields = fields
        }
    }

    @Model
    final class CustomExerciseCategory {
        var id: UUID
        var name: String
        var orderIndex: Int

        init(id: UUID, name: String, orderIndex: Int) {
            self.id = id
            self.name = name
            self.orderIndex = orderIndex
        }
    }

    @Model
    final class FieldDefinition {
        var id: UUID
        var key: String
        var label: String
        var typeRawValue: String
        var orderIndex: Int
        var definition: ExerciseDefinition?

        init(id: UUID, key: String, label: String, typeRawValue: String, orderIndex: Int, definition: ExerciseDefinition?) {
            self.id = id
            self.key = key
            self.label = label
            self.typeRawValue = typeRawValue
            self.orderIndex = orderIndex
            self.definition = definition
        }
    }

    @Model
    final class FieldValue {
        var id: UUID
        var fieldKey: String
        var label: String
        var typeRawValue: String
        var orderIndex: Int
        var textValue: String?
        var numberValue: Double?
        var set: SetEntry?

        init(
            id: UUID, fieldKey: String, label: String, typeRawValue: String, orderIndex: Int,
            textValue: String?, numberValue: Double?, set: SetEntry?
        ) {
            self.id = id
            self.fieldKey = fieldKey
            self.label = label
            self.typeRawValue = typeRawValue
            self.orderIndex = orderIndex
            self.textValue = textValue
            self.numberValue = numberValue
            self.set = set
        }
    }
}
