import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

@MainActor
struct ActivityGraphsTests {
    private let options = CategoryFilter.options
    private let strength = ExerciseCategory.strength
    private let cardio = ExerciseCategory.cardio
    private let mobility = ExerciseCategory.mobility

    private func names(_ graphs: ActivityGraphs) -> [String] {
        graphs.categories(options: options).map(CategoryFilter.name(of:))
    }

    @Test func strengthThenCardioIsTheStandard() {
        let graphs = ActivityGraphs(stored: "", options: options)
        #expect(graphs == .standard)
        #expect(graphs.isStandard)
        #expect(names(graphs) == ["Strength", "Cardio"])
    }

    @Test func theOrderIsKeptThroughStorage() {
        let graphs = ActivityGraphs(ids: [mobility.id, "", strength.id])
        let read = ActivityGraphs(stored: graphs.stored, options: options)
        #expect(read == graphs)
        #expect(names(read) == ["Mobility", "No Category", "Strength"])
    }

    @Test func aCategoryNoLongerOnOfferAndASecondGraphOfOneDropOut() {
        let stored = ActivityGraphs(ids: ["pilates", cardio.id, cardio.id, mobility.id]).stored
        #expect(names(ActivityGraphs(stored: stored, options: options)) == ["Cardio", "Mobility"])
    }

    @Test func withNothingLeftTheStandardComesBack() {
        let stored = ActivityGraphs(ids: ["pilates"]).stored
        #expect(ActivityGraphs(stored: stored, options: options) == .standard)
        #expect(ActivityGraphs(stored: "not json", options: options) == .standard)
    }

    @Test func aGraphIsAddedAfterTheShownOneAndOnlyOnce() {
        var graphs = ActivityGraphs.standard
        #expect(graphs.add(mobility, after: 0) == 1)
        #expect(names(graphs) == ["Strength", "Mobility", "Cardio"])
        #expect(graphs.add(cardio, after: 0) == nil)
        #expect(names(graphs) == ["Strength", "Mobility", "Cardio"])
    }

    @Test func onlyCategoriesWithoutAGraphAreOffered() {
        let graphs = ActivityGraphs.standard
        #expect(graphs.unshown(options: options).map(CategoryFilter.name(of:)) == ["Mobility", "Isometrics", "No Category"])
        #expect(graphs.choices(at: 1, options: options).map(CategoryFilter.name(of:)) == ["Cardio", "Mobility", "Isometrics", "No Category"])
    }

    @Test func aGraphCannotBeSwitchedToACategoryAnotherShows() {
        var graphs = ActivityGraphs.standard
        graphs.replace(at: 1, with: strength)
        #expect(names(graphs) == ["Strength", "Cardio"])
        graphs.replace(at: 1, with: nil)
        #expect(names(graphs) == ["Strength", "No Category"])
    }

    @Test func theLastGraphCannotBeRemoved() {
        var graphs = ActivityGraphs.standard
        graphs.remove(at: 0)
        #expect(names(graphs) == ["Cardio"])
        graphs.remove(at: 0)
        #expect(names(graphs) == ["Cardio"])
    }

    @Test func aGraphMovesOnePlaceAndStopsAtTheEnds() {
        var graphs = ActivityGraphs.standard
        #expect(graphs.move(at: 0, by: -1) == 0)
        #expect(graphs.move(at: 0, by: 1) == 1)
        #expect(names(graphs) == ["Cardio", "Strength"])
        #expect(!graphs.isStandard)
        #expect(graphs.move(at: 1, by: 1) == 1)
    }

    // MARK: - What a workout is worth to one graph

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func definition(_ name: String, category: String, in context: ModelContext) {
        context.insert(ExerciseDefinition(name: name, orderIndex: 0, categoryName: category, muscleGroupNames: []))
    }

    private func entry(_ name: String, sets: Int, in session: WorkoutSession, context: ModelContext) {
        let entry = ExerciseEntry(name: name, notes: "", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
        context.insert(entry)
        for number in 1...sets {
            let set = SetEntry(setNumber: number, exercise: entry)
            context.insert(set)
            context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 0, numberValue: 8, set: set))
        }
    }

    @Test func aWorkoutCountsOnlyTheSetsOfTheGraphsCategory() throws {
        let context = try context()
        definition("Squat", category: "Strength", in: context)
        definition("Rowing", category: "cardio", in: context)
        definition("Plank", category: "", in: context)
        let mixed = WorkoutSession(date: Date(timeIntervalSinceReferenceDate: 0))
        let liftOnly = WorkoutSession(date: Date(timeIntervalSinceReferenceDate: 86_400))
        context.insert(mixed)
        context.insert(liftOnly)
        entry("squat", sets: 3, in: mixed, context: context)
        entry("Rowing", sets: 1, in: mixed, context: context)
        entry("Plank", sets: 2, in: mixed, context: context)
        entry("Gone Exercise", sets: 4, in: mixed, context: context)
        entry("Squat", sets: 5, in: liftOnly, context: context)
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let sessions = [mixed, liftOnly]

        let strengthDays = ActivityGrid.activity(of: sessions, in: strength, definitions: definitions)
        #expect(strengthDays.map(\.count) == [3, 5])

        // The lift-only workout is not a day of zero cardio; it is left out.
        let cardioDays = ActivityGrid.activity(of: sessions, in: cardio, definitions: definitions)
        #expect(cardioDays.map(\.count) == [1])
        #expect(cardioDays.map(\.date) == [mixed.date])

        // A blank category and an exercise that is gone both count as none.
        let unfiled = ActivityGrid.activity(of: sessions, in: nil, definitions: definitions)
        #expect(unfiled.map(\.count) == [6])
    }
}
