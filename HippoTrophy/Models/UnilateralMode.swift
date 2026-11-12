import Foundation

/// How an exercise was trained, and therefore how its sets are logged. Stored
/// as two booleans on the entry; `unilateralMode` is the only way in or out.
enum UnilateralMode: String, CaseIterable {
    /// Both sides at once: one weight, one set list.
    case bilateral
    /// One side at a time with the same weight on both, logged once. The sets
    /// look like a bilateral log; the mode is what says the number is per side.
    case oneSided
    /// One side at a time, sides logged apart, for when they differ.
    case perSide

    /// The words of `ExerciseSides`, so an exercise and its entries speak
    /// alike. Both unilateral titles deliberately start the same way: the two
    /// modes mean the same training and differ only in how it is written down.
    var title: String {
        switch self {
        case .bilateral: return "Bilateral"
        case .oneSided: return "Unilateral, Same Weight"
        case .perSide: return "Unilateral, Log L/R"
        }
    }

    /// The short form for the capsule next to an exercise name.
    var shortTitle: String {
        switch self {
        case .bilateral: return "Bilateral"
        case .oneSided: return "Unilateral"
        case .perSide: return "L/R"
        }
    }

    /// Whether a logged weight is what a single side moved. Both one-sided modes
    /// log per side already; a bilateral weight is shared between the two.
    var logsPerSideWeight: Bool { self != .bilateral }
}
