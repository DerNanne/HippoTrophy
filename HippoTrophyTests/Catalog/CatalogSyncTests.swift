import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

struct CatalogSyncTests {
    private let bench = CatalogExercise(key: "barbell-bench-press", name: "Barbell Bench Press", muscleGroupNames: ["chest", "triceps"])
    private let curl = CatalogExercise(key: "dumbbell-curl", name: "Dumbbell Curl", muscleGroupNames: ["biceps"])
    private let hold = CatalogExercise(
        key: "isometric-leg-extension", name: "Isometric Leg Extension", muscleGroupNames: ["quads"], sides: .one,
        category: "Isometrics",
        fields: [
            FieldRecord(key: "weight", label: "Weight", type: "weight"),
            FieldRecord(key: "f1", label: "Hold", type: "time"),
        ]
    )
    private static let repsOnly = ExerciseShape(tracksSets: true, fields: [FieldShape(labelKey: "reps", type: "reps")])

    private func own(_ name: String, muscles: [String] = [], plain: Bool = true, sides: ExerciseSides = .either) -> CatalogCandidate {
        CatalogCandidate(id: UUID(), name: name, catalogKey: nil, muscleGroupNames: muscles, shape: plain ? CatalogExercise.plain.shape : Self.repsOnly, sides: sides)
    }

    private func catalog(_ exercise: CatalogExercise, name: String? = nil, muscles: [String]? = nil) -> CatalogCandidate {
        CatalogCandidate(
            id: UUID(), name: name ?? exercise.name, catalogKey: exercise.key,
            muscleGroupNames: muscles ?? exercise.muscleGroupNames, sides: exercise.sides
        )
    }

    @Test func anEmptyStoreGetsTheWholeCatalog() {
        let sync = CatalogSync.plan(catalog: [bench, curl], store: [])
        #expect(sync.inserts == [bench, curl])
    }

    @Test func aStoreInStepWithTheCatalogNeedsNothing() {
        let sync = CatalogSync.plan(catalog: [bench, curl], store: [catalog(bench), catalog(curl)])
        #expect(sync.isEmpty)
    }

    /// The testers' case: an exercise they typed in themselves, no muscles.
    @Test func anOwnExerciseWithTheCatalogsNameAndNoMusclesIsAdopted() {
        let mine = own("barbell bench press ")
        let sync = CatalogSync.plan(catalog: [bench], store: [mine])
        #expect(sync.adoptions == [mine.id: bench])
        #expect(sync.inserts.isEmpty)
    }

    @Test func anOwnExerciseWithTheCatalogsMusclesInAnotherOrderIsAdopted() {
        let mine = own("Barbell Bench Press", muscles: ["triceps", "chest"])
        #expect(CatalogSync.plan(catalog: [bench], store: [mine]).adoptions == [mine.id: bench])
    }

    /// Their muscles are a choice the catalog would overwrite; their fields
    /// one it cannot hold. Both stay theirs — and the catalog exercise comes
    /// in beside it, so the catalog is whole whatever the user's own are
    /// called.
    @Test(arguments: [(["chest"], true), ([], false)])
    func anOwnExerciseThatDiffersStaysOwnAndTheCatalogComesBeside(muscles: [String], plain: Bool) {
        let mine = own("Barbell Bench Press", muscles: muscles, plain: plain)
        let sync = CatalogSync.plan(catalog: [bench], store: [mine])
        #expect(sync.adoptions.isEmpty)
        #expect(sync.inserts == [bench])
    }

    /// An own exercise logged either way joins a two-sided or a one-sided
    /// catalog exercise alike; its entries are moved to where they belong.
    @Test func anOwnExerciseTrainedEitherWayIsAdopted() {
        let mine = own("Barbell Bench Press", sides: .either)
        #expect(CatalogSync.plan(catalog: [bench], store: [mine]).adoptions == [mine.id: bench])
    }

