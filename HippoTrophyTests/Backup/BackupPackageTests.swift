import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The two wrappings of a backup, and a photo's way out of the store and back,
/// an exercise's and a machine's.
@MainActor
struct BackupPackageTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// A real picture, prepared the way the editor prepares one.
    private func picture() throws -> Data {
        try #require(CoverageBackup.package().photos.values.first)
    }

    private func own(_ name: String, photo: Data? = nil, in context: ModelContext) -> ExerciseDefinition {
        let definition = ExerciseDefinition.insertPlainSetsAndReps(name: name, orderIndex: 0, in: context)
        definition.setPhoto(photo, in: context)
        return definition
    }

    private func record(_ name: String, photo: String?) -> ExerciseRecord {
        ExerciseRecord(
            name: name, category: "", muscleGroupNames: [], tracksSets: true, sides: "both",
            fields: [FieldRecord(key: "f1", label: "Time", type: "time")], photo: photo
        )
    }

    private func imported(
        _ records: [ExerciseRecord], photos: [String: Data], into context: ModelContext
    ) throws -> ImportSummary {
        let existing = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let plan = ImportPlanner.plan(
            file: BackupFile(exportedAt: .now, exercises: records),
            existing: existing.map { ImportPlanner.Existing(id: $0.id, record: BackupExporter.record($0)) },
            knownWorkoutIDs: []
        )
        let summary = BackupImporter(context: context).apply(plan, decisions: ImportDecisions(), selection: ImportSelection(), photos: photos)
        try context.save()
        return summary
    }

    // MARK: - Wrappings

    @Test func withoutPhotosABackupStaysPlainJSON() throws {
        let context = try context()
        let package = BackupExporter.package(definitions: [own("Rowing", in: context)], sessions: nil)
        #expect(!package.isZip)
        let data = try package.encoded()
        #expect(!BackupZip.isZip(data))
        #expect(try BackupCoding.readBackup(from: data).exercises?.first?.photo == nil)
    }

    @Test func withPhotosItIsAZipOfTheSameJSON() throws {
        let context = try context()
        let picture = try picture()
        let package = BackupExporter.package(definitions: [own("Rowing", photo: picture, in: context)], sessions: nil)
        let data = try package.encoded()
        #expect(BackupZip.isZip(data))

        let contents = try BackupZip.read(data)
        #expect(Set(contents.keys) == ["backup.json", "photos/1.jpg"])
        #expect(contents["photos/1.jpg"] == picture)
        #expect(try BackupCoding.readBackup(from: #require(contents["backup.json"])).exercises?.first?.photo == "photos/1.jpg")
    }

    @Test func photosSwitchedOffGiveTheJSONAloneNamingNone() throws {
        let context = try context()
        let package = BackupExporter.package(
            definitions: [own("Rowing", photo: try picture(), in: context)], sessions: nil, includingPhotos: false
        )
        #expect(!package.isZip)
        #expect(package.file.photoCount == 0)
    }

    @Test func eachPhotoHasANameOfItsOwn() throws {
        let context = try context()
        let picture = try picture()
        let package = BackupExporter.package(
            definitions: [
                own("Rowing", photo: picture, in: context), own("Plain", in: context), own("Swing", photo: picture, in: context)
            ],
            sessions: nil
        )
        #expect(package.file.exercises?.map(\.photo) == ["photos/1.jpg", nil, "photos/2.jpg"])
        #expect(package.photos.count == 2)
    }

    @Test func theFileIsReadByWhatItIsNotByWhatItIsCalled() throws {
        let file = BackupFile(exportedAt: .now, exercises: [record("Rowing", photo: nil)])
        let json = try BackupCoding.encoder.encode(file)
        #expect(!(try BackupPackage.read(from: json).isZip))
    }

    @Test func aZipWithoutABackupInItIsSaidToBeNone() throws {
        let zip = try BackupZip.write([BackupZip.Entry(name: "holiday.jpg", data: Data([1]))], modified: .now)
        #expect(throws: BackupReadError.notABackup) { try BackupPackage.read(from: zip) }
    }

    @Test func aPackageTakesOnlyPicturesFromTheFolder() throws {
        let json = try BackupCoding.encoder.encode(BackupFile(exportedAt: .now, exercises: []))
        let zip = try BackupZip.write(
            [
                BackupZip.Entry(name: "backup.json", data: json),
                BackupZip.Entry(name: "photos/1.jpg", data: Data([1])),
                BackupZip.Entry(name: "__MACOSX/photos/._1.jpg", data: Data([2]))
            ],
            modified: .now
        )
        #expect(try Set(BackupPackage.read(from: zip).photos.keys) == ["photos/1.jpg"])
    }

    @Test func aFileNamingAPhotoItDoesNotHaveSaysHowManyAreMissing() throws {
        let file = BackupFile(exportedAt: .now, exercises: [record("Rowing", photo: "photos/1.jpg"), record("Swing", photo: nil)])
        #expect(BackupPackage(file: file).missingPhotoCount == 1)
        #expect(BackupPackage(file: file, photos: ["photos/1.jpg": Data()]).missingPhotoCount == 0)
    }

    // MARK: - Catalog

    /// The catalog's exercise has the catalog's picture. One the catalog
    /// adopted keeps the photo in the store, but shows and exports none.
    @Test func aCatalogExerciseShowsAndExportsNoPhoto() throws {
        let context = try context()
        let definition = own("Rowing", photo: try picture(), in: context)
        definition.catalogKey = "rowing"
        #expect(definition.photo != nil)
        #expect(definition.ownPhoto == nil)
        #expect(BackupExporter.package(definitions: [definition], sessions: nil).photos.isEmpty)

        definition.catalogKey = nil
        #expect(definition.ownPhoto != nil)
    }

    // MARK: - Import

    @Test func aNewExerciseComesWithItsPhoto() throws {
        let context = try context()
        let picture = try picture()
        let summary = try imported([record("Rowing", photo: "photos/1.jpg")], photos: ["photos/1.jpg": picture], into: context)
        #expect(summary.photosAdded == 1)
        #expect(summary.photosMissing == 0)
        #expect(summary.message.contains("1 photo"))
        #expect(try context.fetch(FetchDescriptor<ExerciseDefinition>()).first?.ownPhoto?.data == picture)
    }

    @Test func anExerciseHereWithoutAPhotoTakesTheFiles() throws {
        let context = try context()
        let picture = try picture()
        let definition = own("Rowing", in: context)
        let summary = try imported([BackupExporter.record(definition).withPhoto("photos/1.jpg")], photos: ["photos/1.jpg": picture], into: context)
        #expect(summary.photosAdded == 1)
        #expect(definition.ownPhoto?.data == picture)
    }

    @Test func aPhotoHereStays() throws {
        let context = try context()
        let picture = try picture()
        let definition = own("Rowing", photo: picture, in: context)
        let other = picture + Data([0])
        let summary = try imported([BackupExporter.record(definition).withPhoto("photos/1.jpg")], photos: ["photos/1.jpg": other], into: context)
        #expect(summary.photosAdded == 0)
        #expect(summary.photosMissing == 0)
        #expect(definition.ownPhoto?.data == picture)
    }

    @Test func aPhotoMissingFromThePackageIsSaidAndTheExerciseStillComes() throws {
        let context = try context()
        let summary = try imported([record("Rowing", photo: "photos/1.jpg")], photos: [:], into: context)
        #expect(summary.exercisesAdded == 1)
        #expect(summary.photosMissing == 1)
        #expect(summary.message.contains("⚠️"))
        #expect(try context.fetch(FetchDescriptor<ExerciseDefinition>()).first?.photo == nil)
    }

    @Test func somethingThatIsNoPictureCountsAsMissing() throws {
        let context = try context()
        let summary = try imported([record("Rowing", photo: "photos/1.jpg")], photos: ["photos/1.jpg": Data("no picture".utf8)], into: context)
        #expect(summary.photosMissing == 1)
        #expect(summary.photosAdded == 0)
    }

    @Test func aPhotoIsNoDifferenceWorthAQuestion() throws {
        let context = try context()
        let definition = own("Rowing", in: context)
        let plan = ImportPlanner.plan(
            file: BackupFile(exportedAt: .now, exercises: [BackupExporter.record(definition).withPhoto("photos/1.jpg")]),
            existing: [ImportPlanner.Existing(id: definition.id, record: BackupExporter.record(definition))],
            knownWorkoutIDs: []
        )
        #expect(!plan.needsReview)
    }

    // MARK: - Editing and merging

    @Test func replacingAPhotoLeavesNoOldOneBehind() throws {
        let context = try context()
        let picture = try picture()
        let definition = own("Rowing", photo: picture, in: context)
        try context.save()
        let first = try #require(definition.photo?.id)

        definition.setPhoto(picture + Data([0]), in: context)
        try context.save()
        #expect(definition.photo?.id != first)
        #expect(try context.fetchCount(FetchDescriptor<ExercisePhoto>()) == 1)

        definition.setPhoto(nil, in: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ExercisePhoto>()) == 0)
    }

    @Test func deletingAnExerciseTakesItsPhoto() throws {
        let context = try context()
        let definition = own("Rowing", photo: try picture(), in: context)
        try context.save()
        context.delete(definition)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ExercisePhoto>()) == 0)
    }

    private func merge(_ source: ExerciseDefinition, into target: ExerciseDefinition, in context: ModelContext) throws {
        let mapping = FieldMapping.suggested(from: BackupExporter.record(source), into: BackupExporter.record(target))
        try ExerciseMerging.merge(source, into: target, mapping: mapping, in: context)
        try context.save()
    }

    @Test func aMergeGivesATargetWithoutAPhotoTheSources() throws {
        let context = try context()
        let picture = try picture()
        let source = own("Rowing", photo: picture, in: context)
        let target = own("Row", in: context)
        try merge(source, into: target, in: context)
        #expect(target.ownPhoto?.data == picture)
        #expect(try context.fetchCount(FetchDescriptor<ExercisePhoto>()) == 1)
    }

    @Test func aMergeLeavesATargetItsOwnPhoto() throws {
        let context = try context()
        let picture = try picture()
        let source = own("Rowing", photo: picture + Data([0]), in: context)
        let target = own("Row", photo: picture, in: context)
        try merge(source, into: target, in: context)
        #expect(target.ownPhoto?.data == picture)
        #expect(try context.fetchCount(FetchDescriptor<ExercisePhoto>()) == 1)
    }

    // MARK: - Machines

    private func machine(_ name: String, photo: Data? = nil, in context: ModelContext) -> Machine {
        let machine = GymChoices.addMachine(named: name, at: nil, in: context)
        machine.setPhoto(photo, in: context)
        return machine
    }

    private func importedMachines(
        _ records: [MachineRecord], photos: [String: Data], into context: ModelContext
    ) throws -> ImportSummary {
        let plan = ImportPlanner.plan(file: BackupFile(exportedAt: .now, machines: records), existing: [], knownWorkoutIDs: [])
        let summary = BackupImporter(context: context).apply(plan, decisions: ImportDecisions(), selection: ImportSelection(), photos: photos)
        try context.save()
        return summary
    }

    @Test func aMachinesPhotoIsNumberedAfterTheExercises() throws {
        let context = try context()
        let picture = try picture()
        let package = BackupExporter.package(
            definitions: [own("Rowing", photo: picture, in: context)], sessions: nil,
            machines: [machine("Smith Machine", photo: picture + Data([1]), in: context), machine("Hack Squat", in: context)]
        )
        #expect(package.file.exercises?.first?.photo == "photos/1.jpg")
        #expect(package.file.machines?.map(\.photo) == [nil, "photos/2.jpg"])
        #expect(package.photos["photos/2.jpg"] == picture + Data([1]))
    }

    /// Machines always go along, so their photos do too, with or without the
    /// exercises.
    @Test func aMachinesPhotoGoesWithoutTheExercises() throws {
        let context = try context()
        let package = BackupExporter.package(
            definitions: nil, sessions: nil, machines: [machine("Smith Machine", photo: try picture(), in: context)]
        )
        #expect(package.isZip)
        #expect(package.file.machines?.first?.photo == "photos/1.jpg")
    }

    @Test func photosSwitchedOffNameNoMachinesPhoto() throws {
        let context = try context()
        let package = BackupExporter.package(
            definitions: nil, sessions: nil, machines: [machine("Smith Machine", photo: try picture(), in: context)],
            includingPhotos: false
        )
        #expect(!package.isZip)
        #expect(package.file.machines?.first?.photo == nil)
    }

    @Test func aNewMachineComesWithItsPhoto() throws {
        let context = try context()
        let picture = try picture()
        let summary = try importedMachines([MachineRecord(name: "Smith Machine", photo: "photos/1.jpg")], photos: ["photos/1.jpg": picture], into: context)
        #expect(summary.machinesAdded == 1)
        #expect(summary.photosAdded == 1)
        #expect(try context.fetch(FetchDescriptor<Machine>()).first?.photo?.data == picture)
    }

    @Test func aMachineHereWithoutAPhotoTakesTheFiles() throws {
        let context = try context()
        let picture = try picture()
        let here = machine("Smith Machine", in: context)
        let summary = try importedMachines([MachineRecord(name: "smith machine", photo: "photos/1.jpg")], photos: ["photos/1.jpg": picture], into: context)
        #expect(summary.machinesAdded == 0)
        #expect(summary.photosAdded == 1)
        #expect(here.photo?.data == picture)
    }

    @Test func aMachinesPhotoHereStays() throws {
        let context = try context()
        let picture = try picture()
        let here = machine("Smith Machine", photo: picture, in: context)
        let summary = try importedMachines([MachineRecord(name: "Smith Machine", photo: "photos/1.jpg")], photos: ["photos/1.jpg": picture + Data([0])], into: context)
        #expect(summary.photosAdded == 0)
        #expect(here.photo?.data == picture)
        #expect(try context.fetchCount(FetchDescriptor<MachinePhoto>()) == 1)
    }

    @Test func aMachinesPhotoMissingFromThePackageIsSaidAndTheMachineStillComes() throws {
        let context = try context()
        let file = BackupFile(exportedAt: .now, machines: [MachineRecord(name: "Smith Machine", photo: "photos/1.jpg")])
        #expect(BackupPackage(file: file).missingPhotoCount == 1)
        let summary = try importedMachines(file.machines ?? [], photos: [:], into: context)
        #expect(summary.machinesAdded == 1)
        #expect(summary.photosMissing == 1)
        #expect(try context.fetchCount(FetchDescriptor<MachinePhoto>()) == 0)
    }

    @Test func replacingAMachinesPhotoLeavesNoOldOneBehind() throws {
        let context = try context()
        let picture = try picture()
        let machine = machine("Smith Machine", photo: picture, in: context)
        try context.save()
        machine.setPhoto(picture + Data([0]), in: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<MachinePhoto>()) == 1)
        machine.setPhoto(nil, in: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<MachinePhoto>()) == 0)
    }

    @Test func deletingAMachineTakesItsPhoto() throws {
        let context = try context()
        let machine = machine("Smith Machine", photo: try picture(), in: context)
        try context.save()
        context.delete(machine)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<MachinePhoto>()) == 0)
    }

    // MARK: - Framing

    @Test func aCentredPhotoLeavesTheFramingOut() throws {
        let context = try context()
        let package = BackupExporter.package(definitions: [own("Rowing", photo: try picture(), in: context)], sessions: nil)
        #expect(package.file.exercises?.first?.photo != nil)
        #expect(package.file.exercises?.first?.photoFraming == nil)
    }

    @Test func aFramedPhotoTakesItsFramingAlongAndBack() throws {
        let context = try context()
        let picture = try picture()
        let framing = PhotoFraming(x: 0.3, y: 0.6, zoom: 2.5)
        let definition = own("Rowing", in: context)
        definition.setPhoto(picture, framing: framing, in: context)
        let machine = machine("Smith Machine", in: context)
        machine.setPhoto(picture, framing: framing, in: context)

        let package = BackupExporter.package(definitions: [definition], sessions: nil, machines: [machine])
        #expect(package.file.exercises?.first?.photoFraming == FramingRecord(x: 0.3, y: 0.6, zoom: 2.5))
        #expect(package.file.machines?.first?.photoFraming == FramingRecord(x: 0.3, y: 0.6, zoom: 2.5))

        let other = try self.context()
        let plan = ImportPlanner.plan(file: package.file, existing: [], knownWorkoutIDs: [])
        _ = BackupImporter(context: other).apply(plan, decisions: ImportDecisions(), selection: ImportSelection(), photos: package.photos)
        try other.save()
        #expect(try other.fetch(FetchDescriptor<ExercisePhoto>()).map(\.framing) == [framing])
        #expect(try other.fetch(FetchDescriptor<MachinePhoto>()).map(\.framing) == [framing])
    }

    /// Framing anew keeps the photo, so its picture is not written again.
    @Test func reframingKeepsThePhoto() throws {
        let context = try context()
        let picture = try picture()
        let machine = machine("Smith Machine", photo: picture, in: context)
        try context.save()
        let id = try #require(machine.photo?.id)

        machine.setPhoto(PhotoDraft(data: picture, framing: PhotoFraming(x: 0.2, y: 0.5, zoom: 1)), in: context)
        try context.save()
        #expect(machine.photo?.id == id)
        #expect(machine.photo?.framing == PhotoFraming(x: 0.2, y: 0.5, zoom: 1))
    }

    /// A new picture starts centred, whatever the old one's framing was.
    @Test func aNewPictureIsANewPhoto() throws {
        let context = try context()
        let picture = try picture()
        let machine = machine("Smith Machine", in: context)
        machine.setPhoto(picture, framing: PhotoFraming(x: 0.2, y: 0.5, zoom: 3), in: context)
        machine.setPhoto(PhotoDraft(data: picture + Data([0])), in: context)
        try context.save()
        #expect(machine.photo?.framing == .centered)
        #expect(try context.fetchCount(FetchDescriptor<MachinePhoto>()) == 1)
    }
}

private extension ExerciseRecord {
    func withPhoto(_ name: String) -> ExerciseRecord {
        var record = self
        record.photo = name
        return record
    }
}
