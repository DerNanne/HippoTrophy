import Foundation

/// Format 21, frozen when format 22 took the user's own categories out. Differs
/// from format 20 by the side an entry starts with and the order across a
/// set's sides.
///
/// Read only to be brought forward: `upgraded()` turns it into format 22.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV21: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var exercises: [ExerciseRecord]?
    var workouts: [WorkoutRecord]?
    var templates: [TemplateRecord]?
    var gyms: [GymRecord]?
    var machines: [MachineRecord]?

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
        var gym: String?
        var exercises: [EntryRecord]
    }

    struct TemplateRecord: Codable {
        var id: UUID
        var name: String
        var notes: String
        var archived: Bool
        var plannedFor: Date?
        var gym: String?
        var exercises: [EntryRecord]
    }

    struct EntryRecord: Codable {
        var exercise: String
        var catalogKey: String?
        var notes: String
        var instructions: String
        var mode: String
        var assistance: String
        var effortScale: String
        var supersetGroup: Int?
        var machine: String?
        var startSide: String?
        var sets: [SetRecord]
    }

    struct GymRecord: Codable {
        var name: String
        var machines: [String]
    }

    struct MachineRecord: Codable {
        var name: String
    }

    struct SetRecord: Codable {
        var side: String
        var effort: Double?
        var supersetPosition: Int?
        var sideOrder: Int?
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

    /// Format 22 knows only the categories the app ships with. An exercise
    /// filed under one of the user's own arrives without a category, silently,
    /// as it does in a store: `AppMigrationPlan.v14ToV15`.
    func upgraded() -> BackupFileV22 {
        func entries(_ records: [EntryRecord]) -> [BackupFileV22.EntryRecord] {
            records.map { entry in
                BackupFileV22.EntryRecord(
                    exercise: entry.exercise,
                    catalogKey: entry.catalogKey,
                    notes: entry.notes,
                    instructions: entry.instructions,
                    mode: entry.mode,
                    assistance: entry.assistance,
                    effortScale: entry.effortScale,
                    supersetGroup: entry.supersetGroup,
                    machine: entry.machine,
                    startSide: entry.startSide,
                    sets: entry.sets.map { set in
                        BackupFileV22.SetRecord(
                            side: set.side,
                            effort: set.effort,
                            supersetPosition: set.supersetPosition,
                            sideOrder: set.sideOrder,
                            done: set.done,
                            values: set.values.map {
                                BackupFileV22.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
                            }
                        )
                    }
                )
            }
        }
        return BackupFileV22(
            formatVersion: 22,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV22.ExerciseRecord(
                    name: exercise.name,
                    category: ExerciseCategory.resolve(exercise.category) == nil ? "" : exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    secondaryMuscleGroupNames: exercise.secondaryMuscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    sides: exercise.sides,
                    offersAssistance: exercise.offersAssistance,
                    fields: exercise.fields.map { BackupFileV22.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey,
                    restSeconds: exercise.restSeconds
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV22.WorkoutRecord(
                    id: workout.id, name: workout.name, date: workout.date, notes: workout.notes,
                    durationSeconds: workout.durationSeconds, gym: workout.gym, exercises: entries(workout.exercises)
                )
            },
            templates: templates?.map { template in
                BackupFileV22.TemplateRecord(
                    id: template.id, name: template.name, notes: template.notes, archived: template.archived,
                    plannedFor: template.plannedFor, gym: template.gym, exercises: entries(template.exercises)
                )
            },
            gyms: gyms?.map { BackupFileV22.GymRecord(name: $0.name, machines: $0.machines) },
            machines: machines?.map { BackupFileV22.MachineRecord(name: $0.name) }
        )
    }
}
