import Foundation

/// Format 18, frozen when format 19 gave an exercise in a workout its
/// instructions. Differs from format 17 by `plannedFor` on a template.
///
/// Read only to be brought forward: `upgraded()` turns it into format 19.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV18: Codable {
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
        var restSeconds: Int?
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
        var durationSeconds: Int?
        var exercises: [EntryRecord]
    }

    struct TemplateRecord: Codable {
        var id: UUID
        var name: String
        var notes: String
        var archived: Bool
        var plannedFor: Date?
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

    /// Format 19 gives an entry instructions besides its note. In a workout
    /// there were none. In a template the note can only have been how the
    /// exercise is to be done — a template is never trained — so it becomes
    /// the instructions, as `AppMigrationPlan.v11ToV12` does in the store.
    func upgraded() -> BackupFileV19 {
        func entries(_ records: [EntryRecord], inTemplate: Bool) -> [BackupFileV19.EntryRecord] {
            records.map { entry in
                BackupFileV19.EntryRecord(
                    exercise: entry.exercise,
                    catalogKey: entry.catalogKey,
                    notes: inTemplate ? "" : entry.notes,
                    instructions: inTemplate ? entry.notes : "",
                    mode: entry.mode,
                    assistance: entry.assistance,
                    effortScale: entry.effortScale,
                    supersetGroup: entry.supersetGroup,
                    sets: entry.sets.map { set in
                        BackupFileV19.SetRecord(
                            side: set.side,
                            effort: set.effort,
                            supersetPosition: set.supersetPosition,
                            done: set.done,
                            values: set.values.map {
                                BackupFileV19.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
                            }
                        )
                    }
                )
            }
        }
        return BackupFileV19(
            formatVersion: 19,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV19.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    secondaryMuscleGroupNames: exercise.secondaryMuscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    sides: exercise.sides,
                    offersAssistance: exercise.offersAssistance,
                    fields: exercise.fields.map { BackupFileV19.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey,
                    restSeconds: exercise.restSeconds
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV19.WorkoutRecord(
                    id: workout.id, name: workout.name, date: workout.date, notes: workout.notes,
                    durationSeconds: workout.durationSeconds, exercises: entries(workout.exercises, inTemplate: false)
                )
            },
            templates: templates?.map { template in
                BackupFileV19.TemplateRecord(
                    id: template.id, name: template.name, notes: template.notes, archived: template.archived,
                    plannedFor: template.plannedFor, exercises: entries(template.exercises, inTemplate: true)
                )
            }
        )
    }
}
