import Foundation

/// Format 14, frozen when format 15 told a set done from one only planned.
/// Differs from format 13 by `templates`.
///
/// Read only to be brought forward: `upgraded()` turns it into format 15.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV14: Codable {
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
        var values: [ValueRecord]
    }

    struct ValueRecord: Codable {
        var key: String
        var label: String
        var type: String
        var text: String?
        var number: Double?
    }

    /// Format 15 tells a set done from one only planned. Every set logged
    /// before was done, and so is every set a template held: the template
    /// starts its workouts with planned sets of its own, whatever it says.
    func upgraded() -> BackupFileV15 {
        func entries(_ records: [EntryRecord]) -> [BackupFileV15.EntryRecord] {
            records.map { entry in
                BackupFileV15.EntryRecord(
                    exercise: entry.exercise,
                    catalogKey: entry.catalogKey,
                    notes: entry.notes,
                    mode: entry.mode,
                    assistance: entry.assistance,
                    effortScale: entry.effortScale,
                    supersetGroup: entry.supersetGroup,
                    sets: entry.sets.map { set in
                        BackupFileV15.SetRecord(
                            side: set.side,
                            effort: set.effort,
                            supersetPosition: set.supersetPosition,
                            done: true,
                            values: set.values.map {
                                BackupFileV15.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
                            }
                        )
                    }
                )
            }
        }
        return BackupFileV15(
            formatVersion: 15,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV15.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    secondaryMuscleGroupNames: exercise.secondaryMuscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    sides: exercise.sides,
                    offersAssistance: exercise.offersAssistance,
                    fields: exercise.fields.map { BackupFileV15.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV15.WorkoutRecord(
                    id: workout.id, name: workout.name, date: workout.date, notes: workout.notes,
                    exercises: entries(workout.exercises)
                )
            },
            templates: templates?.map { template in
                BackupFileV15.TemplateRecord(
                    id: template.id, name: template.name, notes: template.notes, archived: template.archived,
                    exercises: entries(template.exercises)
                )
            }
        )
    }
}
