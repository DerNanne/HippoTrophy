import CoreData
import Foundation
import SQLite3
import SwiftData
import Testing
@testable import HippoTrophy

/// Next to this file lies one store per schema version in `AppMigrationPlan`
/// — `SchemaV1.store` and so on — each `CoverageBackup.json` imported by the
/// app as it was under that version. A device can hold any of them, so each
/// has to open under today's app and hold what it held.
///
/// The files are written once, by `writeTheNewestStore`, and never again.
@MainActor
struct StoreFixtureTests {
    private final class BundleToken {}

    private static let versions = AppMigrationPlan.schemas.map { String(describing: $0) }

    /// A copy of the version's store in a folder of its own: opening a store
    /// writes to it, so the original is never opened.
    private func copyOfStore(_ version: String) throws -> URL {
        let fixture = try #require(
            Bundle(for: BundleToken.self).url(forResource: version, withExtension: "store"),
            "\(version).store is missing; see writeTheNewestStore"
        )
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }

    /// A version, once a store was written in it, keeps its shape. SwiftData
    /// does not hold anyone to that: a store whose shape differs a little from
    /// its version is quietly migrated, so a model changed without a new
    /// version would pass the test below and leave the plan wrong about what
    /// is out there. This compares the shape itself.
    @Test(arguments: versions)
    func everyVersionStillHasTheShapeItsStoreWasWrittenIn(version: String) throws {
        let schema = try #require(AppMigrationPlan.schemas.first { String(describing: $0) == version })
        let url = try copyOfStore(version)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: schema.models))
        #expect(
            model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata),
            "\(version) no longer matches \(version).store. A model changed: freeze \(version)'s models as they were and add the change as a new version."
        )
    }

    @Test(arguments: versions)
    func everyVersionsStoreOpensWithEverythingInIt(version: String) throws {
        let url = try copyOfStore(version)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try AppSchema.openStore(at: url)

        // Each store holds the file it was written from, brought forward. A
        // `SchemaV1` store came from format 8 and knows no catalog, a
        // `SchemaV2` store's entries carry no key, a `SchemaV3` store knows
        // two ways of training rather than three, a `SchemaV4` store no
        // secondary muscles, a `SchemaV5` store no help, a `SchemaV6` store
        // no templates, a `SchemaV7` store no planned sets, a `SchemaV8`
        // store no rests, a `SchemaV9` store no durations, a `SchemaV10`
        // store no day variants, a `SchemaV11` store no instructions, a
        // `SchemaV12` store no gyms, a `SchemaV13` store no start sides; a store
        // that held a category of the user's own holds none now, nor does
        // its file brought forward; a `SchemaV15` store has no photos, a
        // `SchemaV16` store none of a machine, a `SchemaV17` store frames
        // none. None is
        // run through `CatalogSync` here,
        // so each still holds exactly what it was given.
        let file: BackupFile = switch version {
        case "SchemaV1": try CoverageBackup.readFormatEight()
        case "SchemaV2": try Self.withoutKeysOnEntries(CoverageBackup.readFormatNine())
        case "SchemaV3": try CoverageBackup.readFormatTen()
        case "SchemaV4": try CoverageBackup.readFormatEleven()
        case "SchemaV5": try CoverageBackup.readFormatTwelve()
        case "SchemaV6": try CoverageBackup.readFormatThirteen()
        case "SchemaV7": try CoverageBackup.readFormatFourteen()
        case "SchemaV8": try CoverageBackup.readFormatFifteen()
        case "SchemaV9": try CoverageBackup.readFormatSixteen()
        case "SchemaV10": try CoverageBackup.readFormatSeventeen()
        case "SchemaV11": try CoverageBackup.readFormatEighteen()
        case "SchemaV12": try CoverageBackup.readFormatNineteen()
        case "SchemaV13": try CoverageBackup.readFormatTwenty()
        case "SchemaV14": try CoverageBackup.readFormatTwentyOne()
        case "SchemaV15": try CoverageBackup.readFormatTwentyTwo()
        case "SchemaV16": try CoverageBackup.readFormatTwentyThree()
        case "SchemaV17": try CoverageBackup.readFormatTwentyFour()
        case "SchemaV18": try CoverageBackup.readFormatTwentyFive()
        default: try CoverageBackup.read()
        }
        try CoverageBackup.expectExport(of: ModelContext(container), toBe: file)
    }

    /// Since `SchemaV15` the only categories are the app's: an exercise filed
    /// under the user's own is left without one and nothing says so.
    @Test func aStoreDropsACategoryOfTheUsersOwnWithoutSayingSo() throws {
        let url = try copyOfStore("SchemaV14")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let context = ModelContext(try AppSchema.openStore(at: url))
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        #expect(definitions.first { $0.name == "Bouldering" }?.categoryName == "")
        #expect(definitions.allSatisfy { $0.categoryName.isEmpty || $0.category != nil })
    }

    /// A `SchemaV2` store has no place for a key on an entry, so what it gives
    /// back has none.
    private static func withoutKeysOnEntries(_ file: BackupFile) -> BackupFile {
        var file = file
        file.workouts = file.workouts?.map { workout in
            var workout = workout
            workout.exercises = workout.exercises.map { var entry = $0; entry.catalogKey = nil; return entry }
            return workout
        }
        return file
    }

    /// Writes the store of the newest schema version next to this file. Run
    /// by hand, once, in the branch that adds the version:
    ///
    ///     TEST_RUNNER_WRITE_STORE_FIXTURE=1 xcodebuild test … \
    ///         '-only-testing:HippoTrophyTests/StoreFixtureTests/writeTheNewestStore()'
    ///
    /// The simulator writes straight into the source folder. The store is
    /// copied into a single file, because SQLite keeps recent writes in a
    /// separate log that a plain copy would leave behind.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WRITE_STORE_FIXTURE"] != nil))
    func writeTheNewestStore() throws {
        let newest = String(describing: try #require(AppMigrationPlan.schemas.last))
        let target = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "\(newest).store")

        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "default.store")

        let container = try AppSchema.openStore(at: url)
        try CoverageBackup.importFile(CoverageBackup.read(), into: ModelContext(container))

        try? FileManager.default.removeItem(at: target)
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        let quoted = target.path.replacingOccurrences(of: "'", with: "''")
        try #require(sqlite3_exec(database, "VACUUM INTO '\(quoted)'", nil, nil, nil) == SQLITE_OK, "\(String(cString: sqlite3_errmsg(database)))")
    }
}
