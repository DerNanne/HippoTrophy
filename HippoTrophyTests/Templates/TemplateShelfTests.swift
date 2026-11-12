import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The templates on the start screen: which are there, in what order, and
/// where a new, duplicated, dragged or archived one ends up.
@MainActor
struct TemplateShelfTests {
    private func template(_ name: String, order: Int, archived: Bool = false) -> WorkoutSession {
        let template = WorkoutSession(name: name)
        template.isTemplate = true
        template.templateOrder = order
        template.isArchived = archived
        return template
    }

    private func names(_ sessions: [WorkoutSession]) -> [String] {
        TemplateShelf(sessions).templates.map(\.name)
    }

    @Test func holdsTemplatesInTheirOrderAndNoWorkouts() {
        let workout = WorkoutSession(name: "Monday")
        let sessions = [template("B", order: 1), workout, template("A", order: 0), template("Old", order: 0, archived: true)]
        let shelf = TemplateShelf(sessions)
        #expect(shelf.templates.map(\.name) == ["A", "B"])
        #expect(shelf.archived.map(\.name) == ["Old"])
    }

    @Test func aNewTemplateStandsFirst() {
        let sessions = [template("A", order: 0), template("B", order: 1)]
        let new = template("New", order: 0)
        TemplateShelf(sessions).placeFirst(new)
        #expect(names(sessions + [new]) == ["New", "A", "B"])
        #expect((sessions + [new]).map(\.templateOrder).sorted() == [0, 1, 2])
    }

    @Test func aDuplicateStandsBehindItsOriginal() {
        let a = template("A", order: 0)
        let sessions = [a, template("B", order: 1)]
        let copy = template("A Copy", order: 0)
        TemplateShelf(sessions).place(copy, after: a)
        #expect(names(sessions + [copy]) == ["A", "A Copy", "B"])
    }

    @Test(arguments: [
        ("A", "C", ["B", "C", "A"]),
        ("C", "A", ["C", "A", "B"]),
        ("B", "B", ["A", "B", "C"])
    ])
    func aDraggedTemplateTakesThePlaceItIsDroppedOn(dragged: String, target: String, expected: [String]) {
        let sessions = [template("A", order: 0), template("B", order: 1), template("C", order: 2)]
        let byName = Dictionary(uniqueKeysWithValues: sessions.map { ($0.name, $0) })
        TemplateShelf(sessions).move(byName[dragged]!, to: byName[target]!)
        #expect(names(sessions) == expected)
    }

    @Test func anArchivedTemplateLeavesTheShelfAndComesBackFirst() {
        let b = template("B", order: 1)
        let sessions = [template("A", order: 0), b, template("C", order: 2)]
        TemplateShelf(sessions).archive(b)
        #expect(names(sessions) == ["A", "C"])
        #expect(TemplateShelf(sessions).archived.map(\.name) == ["B"])

        TemplateShelf(sessions).placeFirst(b)
        #expect(names(sessions) == ["B", "A", "C"])
        #expect(TemplateShelf(sessions).archived.isEmpty)
    }

    /// A template's sets are planned, not done: all of them are counted,
    /// empty ones too.
    @Test func aTemplatesSummaryCountsEverySetItPlans() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let template = template("Push", order: 0)
        context.insert(template)
        let bench = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: template)
        context.insert(bench)
        for number in 1...3 { context.insert(SetEntry(setNumber: number, exercise: bench)) }
        #expect(TemplateShelf.summary(of: template) == "1 exercise • 3 sets")
    }

    @Test func aTemplateOfAnUnnamedWorkoutAsksToBeRenamed() {
        #expect(TemplateShelf.name(forTemplateOf: "  Push A ") == "Push A")
        #expect(TemplateShelf.name(forTemplateOf: " ") == "New Template")
        #expect(TemplateShelf.duplicateName(of: "Push A") == "Push A Copy")
    }

    /// A template is the workout's exercises, sets and values; a workout
    /// started from it is a workout again, and neither shares anything with
    /// the other.
    @Test func aTemplateCopiesTheWorkoutAndStartsWorkoutsOfItsOwn() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let workout = WorkoutSession(name: "Push", date: .distantPast)
        context.insert(workout)
        let bench = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .levels, session: workout)
        context.insert(bench)
        let set = SetEntry(setNumber: 1, exercise: bench)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "weight", label: "Weight", typeRawValue: "weight", orderIndex: 0, numberValue: 60, set: set))

        let template = workout.templateCopy(named: "Push Day")
        context.insert(template)
        let started = template.copy(dated: .now)
        context.insert(started)
        try context.save()

        #expect(template.isTemplate)
        #expect(template.name == "Push Day")
        #expect(template.exercises.first?.sets.first?.weightKg == 60)
        #expect(template.exercises.first?.isInTemplate == true)
        #expect(!started.isTemplate)
        #expect(started.name == "Push Day")
        #expect(started.exercises.first?.isInTemplate == false)
        #expect(Set([workout.id, template.id, started.id]).count == 3)
    }
}

