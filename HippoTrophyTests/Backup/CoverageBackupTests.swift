import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// `CoverageBackup.json`, next to this file, is a backup that holds every kind
/// of thing the app can hold — every field type, mode, side and effort scale,
/// supersets, once-per-workout exercises, empty values, and the odd corners
/// listed in `theOddCornersAreInTheFile`. It is the file to import when a test
/// in the simulator needs a store with all of it.
///
/// It is what an export can look like, not a collection of broken input: a
/// hand-edited file with unknown muscles or a rating its scale cannot hold is
/// the importer's tests' business. States an import cannot produce — an entry
/// whose exercise was deleted, values under a key the exercise no longer has —
/// are not in it either.
///
/// It is in the current format and read with `readBackup`. The files of
/// format 11, the oldest the app reads, and of formats 12 to 15 stay next
/// to it as `CoverageBackup-v11.json`, `-v12` to `-v15` and have to arrive
/// whole. The files of formats 8
/// to 10 — `CoverageBackup-v8.json` (the first testers'), `-v9`, `-v10` —
/// stay because the store fixtures of their time were written from them; the
/// app refuses them, and the frozen types under `OldFormats` bring them
/// forward here only. When the format moves on again, this file is kept
/// under its version and has to arrive whole, and a copy in the new format
/// takes its place.
///
/// `CoverageBackup.zip` is this same file as a package, with the photo it
/// names. It was zipped on a computer, deflated, so that it stands for what
/// others write too. It moves on with the file: `CoverageBackup-v<alt>.zip`
/// stays and is never written again.
@MainActor
struct CoverageBackupTests {
    @Test func importingAndExportingGivesBackTheSameFile() throws {
        let file = try CoverageBackup.read()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        try CoverageBackup.importFile(file, into: context)

        try CoverageBackup.expectExport(of: context, toBe: file)
    }

    /// Fails the day the format changes, on purpose: the file here is then
    /// kept as `CoverageBackup-v26.json`, with a frozen reader, a step to the
    /// new format and a test like the ones below; a copy in the new format
    /// takes its place, in the package too.
    @Test func formatTwentySixIsWhatThisFileIsIn() throws {
        #expect(BackupFile.currentFormatVersion == 26)
        #expect(try CoverageBackup.read().formatVersion == 26)
    }

    /// Format 26 brings the Isometrics category. A format-25 file has nothing
    /// filed under it; this file is that one with exercises added, one of
    /// them under Isometrics.
    @Test func formatTwentySixIsFormatTwentyFiveWithIsometrics() throws {
        let encoder = BackupCoding.encoder
        let twentyFive = try CoverageBackup.readFormatTwentyFive()
        let isometrics = ExerciseCategory.isometrics.name
        #expect(twentyFive.exercises?.contains { $0.category == isometrics } == false)

        let current = try CoverageBackup.read()
        let before = Set((twentyFive.exercises ?? []).map(\.name))
        let added = (current.exercises ?? []).filter { !before.contains($0.name) }
        #expect(added.filter { $0.category == isometrics }.map(\.name) == ["Isometric Leg Extension"])
        let kept = current.exercises?.filter { before.contains($0.name) }
        #expect(try encoder.encode(kept) == encoder.encode(twentyFive.exercises))
        #expect(try encoder.encode(current.machines) == encoder.encode(twentyFive.machines))
        #expect(try encoder.encode(current.gyms) == encoder.encode(twentyFive.gyms))
        #expect(try encoder.encode(current.workouts) == encoder.encode(twentyFive.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(twentyFive.templates))
    }

    /// The format-25 file arrives whole: imported, it exports as the
    /// format-26 file it was brought forward to.
    @Test func theFormatTwentyFiveFileArrivesWhole() throws {
        let twentyFive = try CoverageBackup.readFormatTwentyFive()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(twentyFive, into: context)
        try CoverageBackup.expectExport(of: context, toBe: twentyFive)
    }

    /// The format-25 package still brings both photos with their framing.
    @Test func theFormatTwentyFivePackageArrivesWhole() throws {
        let package = try CoverageBackup.packageFormatTwentyFive()
        #expect(package.file.formatVersion == BackupFile.currentFormatVersion)
        #expect(package.photos.count == 2)
        #expect(package.missingPhotoCount == 0)

        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let plan = ImportPlanner.plan(file: package.file, existing: [], knownWorkoutIDs: [])
        let summary = BackupImporter(context: context).apply(plan, decisions: ImportDecisions(), selection: ImportSelection(), photos: package.photos)
        #expect(summary.photosAdded == 2)
        #expect(try context.fetch(FetchDescriptor<ExercisePhoto>()).map(\.framing) == [PhotoFraming(x: 0.25, y: 0.75, zoom: 2)])
        #expect(try context.fetch(FetchDescriptor<MachinePhoto>()).map(\.framing) == [PhotoFraming(x: 0.5, y: 0.25, zoom: 1.5)])
    }

    /// Format 25 brings a photo's framing. A format-24 file has none; this
    /// file is that one with the exercise's and the machine's photo framed.
    @Test func formatTwentyFiveIsFormatTwentyFourWithFraming() throws {
        let encoder = BackupCoding.encoder
        let twentyFour = try CoverageBackup.readFormatTwentyFour()
        #expect(twentyFour.exercises?.allSatisfy { $0.photoFraming == nil } == true)
        #expect(twentyFour.machines?.allSatisfy { $0.photoFraming == nil } == true)

        let current = try CoverageBackup.readFormatTwentyFive()
        let exercises = current.exercises?.map { var exercise = $0; exercise.photoFraming = nil; return exercise }
        let machines = current.machines?.map { var machine = $0; machine.photoFraming = nil; return machine }
        #expect(try encoder.encode(exercises) == encoder.encode(twentyFour.exercises))
        #expect(try encoder.encode(machines) == encoder.encode(twentyFour.machines))
        #expect(try encoder.encode(current.gyms) == encoder.encode(twentyFour.gyms))
        #expect(try encoder.encode(current.workouts) == encoder.encode(twentyFour.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(twentyFour.templates))
    }

