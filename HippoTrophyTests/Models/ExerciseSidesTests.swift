import Testing
@testable import HippoTrophy

/// How an exercise is trained decides which modes its entries offer and
/// which one a new entry starts in.
struct ExerciseSidesTests {
    @Test func eachWayOffersTheModesThatFit() {
        #expect(ExerciseSides.both.modes == [.bilateral])
        #expect(ExerciseSides.either.modes == [.bilateral, .oneSided, .perSide])
        #expect(ExerciseSides.one.modes == [.oneSided, .perSide])
    }

    /// A two-sided exercise has nothing to choose, so no menu.
    @Test func aTwoSidedEntryHasNoMenu() {
        #expect(ExerciseSides.both.choices(current: .bilateral).isEmpty)
    }

    @Test func aOneSidedEntryChoosesOnlyHowItIsLogged() {
        #expect(ExerciseSides.one.choices(current: .oneSided) == [.oneSided, .perSide])
        #expect(ExerciseSides.either.choices(current: .bilateral) == [.bilateral, .oneSided, .perSide])
    }

    /// What is written down stays reachable: an entry logged left and right
    /// under an exercise since made two-sided keeps its menu, with the way
    /// back.
    @Test func anEntryThatNoLongerFitsKeepsItsModeInReach() {
        #expect(ExerciseSides.both.choices(current: .perSide) == [.bilateral, .perSide])
        #expect(ExerciseSides.one.choices(current: .bilateral) == [.bilateral, .oneSided, .perSide])
    }

    @Test func aNewEntryStartsTheWayTheLastOneWasLogged() {
        #expect(ExerciseSides.one.startMode(lastLogged: .perSide, inSuperset: false) == .perSide)
        #expect(ExerciseSides.either.startMode(lastLogged: .oneSided, inSuperset: false) == .oneSided)
    }

    @Test func withoutALastOneItStartsWithTheFirstThatFits() {
        #expect(ExerciseSides.both.startMode(lastLogged: nil, inSuperset: false) == .bilateral)
        #expect(ExerciseSides.either.startMode(lastLogged: nil, inSuperset: false) == .bilateral)
        #expect(ExerciseSides.one.startMode(lastLogged: nil, inSuperset: false) == .oneSided)
    }

    /// A last mode that no longer fits is not carried over.
    @Test func aLastModeThatNoLongerFitsIsDropped() {
        #expect(ExerciseSides.one.startMode(lastLogged: .bilateral, inSuperset: false) == .oneSided)
        #expect(ExerciseSides.both.startMode(lastLogged: .perSide, inSuperset: false) == .bilateral)
    }

    /// Left/right does not interleave with a partner's sets; a one-sided
    /// exercise stays one-sided.
    @Test func inASupersetLeftAndRightGiveWay() {
        #expect(ExerciseSides.one.startMode(lastLogged: .perSide, inSuperset: true) == .oneSided)
        #expect(ExerciseSides.either.startMode(lastLogged: .perSide, inSuperset: true) == .bilateral)
    }

    @Test func onlyTwoSidedAndOneSidedDoNotMerge() {
        #expect(!ExerciseSides.both.canMerge(into: .one))
        #expect(!ExerciseSides.one.canMerge(into: .both))
        for sides in ExerciseSides.allCases {
            #expect(sides.canMerge(into: sides))
            #expect(sides.canMerge(into: .either))
            #expect(ExerciseSides.either.canMerge(into: sides))
        }
    }
}
