import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// `CoverageBackup.json` and the comparison that says a store holds exactly
/// what the file does — shared by the backup's round trip and the store
/// fixtures, which are that file imported under each schema version.
@MainActor
enum CoverageBackup {
    private final class BundleToken {}

    /// The file in today's format.
    static func read() throws -> BackupFile {
        try read("CoverageBackup")
    }

    /// The file as format 8 had it — what the first testers hold — brought
    /// forward to today's by the frozen types the app no longer uses.
    static func readFormatEight() throws -> BackupFile {
        try BackupCoding.decoder.decode(BackupFileV8.self, from: data("CoverageBackup-v8")).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
    }

    /// The file as format 9 had it — the first with the catalog — brought
    /// forward to today's.
    static func readFormatNine() throws -> BackupFile {
        try BackupCoding.decoder.decode(BackupFileV9.self, from: data("CoverageBackup-v9")).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
    }

    /// The file as format 10 had it — the last with one-sided training as a
    /// switch — brought forward to today's.
    static func readFormatTen() throws -> BackupFile {
        try BackupCoding.decoder.decode(BackupFileV10.self, from: data("CoverageBackup-v10")).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
    }

    /// The file as format 11 had it — the last without secondary muscles —
    /// read the way the app reads such a file.
    static func readFormatEleven() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v11"))
    }

    /// The file as format 12 had it — the last without assistance — read the
    /// way the app reads such a file.
    static func readFormatTwelve() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v12"))
    }

    /// The file as format 13 had it — the last without templates — read the
    /// way the app reads such a file.
    static func readFormatThirteen() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v13"))
    }

    /// The file as format 14 had it — the last without done sets — read the
    /// way the app reads such a file.
    static func readFormatFourteen() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v14"))
    }

    /// The file as format 15 had it — the last without rests — read the way
    /// the app reads such a file.
    static func readFormatFifteen() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v15"))
    }

    /// The file as format 16 had it — the last without a workout's
    /// duration — read the way the app reads such a file.
    static func readFormatSixteen() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v16"))
    }

    /// The file as format 17 had it — the last without day variants — read
    /// the way the app reads such a file.
    static func readFormatSeventeen() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v17"))
    }

    /// The file as format 18 had it — the last without instructions — read
    /// the way the app reads such a file.
    static func readFormatEighteen() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v18"))
    }

    /// The file as format 19 had it — the last without gyms and machines —
    /// read the way the app reads such a file.
    static func readFormatNineteen() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v19"))
    }

    /// The file as format 20 had it — the last without a start side or an
    /// order across sides — read the way the app reads such a file.
    static func readFormatTwenty() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v20"))
    }

    /// The file as format 21 had it — the last with categories of the user's
    /// own — read the way the app reads such a file.
    static func readFormatTwentyOne() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v21"))
    }

    /// The file as format 22 had it — the last without photos — read the way
    /// the app reads such a file.
    static func readFormatTwentyTwo() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v22"))
    }

    /// The file as format 23 had it — the last without a machine's photo —
    /// read the way the app reads such a file.
    static func readFormatTwentyThree() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v23"))
    }

    /// The file as format 24 had it — the last without a photo's framing —
    /// read the way the app reads such a file.
    static func readFormatTwentyFour() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v24"))
    }

    /// The format-24 file as a package, with its two photos.
    static func packageFormatTwentyFour() throws -> BackupPackage {
        try package("CoverageBackup-v24")
    }

    /// The file as format 25 had it — the last without Isometrics — read the
    /// way the app reads such a file.
    static func readFormatTwentyFive() throws -> BackupFile {
        try BackupCoding.readBackup(from: data("CoverageBackup-v25"))
    }

    /// The format-25 file as a package, with its two photos, one framed.
    static func packageFormatTwentyFive() throws -> BackupPackage {
        try package("CoverageBackup-v25")
    }

    /// The file in today's format as a package, with the photos it names.
    /// Zipped on a computer, so it also says the app reads what others write.
    static func package() throws -> BackupPackage {
        try package("CoverageBackup")
    }

    /// The format-23 file as a package, with the exercise's photo.
    static func packageFormatTwentyThree() throws -> BackupPackage {
        try package("CoverageBackup-v23")
    }

    private static func package(_ name: String) throws -> BackupPackage {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "zip"))
        return try BackupPackage.read(from: Data(contentsOf: url))
    }

    /// The raw file, as `readBackup` would be handed it.
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private static func read(_ name: String) throws -> BackupFile {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"))
        return try BackupCoding.readBackup(from: Data(contentsOf: url))
    }

    /// Imports the file into an empty store, the way the Backup menu does with
    /// nothing to ask: the file is one the app wrote, so nothing needs review.
    static func importFile(_ file: BackupFile, into context: ModelContext) throws {
        let plan = ImportPlanner.plan(file: file, existing: [], knownWorkoutIDs: [])
        #expect(!plan.needsReview)
        let summary = BackupImporter(context: context).apply(plan, decisions: ImportDecisions(), selection: ImportSelection(), photos: try package().photos)
        try context.save()
        #expect(summary.unknownMuscles.isEmpty)
        #expect(summary.photosMissing == 0)
    }

    /// Exports the store the way the Backup menu does and expects the file
    /// back, workout by workout so a difference names the workout. A file
    /// without templates expects a store without any.
    static func expectExport(of context: ModelContext, toBe file: BackupFile) throws {
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>(sortBy: [SortDescriptor(\.orderIndex)]))
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: WorkoutSession.trained, sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
        let templates = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: WorkoutSession.templates, sortBy: [SortDescriptor(\.templateOrder)]
        ))
        let expectedTemplates = file.templates ?? []
        let exportedTemplates = templates.map(BackupExporter.templateRecord)
        #expect(exportedTemplates.map(\.id) == expectedTemplates.map(\.id))
        for (template, original) in zip(exportedTemplates, expectedTemplates) {
            var template = template, original = original
            template.exercises = sidesApart(template.exercises)
            original.exercises = sidesApart(original.exercises)
            #expect(try json(template) == json(original), "template \(original.name)")
        }

        // One package, so the photos are numbered as the Backup menu numbers
        // them: the exercises' first, then the machines'.
        let package = BackupExporter.package(
            definitions: definitions, sessions: nil,
            gyms: try context.fetch(FetchDescriptor<Gym>()),
            machines: try context.fetch(FetchDescriptor<Machine>())
        )
        #expect(try json(package.file.exercises) == json(file.exercises))
        #expect(try json(package.file.gyms ?? []) == json(file.gyms ?? []))
        #expect(try json(package.file.machines ?? []) == json(file.machines ?? []))

        let expected = file.workouts ?? []
        let exported = sessions.map(BackupExporter.record)
        #expect(exported.map(\.id) == expected.map(\.id))
        for (workout, original) in zip(exported, expected) {
            #expect(try json(sidesApart(workout)) == json(sidesApart(original)), "\(original.name) on \(original.date)")
        }
    }

    private static func json(_ value: some Encodable) throws -> String {
        String(decoding: try BackupCoding.encoder.encode(value), as: UTF8.self)
    }

    /// A left/right log numbers each side on its own, and the export sorts by
    /// that number — so the left and the right set of the same number come out
    /// in whatever order the store hands them over. Only the order within a
    /// side means anything, and that is what is compared.
    private static func sidesApart(_ workout: WorkoutRecord) -> WorkoutRecord {
        var workout = workout
        workout.exercises = sidesApart(workout.exercises)
        return workout
    }

    private static func sidesApart(_ entries: [EntryRecord]) -> [EntryRecord] {
        entries.map { entry in
            var entry = entry
            entry.sets = SetSide.allCases.flatMap { side in entry.sets.filter { $0.side == side.rawValue } }
            return entry
        }
    }
}