    /// The format-24 file arrives whole: imported, it exports as the
    /// format-25 file it was brought forward to, every photo centred.
    @Test func theFormatTwentyFourFileArrivesWhole() throws {
        let twentyFour = try CoverageBackup.readFormatTwentyFour()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(twentyFour, into: context)
        try CoverageBackup.expectExport(of: context, toBe: twentyFour)
    }

    /// The format-24 package still brings both photos, centred.
    @Test func theFormatTwentyFourPackageArrivesWhole() throws {
        let package = try CoverageBackup.packageFormatTwentyFour()
        #expect(package.photos.count == 2)
        #expect(package.missingPhotoCount == 0)

        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let plan = ImportPlanner.plan(file: package.file, existing: [], knownWorkoutIDs: [])
        let summary = BackupImporter(context: context).apply(plan, decisions: ImportDecisions(), selection: ImportSelection(), photos: package.photos)
        #expect(summary.photosAdded == 2)
        #expect(try context.fetch(FetchDescriptor<ExercisePhoto>()).map(\.framing) == [.centered])
        #expect(try context.fetch(FetchDescriptor<MachinePhoto>()).map(\.framing) == [.centered])
    }

    /// Format 24 brings a photo for a machine. A format-23 file has none;
    /// the format-24 file is that one with one machine naming a photo.
    @Test func formatTwentyFourIsFormatTwentyThreeWithAMachinePhoto() throws {
        let encoder = BackupCoding.encoder
        let twentyThree = try CoverageBackup.readFormatTwentyThree()
        #expect(twentyThree.machines?.allSatisfy { $0.photo == nil } == true)

        let current = try CoverageBackup.readFormatTwentyFour()
        let withoutPhotos = current.machines?.map { var machine = $0; machine.photo = nil; return machine }
        #expect(try encoder.encode(withoutPhotos) == encoder.encode(twentyThree.machines))
        #expect(try encoder.encode(current.exercises) == encoder.encode(twentyThree.exercises))
        #expect(try encoder.encode(current.gyms) == encoder.encode(twentyThree.gyms))
        #expect(try encoder.encode(current.workouts) == encoder.encode(twentyThree.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(twentyThree.templates))
    }

    /// The format-23 file arrives whole: imported, it exports as the
    /// format-24 file it was brought forward to.
    @Test func theFormatTwentyThreeFileArrivesWhole() throws {
        let twentyThree = try CoverageBackup.readFormatTwentyThree()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(twentyThree, into: context)
        try CoverageBackup.expectExport(of: context, toBe: twentyThree)
    }

    /// The format-23 package still brings its exercise's photo, byte for byte.
    @Test func theFormatTwentyThreePackageArrivesWhole() throws {
        let package = try CoverageBackup.packageFormatTwentyThree()
        #expect(package.file.formatVersion == BackupFile.currentFormatVersion)
        #expect(package.photos.count == 1)
        #expect(package.missingPhotoCount == 0)

        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let plan = ImportPlanner.plan(file: package.file, existing: [], knownWorkoutIDs: [])
        let summary = BackupImporter(context: context).apply(plan, decisions: ImportDecisions(), selection: ImportSelection(), photos: package.photos)
        #expect(summary.photosAdded == 1)
        #expect(summary.photosMissing == 0)
        let photos = try context.fetch(FetchDescriptor<ExercisePhoto>())
        #expect(photos.map(\.data) == Array(package.photos.values))
    }

    /// Format 23 brings a photo for an exercise. A format-22 file has none;
    /// the format-23 file is that one with one exercise naming a photo.
    @Test func formatTwentyThreeIsFormatTwentyTwoWithAPhoto() throws {
        let encoder = BackupCoding.encoder
        let twentyTwo = try CoverageBackup.readFormatTwentyTwo()
        #expect(twentyTwo.photoCount == 0)

        let current = try CoverageBackup.readFormatTwentyThree()
        let withoutPhotos = current.exercises?.map { var exercise = $0; exercise.photo = nil; return exercise }
        #expect(try encoder.encode(withoutPhotos) == encoder.encode(twentyTwo.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(twentyTwo.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(twentyTwo.templates))
    }

    /// The format-22 file arrives whole: imported, it exports as the
    /// format-23 file it was brought forward to.
    @Test func theFormatTwentyTwoFileArrivesWhole() throws {
        let twentyTwo = try CoverageBackup.readFormatTwentyTwo()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(twentyTwo, into: context)
        try CoverageBackup.expectExport(of: context, toBe: twentyTwo)
    }

    /// The package holds the JSON next to it, and the photos — an exercise's
    /// and a machine's — come back byte for byte through an import and an
    /// export.
    @Test func thePackageArrivesWhole() throws {
        let package = try CoverageBackup.package()
        let encoder = BackupCoding.encoder
        #expect(try encoder.encode(package.file) == encoder.encode(CoverageBackup.read()))
        #expect(package.photos.count == 2)
        #expect(package.missingPhotoCount == 0)

        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(package.file, into: context)
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>(sortBy: [SortDescriptor(\.orderIndex)]))
        let machines = try context.fetch(FetchDescriptor<Machine>())
        let exported = BackupExporter.package(definitions: definitions, sessions: nil, machines: machines)
        #expect(exported.photos == package.photos)

