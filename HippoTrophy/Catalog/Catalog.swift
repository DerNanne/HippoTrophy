import Foundation

/// One exercise that ships with the app. Plain weight training — Weight and
/// Reps in sets, filed under Strength — says nothing about it; anything else
/// names its category, its fields, or that it is logged once per workout.
nonisolated struct CatalogExercise: Codable, Hashable {
    /// Stable for good: a definition in the store and an exercise in a backup
    /// point at the catalog by this, whatever the name says in a later version
    /// or another language.
    var key: String
    var name: String
    /// The muscles it is mainly for, a set counting in full for each.
    var muscleGroupNames: [String]
    /// The muscles it works along the way, a set counting half for each —
    /// see `MuscleTargets`.
    var secondaryMuscleGroupNames: [String] = []
    /// Two-sided or one-sided, never either: the one-sided form of a
    /// two-sided exercise is an exercise of its own.
    var sides: ExerciseSides = .both
    /// Whether it can be logged assisted, a machine's help in place of the
    /// weight — the bodyweight exercises a dip or pull-up machine helps with.
    var offersAssistance: Bool = false
    /// For the one-sided form of a two-sided catalog exercise, that one's key
    /// — the one place that says Leg Press (Unilateral) belongs to Leg Press.
    var unilateralOf: String? = nil
    /// The category's plain name; absent for Strength.
    var category: String? = nil
    /// What it logs, in order; absent for Weight and Reps. Set once, when the
    /// exercise is added: the values logged are stored under these keys.
    var fields: [FieldRecord]? = nil
    /// False for an exercise logged once per workout; absent for sets.
    var tracksSets: Bool? = nil

    var categoryName: String { category ?? ExerciseCategory.strength.name }

    var fieldRecords: [FieldRecord] {
        // `FieldType.standard`, spelled out: that list lives on the main actor.
        fields ?? [FieldType.weight, .reps].map { FieldRecord(key: $0.standardKey ?? $0.rawValue, label: $0.displayName, type: $0.rawValue) }
    }

    var logsSets: Bool { tracksSets ?? true }

    /// What an exercise of the user's own must log to be taken for this one —
    /// the same comparison a backup's import makes, see `ExerciseRecord.shape`.
    var shape: ExerciseShape {
        ExerciseShape(tracksSets: logsSets, fields: Set(fieldRecords.map { FieldShape(labelKey: $0.label.exerciseKey, type: $0.type) }))
    }
}

/// The file format of `Catalog.json`.
nonisolated struct CatalogFile: Codable {
    var exercises: [CatalogExercise]
}

nonisolated extension CatalogExercise {
    /// Weight and Reps in sets, under Strength: what a catalog exercise is
    /// when it says nothing else.
    static let plain = CatalogExercise(key: "", name: "", muscleGroupNames: [])
}

nonisolated enum Catalog {
    /// The catalog shipped in the bundle, read once. A missing or broken file
    /// leaves the catalog empty rather than the app unable to start;
    /// `CatalogTests` keeps the shipped file readable and clean.
    static let exercises: [CatalogExercise] = {
        guard let url = Bundle.main.url(forResource: "Catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CatalogFile.self, from: data)
        else { return [] }
        return file.exercises
    }()

    static func exercise(forKey key: String) -> CatalogExercise? {
        exercises.first { $0.key == key }
    }

    /// The one-sided form of the exercise under `key`, if the catalog has one.
    static func unilateralVariant(of key: String, in catalog: [CatalogExercise] = exercises) -> CatalogExercise? {
        catalog.first { $0.unilateralOf == key }
    }
}