    /// A one-sided own exercise is not the two-sided catalog one: it stays,
    /// and the catalog exercise comes in beside it.
    @Test func aOneSidedOwnExerciseIsNotAdoptedByATwoSidedOne() {
        let mine = own("Barbell Bench Press", sides: .one)
        let sync = CatalogSync.plan(catalog: [bench], store: [mine])
        #expect(sync.adoptions.isEmpty)
        #expect(sync.inserts == [bench])
    }

    @Test func aCatalogExerciseFollowsTheCatalogsSides() {
        let stored = catalog(bench)
        var either = stored
        either.sides = .either
        #expect(CatalogSync.plan(catalog: [bench], store: [either]).refreshes == [either.id: bench])
    }

    /// Once both are there, nothing more happens.
    @Test func anOwnVersionBesideItsCatalogExerciseNeedsNothing() {
        let mine = own("Barbell Bench Press", muscles: ["chest"])
        #expect(CatalogSync.plan(catalog: [bench], store: [mine, catalog(bench)]).isEmpty)
    }

    /// Nothing fuzzier than the one name rule: a typo is the migration
    /// assistant's to catch, not the launch's.
    @Test func aNameThatIsOnlyCloseIsNotAdopted() {
        let mine = own("Barbel Bench Press")
        let sync = CatalogSync.plan(catalog: [bench], store: [mine])
        #expect(sync.adoptions.isEmpty)
        #expect(sync.inserts == [bench])
    }

    @Test func aCatalogExerciseFollowsTheCatalogsNameAndMuscles() {
        let stale = catalog(bench, name: "Bench Press", muscles: ["chest"])
        #expect(CatalogSync.plan(catalog: [bench], store: [stale]).refreshes == [stale.id: bench])
    }

    /// The catalog that tells main muscles from secondary ones reaches the
    /// exercises in the store from before it.
    @Test func aCatalogExerciseFollowsTheCatalogsSecondaryMuscles() {
        let squat = CatalogExercise(key: "back-squat", name: "Back Squat", muscleGroupNames: ["quads", "glutes"], secondaryMuscleGroupNames: ["adductors"])
        let stale = catalog(squat)
        let before = CatalogCandidate(
            id: stale.id, name: stale.name, catalogKey: stale.catalogKey, muscleGroupNames: stale.muscleGroupNames,
            secondaryMuscleGroupNames: [], sides: stale.sides
        )
        #expect(CatalogSync.plan(catalog: [squat], store: [before]).refreshes == [before.id: squat])
    }

    /// Filed before there were secondary muscles, an own exercise with the
    /// catalog's main ones is filed like the catalog; one with other
    /// secondary ones is a choice of its own.
    /// The list builds up to 20 shipped filed every muscle alike — Bench
    /// Press as Chest and Triceps. Imported from it, an exercise is the
    /// catalog's, now that Triceps is secondary there; one missing a main
    /// muscle, or naming one the catalog does not, stays the user's. The
    /// update test from build 20 found 22 of the list's exercises left
    /// beside their catalog twins under the first rule.
    @Test(arguments: [
        (["chest", "triceps"], true),
        (["chest", "triceps", "shoulders"], true),
        (["chest"], true),
        (["triceps"], false),
        (["chest", "back"], false),
    ])
    func anExerciseFiledBeforeSecondaryMusclesIsTheCatalogsWhenItNamesItsMuscles(muscles: [String], adopted: Bool) {
        let bench = CatalogExercise(
            key: "barbell-bench-press", name: "Barbell Bench Press",
            muscleGroupNames: ["chest"], secondaryMuscleGroupNames: ["triceps", "shoulders"]
        )
        let mine = CatalogCandidate(
            id: UUID(), name: "Barbell Bench Press", catalogKey: nil, muscleGroupNames: muscles,
            sides: .either
        )
        #expect(!CatalogSync.plan(catalog: [bench], store: [mine]).adoptions.isEmpty == adopted)
    }

