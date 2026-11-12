import Foundation

/// Format 11, frozen when format 12 added `secondaryMuscleGroupNames` to an
/// exercise. Differs from format 10 by `sides` in place of `allowsSides`.
///
/// Read only to be brought forward: `upgraded()` turns it into format 12.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV11: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var exercises: [ExerciseRecord]?
    var workouts: [WorkoutRecord]?

    struct ExerciseRecord: Codable {
        var name: String
        var category: String
        var muscleGroupNames: [String]
        var tracksSets: Bool
        var sides: String
        var fields: [FieldRecord]
        var catalogKey: String?
    }

    struct FieldRecord: Codable {
        var key: String
        var label: String
        var type: String
    }

    struct WorkoutRecord: Codable {
        var id: UUID
        var name: String
        var date: Date
        var notes: String
        var exercises: [EntryRecord]
    }

    struct EntryRecord: Codable {
        var exercise: String
        var catalogKey: String?
        var notes: String
        var mode: String
        var effortScale: String
        var supersetGroup: Int?
        var sets: [SetRecord]
    }

    struct SetRecord: Codable {
        var side: String
        var effort: Double?
        var supersetPosition: Int?
        var values: [ValueRecord]
    }

    struct ValueRecord: Codable {
        var key: String
        var label: String
        var type: String
        var text: String?
        var number: Double?
    }

    /// Format 12 tells the muscles an exercise mainly trains from the ones it
    /// helps. Everything picked before counted in full, as a main muscle
    /// does, so it stays where it was and nothing is secondary. A catalog
    /// exercise's muscles are the catalog's, whatever the file says.
    func upgraded() -> BackupFileV12 {
        BackupFileV12(
            formatVersion: 12,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV12.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    secondaryMuscleGroupNames: [],
                    tracksSets: exercise.tracksSets,
                    sides: exercise.sides,
                    fields: exercise.fields.map { BackupFileV12.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV12.WorkoutRecord(
                    id: workout.id,
                    name: workout.name,
                    date: workout.date,
                    notes: workout.notes,
                    exercises: workout.exercises.map { entry in
                        BackupFileV12.EntryRecord(
                            exercise: entry.exercise,
                            catalogKey: entry.catalogKey,
                            notes: entry.notes,
                            mode: entry.mode,
                            effortScale: entry.effortScale,
                            supersetGroup: entry.supersetGroup,
                            sets: entry.sets.map { set in
                                BackupFileV12.SetRecord(
                                    side: set.side,
                                    effort: set.effort,
                                    supersetPosition: set.supersetPosition,
                                    values: set.values.map {
                                        BackupFileV12.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
                                    }
                                )
                            }
                        )
                    }
                )
            }
        )
    }
}
