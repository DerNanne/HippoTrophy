import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The importer against a real, in-memory store: what a file becomes on a
/// device, and what a second import of the same file does not become.
@MainActor
struct BackupImporterTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func definitions(in context: ModelContext) throws -> [ExerciseDefinition] {
        try context.fetch(FetchDescriptor<ExerciseDefinition>())
    }

    private func entries(in context: ModelContext) throws -> [ExerciseEntry] {
        try context.fetch(FetchDescriptor<ExerciseEntry>())
    }

    private let rowing = ExerciseRecord(name: "Rowing", category: "Cardio", muscleGroupNames: ["back"], tracksSets: false, sides: "both", fields: [
        FieldRecord(key: "f1", label: "Time", type: "time"), FieldRecord(key: "f2", label: "Distance", type: "number")
    ])

    private func file(exercises: [ExerciseRecord], workouts: [WorkoutRecord]) -> BackupFile {
        BackupFile(exportedAt: .now, exercises: exercises, workouts: workouts)
    }

    private func workout(id: UUID = UUID(), _ entries: [EntryRecord]) -> WorkoutRecord {
        WorkoutRecord(id: id, name: "", date: .now, notes: "", exercises: entries)
    }

    private func rowingEntry(timeKey: String = "f1", distanceKey: String = "f2") -> EntryRecord {
        EntryRecord(exercise: "Rowing", notes: "", mode: "bilateral", effortScale: "levels", sets: [
            SetRecord(side: "both", effort: 2, values: [
                ValueRecord(key: timeKey, label: "Time", type: "time", text: nil, number: 480),
                ValueRecord(key: distanceKey, label: "Distance", type: "number", text: nil, number: 2000)
            ])
        ])
    }

    private func single(_ exercise: String, values: [ValueRecord], effort: Double? = nil, mode: String = "bilateral") -> EntryRecord {
        EntryRecord(exercise: exercise, notes: "", mode: mode, effortScale: "levels", sets: [SetRecord(side: mode == "perSide" ? "left" : "both", effort: effort, values: values)])
    }

    private func run(_ file: BackupFile, in context: ModelContext, decisions: ImportDecisions = ImportDecisions(), selection: ImportSelection = ImportSelection()) throws -> ImportSummary {
        let existing = try definitions(in: context).map { ImportPlanner.Existing(id: $0.id, record: BackupExporter.record($0)) }
        let known = Set(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id))
        let plan = ImportPlanner.plan(file: file, existing: existing, knownWorkoutIDs: known)
        let summary = BackupImporter(context: context).apply(plan, decisions: decisions, selection: selection)
        try context.save()
        return summary
    }

    @Test func aFileFillsAnEmptyStore() throws {
        let context = try context()
        let summary = try run(file(exercises: [rowing], workouts: [workout([rowingEntry()])]), in: context)

        #expect(summary.exercisesAdded == 1)
        #expect(summary.workoutsAdded == 1)
        let definition = try #require(try definitions(in: context).first)
        #expect(definition.sortedFields.map(\.label) == ["Time", "Distance"])
        #expect(definition.muscleGroupNames == ["back"])
        let entry = try #require(try entries(in: context).first)
        #expect(entry.definitionID == definition.id)
        let set = try #require(entry.sets.first)
        #expect(set.effort == .level(.hard))
        #expect(set.sortedValues.map(\.numberValue) == [480, 2000])
    }

    @Test func theSameFileTwiceAddsNothing() throws {
        let context = try context()
        let file = file(exercises: [rowing], workouts: [workout([rowingEntry()])])
        _ = try run(file, in: context)
        let again = try run(file, in: context)

        #expect(again.exercisesAdded == 0)
        #expect(again.exercisesUnchanged == 1)
        #expect(again.workoutsAdded == 0)
        #expect(again.workoutsSkipped == 1)
        #expect(try entries(in: context).count == 1)
    }

    /// A rest is never a question: the file brings one the device lacks,
    /// and one set here stays, whatever the file says.
    @Test func aRestSetHereStaysAndAMissingOneComesFromTheFile() throws {
        let context = try context()
        var mine = rowing
        mine.name = "Mine"
        _ = try run(file(exercises: [rowing, mine], workouts: []), in: context)
        let stored = try definitions(in: context)
        try #require(stored.first { $0.name == "Mine" }).restSeconds = 60

        var theirs = rowing
        theirs.restSeconds = 150
        var theirMine = mine
        theirMine.restSeconds = 0
        let summary = try run(file(exercises: [theirs, theirMine], workouts: []), in: context)

        #expect(summary.exercisesUnchanged == 2)
        #expect(stored.first { $0.name == "Rowing" }?.restSeconds == 150)
        #expect(stored.first { $0.name == "Mine" }?.restSeconds == 60)
    }

    /// The other device keyed the same fields differently. A value still
    /// finds its field — by title — so it lands under the right key here.
    @Test func valuesFindTheirFieldByTitleNotByKey() throws {
        let context = try context()
        _ = try run(file(exercises: [rowing], workouts: []), in: context)

        var theirs = rowing
        theirs.fields = [FieldRecord(key: "f7", label: "Distance", type: "number"), FieldRecord(key: "f8", label: "Time", type: "time")]
        _ = try run(file(exercises: [theirs], workouts: [workout([rowingEntry(timeKey: "f8", distanceKey: "f7")])]), in: context)

        let set = try #require(try entries(in: context).first?.sets.first)
        #expect(set.sortedValues.map(\.fieldKey) == ["f1", "f2"])
        #expect(set.sortedValues.map(\.label) == ["Time", "Distance"])
    }

    /// Skipping a conflicting exercise leaves the file's values exactly as they
    /// were logged, even where a key happens to collide.
    @Test func aSkippedConflictKeepsTheFilesValuesUntouched() throws {
        let context = try context()
        _ = try run(file(exercises: [rowing], workouts: []), in: context)

        let other = ExerciseRecord(name: "Rowing", category: "Cardio", muscleGroupNames: [], tracksSets: false, sides: "both", fields: [
            FieldRecord(key: "f1", label: "Heart Rate", type: "number")
        ])
        let entry = single("Rowing", values: [ValueRecord(key: "f1", label: "Heart Rate", type: "number", text: nil, number: 150)])
        var decisions = ImportDecisions()
        decisions.conflicts["rowing"] = .skip
        let summary = try run(file(exercises: [other], workouts: [workout([entry])]), in: context, decisions: decisions)

        #expect(summary.exercisesSkipped == 1)
        #expect(try definitions(in: context).count == 1)
        let stored = try #require(try entries(in: context).first?.sets.first)
        #expect(stored.values.map(\.label) == ["Heart Rate"])
        #expect(stored.values.first?.numberValue == 150)
    }

    @Test func aMergedConflictCarriesFieldsAndRewritesKeys() throws {
        let context = try context()
        _ = try run(file(exercises: [rowing], workouts: []), in: context)

        let other = ExerciseRecord(name: "Rowing", category: "Cardio", muscleGroupNames: [], tracksSets: false, sides: "both", fields: [
            FieldRecord(key: "f1", label: "Dauer", type: "time"), FieldRecord(key: "f2", label: "Heart Rate", type: "number")
        ])
        let entry = single("Rowing", values: [
            ValueRecord(key: "f1", label: "Dauer", type: "time", text: nil, number: 600),
            ValueRecord(key: "f2", label: "Heart Rate", type: "number", text: nil, number: 150)
        ])
        var decisions = ImportDecisions()
        decisions.conflicts["rowing"] = .merge(FieldMapping(destinations: ["f1": .field(targetKey: "f1"), "f2": .newField]))
        let summary = try run(file(exercises: [other], workouts: [workout([entry])]), in: context, decisions: decisions)

        #expect(summary.exercisesMerged == 1)
        let definition = try #require(try definitions(in: context).first)
        #expect(definition.sortedFields.map(\.label) == ["Time", "Distance", "Heart Rate"])
        let stored = try #require(try entries(in: context).first?.sets.first)
        #expect(stored.sortedValues.map(\.label) == ["Time", "Distance", "Heart Rate"])
        #expect(stored.sortedValues.map(\.numberValue) == [600, nil, 150])
    }

    @Test func aRenamedConflictMakesASecondExercise() throws {
        let context = try context()
        _ = try run(file(exercises: [rowing], workouts: []), in: context)
        let other = ExerciseRecord(name: "Rowing", category: "Strength", muscleGroupNames: [], tracksSets: true, sides: "either", fields: [
            FieldRecord(key: "weight", label: "Weight", type: "weight"), FieldRecord(key: "reps", label: "Reps", type: "reps")
        ])
        var decisions = ImportDecisions()
        decisions.conflicts["rowing"] = .rename("Rowing Machine")
        let entry = single("Rowing", values: [
            ValueRecord(key: "weight", label: "Weight", type: "weight", text: nil, number: 40),
            ValueRecord(key: "reps", label: "Reps", type: "reps", text: nil, number: 10)
        ], mode: "perSide")
        _ = try run(file(exercises: [other], workouts: [workout([entry])]), in: context, decisions: decisions)

        #expect(Set(try definitions(in: context).map(\.name)) == ["Rowing", "Rowing Machine"])
        let stored = try #require(try entries(in: context).first)
        #expect(stored.name == "Rowing Machine")
        #expect(stored.unilateralMode == .perSide)
        #expect(stored.sortedSets.first?.setNumber == 1)
        #expect(stored.sortedSets.first?.weightKg == 40)
        #expect(stored.sortedSets.first?.reps == 10)
    }

    @Test func anEntryWhoseExerciseIsNotInTheFileGetsADefinitionOfItsOwn() throws {
        let context = try context()
        let entry = single("Plank", values: [ValueRecord(key: "f1", label: "Hold", type: "time", text: nil, number: 60)])
        let summary = try run(file(exercises: [], workouts: [workout([entry])]), in: context)

        #expect(summary.exercisesAdded == 1)
        let definition = try #require(try definitions(in: context).first)
        #expect(definition.name == "Plank")
        #expect(definition.tracksSets == false)
        #expect(definition.sortedFields.map(\.label) == ["Hold"])
    }

    @Test func theFilesSideWinsOnlyWhereItWasChosen() throws {
        let context = try context()
        _ = try run(file(exercises: [rowing], workouts: []), in: context)
        var theirs = rowing
        theirs.category = "Mobility"
        theirs.muscleGroupNames = ["core"]
        var decisions = ImportDecisions()
        decisions.attributes["rowing"] = [.category(local: "Cardio", file: "Mobility"): .file]
        let summary = try run(file(exercises: [theirs], workouts: []), in: context, decisions: decisions)

        #expect(summary.exercisesUpdated == 1)
        let definition = try #require(try definitions(in: context).first)
        #expect(definition.categoryName == "Mobility")
        #expect(definition.muscleGroupNames == ["back"])
    }

    @Test func replacingDeletesWhatWasThereFirst() throws {
        let context = try context()
        _ = try run(file(exercises: [rowing], workouts: [workout([rowingEntry()])]), in: context)
        var selection = ImportSelection()
        selection.replaceWorkouts = true
        _ = try run(file(exercises: [], workouts: [workout([rowingEntry()])]), in: context, selection: selection)

        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).count == 1)
    }

    /// A left/right log numbers its sets per side, the way the editor does.
    @Test func sidesAreNumberedSeparately() throws {
        let context = try context()
        let sets = ["left", "right", "left", "right", "left"].map {
            SetRecord(side: $0, values: [ValueRecord(key: "reps", label: "Reps", type: "reps", text: nil, number: 10)])
        }
        let entry = EntryRecord(exercise: "Leg Curl", notes: "", mode: "perSide", effortScale: "levels", sets: sets)
        _ = try run(file(exercises: [], workouts: [workout([entry])]), in: context)

        let stored = try #require(try entries(in: context).first)
        #expect(stored.sortedSets.filter { $0.side == .left }.map(\.setNumber) == [1, 2, 3])
        #expect(stored.sortedSets.filter { $0.side == .right }.map(\.setNumber) == [1, 2])
    }

    /// The file's group number means nothing outside its own workout — two
    /// entries sharing one get a fresh, shared id; an ungrouped one gets none.
    @Test func entriesSharingAGroupNumberComeBackPaired() throws {
        let context = try context()
        let curl = single("Curl", values: [])
        var pushdown = single("Pushdown", values: [])
        var group = curl
        group.supersetGroup = 1
        pushdown.supersetGroup = 1
        let squat = single("Squat", values: [])
        _ = try run(file(exercises: [], workouts: [workout([group, pushdown, squat])]), in: context)

        let stored = try entries(in: context)
        let byName = Dictionary(uniqueKeysWithValues: stored.map { ($0.name, $0) })
        let curlID = try #require(byName["Curl"]?.supersetID)
        #expect(byName["Pushdown"]?.supersetID == curlID)
        #expect(byName["Squat"]?.supersetID == nil)
    }

    /// Two different groups in the same workout stay two different pairs.
    @Test func twoGroupsInOneWorkoutStayApart() throws {
        let context = try context()
        var a1 = single("Curl", values: []); a1.supersetGroup = 1
        var a2 = single("Pushdown", values: []); a2.supersetGroup = 1
        var b1 = single("Squat", values: []); b1.supersetGroup = 2
        var b2 = single("Lunge", values: []); b2.supersetGroup = 2
        _ = try run(file(exercises: [], workouts: [workout([a1, a2, b1, b2])]), in: context)

        let stored = try entries(in: context)
        let byName = Dictionary(uniqueKeysWithValues: stored.map { ($0.name, $0) })
        let groupA = try #require(byName["Curl"]?.supersetID)
        let groupB = try #require(byName["Squat"]?.supersetID)
        #expect(byName["Pushdown"]?.supersetID == groupA)
        #expect(byName["Lunge"]?.supersetID == groupB)
        #expect(groupA != groupB)
    }

    /// A superset's shared order comes back as it was exported; outside a
    /// superset a stray position is not taken over.
    @Test func aSupersetsSetOrderComesBack() throws {
        let context = try context()
        let reps = [ValueRecord(key: "reps", label: "Reps", type: "reps", text: nil, number: 8)]
        func set(_ position: Int?) -> SetRecord {
            SetRecord(side: "both", supersetPosition: position, values: reps)
        }
        var curl = single("Curl", values: reps); curl.supersetGroup = 1
        curl.sets = [set(1), set(3), set(4)]
        var pushdown = single("Pushdown", values: reps); pushdown.supersetGroup = 1
        pushdown.sets = [set(2)]
        var squat = single("Squat", values: reps)
        squat.sets = [set(7)]
        _ = try run(file(exercises: [], workouts: [workout([curl, pushdown, squat])]), in: context)

        let stored = try entries(in: context)
        let byName = Dictionary(uniqueKeysWithValues: stored.map { ($0.name, $0) })
        #expect(byName["Curl"]?.sortedSets.map(\.supersetPosition) == [1, 3, 4])
        #expect(byName["Pushdown"]?.sortedSets.map(\.supersetPosition) == [2])
        #expect(byName["Squat"]?.sortedSets.map(\.supersetPosition) == [nil])
    }

    @Test func theScaleAndTheRatingsComeBack() throws {
        let context = try context()
        let reps = [ValueRecord(key: "reps", label: "Reps", type: "reps", text: nil, number: 8)]
        var bench = single("Bench", values: reps)
        bench.sets = [
            SetRecord(side: "both", effort: 0, values: reps),
            SetRecord(side: "both", values: reps),
            SetRecord(side: "both", effort: 2, values: reps),
        ]
        var plank = single("Plank", values: reps)
        plank.effortScale = "off"
        _ = try run(file(exercises: [], workouts: [workout([bench, plank])]), in: context)

        let byName = Dictionary(uniqueKeysWithValues: try entries(in: context).map { ($0.name, $0) })
        #expect(byName["Bench"]?.effortScale == .levels)
        #expect(byName["Bench"]?.sortedSets.map(\.effort) == [.level(.easy), nil, .level(.hard)])
        #expect(byName["Plank"]?.effortScale == .off)
    }

    /// Only a hand-edited file holds a rating its scale cannot read; it is
    /// dropped, and the import summary does not mention it.
    @Test func dropsARatingTheScaleCannotHoldWithoutSayingSo() throws {
        let context = try context()
        let reps = [ValueRecord(key: "reps", label: "Reps", type: "reps", text: nil, number: 8)]
        var bench = single("Bench", values: reps, effort: 7)
        var plank = single("Plank", values: reps, effort: 1)
        plank.effortScale = "off"
        bench.notes = "rated 7 on a three-step scale"
        _ = try run(file(exercises: [], workouts: [workout([bench, plank])]), in: context)

        let byName = Dictionary(uniqueKeysWithValues: try entries(in: context).map { ($0.name, $0) })
        #expect(byName["Bench"]?.sets.first?.effortValue == nil)
        #expect(byName["Plank"]?.sets.first?.effortValue == nil)
    }

    /// The same for a scale this version does not know: the entry rates
    /// nothing, and its ratings go with it.
    @Test func readsAnUnknownScaleAsOffWithoutSayingSo() throws {
        let context = try context()
        let reps = [ValueRecord(key: "reps", label: "Reps", type: "reps", text: nil, number: 8)]
        var bench = single("Bench", values: reps, effort: 2)
        bench.effortScale = "stars"
        _ = try run(file(exercises: [], workouts: [workout([bench])]), in: context)

        let entry = try #require(try entries(in: context).first)
        #expect(entry.effortScale == .off)
        #expect(entry.sets.first?.effortValue == nil)
    }

    // MARK: - Summary

    @Test func theSummaryCountsOneInTheSingular() {
        let summary = ImportSummary(exercisesAdded: 1, exercisesMerged: 1, workoutsAdded: 1, workoutsSkipped: 1)
        #expect(summary.message == "Added 1 exercise and 1 workout.\n\n1 exercise was merged into yours.\n\nSkipped 1 workout already here.")
    }

    @Test func theSummaryCountsSeveralInThePlural() {
        let summary = ImportSummary(exercisesAdded: 2, exercisesMerged: 3, workoutsAdded: 4, workoutsSkipped: 5)
        #expect(summary.message == "Added 2 exercises and 4 workouts.\n\n3 exercises were merged into yours.\n\nSkipped 5 workouts already here.")
    }

    @Test func repsInReserveComeBackToTheHalf() throws {
        let context = try context()
        let reps = [ValueRecord(key: "reps", label: "Reps", type: "reps", text: nil, number: 8)]
        var squat = single("Squat", values: reps)
        squat.effortScale = "rir"
        squat.sets = [0, 2.5, nil, 10].map { SetRecord(side: "both", effort: $0, values: reps) }
        _ = try run(file(exercises: [], workouts: [workout([squat])]), in: context)

        let entry = try #require(try entries(in: context).first)
        #expect(entry.effortScale == .rir)
        #expect(entry.sortedSets.map(\.effort) == [.rir(0), .rir(2.5), nil, .rir(10)])
    }

    /// A catalog exercise is found by its key: a file from a device where the
    /// catalog calls it something else lands on the same exercise, under the
    /// name this device knows, and its entries carry the key.
    @Test func aCatalogExerciseIsFoundByKeyUnderAnotherName() throws {
        let context = try context()
        let bench = ExerciseDefinition.insertPlainSetsAndReps(name: "Barbell Bench Press", orderIndex: 0, muscleGroupNames: ["chest", "triceps"], in: context)
        bench.catalogKey = "barbell-bench-press"
        try context.save()

        var german = BackupExporter.record(bench)
        german.name = "Bankdrücken (Langhantel)"
        var entry = single("Bankdrücken (Langhantel)", values: [ValueRecord(key: "weight", label: "Weight", type: "weight", text: nil, number: 80)])
        entry.catalogKey = "barbell-bench-press"
        let summary = try run(file(exercises: [german], workouts: [workout([entry])]), in: context)

        #expect(summary.exercisesAdded == 0)
        #expect(try definitions(in: context).count == 1)
        let logged = try #require(try entries(in: context).first)
        #expect(logged.definitionID == bench.id)
        #expect(logged.name == "Barbell Bench Press")
        #expect(logged.catalogKey == "barbell-bench-press")
    }

    /// The catalog is on every device: finding it unchanged is not worth a
    /// line in the summary, which would otherwise read "Skipped 100
    /// exercises" for a backup with three of the user's own.
    @Test func anUnchangedCatalogExerciseIsNotCountedAsSkipped() throws {
        let context = try context()
        let bench = ExerciseDefinition.insertPlainSetsAndReps(name: "Barbell Bench Press", orderIndex: 0, in: context)
        bench.catalogKey = "barbell-bench-press"
        try context.save()

        let summary = try run(file(exercises: [BackupExporter.record(bench), rowing], workouts: []), in: context)

        #expect(summary.exercisesAdded == 1)
        #expect(summary.exercisesUnchanged == 0)
        #expect(summary.message == "Added 1 exercise.")
    }

    /// An entry of the user's own exercise carries no key, even when the
    /// exercise it lands on by name is a catalog one — it then is that one.
    @Test func anOwnEntryLandingOnACatalogExerciseTakesItsKey() throws {
        let context = try context()
        let bench = ExerciseDefinition.insertPlainSetsAndReps(name: "Barbell Bench Press", orderIndex: 0, in: context)
        bench.catalogKey = "barbell-bench-press"
        try context.save()

        let entry = single("barbell bench press", values: [ValueRecord(key: "weight", label: "Weight", type: "weight", text: nil, number: 80)])
        _ = try run(file(exercises: [], workouts: [workout([entry])]), in: context)

        let logged = try #require(try entries(in: context).first)
        #expect(logged.definitionID == bench.id)
        #expect(logged.catalogKey == "barbell-bench-press")
    }

    /// Taking the file's version of a catalog exercise makes it the user's
    /// own, under its own name; the catalog exercise is not touched.
    @Test func theFilesVersionOfACatalogExerciseBecomesOwn() throws {
        let context = try context()
        let bench = ExerciseDefinition.insertPlainSetsAndReps(name: "Barbell Bench Press", orderIndex: 0, muscleGroupNames: ["chest", "triceps"], in: context)
        bench.catalogKey = "barbell-bench-press"
        try context.save()

        var theirs = BackupExporter.record(bench)
        theirs.catalogKey = nil
        theirs.muscleGroupNames = ["chest", "shoulders"]
        let entry = single("Barbell Bench Press", values: [ValueRecord(key: "weight", label: "Weight", type: "weight", text: nil, number: 80)])
        var decisions = ImportDecisions()
        decisions.conflicts["barbell bench press"] = .rename("Barbell Bench Press (Mine)")
        _ = try run(file(exercises: [theirs], workouts: [workout([entry])]), in: context, decisions: decisions)

        #expect(bench.muscleGroupNames == ["chest", "triceps"])
        let mine = try #require(try definitions(in: context).first { $0.name == "Barbell Bench Press (Mine)" })
        #expect(mine.catalogKey == nil)
        #expect(mine.muscleGroupNames == ["chest", "shoulders"])
        let logged = try #require(try entries(in: context).first)
        #expect(logged.definitionID == mine.id)
        #expect(logged.catalogKey == nil)
    }

    /// Leaving the file's version to the catalog exercise leaves nothing out:
    /// its workouts land on the catalog's, and the summary says so instead of
    /// "Skipped 1 exercise left out".
    @Test func aConflictLeftToTheCatalogIsAMatchNotASkip() throws {
        let context = try context()
        let bench = ExerciseDefinition.insertPlainSetsAndReps(name: "Barbell Bench Press", orderIndex: 0, muscleGroupNames: ["chest", "triceps"], in: context)
        bench.catalogKey = "barbell-bench-press"
        try context.save()

        var theirs = BackupExporter.record(bench)
        theirs.catalogKey = nil
        theirs.muscleGroupNames = ["chest"]
        let entry = single("Barbell Bench Press", values: [ValueRecord(key: "weight", label: "Weight", type: "weight", text: nil, number: 80)])
        let summary = try run(file(exercises: [theirs], workouts: [workout([entry])]), in: context)

        #expect(summary.exercisesMatchedToCatalog == 1)
        #expect(summary.exercisesSkipped == 0)
        #expect(summary.message == "Added 1 workout.\n\n1 exercise is the catalog's here; the workouts use those.")
        #expect(try entries(in: context).first?.definitionID == bench.id)
    }

    @Test func theSummarySaysWhatWasLeftOutOnALineOfItsOwn() {
        let summary = ImportSummary(exercisesSkipped: 2, exercisesUnchanged: 3, workoutsSkipped: 1)
        #expect(summary.message == "Nothing was added.\n\nLeft out 2 exercises of the file; the workouts use yours.\n\nSkipped 3 exercises already here, 1 workout already here.")
    }

    /// The user's own version of a catalog exercise lives beside it: an entry
    /// with no key goes to the own one, an entry with the key to the catalog's.
    @Test func entriesFindTheirKindWhenAnOwnVersionSitsBesideTheCatalogExercise() throws {
        let context = try context()
        let catalog = ExerciseDefinition.insertPlainSetsAndReps(name: "Barbell Bench Press", orderIndex: 0, in: context)
        catalog.catalogKey = "barbell-bench-press"
        let mine = ExerciseDefinition.insertPlainSetsAndReps(name: "Barbell Bench Press", orderIndex: 1, muscleGroupNames: ["chest"], in: context)
        try context.save()

        let values = [ValueRecord(key: "weight", label: "Weight", type: "weight", text: nil, number: 80)]
        let own = single("Barbell Bench Press", values: values)
        var keyed = single("Barbell Bench Press", values: values)
        keyed.catalogKey = "barbell-bench-press"
        _ = try run(file(exercises: [], workouts: [workout([own]), workout([keyed])]), in: context)

        let logged = try entries(in: context)
        #expect(logged.count == 2)
        #expect(Set(logged.map(\.definitionID)) == [catalog.id, mine.id])
        for entry in logged {
            #expect(entry.catalogKey == (entry.definitionID == catalog.id ? "barbell-bench-press" : nil))
        }
    }

    /// An assisted entry whose exercise the file does not bring makes one
    /// with a weight field — the help stood in for it — that offers help.
    @Test func anAssistedEntryWithoutItsExerciseMakesOneThatCanBeAssisted() throws {
        let context = try context()
        var entry = single("Pull-Up", values: [
            ValueRecord(key: "weight", label: "Assist", type: "assistance", number: 25),
            ValueRecord(key: "reps", label: "Reps", type: "reps", number: 8)
        ])
        entry.assistance = Assistance.machine.rawValue

        _ = try run(file(exercises: [], workouts: [workout([entry])]), in: context)

        let definition = try #require(try definitions(in: context).first)
        #expect(definition.offersAssistance)
        #expect(definition.sortedFields.map(\.type) == [.weight, .reps])
        let logged = try #require(try entries(in: context).first)
        #expect(logged.assistance == .machine)
        #expect(logged.sets.first?.assistanceKg == 25)
        #expect(logged.sets.first?.values.first { $0.fieldKey == "weight" }?.label == "Assist")
    }

    @Test func importedTemplatesStandFirstInTheFilesOrder() throws {
        let context = try context()
        for (order, name) in ["Push A", "Pull A"].enumerated() {
            let template = WorkoutSession(name: name)
            template.isTemplate = true
            template.templateOrder = order
            context.insert(template)
        }
        let file = BackupFile(exportedAt: .now, templates: [
            TemplateRecord(id: UUID(), name: "Push B", notes: "", archived: false, plannedFor: .now, exercises: []),
            TemplateRecord(id: UUID(), name: "Pull B", notes: "", archived: false, exercises: [])
        ])
        _ = try run(file, in: context)

        let shelf = TemplateShelf(try context.fetch(FetchDescriptor<WorkoutSession>()))
        #expect(shelf.templates.map(\.name) == ["Push B", "Pull B", "Push A", "Pull A"])
        #expect(shelf.templates.map(\.templateOrder) == [0, 1, 2, 3])
    }
}