    @Test(arguments: [([String](), true), (["adductors"], true), (["hamstrings"], false)])
    func anOwnExerciseWithTheCatalogsMainMusclesIsAdoptedUnlessItsSecondaryOnesDiffer(secondary: [String], adopted: Bool) {
        let squat = CatalogExercise(key: "back-squat", name: "Back Squat", muscleGroupNames: ["quads", "glutes"], secondaryMuscleGroupNames: ["adductors"])
        let mine = CatalogCandidate(
            id: UUID(), name: "Back Squat", catalogKey: nil, muscleGroupNames: ["glutes", "quads"],
            secondaryMuscleGroupNames: secondary, sides: .both
        )
        #expect(!CatalogSync.plan(catalog: [squat], store: [mine]).adoptions.isEmpty == adopted)
    }

    @Test func aKeyTheCatalogDroppedBecomesOwn() {
        let orphan = catalog(curl)
        let sync = CatalogSync.plan(catalog: [bench], store: [catalog(bench), orphan])
        #expect(sync.releases == [orphan.id])
        #expect(sync.deletions.isEmpty)
        #expect(sync.inserts.isEmpty)
    }

    @Test func aKeyTheCatalogDroppedGoesWhenNeverUsed() {
        var orphan = catalog(curl)
        orphan.isUsed = false
        let sync = CatalogSync.plan(catalog: [bench], store: [catalog(bench), orphan])
        #expect(sync.deletions == [orphan.id])
        #expect(sync.releases.isEmpty)
    }

    /// Only a broken backup or a bug could put one key on two exercises;
    /// the first keeps it and nothing is inserted a third time.
    @Test func aSecondDefinitionWithTheSameKeyBecomesOwn() {
        let first = catalog(bench)
        let second = catalog(bench)
        let sync = CatalogSync.plan(catalog: [bench], store: [first, second])
        #expect(sync.releases == [second.id])
        #expect(sync.inserts.isEmpty)
    }

    @MainActor
    @Test func runningItTwiceChangesNothingTheSecondTime() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let mine = ExerciseDefinition.insertPlainSetsAndReps(name: "dumbbell curl", orderIndex: 0, in: context)

