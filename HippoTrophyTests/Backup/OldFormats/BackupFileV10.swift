import Foundation
@testable import HippoTrophy

/// Format 10, frozen when format 11 replaced `allowsSides` on an exercise
/// with `sides`. Differs from format 9 by `catalogKey` on a workout's entry.
///
/// The app no longer reads it (formats before 11 are refused); it stays
/// here to bring forward the coverage file of its version, which the store
/// fixtures of that time were written from. Read only to be brought forward: `upgraded()` turns it into format 11.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV10: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var exercises: [ExerciseRecord]?
    var workouts: [WorkoutRecord]?

    struct ExerciseRecord: Codable {
        var name: String
        var category: String
        var muscleGroupNames: [String]
        var tracksSets: Bool
        var allowsSides: Bool
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

    /// Format 11 says how an exercise is trained in three ways rather than
    /// two. One-sided training on offer meant either way, off meant
    /// two-sided. A catalog exercise's way is the catalog's, whatever the file
    /// says — the import does not ask about it, and `CatalogSync` moves the
    /// entries that no longer fit.
    func upgraded() -> BackupFileV11 {
        BackupFileV11(
            formatVersion: 11,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV11.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    sides: (exercise.allowsSides ? ExerciseSides.either : .both).rawValue,
                    fields: exercise.fields.map { BackupFileV11.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV11.WorkoutRecord(
                    id: workout.id,
                    name: workout.name,
                    date: workout.date,
                    notes: workout.notes,
                    exercises: workout.exercises.map { entry in
                        BackupFileV11.EntryRecord(
                            exercise: entry.exercise,
                            catalogKey: entry.catalogKey,
                            notes: entry.notes,
                            mode: entry.mode,
                            effortScale: entry.effortScale,
                            supersetGroup: entry.supersetGroup,
                            sets: entry.sets.map { set in
                                BackupFileV11.SetRecord(
                                    side: set.side,
                                    effort: set.effort,
                                    supersetPosition: set.supersetPosition,
                                    values: set.values.map {
                                        BackupFileV11.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
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
