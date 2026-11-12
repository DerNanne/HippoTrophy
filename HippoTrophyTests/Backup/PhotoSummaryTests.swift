import Foundation
import Testing
@testable import HippoTrophy

struct PhotoSummaryTests {
    /// With a decimal comma, "2, 1,3 MB" read as one number; the dot keeps
    /// the count apart.
    @Test func theCountStandsApartFromASizeWithADecimalComma() {
        #expect(PhotoSummary.text(sizes: [800_000, 500_000], locale: Locale(identifier: "de_DE")) == "2 · 1,3 MB")
    }

    @Test func aDecimalPointReadsTheSame() {
        #expect(PhotoSummary.text(sizes: [800_000, 500_000], locale: Locale(identifier: "en_US")) == "2 · 1.3 MB")
    }

    @Test func oneSmallPhoto() {
        #expect(PhotoSummary.text(sizes: [442_000], locale: Locale(identifier: "en_US")) == "1 · 442 kB")
    }
}
