import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The exporter's one piece of derived logic: turning a superset's shared,
/// device-only id into a small number that means something only within its
/// own workout.
@MainActor
struct BackupExporterTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func entry(_ name: String, order: Int, supersetID: UUID? = nil, session: WorkoutSession, in context: ModelContext) {
        let entry = ExerciseEntry(name: name, orderIndex: order, definitionID: UUID(), supersetID: supersetID, effortScale: .off, session: session)
        context.insert(entry)
    }

    @Test func pairedEntriesGetTheSameGroupNumber() throws {
        let context = try context()
        let session = WorkoutSession()
        context.insert(session)
        let supersetID = UUID()
        entry("Curl", order: 0, supersetID: supersetID, session: session, in: context)
        entry("Pushdown", order: 1, supersetID: supersetID, session: session, in: context)
        entry("Squat", order: 2, session: session, in: context)

        let record = BackupExporter.record(session)
        #expect(group("Curl", in: record) == group("Pushdown", in: record))
        #expect(group("Curl", in: record) != nil)
        #expect(group("Squat", in: record) == nil)
    }

    @Test func twoSupersetsGetDifferentNumbers() throws {
        let context = try context()
        let session = WorkoutSession()
        context.insert(session)
        let first = UUID()
        let second = UUID()
        entry("Curl", order: 0, supersetID: first, session: session, in: context)
        entry("Squat", order: 1, supersetID: second, session: session, in: context)
        entry("Pushdown", order: 2, supersetID: first, session: session, in: context)
        entry("Lunge", order: 3, supersetID: second, session: session, in: context)

        let record = BackupExporter.record(session)
        #expect(group("Curl", in: record) == group("Pushdown", in: record))
        #expect(group("Squat", in: record) == group("Lunge", in: record))
        #expect(group("Curl", in: record) != group("Squat", in: record))
    }

    /// Single-level optional on purpose: looking a name up in a
    /// `[String: Int?]` dictionary would return `Int??`, where "the key is
    /// missing" and "the key is there with no group" compare equal to `nil`
    /// the same way — exactly the distinction this file needs to draw.
    private func group(_ name: String, in record: WorkoutRecord) -> Int? {
        record.exercises.first { $0.exercise == name }?.supersetGroup
    }

    @Test func aSetCarriesItsSupersetPosition() throws {
        let context = try context()
        let set = SetEntry(setNumber: 2, supersetPosition: 3)
        context.insert(set)
        #expect(BackupExporter.record(set).supersetPosition == 3)
        let plain = SetEntry(setNumber: 1)
        context.insert(plain)
        #expect(BackupExporter.record(plain).supersetPosition == nil)
    }

    @Test func anEntryWritesItsScaleAndEachSetItsRating() throws {
        let context = try context()
        let session = WorkoutSession()
        context.insert(session)
        let entry = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .levels, session: session)
        context.insert(entry)
        let rated = entry.addSet(on: .both, definition: nil, in: context)
        rated.effort = .level(.normal)
        entry.addSet(on: .both, definition: nil, in: context)

        let record = BackupExporter.record(entry)
        #expect(record.effortScale == "levels")
        #expect(record.sets.map(\.effort) == [1, nil])
    }
}
