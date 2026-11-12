import CoreGraphics
import Testing
@testable import HippoTrophy

struct PageSwipeTests {
    private func swipe(at index: Int, of count: Int = 3) -> PageSwipe {
        PageSwipe(index: index, count: count, pageWidth: 300)
    }

    @Test func theRowFollowsTheFingerTowardsAPageThatExists() {
        #expect(swipe(at: 1).offset(for: -120) == -120)
        #expect(swipe(at: 1).offset(for: 120) == 120)
        #expect(swipe(at: 0).offset(for: -120) == -120)
        #expect(swipe(at: 2).offset(for: 120) == 120)
    }

    @Test func pastTheFirstOrLastPageItOnlyGivesALittle() {
        #expect(swipe(at: 0).offset(for: 120) == 40)
        #expect(swipe(at: 2).offset(for: -120) == -40)
        #expect(swipe(at: 0, of: 1).offset(for: -120) == -40)
    }

    @Test func pastHalfAPageItTurns() {
        #expect(swipe(at: 1).target(translation: -151, velocity: 0) == 2)
        #expect(swipe(at: 1).target(translation: 151, velocity: 0) == 0)
    }

    @Test func shortOfHalfAPageItSpringsBack() {
        #expect(swipe(at: 1).target(translation: -150, velocity: -100) == 1)
        #expect(swipe(at: 1).target(translation: 80, velocity: 0) == 1)
    }

    @Test func aQuickFlickTurnsHoweverShort() {
        #expect(swipe(at: 1).target(translation: -40, velocity: -800) == 2)
        #expect(swipe(at: 1).target(translation: 40, velocity: 800) == 0)
    }

    @Test func aFlickBackAfterALongPullCancelsIt() {
        #expect(swipe(at: 1).target(translation: -200, velocity: 600) == 1)
    }

    @Test func aLongFlickStillTurnsOnlyOnePage() {
        #expect(swipe(at: 0).target(translation: -280, velocity: -5000) == 1)
    }

    @Test func thereIsNothingToTurnToPastTheEnds() {
        #expect(swipe(at: 0).target(translation: 200, velocity: 800) == 0)
        #expect(swipe(at: 2).target(translation: -200, velocity: -800) == 2)
    }
}
