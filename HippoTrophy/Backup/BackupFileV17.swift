import Foundation

/// Format 17, frozen when format 18 gave a template the day it was adjusted
/// for. Differs from format 16 by `durationSeconds` on a workout.
///
/// Read only to be brought forward: `upgraded()` turns it into format 18.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV17: Codable {
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

    /// Format 18 gives a template the day it was adjusted for. Every
    /// template was one kept for good.
    func upgraded() -> BackupFileV18 {
        func entries(_ records: [EntryRecord]) -> [BackupFileV18.EntryRecord] {
            records.map { entry in
                BackupFileV18.EntryRecord(
                    exercise: entry.exercise,
                    catalogKey: entry.catalogKey,
                    notes: entry.notes,
                    mode: entry.mode,
                    assistance: entry.assistance,
                    effortScale: entry.effortScale,
                    supersetGroup: entry.supersetGroup,
                    sets: entry.sets.map { set in
                        BackupFileV18.SetRecord(
                            side: set.side,
                            effort: set.effort,
                            supersetPosition: set.supersetPosition,
                            done: set.done,
                            values: set.values.map {
                                BackupFileV18.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
                            }
                        )
                    }
                )
            }
        }
        return BackupFileV18(
            formatVersion: 18,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV18.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    secondaryMuscleGroupNames: exercise.secondaryMuscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    sides: exercise.sides,
                    offersAssistance: exercise.offersAssistance,
                    fields: exercise.fields.map { BackupFileV18.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey,
                    restSeconds: exercise.restSeconds
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV18.WorkoutRecord(
                    id: workout.id, name: workout.name, date: workout.date, notes: workout.notes,
                    durationSeconds: workout.durationSeconds, exercises: entries(workout.exercises)
                )
            },
            templates: templates?.map { template in
                BackupFileV18.TemplateRecord(
                    id: template.id, name: template.name, notes: template.notes, archived: template.archived,
                    plannedFor: nil, exercises: entries(template.exercises)
                )
            }
        )
    }
}
