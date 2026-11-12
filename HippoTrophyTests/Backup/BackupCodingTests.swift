import Foundation
import Testing
@testable import HippoTrophy

/// One encoder and one decoder for the whole backup path. These tests are about
/// what can silently go wrong: a date that comes back as another date, and a
/// file the reader is not entitled to read.
struct BackupCodingTests {
    /// Whole seconds, because ISO 8601 does not carry a fraction — a date with
    /// one would fail this test for the wrong reason.
    private let exportedAt = Date(timeIntervalSince1970: 1_788_000_000)

    private func roundTrip(_ file: BackupFile) throws -> BackupFile {
        try BackupCoding.readBackup(from: try BackupCoding.encoder.encode(file))
    }

    @Test func aFileTheAppWroteReadsBackAsItself() throws {
        let file = BackupFile(
            exportedAt: exportedAt,
            exercises: [
                ExerciseRecord(
                    name: "Rows", category: "Strength", muscleGroupNames: ["back"], tracksSets: true, sides: "either",
                    fields: [FieldRecord(key: "f1", label: "Distance", type: "number")]
                )
            ],
            workouts: [
                WorkoutRecord(
                    id: UUID(), name: "Pull", date: exportedAt, notes: "felt good",
                    exercises: [
                        EntryRecord(
                            exercise: "Rows", notes: "", mode: "bilateral", effortScale: "levels",
                            sets: [SetRecord(side: "both", effort: 0, values: [
                                ValueRecord(key: "weight", label: "Weight", type: "weight", text: nil, number: 60),
                                ValueRecord(key: "f1", label: "Distance", type: "number", text: nil, number: 30)
                            ])]
                        )
                    ]
                )
            ]
        )

        let decoded = try roundTrip(file)
        #expect(decoded.exportedAt == exportedAt)
        #expect(decoded.formatVersion == BackupFile.currentFormatVersion)
        #expect(decoded.exercises?.first?.fields.first?.label == "Distance")
        #expect(decoded.workouts?.first?.exercises.first?.sets.first?.values.map(\.number) == [60, 30])
        #expect(decoded.workouts?.first?.exercises.first?.effortScale == "levels")
        #expect(decoded.workouts?.first?.exercises.first?.sets.first?.effort == 0)
    }

    @Test func datesAreWrittenReadablyRatherThanAsANumber() throws {
        let data = try BackupCoding.encoder.encode(BackupFile(exportedAt: exportedAt))
        #expect(String(decoding: data, as: UTF8.self).contains("2026-"))
    }

    /// Only versions the app knows read. A file from before format 8 would be
    /// defaulted into a different shape, a newer one silently stripped —
    /// both refused.
    @Test func anyOtherVersionIsRefused() {
        for version in [7, BackupFile.currentFormatVersion + 1] {
            let json = #"{"exportedAt": "2026-01-01T00:00:00Z", "formatVersion": \#(version)}"#
            #expect(throws: BackupReadError.otherFormat(version)) {
                try BackupCoding.readBackup(from: Data(json.utf8))
            }
        }
    }

    @Test func aFileWithoutAVersionIsAnError() {
        let json = #"{"exportedAt": "2026-01-01T00:00:00Z"}"#
        #expect(throws: (any Error).self) {
            try BackupCoding.readBackup(from: Data(json.utf8))
        }
    }

    @Test func aSupersetGroupSurvivesTheRoundTrip() throws {
        let file = BackupFile(
            exportedAt: exportedAt,
            workouts: [
                WorkoutRecord(id: UUID(), name: "", date: exportedAt, notes: "", exercises: [
                    EntryRecord(exercise: "Curl", notes: "", mode: "bilateral", effortScale: "levels", supersetGroup: 1, sets: []),
                    EntryRecord(exercise: "Pushdown", notes: "", mode: "bilateral", effortScale: "levels", supersetGroup: 1, sets: []),
                    EntryRecord(exercise: "Squat", notes: "", mode: "bilateral", effortScale: "levels", supersetGroup: nil, sets: [])
                ])
            ]
        )

        let decoded = try roundTrip(file)
        let entries = try #require(decoded.workouts?.first?.exercises)
        #expect(entries.map(\.supersetGroup) == [1, 1, nil])
    }

    @Test func everySectionIsOptionalOnBothSides() throws {
        let decoded = try roundTrip(BackupFile(exportedAt: exportedAt))
        #expect(decoded.exercises == nil)
        #expect(decoded.workouts == nil)
        #expect(decoded.isEmpty)
    }
}
