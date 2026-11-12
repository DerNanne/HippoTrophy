import Foundation

/// Format 20, frozen when format 21 brought the side an entry starts with and
/// the order across a set's sides. Differs from format 19 by gyms and
/// machines, a workout's and a template's `gym` and an entry's `machine`.
///
/// Read only to be brought forward: `upgraded()` turns it into format 21.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV20: Codable {
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

    /// Format 21 brings the side an entry starts with and the order across
    /// sides. Nothing logged so far said either, and nothing is guessed.
    func upgraded() -> BackupFileV21 {
        func entries(_ records: [EntryRecord]) -> [BackupFileV21.EntryRecord] {
            records.map { entry in
                BackupFileV21.EntryRecord(
                    exercise: entry.exercise,
                    catalogKey: entry.catalogKey,
                    notes: entry.notes,
                    instructions: entry.instructions,
                    mode: entry.mode,
                    assistance: entry.assistance,
                    effortScale: entry.effortScale,
                    supersetGroup: entry.supersetGroup,
                    machine: entry.machine,
                    startSide: nil,
                    sets: entry.sets.map { set in
                        BackupFileV21.SetRecord(
                            side: set.side,
                            effort: set.effort,
                            supersetPosition: set.supersetPosition,
                            sideOrder: nil,
                            done: set.done,
                            values: set.values.map {
                                BackupFileV21.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
                            }
                        )
                    }
                )
            }
        }
        return BackupFileV21(
            formatVersion: 21,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV21.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    secondaryMuscleGroupNames: exercise.secondaryMuscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    sides: exercise.sides,
                    offersAssistance: exercise.offersAssistance,
                    fields: exercise.fields.map { BackupFileV21.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey,
                    restSeconds: exercise.restSeconds
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV21.WorkoutRecord(
                    id: workout.id, name: workout.name, date: workout.date, notes: workout.notes,
                    durationSeconds: workout.durationSeconds, gym: workout.gym, exercises: entries(workout.exercises)
                )
            },
            templates: templates?.map { template in
                BackupFileV21.TemplateRecord(
                    id: template.id, name: template.name, notes: template.notes, archived: template.archived,
                    plannedFor: template.plannedFor, gym: template.gym, exercises: entries(template.exercises)
                )
            },
            gyms: gyms?.map { BackupFileV21.GymRecord(name: $0.name, machines: $0.machines) },
            machines: machines?.map { BackupFileV21.MachineRecord(name: $0.name) }
        )
    }
}
