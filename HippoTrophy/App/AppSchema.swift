import Foundation
import SwiftData

/// The store since a photo says which part of it a tile shows: `framingX`,
/// `framingY` and `framingZoom` on `ExercisePhoto` and `MachinePhoto`.
///
/// It lists the live model types, which is right only while it is the newest
/// version. Before a model changes, the classes as they are here are copied
/// into this enum and frozen (as `SchemaV1` to `SchemaV17` were), the change
/// becomes `SchemaV19`, and a stage in `AppMigrationPlan` leads from one to the
/// other. `StoreFixtureTests` fails on a model change that skips this.
nonisolated enum SchemaV18: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(18, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WorkoutSession.self,
            ExerciseEntry.self,
            SetEntry.self,
            ExerciseDefinition.self,
            ExercisePhoto.self,
            FieldDefinition.self,
            FieldValue.self,
            Gym.self,
            Machine.self,
            MachinePhoto.self
        ]
    }
}

/// Every version a store on someone's device can be in, oldest first, and the
/// steps between them. SwiftData does not insist on an exact match — a store
/// that is off by an added optional property is quietly migrated — so the
/// plan is only as true as `StoreFixtureTests` keeps it.
nonisolated enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self, SchemaV8.self, SchemaV9.self, SchemaV10.self, SchemaV11.self, SchemaV12.self, SchemaV13.self, SchemaV14.self, SchemaV15.self, SchemaV16.self, SchemaV17.self, SchemaV18.self] }
    static var stages: [MigrationStage] { [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7, v7ToV8, v8ToV9, v9ToV10, v10ToV11, v11ToV12, v12ToV13, v13ToV14, v14ToV15, v15ToV16, v16ToV17, v17ToV18] }

    /// Adds `catalogKey`, nil for every exercise already there: before the
    /// catalog, every exercise was the user's own. Which of them match a
    /// catalog exercise is decided at launch by `CatalogSync`, not here.
    static var v1ToV2: MigrationStage { .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self) }

    /// Adds `catalogKey` to every entry, nil to begin with. Which entries were
    /// logged from a catalog exercise is the definition's to say, through
    /// `definitionID`; `CatalogSync` writes it on the next launch.
    static var v2ToV3: MigrationStage { .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self) }

    /// Adds `onlyOneSided` to every exercise, false to begin with: one-sided
    /// training on offer meant either way, off meant two-sided, and that is
    /// what both still mean. Which catalog exercises are one-sided only, and
    /// which entries move with that, is decided at launch by `CatalogSync`.
    static var v3ToV4: MigrationStage { .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self) }

    /// Adds `secondaryMuscleGroupNames` to every exercise, empty to begin
    /// with: every muscle picked so far counted in full, and that is what a
    /// main muscle does. The catalog's exercises get theirs from
    /// `CatalogSync` on the next launch.
    static var v4ToV5: MigrationStage { .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self) }

    /// Adds `offersAssistance` to every exercise, false to begin with, and
    /// `assistanceRawValue` to every entry, unassisted: nothing logged so
    /// far was helped up, as far as the app knows. Which catalog exercises
    /// offer it is decided at launch by `CatalogSync`.
    static var v5ToV6: MigrationStage { .lightweight(fromVersion: SchemaV5.self, toVersion: SchemaV6.self) }

    /// Adds `isTemplate`, `isArchived` and `templateOrder` to every workout,
    /// false, false and 0: there were no templates, so every workout stored
    /// was trained.
    static var v6ToV7: MigrationStage { .lightweight(fromVersion: SchemaV6.self, toVersion: SchemaV7.self) }

    /// Adds `isDone` to every set, true: before a set could be ticked off,
    /// every set logged was a set done.
    static var v7ToV8: MigrationStage { .lightweight(fromVersion: SchemaV7.self, toVersion: SchemaV8.self) }

    /// Adds `restSeconds` to every exercise, nil: until there was a rest
    /// timer, no exercise had a rest of its own, and nil is the one that
    /// follows the setting.
    static var v8ToV9: MigrationStage { .lightweight(fromVersion: SchemaV8.self, toVersion: SchemaV9.self) }

    /// Adds `durationSeconds` to every workout, nil: until the editor timed
    /// a workout from its start to Finish, none was timed, and a guess from
    /// its sets would read as a measurement.
    static var v9ToV10: MigrationStage { .lightweight(fromVersion: SchemaV9.self, toVersion: SchemaV10.self) }

    /// Adds `plannedFor` to every workout, nil: until a template could be
    /// adjusted for a day, every template was one kept for good.
    static var v10ToV11: MigrationStage { .lightweight(fromVersion: SchemaV10.self, toVersion: SchemaV11.self) }

    /// Adds `instructions` to every entry, empty: until there were
    /// instructions, all an entry said besides its sets was its note. In a
    /// template that note can only have been how the exercise is to be done —
    /// a template is never trained, so it has nothing to report — and it
    /// becomes the template's instructions. `BackupFileV18.upgraded()` does
    /// the same for a backup.
    ///
    /// Works on `SchemaV12`'s frozen types, never the live ones: a store on
    /// its way to a later version passes through here in V12's shape, which
    /// the live types outgrow.
    static var v11ToV12: MigrationStage {
        .custom(fromVersion: SchemaV11.self, toVersion: SchemaV12.self, willMigrate: nil) { context in
            let entries = try context.fetch(FetchDescriptor<SchemaV12.ExerciseEntry>())
            for entry in entries where entry.session?.isTemplate == true && !entry.notes.isEmpty {
                entry.instructions = entry.notes
                entry.notes = ""
            }
            try context.save()
        }
    }

    /// Adds gyms and machines, none to begin with, and `gym` to every
    /// workout and `machine` to every entry, nil: until there were gyms, no
    /// workout said where it was trained.
    static var v12ToV13: MigrationStage { .lightweight(fromVersion: SchemaV12.self, toVersion: SchemaV13.self) }

    /// Adds `startSideRawValue` to every entry and `sideOrder` to every set,
    /// nil: nothing logged so far said which side came first or in which
    /// order the sides went, and nothing is guessed for it now.
    static var v13ToV14: MigrationStage { .lightweight(fromVersion: SchemaV13.self, toVersion: SchemaV14.self) }

    /// Takes the user's own categories out. An exercise filed under one is
    /// left without a category, silently: nothing says so, and the name is
    /// gone. `BackupFileV21.upgraded()` does the same for a backup.
    ///
    /// Before the step, on `SchemaV14`'s frozen types: those still hold the
    /// name, and a store passes through here in that shape whatever comes later.
    static var v14ToV15: MigrationStage {
        .custom(fromVersion: SchemaV14.self, toVersion: SchemaV15.self, willMigrate: { context in
            let definitions = try context.fetch(FetchDescriptor<SchemaV14.ExerciseDefinition>())
            for definition in definitions where ExerciseCategory.resolve(definition.categoryName) == nil {
                definition.categoryName = ""
            }
            try context.save()
        }, didMigrate: nil)
    }

    /// Adds photos, none to begin with, and `photo` to every exercise, nil:
    /// until there were photos, an exercise of the user's own had none.
    static var v15ToV16: MigrationStage { .lightweight(fromVersion: SchemaV15.self, toVersion: SchemaV16.self) }

    /// Adds machine photos, none to begin with, and `photo` to every machine,
    /// nil: until there were machine photos, a machine had none.
    static var v16ToV17: MigrationStage { .lightweight(fromVersion: SchemaV16.self, toVersion: SchemaV17.self) }

    /// Adds the framing to every photo, centred and unzoomed: what a tile
    /// showed of it until then.
    static var v17ToV18: MigrationStage { .lightweight(fromVersion: SchemaV17.self, toVersion: SchemaV18.self) }
}

enum AppSchema {
    /// The models as the app writes them today, for containers that never
    /// meet a stored file — previews and tests.
    static let models = SchemaV18.models

    /// The store the app runs on, brought up to the current version. Without a
    /// URL it is the store `.modelContainer(for:)` used before there were
    /// versions, so a device keeps its data across that change.
    static func openStore(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV18.self)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) } ?? ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration)
    }
}
