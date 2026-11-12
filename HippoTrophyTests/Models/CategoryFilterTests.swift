import Foundation
import Testing
@testable import HippoTrophy

@MainActor
struct CategoryFilterTests {
    private let options = CategoryFilter.options
    private let strength = ExerciseCategory.strength
    private let cardio = ExerciseCategory.cardio
    private let mobility = ExerciseCategory.mobility
    private let isometrics = ExerciseCategory.isometrics

    @Test func strengthAloneIsTheStandard() {
        let filter = CategoryFilter(stored: "", options: options)
        #expect(filter == .standard)
        #expect(filter.includes(categoryName: "Strength"))
        #expect(!filter.includes(categoryName: "Cardio"))
        #expect(!filter.includes(categoryName: ""))
        #expect(!filter.includes(categoryName: nil))
    }

    @Test func theMenuOffersTheCategoriesThenNoCategory() {
        #expect(options.map(CategoryFilter.name(of:)) == ["Strength", "Cardio", "Mobility", "Isometrics", "No Category"])
    }

    @Test func namesMatchWhateverTheCase() {
        var filter = CategoryFilter.standard
        filter.toggle(mobility)
        #expect(filter.includes(categoryName: " mobility"))
        #expect(filter.includes(categoryName: "STRENGTH"))
    }

    @Test func aNameTheAppDoesNotKnowIsNoCategory() {
        #expect(ExerciseCategory.resolve("Yoga") == nil)
        #expect(!CategoryFilter.standard.includes(categoryName: "Yoga"))
        var filter = CategoryFilter.standard
        filter.toggle(nil)
        #expect(filter.includes(categoryName: "Yoga"))
    }

    @Test func noCategoryCountsBlankAndDeletedExercises() {
        var filter = CategoryFilter.standard
        filter.toggle(nil)
        #expect(filter.includes(categoryName: ""))
        #expect(filter.includes(categoryName: nil))
    }

    @Test func theLastPickedCategoryCannotBeDropped() {
        var filter = CategoryFilter.standard
        filter.toggle(strength)
        #expect(filter == .standard)
        filter.toggle(cardio)
        filter.toggle(strength)
        #expect(filter.contains(cardio))
        #expect(!filter.contains(strength))
    }

    @Test func aChoiceSurvivesStorage() {
        var filter = CategoryFilter.standard
        filter.toggle(cardio)
        filter.toggle(nil)
        #expect(CategoryFilter(stored: filter.stored, options: options) == filter)
    }

    @Test func aCategoryNoLongerOfferedDropsOut() {
        // A category of the user's own, stored before they went.
        #expect(CategoryFilter(stored: #"["strength","yoga"]"#, options: options) == .standard)
        #expect(CategoryFilter(stored: #"["yoga"]"#, options: options) == .standard)
    }

    @Test func somethingUnreadableInStorageIsTheStandard() {
        #expect(CategoryFilter(stored: "Strength", options: options) == .standard)
    }

    @Test func theHeadingNamesOneByOneOnlyWhatItSpellsOut() {
        var filter = CategoryFilter.standard
        #expect(filter.named(options: options) == [strength])
        filter.toggle(cardio)
        #expect(filter.named(options: options) == [strength, cardio])
        filter.toggle(nil)
        #expect(filter.named(options: options) == nil)

        let twoOptions = CategoryFilter.options.filter { $0 == strength || $0 == nil }
        var both = CategoryFilter.standard
        both.toggle(nil)
        #expect(both.named(options: twoOptions) == nil)
        #expect(both.label(options: twoOptions) == "All Categories")
    }

    @Test func theLabelNamesUpToTwoThenCountsThenSaysAll() {
        var filter = CategoryFilter.standard
        #expect(filter.label(options: options) == "Strength")
        filter.toggle(cardio)
        #expect(filter.label(options: options) == "Strength, Cardio")
        filter.toggle(nil)
        #expect(filter.label(options: options) == "3 Categories")
        filter.toggle(mobility)
        #expect(filter.label(options: options) == "4 Categories")
        filter.toggle(isometrics)
        #expect(filter.label(options: options) == "All Categories")
    }
}
