import Foundation

/// Format 15, frozen when format 16 gave an exercise a rest of its own.
/// Differs from format 14 by `done` on a set.
///
/// Read only to be brought forward: `upgraded()` turns it into format 16.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV15: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var exercises: [ExerciseRecord]?
    var workouts: [WorkoutRecord]?
    var templates: [TemplateRecord]?

    struct ExerciseRecord: Codable {
        var name: String
        var category: String
        var muscleGroupNames: [String]
        var secondaryMuscleGroupNames: [String]
        var tracksSets: Bool
        var sides: String
        var offersAssistance: Bool
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

    struct TemplateRecord: Codable {
        var id: UUID
        var name: String
        var notes: String
        var archived: Bool
        var exercises: [EntryRecord]
    }

    struct EntryRecord: Codable {
        var exercise: String
        var catalogKey: String?
        var notes: String
        var mode: String
        var assistance: String
        var effortScale: String
        var supersetGroup: Int?
        var sets: [SetRecord]
    }

    struct SetRecord: Codable {
        var side: String
        var effort: Double?
        var supersetPosition: Int?
        var done: Bool
        var values: [ValueRecord]
    }

    struct ValueRecord: Codable {
        var key: String
        var label: String
        var type: String
        var text: String?
        var number: Double?
    }

    /// Format 16 gives an exercise a rest of its own. None had one: every
    /// exercise follows the setting, which the file leaves out.
    func upgraded() -> BackupFileV16 {
        func entries(_ records: [EntryRecord]) -> [BackupFileV16.EntryRecord] {
            records.map { entry in
                BackupFileV16.EntryRecord(
                    exercise: entry.exercise,
                    catalogKey: entry.catalogKey,
                    notes: entry.notes,
                    mode: entry.mode,
                    assistance: entry.assistance,
                    effortScale: entry.effortScale,
                    supersetGroup: entry.supersetGroup,
                    sets: entry.sets.map { set in
                        BackupFileV16.SetRecord(
                            side: set.side,
                            effort: set.effort,
                            supersetPosition: set.supersetPosition,
                            done: set.done,
                            values: set.values.map {
                                BackupFileV16.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
                            }
                        )
                    }
                )
            }
        }
        return BackupFileV16(
            formatVersion: 16,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV16.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    secondaryMuscleGroupNames: exercise.secondaryMuscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    sides: exercise.sides,
                    offersAssistance: exercise.offersAssistance,
                    fields: exercise.fields.map { BackupFileV16.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey,
                    restSeconds: nil
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV16.WorkoutRecord(
                    id: workout.id, name: workout.name, date: workout.date, notes: workout.notes,
                    exercises: entries(workout.exercises)
                )
            },
            templates: templates?.map { template in
                BackupFileV16.TemplateRecord(
                    id: template.id, name: template.name, notes: template.notes, archived: template.archived,
                    exercises: entries(template.exercises)
                )
            }
        )
    }
}