        let again = try BackupPackage.read(from: exported.encoded())
        #expect(again.photos == package.photos)
    }

    /// Format 22 knows only the app's own categories. A format-21 file's
    /// exercise filed under another arrives without one and nothing says so:
    /// deliberate, and the only difference to this file.
    @Test func formatTwentyTwoDropsACategoryOfTheUsersOwnWithoutSayingSo() throws {
        let encoder = BackupCoding.encoder
        let raw = try BackupCoding.decoder.decode(BackupFileV21.self, from: CoverageBackup.data("CoverageBackup-v21"))
        #expect(raw.exercises?.first { $0.name == "Bouldering" }?.category == "Climbing")

        let twentyOne = try CoverageBackup.readFormatTwentyOne()
        #expect(twentyOne.exercises?.first { $0.name == "Bouldering" }?.category == "")

        let current = try CoverageBackup.readFormatTwentyTwo()
        #expect(try encoder.encode(current.exercises) == encoder.encode(twentyOne.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(twentyOne.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(twentyOne.templates))
    }

    /// The format-21 file arrives whole: imported, it exports as the
    /// format-22 file it was brought forward to.
    @Test func theFormatTwentyOneFileArrivesWhole() throws {
        let twentyOne = try CoverageBackup.readFormatTwentyOne()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(twentyOne, into: context)
        try CoverageBackup.expectExport(of: context, toBe: twentyOne)
    }

    /// Format 21 brings the side an entry starts with and the order across
    /// sides. A format-20 file arrives with neither, nothing guessed; this
    /// file is that one with four entries saying a side, one of them with a
    /// free order.
    @Test func formatTwentyOneIsFormatTwentyWithStartSidesAndOrder() throws {
        let encoder = BackupCoding.encoder
        let twenty = try CoverageBackup.readFormatTwenty()
        #expect(twenty.workouts?.flatMap(\.exercises).allSatisfy { $0.startSide == nil } == true)
        #expect(twenty.workouts?.flatMap(\.exercises).flatMap(\.sets).allSatisfy { $0.sideOrder == nil } == true)

        var current = try CoverageBackup.readFormatTwentyTwo()
        #expect(current.workouts?.flatMap(\.exercises).filter { $0.startSide != nil }.count == 4)
        current.workouts = current.workouts?.map { workout in
            var workout = workout
            workout.exercises = workout.exercises.map { entry in
                var entry = entry
                entry.startSide = nil
                entry.sets = entry.sets.map { var set = $0; set.sideOrder = nil; return set }
                return entry
            }
            return workout
        }
        #expect(try encoder.encode(current.exercises) == encoder.encode(twenty.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(twenty.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(twenty.templates))
    }

    /// The format-20 file arrives whole: imported, it exports as the
    /// format-21 file it was brought forward to, with no start side.
    @Test func theFormatTwentyFileArrivesWhole() throws {
        let twenty = try CoverageBackup.readFormatTwenty()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(twenty, into: context)
        try CoverageBackup.expectExport(of: context, toBe: twenty)
    }

    /// Format 20 brings gyms and machines. A format-19 file arrives with
    /// none; this file is that one with three gyms and four machines, three
    /// workouts and a template at a gym, and exercises at a machine.
    @Test func formatTwentyIsFormatNineteenWithGymsAndMachines() throws {
        let encoder = BackupCoding.encoder
        let nineteen = try CoverageBackup.readFormatNineteen()
        #expect(nineteen.gyms == nil && nineteen.machines == nil)

        var current = try CoverageBackup.readFormatTwenty()
        #expect(current.gyms?.map(\.name) == ["Downtown Gym", "Forge Fitness", "Home"])
        #expect(current.machines?.count == 4)
        current.workouts = current.workouts?.map { workout in
            var workout = workout
            workout.gym = nil
            workout.exercises = workout.exercises.map { var entry = $0; entry.machine = nil; return entry }
            return workout
        }
        current.templates = current.templates?.map { template in
            var template = template
            template.gym = nil
            template.exercises = template.exercises.map { var entry = $0; entry.machine = nil; return entry }
            return template
        }
        #expect(try encoder.encode(current.exercises) == encoder.encode(nineteen.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(nineteen.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(nineteen.templates))
    }

    /// The format-19 file arrives whole: imported, it exports as the
    /// format-20 file it was brought forward to, with no gym or machine.
    @Test func theFormatNineteenFileArrivesWhole() throws {
        let nineteen = try CoverageBackup.readFormatNineteen()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(nineteen, into: context)
        try CoverageBackup.expectExport(of: context, toBe: nineteen)
    }

    /// Format 19 gives an entry instructions besides its note. A format-18
    /// file arrives with no instructions in a workout and a template's notes
    /// as its instructions — a template was never trained, so its notes were
    /// how to do it. This file is that one with instructions on two exercises
    /// of workouts, one beside its note and one alone.
    @Test func formatNineteenIsFormatEighteenWithInstructions() throws {
        let encoder = BackupCoding.encoder
        let eighteen = try CoverageBackup.readFormatEighteen()
        #expect(eighteen.workouts?.allSatisfy { $0.exercises.allSatisfy { $0.instructions.isEmpty } } == true)
        #expect(eighteen.templates?.allSatisfy { $0.exercises.allSatisfy { $0.notes.isEmpty } } == true)
        #expect(eighteen.templates?.flatMap(\.exercises).filter { !$0.instructions.isEmpty }.count == 3)

        var current = try CoverageBackup.readFormatNineteen()
        let instructed = current.workouts?.flatMap(\.exercises).filter { !$0.instructions.isEmpty } ?? []
        #expect(instructed.map { $0.notes.isEmpty } == [false, true])
        current.workouts = current.workouts?.map { workout in
            var workout = workout
            workout.exercises = workout.exercises.map { var entry = $0; entry.instructions = ""; return entry }
            return workout
        }
        #expect(try encoder.encode(current.exercises) == encoder.encode(eighteen.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(eighteen.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(eighteen.templates))
    }

    /// The format-18 file arrives whole: imported, it exports as the
    /// format-19 file it was brought forward to.
    @Test func theFormatEighteenFileArrivesWhole() throws {
        let eighteen = try CoverageBackup.readFormatEighteen()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(eighteen, into: context)
        try CoverageBackup.expectExport(of: context, toBe: eighteen)
    }

    /// Format 18 gives a template the day it was adjusted for. A format-17
    /// file arrives with every template kept for good; this file is that one
    /// with two day variants added, one on the shelf and one archived.
    @Test func formatEighteenIsFormatSeventeenWithDayVariants() throws {
        let encoder = BackupCoding.encoder
        let seventeen = try CoverageBackup.readFormatSeventeen()
        #expect(seventeen.templates?.allSatisfy { $0.plannedFor == nil } == true)

        var current = try CoverageBackup.readFormatEighteen()
        #expect(current.templates?.filter { $0.plannedFor != nil }.map(\.archived) == [false, true])
        current.templates = current.templates?.filter { $0.plannedFor == nil }
        #expect(try encoder.encode(current.exercises) == encoder.encode(seventeen.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(seventeen.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(seventeen.templates))
    }

    /// The format-17 file arrives whole: imported, it exports as the
    /// format-18 file it was brought forward to, with no day variant.
    @Test func theFormatSeventeenFileArrivesWhole() throws {
        let seventeen = try CoverageBackup.readFormatSeventeen()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(seventeen, into: context)
        try CoverageBackup.expectExport(of: context, toBe: seventeen)
    }

    /// Format 17 gives a workout its duration. A format-16 file arrives with
    /// none timed; this file is that one with two workouts timed.
    @Test func formatSeventeenIsFormatSixteenWithDurations() throws {
        let encoder = BackupCoding.encoder
        let sixteen = try CoverageBackup.readFormatSixteen()
        #expect(sixteen.workouts?.allSatisfy { $0.durationSeconds == nil } == true)

        var current = try CoverageBackup.readFormatSeventeen()
        #expect(current.workouts?.compactMap(\.durationSeconds).sorted() == [2715, 4140])
        current.workouts = current.workouts?.map { var record = $0; record.durationSeconds = nil; return record }
        #expect(try encoder.encode(current.exercises) == encoder.encode(sixteen.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(sixteen.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(sixteen.templates))
    }

    /// The format-16 file arrives whole: imported, it exports as the
    /// format-17 file it was brought forward to, with no workout timed.
    @Test func theFormatSixteenFileArrivesWhole() throws {
        let sixteen = try CoverageBackup.readFormatSixteen()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(sixteen, into: context)
        try CoverageBackup.expectExport(of: context, toBe: sixteen)
    }

    /// Format 16 gives an exercise a rest of its own. A format-15 file
    /// arrives with none, every exercise following the setting; this file is
    /// that one with three rests, one of them no timer at all.
    @Test func formatSixteenIsFormatFifteenWithRests() throws {
        let encoder = BackupCoding.encoder
        let fifteen = try CoverageBackup.readFormatFifteen()
        #expect(fifteen.exercises?.allSatisfy { $0.restSeconds == nil } == true)

        var current = try CoverageBackup.readFormatSixteen()
        #expect(current.exercises?.compactMap(\.restSeconds).sorted() == [0, 180, 240])
        current.exercises = current.exercises?.map { var record = $0; record.restSeconds = nil; return record }
        #expect(try encoder.encode(current.exercises) == encoder.encode(fifteen.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(fifteen.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(fifteen.templates))
    }

    /// The format-15 file arrives whole: imported, it exports as the
    /// format-16 file it was brought forward to, without rests.
    @Test func theFormatFifteenFileArrivesWhole() throws {
        let fifteen = try CoverageBackup.readFormatFifteen()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(fifteen, into: context)
        try CoverageBackup.expectExport(of: context, toBe: fifteen)
    }

    /// Format 15 tells a set done from one only planned. A format-14 file
    /// arrives with every set done, as every set was; this file is that one
    /// with the templates' sets planned — as a template made today exports
    /// them — and two sets of workouts left open.
    @Test func formatFifteenIsFormatFourteenWithDoneSets() throws {
        let encoder = BackupCoding.encoder
        let fourteen = try CoverageBackup.readFormatFourteen()
        let allSets = (fourteen.workouts ?? []).flatMap(\.exercises).flatMap(\.sets)
            + (fourteen.templates ?? []).flatMap(\.exercises).flatMap(\.sets)
        #expect(allSets.allSatisfy { $0.done })

        func everyDone(_ entries: [EntryRecord]) -> [EntryRecord] {
            entries.map { entry in
                var entry = entry
                entry.sets = entry.sets.map { var set = $0; set.done = true; return set }
                return entry
            }
        }
        var current = try CoverageBackup.readFormatFifteen()
        let open = (current.workouts ?? []).flatMap(\.exercises).flatMap(\.sets).filter { !$0.done }
        #expect(open.count == 2)
        #expect((current.templates ?? []).flatMap(\.exercises).flatMap(\.sets).allSatisfy { !$0.done })
        current.workouts = current.workouts?.map { var workout = $0; workout.exercises = everyDone(workout.exercises); return workout }
        current.templates = current.templates?.map { var template = $0; template.exercises = everyDone(template.exercises); return template }
        #expect(try encoder.encode(current.exercises) == encoder.encode(fourteen.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(fourteen.workouts))
        #expect(try encoder.encode(current.templates) == encoder.encode(fourteen.templates))
    }

    /// A format-15 file is read as format 15: a set without its `done` is no
    /// such file, and is not guessed into one.
    @Test func aFormatFifteenSetWithoutDoneIsNotRead() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: CoverageBackup.data("CoverageBackup-v15")) as? [String: Any])
        var workouts = try #require(json["workouts"] as? [[String: Any]])
        var entries = try #require(workouts[0]["exercises"] as? [[String: Any]])
        var sets = try #require(entries[0]["sets"] as? [[String: Any]])
        sets[0].removeValue(forKey: "done")
        entries[0]["sets"] = sets
        workouts[0]["exercises"] = entries
        json["workouts"] = workouts
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) {
            try BackupCoding.readBackup(from: data)
        }
    }

    /// The format-14 file arrives whole: imported, it exports as the
    /// format-15 file it was brought forward to, every set done.
    @Test func theFormatFourteenFileArrivesWhole() throws {
        let fourteen = try CoverageBackup.readFormatFourteen()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(fourteen, into: context)
        try CoverageBackup.expectExport(of: context, toBe: fourteen)
    }

    /// Format 14 carries templates. A format-13 file arrives without the
    /// section — there were none to have — and is otherwise this file.
    @Test func formatFourteenIsFormatThirteenWithTemplates() throws {
        let encoder = BackupCoding.encoder
        let current = try CoverageBackup.readFormatFourteen()
        let thirteen = try CoverageBackup.readFormatThirteen()
        #expect(thirteen.templates == nil)
        #expect(current.templates?.isEmpty == false)
        #expect(try encoder.encode(current.exercises) == encoder.encode(thirteen.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(thirteen.workouts))
    }

    /// The format-13 file arrives whole: imported, it exports as the
    /// format-15 file it was brought forward to, with no templates.
    @Test func theFormatThirteenFileArrivesWhole() throws {
        let thirteen = try CoverageBackup.readFormatThirteen()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(thirteen, into: context)
        try CoverageBackup.expectExport(of: context, toBe: thirteen)
    }

    /// Templates are no history: importing the file adds them beside the
    /// workouts, and none of them counts as one.
    @Test func theTemplatesArriveAsTemplates() throws {
        let file = try CoverageBackup.read()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(file, into: context)

        let trained = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.trained))
        let templates = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))
        #expect(trained.count == file.workouts?.count)
        #expect(templates.count == file.templates?.count)
        let shelf = TemplateShelf(templates)
        #expect(shelf.templates.map(\.name) == file.templates?.filter { !$0.archived }.map(\.name))
        #expect(shelf.archived.map(\.name) == file.templates?.filter(\.archived).map(\.name))
    }

    /// Importing the same file twice brings its templates once.
    @Test func aTemplateAlreadyHereIsSkipped() throws {
        let file = try CoverageBackup.read()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(file, into: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))
        let plan = ImportPlanner.plan(
            file: file,
            existing: try context.fetch(FetchDescriptor<ExerciseDefinition>()).map { ImportPlanner.Existing(id: $0.id, record: BackupExporter.record($0)) },
            knownWorkoutIDs: [],
            knownTemplateIDs: Set(templates.map(\.id))
        )
        let summary = BackupImporter(context: context).apply(
            plan, decisions: ImportDecisions(), selection: ImportSelection(exercises: false, workouts: false, templates: true)
        )
        #expect(summary.templatesAdded == 0)
        #expect(summary.templatesSkipped == file.templates?.count)
    }

    /// "Replace All" starts the history over from the file; the templates
    /// on the device are no history and stay.
    @Test func replacingTheWorkoutsKeepsTheTemplates() throws {
        let file = try CoverageBackup.read()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(file, into: context)

        var workoutsOnly = file
        workoutsOnly.templates = nil
        let plan = ImportPlanner.plan(file: workoutsOnly, existing: [], knownWorkoutIDs: [])
        _ = BackupImporter(context: context).apply(
            plan, decisions: ImportDecisions(), selection: ImportSelection(exercises: false, workouts: true, templates: false, replaceWorkouts: true)
        )
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates)) == file.templates?.count)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.trained)) == file.workouts?.count)
    }

    /// Format 13 knows assisted sets. A format-12 file arrives with no
    /// exercise offering help and every entry unassisted, as nothing could
    /// be then; the format-13 file is that one with the own Pull-Up offering
    /// it and the Pull-Up of "Push B" done on the machine, its weight field
    /// logging the help.
    @Test func formatThirteenIsFormatTwelveWithAssistance() throws {
        let encoder = BackupCoding.encoder
        let current = try CoverageBackup.readFormatThirteen()
        var twelve = try CoverageBackup.readFormatTwelve()
        #expect(twelve.exercises?.allSatisfy { !$0.offersAssistance } == true)
        #expect(twelve.workouts?.flatMap(\.exercises).allSatisfy { $0.assistance == Assistance.unassisted.rawValue } == true)
        twelve.exercises = twelve.exercises?.map { record in
            var record = record
            record.offersAssistance = record.name == "Pull-Up"
            return record
        }
        twelve.workouts = twelve.workouts?.map { workout in
            var workout = workout
            guard workout.name == "Push B" else { return workout }
            workout.exercises = workout.exercises.map { entry in
                guard entry.exercise == "Pull-Up" else { return entry }
                var entry = entry
                entry.assistance = Assistance.machine.rawValue
                entry.sets = zip(entry.sets, [25.0, 20.0]).map { set, help in
                    var set = set
                    set.values = set.values.map { value in
                        guard value.type == FieldType.weight.rawValue else { return value }
                        return ValueRecord(key: value.key, label: "Assist", type: FieldType.assistance.rawValue, number: help)
                    }
                    return set
                }
                return entry
            }
            return workout
        }
        #expect(try encoder.encode(current.exercises) == encoder.encode(twelve.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(twelve.workouts))
    }

    /// A format-13 file is read as format 13: one without the keys for help
    /// is no such file, and is not guessed into one.
    @Test(arguments: ["exercises", "workouts"])
    func aFormatThirteenFileWithoutTheKeysForHelpIsNotRead(section: String) throws {
        var json = try #require(try JSONSerialization.jsonObject(with: CoverageBackup.data("CoverageBackup-v13")) as? [String: Any])
        if section == "exercises" {
            var exercises = try #require(json["exercises"] as? [[String: Any]])
            exercises[0].removeValue(forKey: "offersAssistance")
            json["exercises"] = exercises
        } else {
            var workouts = try #require(json["workouts"] as? [[String: Any]])
            var entries = try #require(workouts[0]["exercises"] as? [[String: Any]])
            entries[0].removeValue(forKey: "assistance")
            workouts[0]["exercises"] = entries
            json["workouts"] = workouts
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) {
            try BackupCoding.readBackup(from: data)
        }
    }

    /// The format-12 file arrives whole: imported, it exports as the
    /// format-15 file it was brought forward to.
    @Test func theFormatTwelveFileArrivesWhole() throws {
        let twelve = try CoverageBackup.readFormatTwelve()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(twelve, into: context)
        try CoverageBackup.expectExport(of: context, toBe: twelve)
    }

    /// Format 12 tells main muscles from secondary ones. A format-11 file
    /// arrives with every muscle a main one, as all of them counted then;
    /// this file is that one with the catalog's muscles for the catalog
    /// exercises — what an export after `CatalogSync` holds — and secondary
    /// muscles on the rowing erg.
    @Test func formatTwelveIsFormatElevenWithSecondaryMuscles() throws {
        let encoder = BackupCoding.encoder
        let current = try CoverageBackup.readFormatTwelve()
        var eleven = try CoverageBackup.readFormatEleven()
        #expect(eleven.exercises?.allSatisfy { $0.secondaryMuscleGroupNames.isEmpty } == true)
        eleven.exercises = eleven.exercises?.map { record in
            var record = record
            if let key = record.catalogKey, let exercise = Catalog.exercise(forKey: key) {
                record.muscleGroupNames = exercise.muscleGroupNames
                record.secondaryMuscleGroupNames = exercise.secondaryMuscleGroupNames
            }
            if record.name == "Rowing Erg" {
                record.secondaryMuscleGroupNames = ["glutes", "biceps"]
            }
            return record
        }
        #expect(try encoder.encode(current.exercises) == encoder.encode(eleven.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(eleven.workouts))
    }

    /// A format-12 file is read as format 12: one without secondary muscles
    /// on an exercise is no such file, and is not guessed into one.
    @Test func aFormatTwelveExerciseWithoutSecondaryMusclesIsNotRead() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: CoverageBackup.data("CoverageBackup-v12")) as? [String: Any])
        var exercises = try #require(json["exercises"] as? [[String: Any]])
        exercises[0].removeValue(forKey: "secondaryMuscleGroupNames")
        json["exercises"] = exercises
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) {
            try BackupCoding.readBackup(from: data)
        }
    }

    /// The format-11 file arrives whole: imported, it exports as the
    /// format-15 file it was brought forward to.
    @Test func theFormatElevenFileArrivesWhole() throws {
        let eleven = try CoverageBackup.readFormatEleven()
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CoverageBackup.importFile(eleven, into: context)
        try CoverageBackup.expectExport(of: context, toBe: eleven)
    }

    /// Format 11 is the oldest read: a backup from before the sides
    /// assistant would bring undecided exercises back after it has run. It is
    /// refused with a pointer to support, which converts it by hand; a newer
    /// one only with the word that it is newer.
    @Test(arguments: [7, 8, 9, 10])
    func formatsBeforeElevenAreRefusedWithAPointerToSupport(version: Int) throws {
        let old = #"{"exportedAt": "2026-01-01T00:00:00Z", "formatVersion": \#(version)}"#
        #expect(throws: BackupReadError.otherFormat(version)) {
            try BackupCoding.readBackup(from: Data(old.utf8))
        }
        let error = BackupReadError.otherFormat(version)
        #expect(error.localizedDescription.contains(Support.address))
        #expect(error.supportMail?.absoluteString.hasPrefix("mailto:\(Support.address)") == true)
    }

    @Test func theTestersFormatEightFileIsRefused() throws {
        #expect(throws: BackupReadError.otherFormat(8)) {
            try BackupCoding.readBackup(from: CoverageBackup.data("CoverageBackup-v8"))
        }
    }

    @Test func aNewerFormatPointsToAnUpdateNotToSupport() {
        let error = BackupReadError.otherFormat(BackupFile.currentFormatVersion + 1)
        #expect(error.supportMail == nil)
        #expect(error.localizedDescription.contains("newer"))
    }

    /// Format 11 spells out how an exercise is trained; format 10 had a
    /// switch, on for either way, off for two-sided. This file is the
    /// format-10 one brought forward, with the catalog's way for the catalog
    /// exercises — what an export after `CatalogSync` holds — and the couch
    /// stretch one-sided only.
    @Test func formatElevenIsFormatTenWithTheSidesSpelledOut() throws {
        let encoder = BackupCoding.encoder
        let current = try CoverageBackup.readFormatEleven()
        var ten = try CoverageBackup.readFormatTen()
        ten.exercises = ten.exercises?.map { record in
            var record = record
            if let key = record.catalogKey, let exercise = Catalog.exercise(forKey: key) {
                record.sides = exercise.sides.rawValue
            }
            if record.name == "Couch Stretch" {
                record.sides = ExerciseSides.one.rawValue
            }
            return record
        }
        #expect(try encoder.encode(current.exercises) == encoder.encode(ten.exercises))
        #expect(try encoder.encode(current.workouts) == encoder.encode(ten.workouts))
    }

    /// Format 10 differs from 9 only by the key on an entry, and a format-9
    /// entry is given the key of the exercise it names: the format-9 file
    /// brought forward is this one.
    @Test func formatTenIsFormatNineWithTheKeysOnTheEntries() throws {
        let encoder = BackupCoding.encoder
        let ten = try CoverageBackup.readFormatTen()
        let nine = try CoverageBackup.readFormatNine()
        #expect(try encoder.encode(ten.exercises) == encoder.encode(nine.exercises))
        #expect(try encoder.encode(ten.workouts) == encoder.encode(nine.workouts))
    }

    /// Format 9 differs from 8 only by catalog keys: the format-10 file with
    /// every key taken out is the format-8 file brought forward.
    @Test func formatEightIsFormatTenWithoutCatalogKeys() throws {
        var ten = try CoverageBackup.readFormatTen()
        ten.exercises = ten.exercises?.map { var record = $0; record.catalogKey = nil; return record }
        ten.workouts = ten.workouts?.map { workout in
            var workout = workout
            workout.exercises = workout.exercises.map { var entry = $0; entry.catalogKey = nil; return entry }
            return workout
        }
        let encoder = BackupCoding.encoder
        let eight = try CoverageBackup.readFormatEight()
        #expect(try encoder.encode(ten.exercises) == encoder.encode(eight.exercises))
        #expect(try encoder.encode(ten.workouts) == encoder.encode(eight.workouts))
    }

    /// Every case of the types a file spells. A new field type, mode, side,
    /// scale or kind of help fails here until the file has one. Help is no
    /// field of an exercise, only a logged value.
    @Test func everyKindTheAppKnowsIsInTheFile() throws {
        let file = try CoverageBackup.read()
        let exercises = file.exercises ?? []
        let entries = (file.workouts ?? []).flatMap(\.exercises)
        let sets = entries.flatMap(\.sets)

        #expect(Set(exercises.flatMap(\.fields).map(\.type)) == Set(FieldType.allCases.filter { $0 != .assistance }.map(\.rawValue)))
        #expect(Set(sets.flatMap(\.values).filter { $0.text != nil || $0.number != nil }.map(\.type)) == Set(FieldType.allCases.map(\.rawValue)))
        #expect(Set(entries.map(\.mode)) == Set(UnilateralMode.allCases.map(\.rawValue)))
        #expect(Set(entries.map(\.assistance)) == Set(Assistance.allCases.map(\.rawValue)))
        #expect(Set(entries.map(\.effortScale)) == Set(EffortScale.allCases.map(\.rawValue)))
        #expect(Set(sets.map(\.side)) == Set(SetSide.allCases.map(\.rawValue)))
        #expect(Set(exercises.map(\.sides)) == Set(ExerciseSides.allCases.map(\.rawValue)))

        let categories = exercises.map(\.category)
        #expect(Set(categories).isSuperset(of: ExerciseCategory.allCases.map(\.name)))
        #expect(categories.contains(""))

        func ratings(on scale: EffortScale) -> Set<Double?> {
            Set(entries.filter { $0.effortScale == scale.rawValue }.flatMap(\.sets).map(\.effort))
        }
        #expect(ratings(on: .levels).isSuperset(of: EffortLevel.allCases.map { Double($0.rawValue) } + [nil]))
        let rir = ratings(on: .rir)
        #expect(rir.isSuperset(of: [EffortScale.rirRange.lowerBound, EffortScale.rirRange.upperBound, nil]))
        #expect(rir.contains { $0.map { $0 != $0.rounded() } ?? false })
    }

    /// The corners worth having on screen at once. Each line is one; taking
    /// one out of the file is a decision, not a tidy-up.
    @Test func theOddCornersAreInTheFile() throws {
        let file = try CoverageBackup.read()
        let exercises = file.exercises ?? []
        let workouts = file.workouts ?? []
        let entries = workouts.flatMap(\.exercises)
        let sets = entries.flatMap(\.sets)
        let values = sets.flatMap(\.values)
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })

        // Sides
        #expect(entries.contains { $0.mode == UnilateralMode.oneSided.rawValue && $0.startSide != nil }, "same weight saying its first side")
        #expect(entries.contains { $0.mode == UnilateralMode.perSide.rawValue && $0.startSide == "right" }, "left and right starting right")
        #expect(entries.contains { $0.mode == UnilateralMode.perSide.rawValue && $0.startSide == nil }, "left and right from before there was a first side")
        #expect(entries.contains { $0.sets.contains { $0.sideOrder != nil } }, "an order chosen freely")

        // Exercises
        #expect(exercises.contains { $0.catalogKey == nil && $0.photo != nil }, "an own exercise with a photo")
        #expect(exercises.contains { exercise in
            exercise.catalogKey != nil && exercise.fields.contains { FieldType(rawValue: $0.type)?.isStandard != true }
        }, "a catalog exercise that logs more than weight and reps")
        #expect(exercises.contains { $0.catalogKey != nil && !$0.tracksSets }, "a catalog exercise logged once per workout")
        #expect(exercises.contains { $0.photoFraming.map { $0.zoom > 1 } == true }, "an exercise's photo framed and zoomed")
        #expect(exercises.contains { !$0.tracksSets }, "once per workout")
        #expect(exercises.contains { $0.tracksSets && $0.sides == ExerciseSides.both.rawValue }, "sets without sides")
        #expect(exercises.contains { $0.catalogKey == nil && $0.sides == ExerciseSides.one.rawValue }, "an own exercise one-sided only")
        #expect(exercises.contains { $0.fields.count == ExerciseDefinition.maxFields }, "as many fields as fit")
        #expect(exercises.contains { $0.fields.count == 1 }, "a single field")
        #expect(exercises.contains { $0.fields.map(\.type) == [FieldType.reps.rawValue, FieldType.weight.rawValue] }, "reps before weight")
        #expect(exercises.contains { exercise in
            let types = exercise.fields.compactMap { FieldType(rawValue: $0.type) }
            return types.contains(where: \.isStandard) && types.contains { !$0.isStandard }
        }, "standard and own fields together")
        #expect(exercises.contains { $0.muscleGroupNames.isEmpty }, "no muscles filed yet")
        #expect(exercises.contains { $0.muscleGroupNames.count > 2 }, "several main muscles")
        #expect(exercises.contains { $0.catalogKey == nil && !$0.secondaryMuscleGroupNames.isEmpty }, "an own exercise with secondary muscles")
        #expect(exercises.contains { $0.catalogKey != nil && !$0.secondaryMuscleGroupNames.isEmpty }, "a catalog exercise with secondary muscles")
        #expect(exercises.contains { $0.name.contains { !$0.isASCII } }, "a name beyond ASCII")
        #expect(exercises.contains { $0.catalogKey == nil && $0.offersAssistance }, "an own exercise that can be assisted")
        #expect(exercises.contains { exercise in !entries.contains { $0.exercise == exercise.name } }, "never logged")
        #expect(exercises.contains { $0.catalogKey != nil }, "a catalog exercise")
        #expect(exercises.contains { $0.catalogKey == nil && ($0.restSeconds ?? 0) > 0 }, "an own exercise with a rest of its own")
        #expect(exercises.contains { $0.catalogKey != nil && ($0.restSeconds ?? 0) > 0 }, "a catalog exercise with a rest of its own")
        #expect(exercises.contains { $0.restSeconds == 0 }, "an exercise with no rest timer")
        #expect(entries.contains { $0.catalogKey != nil }, "an entry of a catalog exercise")
        #expect(workouts.contains { ($0.durationSeconds ?? 0) > 0 }, "a timed workout")
        #expect(workouts.contains { $0.durationSeconds == nil }, "a workout not timed")
        #expect(exercises.contains { exercise in
            exercise.catalogKey == nil && Catalog.exercises.contains { $0.name.exerciseKey == exercise.name.exerciseKey }
        }, "an own exercise under a catalog exercise's name")

        // Entries and sets
        #expect(entries.contains { $0.sets.isEmpty && $0.notes.isEmpty }, "added and forgotten")
        #expect(entries.contains { $0.sets.isEmpty && !$0.notes.isEmpty }, "only a note")
        #expect(entries.contains { $0.mode != UnilateralMode.bilateral.rawValue && byName[$0.exercise]?.sides == ExerciseSides.both.rawValue }, "one-sided where the exercise no longer offers sides")
        #expect(entries.contains { entry in
            let count = { (side: SetSide) in entry.sets.filter { $0.side == side.rawValue }.count }
            return entry.mode == UnilateralMode.perSide.rawValue && count(.left) != count(.right)
        }, "more sets on one side than the other")
        #expect(sets.contains { $0.values.allSatisfy { $0.text == nil && $0.number == nil } }, "a set with nothing in it")
        #expect(Set(entries.filter { $0.exercise == "Pull-Up" }.map(\.assistance)).count > 1, "assisted and weighted in one history")
        #expect(entries.contains { entry in
            entry.assistance != Assistance.unassisted.rawValue
                && byName[entry.exercise]?.fields.first?.type != FieldType.weight.rawValue
        }, "help logged where the weight is not the first field")
        #expect(values.contains { $0.number == 0 }, "a zero, which is not an empty field")
        #expect(values.contains { value in
            guard value.type == FieldType.weight.rawValue, let kilograms = value.number else { return false }
            let pounds = WeightUnit.pounds.value(fromKilograms: kilograms)
            return abs(pounds - pounds.rounded()) < 1e-9 && (kilograms * 100).rounded() != kilograms * 100
        }, "a weight typed in pounds")
        #expect(values.contains { $0.type == FieldType.time.rawValue && ($0.number ?? 0) >= 3600 }, "a duration over an hour")

        // Supersets
        let supersets = workouts.map { workout in
            Dictionary(grouping: workout.exercises.filter { $0.supersetGroup != nil }) { $0.supersetGroup ?? 0 }
        }
        #expect(supersets.contains { $0.count > 1 }, "two supersets in one workout")
        #expect(entries.contains { $0.supersetGroup != nil && $0.mode == UnilateralMode.oneSided.rawValue }, "a one-sided member")
        #expect(supersets.contains { $0.values.contains { Set($0.map(\.effortScale)).count > 1 } }, "members rated on different scales")
        #expect(supersets.contains { $0.values.contains { Set($0.map(\.sets.count)).count > 1 } }, "members with different set counts")

        // Gyms and machines
        let gyms = file.gyms ?? []
        let machineNames = (file.machines ?? []).map(\.name)
        #expect(gyms.contains { $0.machines.isEmpty }, "a gym without machines")
        #expect(machineNames.contains { name in gyms.filter { $0.machines.contains(name) }.count > 1 }, "a machine in several gyms")
        #expect(machineNames.contains { name in !gyms.contains { $0.machines.contains(name) } }, "a machine in no gym")
        #expect((file.machines ?? []).contains { $0.photo != nil }, "a machine with a photo")
        #expect((file.machines ?? []).contains { $0.photoFraming != nil }, "a machine's photo framed")
        #expect(workouts.contains { $0.gym != nil }, "a workout at a gym")
        #expect(workouts.contains { $0.gym == nil && $0.exercises.contains { $0.machine != nil } }, "a machine without a gym")
        #expect(entries.contains { $0.machine != nil }, "an exercise at a machine")
        #expect((file.templates ?? []).contains { $0.gym != nil && $0.exercises.contains { $0.machine != nil } }, "a template at a gym, with a machine")

        // Instructions
        #expect(entries.contains { !$0.instructions.isEmpty && !$0.notes.isEmpty }, "instructions beside a note")
        #expect(entries.contains { !$0.instructions.isEmpty && $0.notes.isEmpty }, "instructions without a note")

        // Templates
        let templates = file.templates ?? []
        #expect(templates.flatMap(\.exercises).contains { !$0.instructions.isEmpty }, "instructions in a template")
        #expect(templates.flatMap(\.exercises).allSatisfy { $0.notes.isEmpty }, "no note in a template: it is never trained")
        #expect(templates.contains { $0.archived }, "an archived template")
        #expect(templates.contains { $0.plannedFor != nil && !$0.archived }, "a day variant on the shelf")
        #expect(templates.contains { $0.plannedFor != nil && $0.archived }, "a day variant put away unused")
        #expect(templates.filter { !$0.archived }.count > 1, "several on the shelf, in an order")
        #expect(templates.contains { $0.exercises.isEmpty }, "a template without exercises")
        #expect(templates.contains { $0.exercises.contains { $0.supersetGroup != nil } }, "a superset in a template")
        #expect(templates.contains { $0.exercises.flatMap(\.sets).flatMap(\.values).contains { $0.number != nil } }, "values kept in a template")
        #expect(templates.contains { template in
            workouts.contains { $0.name == template.name }
        }, "a template named like a workout")

        // Done and planned
        #expect(sets.contains { !$0.done && $0.values.contains { $0.text != nil || $0.number != nil } }, "a set planned and not done")
        #expect(sets.contains { !$0.done && $0.values.allSatisfy { $0.text == nil && $0.number == nil } }, "an empty set left open")

        // Workouts
        #expect(workouts.contains { $0.name.isEmpty }, "no name")
        #expect(workouts.contains { $0.exercises.isEmpty }, "no exercises")
        #expect(workouts.contains { $0.notes.contains("\n") }, "notes over several lines")
        #expect(workouts.contains { $0.date < file.exportedAt.addingTimeInterval(-366 * 24 * 3600) }, "older than the activity graph reaches")
        // The simulator takes the Mac's time zone, here one in Central European Time.
        let berlin = Calendar(identifier: .gregorian).with(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let utc = Calendar(identifier: .gregorian).with(timeZone: TimeZone(identifier: "UTC")!)
        #expect(workouts.contains { berlin.component(.day, from: $0.date) != utc.component(.day, from: $0.date) }, "a day apart in Berlin and in UTC")
        let days = workouts.map { berlin.startOfDay(for: $0.date) }
        #expect(Set(days).count < days.count, "two workouts on one day")
    }
}

private extension Calendar {
    func with(timeZone: TimeZone) -> Calendar {
        var calendar = self
        calendar.timeZone = timeZone
        return calendar
    }
}
