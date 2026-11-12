import Foundation

/// What an exercise trains: the muscles it is mainly for, and the ones it
/// works along the way.
///
/// A set counts in full for a main muscle and half for one along the way —
/// a set of squats is a set for Quads and Glutes, half of one for
/// Adductors. Half is a rule of thumb, not a measurement; it keeps a helping
/// muscle from looking as trained as the one the exercise is for, without
/// pretending to know the share.
nonisolated struct MuscleTargets: Equatable {
    static let secondaryShare = 0.5

    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]

    init(primary: [MuscleGroup], secondary: [MuscleGroup]) {
        self.primary = primary
        let main = Set(primary)
        self.secondary = secondary.filter { !main.contains($0) }
    }

    var isEmpty: Bool { primary.isEmpty && secondary.isEmpty }

    var all: [MuscleGroup] { primary + secondary }

    func contains(_ muscle: MuscleGroup) -> Bool {
        share(for: muscle) > 0
    }

    /// How much one set counts for `muscle`: 1, a half, or nothing.
    func share(for muscle: MuscleGroup) -> Double {
        if primary.contains(muscle) { return 1 }
        if secondary.contains(muscle) { return Self.secondaryShare }
        return 0
    }
}

/// The sets a muscle got, kept apart by how they count: from exercises it is
/// a main muscle of, and from those it only helps. Shown apart — a set is
/// never split on screen — and weighed only for the heat map's colour.
nonisolated struct MuscleSets: Equatable, ExpressibleByIntegerLiteral {
    var main: Int
    var secondary: Int

    init(main: Int, secondary: Int = 0) {
        self.main = main
        self.secondary = secondary
    }

    /// Main sets only — what a count was before secondary muscles.
    init(integerLiteral value: Int) {
        self.init(main: value)
    }

    static let zero = MuscleSets(main: 0)

    var isEmpty: Bool { main == 0 && secondary == 0 }

    /// Main sets in full, secondary ones at `MuscleTargets.secondaryShare`.
    var weighted: Double {
        Double(main) + Double(secondary) * MuscleTargets.secondaryShare
    }

    static func + (lhs: MuscleSets, rhs: MuscleSets) -> MuscleSets {
        MuscleSets(main: lhs.main + rhs.main, secondary: lhs.secondary + rhs.secondary)
    }
}
