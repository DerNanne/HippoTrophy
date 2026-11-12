import Testing
@testable import HippoTrophy

@MainActor
struct ExerciseFilterTests {
    private struct Exercise: ExerciseFilterable, Equatable {
        let name: String
        var muscleGroups: [MuscleGroup] = []
        var categoryName = "Strength"
        var isCatalog = true
    }

    private let incline = Exercise(name: "Incline Bench Press", muscleGroups: [.chest, .shoulders])
    private let bench = Exercise(name: "Barbell Bench Press", muscleGroups: [.chest])
    private let fly = Exercise(name: "cable fly", muscleGroups: [.chest])
    private let squat = Exercise(name: "Back Squat", muscleGroups: [.quads])
    private let run = Exercise(name: "Morning Run", categoryName: "Cardio")
    private let stretch = Exercise(name: "Stretch", categoryName: "")

    private func names(_ filter: ExerciseFilter, _ exercises: [Exercise]) -> [String] {
        filter.apply(to: exercises).map(\.name)
    }

    @Test func withoutAFilterEverythingIsThereAlphabeticallyWhateverTheCase() {
        #expect(names(ExerciseFilter(), [incline, fly, bench]) == ["Barbell Bench Press", "cable fly", "Incline Bench Press"])
    }

    @Test func aSearchFindsPartOfANameWithoutMindingCaseOrSpaces() {
        let filter = ExerciseFilter(query: "  bench ")
        #expect(names(filter, [incline, bench, squat]) == ["Barbell Bench Press", "Incline Bench Press"])
    }

    @Test func anExerciseIsFoundUnderEveryMainMuscle() {
        #expect(names(ExerciseFilter(muscle: .muscle(.chest)), [incline]) == [incline.name])
        #expect(names(ExerciseFilter(muscle: .muscle(.shoulders)), [incline]) == [incline.name])
        #expect(names(ExerciseFilter(muscle: .muscle(.quads)), [incline]).isEmpty)
    }

    @Test func theUnfiledAreAChoiceOfTheirOwn() {
        #expect(names(ExerciseFilter(muscle: .unfiled), [bench, run]) == ["Morning Run"])
    }

    @Test func onlyOwnLeavesTheCatalogOutAndWorksWithTheRest() {
        let mine = Exercise(name: "My Press", muscleGroups: [.chest], isCatalog: false)
        let myRun = Exercise(name: "My Run", muscleGroups: [.quads], categoryName: "Cardio", isCatalog: false)
        #expect(names(ExerciseFilter(onlyOwn: true), [bench, mine, myRun]) == ["My Press", "My Run"])
        #expect(names(ExerciseFilter(categoryID: "cardio", onlyOwn: true), [run, mine, myRun]) == ["My Run"])
        #expect(names(ExerciseFilter(muscle: .muscle(.chest), onlyOwn: true), [bench, mine, myRun]) == ["My Press"])
        #expect(names(ExerciseFilter(query: "run", onlyOwn: true), [run, mine, myRun]) == ["My Run"])
        #expect(ExerciseFilter(onlyOwn: true).isNarrowed)
    }

    @Test func onlyOwnIsOfferedWithOwnExercisesOrWhileItIsOn() {
        let mine = Exercise(name: "My Press", isCatalog: false)
        #expect(ExerciseFilter().offersOnlyOwn(among: [bench, mine]))
        #expect(!ExerciseFilter().offersOnlyOwn(among: [bench]))
        #expect(ExerciseFilter(onlyOwn: true).offersOnlyOwn(among: [bench]))
    }

    @Test func onlyOwnKeepsTheChipsToTheCategoriesOfOwnExercises() {
        let mine = Exercise(name: "My Press", isCatalog: false)
        #expect(ExerciseFilter(onlyOwn: true).categoryOptions(among: [run, mine]) == [.strength])
        #expect(ExerciseFilter(categoryID: "cardio", onlyOwn: true).categoryOptions(among: [run, mine]) == [.strength, .cardio])
    }

    @Test func aCategoryIsMatchedWithoutMindingCase() {
        let lowercase = Exercise(name: "Morning Row", categoryName: "cardio")
        #expect(names(ExerciseFilter(categoryID: "cardio"), [lowercase, bench]) == ["Morning Row"])
        #expect(names(ExerciseFilter(categoryID: "strength"), [lowercase, bench]) == ["Barbell Bench Press"])
    }

    @Test func noCategoryIsACategoryToPick() {
        let filter = ExerciseFilter(categoryID: CategoryFilter.noCategoryID)
        #expect(names(filter, [stretch, bench]) == ["Stretch"])
    }

    @Test func allThreeNarrowTogether() {
        let filter = ExerciseFilter(query: "bench", categoryID: "strength", muscle: .muscle(.shoulders))
        #expect(names(filter, [incline, bench, fly, run]) == ["Incline Bench Press"])
    }

    @Test func aBlankSearchNarrowsNothing() {
        #expect(!ExerciseFilter(query: "   ").isNarrowed)
        #expect(ExerciseFilter(query: "a").isNarrowed)
        #expect(ExerciseFilter(categoryID: "strength").isNarrowed)
        #expect(ExerciseFilter(muscle: .unfiled).isNarrowed)
    }

    @Test func aChipIsOfferedOnlyForACategoryInUse() {
        let options = ExerciseFilter().categoryOptions(among: [bench, run])
        #expect(options.map { CategoryFilter.name(of: $0) } == ["Strength", "Cardio"])
    }

    @Test func exercisesWithoutACategoryGetAChipLast() {
        let options = ExerciseFilter().categoryOptions(among: [stretch, bench])
        #expect(options.map { CategoryFilter.name(of: $0) } == ["Strength", "No Category"])
    }

    @Test func thePickedCategoryKeepsItsChipWithNothingLeftInIt() {
        let options = ExerciseFilter(categoryID: "cardio").categoryOptions(among: [bench])
        #expect(options.map { CategoryFilter.name(of: $0) } == ["Strength", "Cardio"])
    }

    @Test func aSearchNamesANewExerciseOnlyWhileTheNameIsFree() {
        #expect(ExerciseFilter(query: " Bench ").newName(among: [incline]) == "Bench")
        #expect(ExerciseFilter(query: "back squat").newName(among: [squat]) == nil)
        #expect(ExerciseFilter(query: "  ").newName(among: [squat]) == nil)
    }

    @Test func aNameIsTakenEvenWhenTheFilterHidesItsExercise() {
        let filter = ExerciseFilter(query: "Back Squat", muscle: .muscle(.chest))
        #expect(names(filter, [squat]).isEmpty)
        #expect(filter.newName(among: [squat]) == nil)
    }

    @Test func aMuscleChoiceSurvivesStorage() {
        for choice in MuscleGroup.allCases.map(MuscleFilter.muscle) + [.unfiled] {
            #expect(MuscleFilter(stored: choice.stored) == choice)
        }
        #expect(MuscleFilter(stored: "") == nil)
        #expect(MuscleFilter(stored: "wings") == nil)
    }
}
