import Foundation
@testable import HippoTrophy

/// Format 8, as the first builds outside the owner's hands wrote it, frozen
/// when format 9 added `catalogKey` to an exercise.
///
/// The app no longer reads it (formats before 11 are refused); it stays
/// here to bring forward the coverage file of its version, which the store
/// fixtures of that time were written from. Read only to be brought forward: `upgraded()` turns it into format 9, and
/// that one on into today's — the way every older file reaches it. Never edit — a file someone holds is
/// in exactly this shape. The records are copied rather than shared with
/// format 9, so a later change to one of them cannot reach back into this.
nonisolated struct BackupFileV8: Codable {
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

    /// Format 9 adds only `catalogKey`, and a format-8 exercise is never a
    /// catalog exercise: the catalog did not exist. If it carries a catalog
    /// exercise's name, `CatalogSync` decides that on the next launch, the
    /// same way it does for one typed in.
    func upgraded() -> BackupFileV9 {
        BackupFileV9(
            formatVersion: 9,
            exportedAt: exportedAt,
            exercises: exercises?.map { exercise in
                BackupFileV9.ExerciseRecord(
                    name: exercise.name,
                    category: exercise.category,
                    muscleGroupNames: exercise.muscleGroupNames,
                    tracksSets: exercise.tracksSets,
                    allowsSides: exercise.allowsSides,
                    fields: exercise.fields.map { BackupFileV9.FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
                    catalogKey: nil
                )
            },
            workouts: workouts?.map { workout in
                BackupFileV9.WorkoutRecord(
                    id: workout.id,
                    name: workout.name,
                    date: workout.date,
                    notes: workout.notes,
                    exercises: workout.exercises.map { entry in
                        BackupFileV9.EntryRecord(
                            exercise: entry.exercise,
                            notes: entry.notes,
                            mode: entry.mode,
                            effortScale: entry.effortScale,
                            supersetGroup: entry.supersetGroup,
                            sets: entry.sets.map { set in
                                BackupFileV9.SetRecord(
                                    side: set.side,
                                    effort: set.effort,
                                    supersetPosition: set.supersetPosition,
                                    values: set.values.map {
                                        BackupFileV9.ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number)
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
