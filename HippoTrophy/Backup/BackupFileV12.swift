import Foundation

/// Format 12, frozen when format 13 added assistance — `offersAssistance` on
/// an exercise, `assistance` on an entry. Differs from format 11 by
/// `secondaryMuscleGroupNames` on an exercise.
///
/// Read only to be brought forward: `upgraded()` turns it into format 13.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV12: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var exercises: [ExerciseRecord]?
    var workouts: [WorkoutRecord]?

    struct ExerciseRecord: Codable {
        var name: String
        var category: String
        var muscleGroupNames: [String]
        var secondaryMuscleGroupNames: [String]
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

    /// Format 13 knows sets helped up by a machine. Nothing before could log
    /// one, so no exercise offers it and every entry is unassisted. A catalog
    /// exercise offers it as the catalog says, whatever the file says.
    func upgraded() -> BackupFileV13 {
        BackupFileV13(
            formatVersion: 13,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV13.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    secondaryMuscleGroupNames: exercise.secondaryMuscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    sides: exercise.sides,
                    offersAssistance: false,
                    fields: exercise.fields.map { BackupFileV13.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV13.WorkoutRecord(
                    id: workout.id,
                    name: workout.name,
                    date: workout.date,
                    notes: workout.notes,
                    exercises: workout.exercises.map { entry in
                        BackupFileV13.EntryRecord(
                            exercise: entry.exercise,
                            catalogKey: entry.catalogKey,
                            notes: entry.notes,
                            mode: entry.mode,
                            assistance: Assistance.unassisted.rawValue,
                            effortScale: entry.effortScale,
                            supersetGroup: entry.supersetGroup,
                            sets: entry.sets.map { set in
                                BackupFileV13.SetRecord(
                                    side: set.side,
                                    effort: set.effort,
                                    supersetPosition: set.supersetPosition,
                                    values: set.values.map {
                                        BackupFileV13.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
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
