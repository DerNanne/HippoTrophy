import Testing
@testable import HippoTrophy

struct HeatScaleTests {
    private let green = HeatScale.RGB(0x34C759)
    private let yellow = HeatScale.RGB(0xFFCC00)
    private let orange = HeatScale.RGB(0xFF9500)
    private let red = HeatScale.RGB(0xFF3B30)
    private let purple = HeatScale.RGB(0xAF52DE)

    private func close(_ a: HeatScale.RGB?, _ b: HeatScale.RGB) -> Bool {
        guard let a else { return false }
        return abs(a.red - b.red) < 1e-9 && abs(a.green - b.green) < 1e-9 && abs(a.blue - b.blue) < 1e-9
    }

    @Test func untrainedHasNoColourOfItsOwn() {
        #expect(HeatScale.color(forShare: 0) == nil)
    }

    @Test func theScaleRunsGreenYellowOrangeRedPurple() {
        #expect(close(HeatScale.color(forShare: 0.25), yellow))
        #expect(close(HeatScale.color(forShare: 0.5), orange))
        #expect(close(HeatScale.color(forShare: 0.75), red))
        #expect(close(HeatScale.color(forShare: 1), purple))
    }

    @Test func theLeastTrainedIsAlmostPureGreen() {
        let color = HeatScale.color(forShare: 0.001)
        #expect(close(color, green.mixed(with: yellow, by: 0.004)))
    }

    @Test func betweenTwoColoursItMixesThem() {
        #expect(close(HeatScale.color(forShare: 0.375), yellow.mixed(with: orange, by: 0.5)))
        #expect(close(HeatScale.color(forShare: 0.125), green.mixed(with: yellow, by: 0.5)))
        #expect(close(HeatScale.color(forShare: 0.875), red.mixed(with: purple, by: 0.5)))
    }

    /// The point of the scale: four steps put a quarter and a half of the
    /// most trained in the same yellow.
    @Test func sharesInTheSameQuarterGetDifferentColours() {
        #expect(QuartileLevel.level(26, highestCount: 100) == QuartileLevel.level(49, highestCount: 100))
        #expect(HeatScale.color(forShare: 0.26) != HeatScale.color(forShare: 0.49))
    }

    @Test func moreThanTheMostStaysPurple() {
        #expect(close(HeatScale.color(forShare: 1.5), purple))
    }
}
