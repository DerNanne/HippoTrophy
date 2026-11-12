import Foundation

/// The one rule for shading a count against the highest one beside it, used
/// by the activity grid and the muscle heat map alike: zero stays empty, and
/// everything else lands in one of four quartiles of the highest count, so the
/// scale fits the person rather than a fixed number.
nonisolated enum QuartileLevel {
    static let highest = 4

    static func level(_ count: Int, highestCount: Int) -> Int {
        level(Double(count), highestCount: Double(highestCount))
    }

    static func level(_ count: Double, highestCount: Double) -> Int {
        guard count > 0 else { return 0 }
        guard highestCount > 1 else { return highest }
        let ratio = count / highestCount
        switch ratio {
        case ..<0.25: return 1
        case ..<0.5: return 2
        case ..<0.75: return 3
        default: return 4
        }
    }
}