        try CatalogSync.run(catalog: [bench, curl], in: context)
        try CatalogSync.run(catalog: [bench, curl], in: context)

        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>(sortBy: [SortDescriptor(\.orderIndex)]))
        #expect(definitions.map(\.name) == ["Dumbbell Curl", "Barbell Bench Press"])
        #expect(definitions.map(\.catalogKey) == ["dumbbell-curl", "barbell-bench-press"])
        #expect(mine.muscleGroupNames == ["biceps"])
        #expect(definitions.allSatisfy { $0.isPlainSetsAndReps })
    }

    /// Adopting can change how the name is written, and a later catalog can
    /// rename; the entries logged from it follow, as they do an edit.
    @MainActor
    @Test func aRenameIsPulledThroughTheEntries() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let mine = ExerciseDefinition.insertPlainSetsAndReps(name: "dumbbell curl", orderIndex: 0, in: context)
        let session = WorkoutSession(name: "Arms")
        context.insert(session)
        let entry = ExerciseEntry(name: "dumbbell curl", orderIndex: 0, definitionID: mine.id, effortScale: .levels, session: session)
        context.insert(entry)

        try CatalogSync.run(catalog: [curl], in: context)
        #expect(entry.name == "Dumbbell Curl")

        let renamed = CatalogExercise(key: curl.key, name: "Dumbbell Biceps Curl", muscleGroupNames: curl.muscleGroupNames)
        try CatalogSync.run(catalog: [renamed], in: context)
        #expect(entry.name == "Dumbbell Biceps Curl")
    }

    /// The overhead extension a build before feature-096 shipped named no tool.
    /// Whoever logged it gets it back as their own, workouts and all, and the
    /// catalog's dumbbell one comes in beside it: which tool it was is theirs
    /// to say, in Review My Exercises.
    @MainActor
    @Test func theOverheadExtensionWithoutAToolBecomesOwn() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let before = ExerciseDefinition.insertPlainSetsAndReps(
            name: "Overhead Triceps Extension", orderIndex: 0, muscleGroupNames: ["triceps"], in: context
        )
        before.catalogKey = "overhead-triceps-extension"
        let session = WorkoutSession(name: "Arms")
        context.insert(session)
        let entry = ExerciseEntry(
            name: "Overhead Triceps Extension", orderIndex: 0, definitionID: before.id, effortScale: .levels,
            catalogKey: "overhead-triceps-extension", session: session
        )
        context.insert(entry)
        entry.notes = "with the rope"

        try CatalogSync.run(in: context)

        #expect(before.catalogKey == nil)
        #expect(before.name == "Overhead Triceps Extension")
        #expect(entry.identity == .own("Overhead Triceps Extension".exerciseKey))
        let dumbbell = try context.fetch(FetchDescriptor<ExerciseDefinition>()).filter { $0.catalogKey == "dumbbell-overhead-triceps-extension" }
        #expect(dumbbell.count == 1)
    }

    /// Never logged, it would be an own exercise nobody asked for; it goes,
    /// with the entry left empty.
    @MainActor
    @Test func aDroppedExerciseNeverUsedGoes() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let before = ExerciseDefinition.insertPlainSetsAndReps(
            name: "Overhead Triceps Extension", orderIndex: 0, muscleGroupNames: ["triceps"], in: context
        )
        before.catalogKey = "overhead-triceps-extension"
        let session = WorkoutSession(name: "Arms")
        context.insert(session)
        context.insert(ExerciseEntry(
            name: "Overhead Triceps Extension", orderIndex: 0, definitionID: before.id, effortScale: .levels,
            catalogKey: "overhead-triceps-extension", session: session
        ))

        try CatalogSync.run(in: context)

        let names = try context.fetch(FetchDescriptor<ExerciseDefinition>()).map(\.name)
        #expect(!names.contains("Overhead Triceps Extension"))
        #expect(names.contains("Dumbbell Overhead Triceps Extension"))
        #expect(try context.fetch(FetchDescriptor<ExerciseEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).count == 1)
    }

    private let legPress = CatalogExercise(key: "leg-press", name: "Leg Press", muscleGroupNames: ["quads", "glutes"])
    private let legPressOne = CatalogExercise(
        key: "leg-press-unilateral", name: "Leg Press (Unilateral)", muscleGroupNames: ["quads", "glutes"],
        sides: .one, unilateralOf: "leg-press"
    )
    private let chestPress = CatalogExercise(key: "chest-press-machine", name: "Chest Press Machine", muscleGroupNames: ["chest", "triceps"])
    private let splitSquat = CatalogExercise(key: "bulgarian-split-squat", name: "Bulgarian Split Squat", muscleGroupNames: ["quads", "glutes"], sides: .one)

    /// A store as the catalog left it, plus one entry of `key` logged in `mode`.
    @MainActor
    private func storeWithEntry(
        of key: String, mode: UnilateralMode, catalog: [CatalogExercise], defaults: UserDefaults
    ) throws -> (ModelContext, ExerciseEntry) {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CatalogSync.run(catalog: catalog, in: context, defaults: defaults)
        let definition = try #require(try context.fetch(FetchDescriptor<ExerciseDefinition>()).first { $0.catalogKey == key })
        let session = WorkoutSession(name: "Legs")
        context.insert(session)
        let entry = ExerciseEntry(name: definition.name, orderIndex: 0, definitionID: definition.id, effortScale: .levels, catalogKey: key, session: session)
        entry.unilateralMode = mode
        context.insert(entry)
        try context.save()
        return (context, entry)
    }

    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CatalogSyncTests-\(UUID().uuidString)")!
    }

    /// Leg Press logged left and right, from before the catalog had a
    /// one-sided form: the entry goes there, logged as it was.
    @MainActor
    @Test func aOneSidedEntryMovesToTheOneSidedForm() throws {
        let catalog = [legPress, legPressOne]
        let defaults = scratchDefaults()
        let (context, entry) = try storeWithEntry(of: "leg-press", mode: .perSide, catalog: catalog, defaults: defaults)

        try CatalogSync.run(catalog: catalog, in: context, defaults: defaults)

        let variant = try #require(try context.fetch(FetchDescriptor<ExerciseDefinition>()).first { $0.catalogKey == "leg-press-unilateral" })
        #expect(variant.sides == .one)
        #expect(entry.definitionID == variant.id)
        #expect(entry.identity == .catalog("leg-press-unilateral"))
        #expect(entry.name == "Leg Press (Unilateral)")
        #expect(entry.unilateralMode == .perSide)
    }

    @MainActor
    @Test func aTwoSidedEntryStaysWithItsTwoSidedExercise() throws {
        let catalog = [legPress, legPressOne]
        let defaults = scratchDefaults()
        let (context, entry) = try storeWithEntry(of: "leg-press", mode: .bilateral, catalog: catalog, defaults: defaults)
        try CatalogSync.run(catalog: catalog, in: context, defaults: defaults)
        #expect(entry.identity == .catalog("leg-press"))
    }

    /// Bulgarian Split Squats logged "normal", where a new entry used to
    /// start: one side was trained either way.
    @MainActor
    @Test func aTwoSidedEntryOfAOneSidedExerciseBecomesSameWeight() throws {
        let catalog = [splitSquat]
        let defaults = scratchDefaults()
        let (context, entry) = try storeWithEntry(of: "bulgarian-split-squat", mode: .bilateral, catalog: catalog, defaults: defaults)
        try CatalogSync.run(catalog: catalog, in: context, defaults: defaults)
        #expect(entry.unilateralMode == .oneSided)
        #expect(entry.identity == .catalog("bulgarian-split-squat"))
    }

    /// No one-sided Chest Press Machine in the catalog yet: the entry goes to
    /// an own one made for it, which the review of My Exercises leaves alone.
    @MainActor
    @Test func withoutAOneSidedFormAnOwnOneIsMadeAndKept() throws {
        let catalog = [chestPress]
        let defaults = scratchDefaults()
        let (context, entry) = try storeWithEntry(of: "chest-press-machine", mode: .perSide, catalog: catalog, defaults: defaults)

        try CatalogSync.run(catalog: catalog, in: context, defaults: defaults)

        let made = try #require(try context.fetch(FetchDescriptor<ExerciseDefinition>()).first { $0.name == "Chest Press Machine (Unilateral)" })
        #expect(!made.isCatalog)
        #expect(made.sides == .one)
        #expect(made.muscleGroupNames == ["chest", "triceps"])
        #expect(made.isPlainSetsAndReps)
        #expect(entry.definitionID == made.id)
        #expect(entry.identity == .own("chest press machine (unilateral)"))
        #expect(entry.unilateralMode == .perSide)
        let kept = KeptOwnExercises(stored: defaults.string(forKey: SettingsKey.keptOwnExercises) ?? "")
        #expect(kept.ids == [made.id])

        // The settlement after it, on the same launch, has nothing to ask
        // about the one it made.
        try SidesSettlement.runOnce(in: context, defaults: defaults)
        #expect(made.sides == .one)
        #expect(!SidesAssistant.load(in: context).exercises.contains { $0.id == made.id })
    }

    /// The day the catalog has it, the own one is adopted by its name,
    /// entries and all.
    @MainActor
    @Test func theOwnOneSidedFormJoinsTheCatalogOnceItIsThere() throws {
        let defaults = scratchDefaults()
        let (context, entry) = try storeWithEntry(of: "chest-press-machine", mode: .perSide, catalog: [chestPress], defaults: defaults)
        try CatalogSync.run(catalog: [chestPress], in: context, defaults: defaults)

        let chestPressOne = CatalogExercise(
            key: "chest-press-machine-unilateral", name: "Chest Press Machine (Unilateral)", muscleGroupNames: ["chest", "triceps"],
            sides: .one, unilateralOf: "chest-press-machine"
        )
        try CatalogSync.run(catalog: [chestPress, chestPressOne], in: context, defaults: defaults)

        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        #expect(definitions.filter { $0.name == "Chest Press Machine (Unilateral)" }.count == 1)
        #expect(entry.identity == .catalog("chest-press-machine-unilateral"))
    }

    @MainActor
    @Test func movingTwiceChangesNothingTheSecondTime() throws {
        let catalog = [legPress, legPressOne, chestPress, splitSquat]
        let defaults = scratchDefaults()
        let (context, _) = try storeWithEntry(of: "chest-press-machine", mode: .perSide, catalog: catalog, defaults: defaults)
        try CatalogSync.run(catalog: catalog, in: context, defaults: defaults)
        let before = try context.fetch(FetchDescriptor<ExerciseDefinition>()).count
        try CatalogSync.run(catalog: catalog, in: context, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<ExerciseDefinition>()).count == before)
        #expect(!context.hasChanges)
    }

    /// The skull crusher a build before feature-152 shipped named no tool.
    /// Whoever logged it gets it back as their own, workouts and all, and the
    /// catalog's two come in beside it: which one it was is theirs to say, in
    /// Review My Exercises.
    @MainActor
    @Test func theSkullCrusherWithoutAToolBecomesOwn() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let before = ExerciseDefinition.insertPlainSetsAndReps(
            name: "Skull Crusher", orderIndex: 0, muscleGroupNames: ["triceps"], in: context
        )
        before.catalogKey = "skull-crusher"
        let session = WorkoutSession(name: "Arms")
        context.insert(session)
        let entry = ExerciseEntry(
            name: "Skull Crusher", orderIndex: 0, definitionID: before.id, effortScale: .levels,
            catalogKey: "skull-crusher", session: session
        )
        context.insert(entry)
        entry.notes = "with the EZ bar"

        try CatalogSync.run(in: context)

        #expect(before.catalogKey == nil)
        #expect(before.name == "Skull Crusher")
        #expect(entry.identity == .own("Skull Crusher".exerciseKey))
        let keys = try context.fetch(FetchDescriptor<ExerciseDefinition>()).compactMap(\.catalogKey)
        #expect(keys.contains("ez-bar-skull-crusher"))
        #expect(keys.contains("dumbbell-skull-crusher"))
    }

    /// A store from before entries carried a key (`SchemaV2`): the entries of
    /// a catalog exercise get it at launch, so history goes by key from then on.
    @MainActor
    @Test func entriesLoggedBeforeTheyCarriedAKeyGetOne() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let definition = ExerciseDefinition.insertPlainSetsAndReps(name: "Dumbbell Curl", orderIndex: 0, muscleGroupNames: ["biceps"], in: context)
        definition.catalogKey = curl.key
        let session = WorkoutSession(name: "Arms")
        context.insert(session)
        let entry = ExerciseEntry(name: "Dumbbell Curl", orderIndex: 0, definitionID: definition.id, effortScale: .levels, session: session)
        context.insert(entry)
        try context.save()

        try CatalogSync.run(catalog: [curl], in: context)
        #expect(entry.catalogKey == curl.key)
        #expect(entry.identity == .catalog(curl.key))
    }

    /// A key the catalog dropped leaves the exercise the user's own, and its
    /// entries with it.
    @MainActor
    @Test func aDroppedKeyLeavesTheEntriesOwnToo() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let definition = ExerciseDefinition.insertPlainSetsAndReps(name: "Dumbbell Curl", orderIndex: 0, in: context)
        definition.catalogKey = curl.key
        let session = WorkoutSession(name: "Arms")
        context.insert(session)
        let entry = ExerciseEntry(name: "Dumbbell Curl", orderIndex: 0, definitionID: definition.id, effortScale: .levels, catalogKey: curl.key, session: session)
        context.insert(entry)
        entry.notes = "seated"

        try CatalogSync.run(catalog: [bench], in: context)
        #expect(definition.catalogKey == nil)
        #expect(entry.catalogKey == nil)
    }

    /// Whether a catalog exercise can be assisted is the catalog's, like its
    /// sides.
    @Test func aCatalogExerciseTakesTheCatalogsAssistance() {
        var dip = CatalogExercise(key: "dip", name: "Dip", muscleGroupNames: ["chest", "triceps"])
        dip.offersAssistance = true
        let stored = catalog(dip)
        #expect(CatalogSync.plan(catalog: [dip], store: [stored]).refreshes == [stored.id: dip])
    }

    @Test func dipsAndPullUpsCanBeAssisted() {
        let offering = Set(Catalog.exercises.filter(\.offersAssistance).map(\.key))
        #expect(offering == ["dip", "pull-up", "chin-up"])
    }

    /// A catalog exercise that is not weight training takes in an own one of
    /// its name only when nothing would tell them apart: category and fields.
    @Test func anOwnExerciseIsTakenInByAHeldOneOnlyWithItsCategoryAndFields() {
        func candidate(category: String, fields: [FieldShape]) -> CatalogCandidate {
            CatalogCandidate(
                id: UUID(), name: "isometric leg extension", catalogKey: nil, muscleGroupNames: [],
                category: category, shape: ExerciseShape(tracksSets: true, fields: Set(fields)), sides: .either
            )
        }
        let weight = FieldShape(labelKey: "weight", type: "weight")
        let holdField = FieldShape(labelKey: "hold", type: "time")

        let same = candidate(category: "Isometrics", fields: [holdField, weight])
        #expect(CatalogSync.plan(catalog: [hold], store: [same]).adoptions == [same.id: hold])

        for other in [
            candidate(category: "Strength", fields: [weight, holdField]),
            candidate(category: "Isometrics", fields: [weight, FieldShape(labelKey: "reps", type: "reps")]),
            candidate(category: "Isometrics", fields: [weight]),
        ] {
            let sync = CatalogSync.plan(catalog: [hold], store: [other])
            #expect(sync.adoptions.isEmpty)
            #expect(sync.inserts == [hold])
        }
    }

    /// Nor does a plain catalog exercise take in an own one filed elsewhere.
    @Test func aPlainCatalogExerciseLeavesAnOwnOneOfAnotherCategory() {
        var mine = own("Barbell Bench Press")
        mine.category = "Isometrics"
        let sync = CatalogSync.plan(catalog: [bench], store: [mine])
        #expect(sync.adoptions.isEmpty)
        #expect(sync.inserts == [bench])
    }

    @MainActor
    @Test func aHeldExerciseArrivesWithItsCategoryAndFields() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CatalogSync.run(catalog: [bench, hold], in: context)

        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>(sortBy: [SortDescriptor(\.orderIndex)]))
        #expect(definitions.map(\.catalogKey) == ["barbell-bench-press", "isometric-leg-extension"])
        let held = try #require(definitions.last)
        #expect(held.category == .isometrics)
        #expect(held.tracksSets)
        #expect(held.sides == .one)
        #expect(held.sortedFields.map(\.key) == ["weight", "f1"])
        #expect(held.sortedFields.map(\.label) == ["Weight", "Hold"])
        #expect(held.sortedFields.map(\.type) == [.weight, .time])
        #expect(definitions.first?.isPlainSetsAndReps == true)
    }

    @MainActor
    @Test func anExerciseLoggedOncePerWorkoutArrivesSo() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let bike = CatalogExercise(
            key: "exercise-bike", name: "Exercise Bike", muscleGroupNames: ["quads"], category: "Cardio",
            fields: [FieldRecord(key: "f1", label: "Duration", type: "time")], tracksSets: false
        )
        try CatalogSync.run(catalog: [bike], in: context)

        let made = try #require(try context.fetch(FetchDescriptor<ExerciseDefinition>()).first)
        #expect(!made.tracksSets)
        #expect(made.category == .cardio)
        #expect(made.sortedFields.map(\.type) == [.time])
    }
}
