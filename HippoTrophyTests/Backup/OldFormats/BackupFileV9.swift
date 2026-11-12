import Foundation
@testable import HippoTrophy

/// Format 9, the first with the catalog, frozen when format 10 added
/// `catalogKey` to a workout's entry. Differs from format 8 by `catalogKey`
/// on an exercise.
///
/// The app no longer reads it (formats before 11 are refused); it stays
/// here to bring forward the coverage file of its version, which the store
/// fixtures of that time were written from. Read only to be brought forward: `upgraded()` turns it into format 10,
/// and that one on into today's.
/// Never edit — a file someone holds is in exactly this shape.
nonisolated struct BackupFileV9: Codable {
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

    /// Format 10 adds `catalogKey` to an entry. In format 9 an entry named
    /// its exercise and nothing more, so its key is the one the file's
    /// exercise of that name carries — the exercise it was logged from.
    func upgraded() -> BackupFileV10 {
        var keyByName: [String: String] = [:]
        for exercise in exercises ?? [] {
            if let key = exercise.catalogKey, keyByName[exercise.name.exerciseKey] == nil {
                keyByName[exercise.name.exerciseKey] = key
            }
        }
        return BackupFileV10(
            formatVersion: 10,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV10.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    allowsSides: exercise.allowsSides,
                    fields: exercise.fields.map { BackupFileV10.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: exercise.catalogKey
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV10.WorkoutRecord(
                    id: workout.id,
                    name: workout.name,
                    date: workout.date,
                    notes: workout.notes,
                    exercises: workout.exercises.map { entry in
                        BackupFileV10.EntryRecord(
                            exercise: entry.exercise,
                            catalogKey: keyByName[entry.exercise.exerciseKey],
                            notes: entry.notes,
                            mode: entry.mode,
                            effortScale: entry.effortScale,
                            supersetGroup: entry.supersetGroup,
                            sets: entry.sets.map { set in
                                BackupFileV10.SetRecord(
                                    side: set.side,
                                    effort: set.effort,
                                    supersetPosition: set.supersetPosition,
                                    values: set.values.map {
                                        BackupFileV10.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
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