/// What Save offers for a new workout and the history's menu does for any:
/// a template of the workout, under its name, first on the shelf.
@MainActor
struct KeepTemplateTests {
    @Test func aWorkoutKeptAsTemplateStandsFirstAndStaysAWorkout() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let older = WorkoutSession(name: "Pull")
        older.isTemplate = true
        context.insert(older)
        let workout = WorkoutSession(name: "Push")
        context.insert(workout)
        context.insert(ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: workout))

        let template = TemplateShelf.keepTemplate(of: workout, in: context)
        try context.save()

        let templates = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))
        #expect(TemplateShelf(templates).templates.map(\.name) == ["Push", "Pull"])
        #expect(template.exercises.map(\.name) == ["Bench"])
        #expect(!workout.isTemplate)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.trained)) == 1)
    }

    @Test func aWorkoutWithNothingInItHasNothingToKeepAsATemplate() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let workout = WorkoutSession(name: "Push")
        context.insert(workout)
        #expect(!workout.canBeKeptAsTemplate)

        // An exercise added and left blank, with or without an empty set.
        let blank = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: workout)
        context.insert(blank)
        #expect(!workout.canBeKeptAsTemplate)
        context.insert(SetEntry(setNumber: 1, exercise: blank))
        #expect(!workout.canBeKeptAsTemplate)
    }

    @Test func aPlannedSetOrAnInstructionIsSomethingToKeepAsATemplate() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let planned = WorkoutSession(name: "Plan")
        context.insert(planned)
        let bench = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: planned)
        context.insert(bench)
        let set = SetEntry(setNumber: 1, isDone: false, exercise: bench)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "weight", label: "Weight", typeRawValue: FieldType.weight.rawValue, orderIndex: 0, textValue: nil, numberValue: 60, set: set))
        #expect(planned.canBeKeptAsTemplate)

        let instructed = WorkoutSession(name: "Instructed")
        context.insert(instructed)
        let warmUp = ExerciseEntry(name: "Warm-up", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: instructed)
        context.insert(warmUp)
        warmUp.instructions = "10 minutes on the rower"
        #expect(instructed.canBeKeptAsTemplate)
    }

    /// A note says what happened in its workout and stays there, so a
    /// template would take nothing from a workout that has only notes.
    @Test func aNoteAloneIsNothingToKeepAsATemplate() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let noted = WorkoutSession(name: "Note")
        context.insert(noted)
        let warmUp = ExerciseEntry(name: "Warm-up", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: noted)
        context.insert(warmUp)
        warmUp.notes = "Skipped, knee"
        #expect(!noted.canBeKeptAsTemplate)
    }

    @Test func anUnnamedWorkoutsTemplateAsksToBeRenamed() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let workout = WorkoutSession()
        context.insert(workout)
        #expect(TemplateShelf.keepTemplate(of: workout, in: context).name == "New Template")
    }
}

/// A dragged card moves a place once it is half a place off its own, and
/// not past either end of the row.
struct TemplateShelfStepTests {
    @Test(arguments: [
        (40.0, 1, 3, 0),
        (60.0, 1, 3, 1),
        (-60.0, 1, 3, -1),
        (60.0, 2, 3, 0),
        (-60.0, 0, 3, 0),
        (500.0, 0, 1, 0)
    ])
    func movesHalfAPlaceOn(offset: Double, index: Int, count: Int, expected: Int) {
        #expect(TemplateShelf.step(offset: offset, stride: 100, index: index, count: count) == expected)
    }
}
