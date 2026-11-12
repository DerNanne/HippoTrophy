import Foundation
import Testing
@testable import HippoTrophy

/// Storage is kilograms everywhere; pounds exist only at the edge. What matters
/// is that the edge is lossless enough that showing a weight never rewrites it.
struct WeightUnitTests {
    @Test func kilogramsPassThroughUntouched() {
        #expect(WeightUnit.kilograms.value(fromKilograms: 60) == 60)
        #expect(WeightUnit.kilograms.kilograms(from: 60) == 60)
    }

    @Test func poundsSurviveTheRoundTrip() {
        for pounds in [45.0, 135.0, 225.0, 1.5, 0.0] {
            let stored = WeightUnit.pounds.kilograms(from: pounds)
            let shown = WeightUnit.pounds.value(fromKilograms: stored)
            #expect(abs(shown - pounds) < 0.000_001)
        }
    }

    @Test func kilogramsSurviveTheRoundTripThroughPounds() {
        for kilograms in [20.0, 60.0, 102.5] {
            let shown = WeightUnit.pounds.value(fromKilograms: kilograms)
            let back = WeightUnit.pounds.kilograms(from: shown)
            #expect(abs(back - kilograms) < 0.000_001)
        }
    }

    /// Half a display step, expressed in kilograms — the slack that keeps a
    /// weight merely rendered in the other unit from counting as an edit.
    @Test func toleranceIsHalfADisplayStep() {
        #expect(abs(WeightUnit.kilograms.storageTolerance - 0.005) < 0.000_001)
        #expect(abs(WeightUnit.pounds.storageTolerance - 0.005 * 0.453_592_37) < 0.000_001)
    }

    /// The case the tolerance was written for: 60 kg shown as 132.28 lb and
    /// typed back must not write 60.001 kg into the set.
    @Test func showingAWeightInPoundsIsNotAnEdit() {
        let stored = 60.0
        let shown = (WeightUnit.pounds.value(fromKilograms: stored) * 100).rounded() / 100
        let typedBack = WeightUnit.pounds.kilograms(from: shown)
        #expect(typedBack != stored)
        #expect(abs(typedBack - stored) <= WeightUnit.pounds.storageTolerance)
    }

    // MARK: - Format

    private let german = Locale(identifier: "de_DE")
    private let english = Locale(identifier: "en_US")

    /// Weights read the way they were entered: no fraction a whole number never
    /// had, and none of the fraction one did have rounded away.
    @Test func writesOnlyTheFractionThereIs() {
        #expect(WeightUnit.kilograms.formatted(kilograms: 60, locale: english) == "60 kg")
        #expect(WeightUnit.kilograms.formatted(kilograms: 62.5, locale: english) == "62.5 kg")
        #expect(WeightUnit.kilograms.formatted(kilograms: 11.25, locale: english) == "11.25 kg")
        #expect(WeightUnit.kilograms.formatted(kilograms: 0, locale: english) == "0 kg")
    }

    /// The device's separator, like every other number in the app — not a dot
    /// beside a "Distance 5,2".
    @Test func takesTheDecimalSeparatorOfTheDevice() {
        #expect(WeightUnit.kilograms.formatted(kilograms: 11.25, locale: german) == "11,25 kg")
        #expect(WeightUnit.kilograms.number(fromKilograms: 62.5, locale: german) == "62,5")
    }

    /// The editor shows this text and reads it back; a group separator would
    /// turn 1,000 lb into one.
    @Test func neverGroupsThousands() {
        let thousandPounds = WeightUnit.pounds.kilograms(from: 1000)
        #expect(WeightUnit.pounds.number(fromKilograms: thousandPounds, locale: english) == "1000")
        #expect(WeightUnit.kilograms.number(fromKilograms: 1250, locale: german) == "1250")
    }

    /// Stored in kilograms, a pound weight is no round number — 225 lb is
    /// 102.058… kg — and still comes back as what was typed.
    @Test func poundsComeBackAsTyped() {
        for pounds in [45.0, 135.0, 225.0, 2.5, 1.25] {
            let stored = WeightUnit.pounds.kilograms(from: pounds)
            let shown = WeightUnit.pounds.number(fromKilograms: stored, locale: english)
            #expect(shown == pounds.formatted(.number.grouping(.never).locale(english)))
        }
        #expect(WeightUnit.pounds.formatted(kilograms: 60, locale: english) == "132.28 lb")
    }
}
