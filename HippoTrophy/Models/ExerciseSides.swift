import Foundation

/// How an exercise is trained: bilateral, both sides at once, or unilateral,
/// one side at a time. A property of the exercise, not of a workout — how one
/// workout's sets were *logged* is the entry's `UnilateralMode`, and this
/// decides which of those modes make sense at all.
///
/// The unilateral form of a bilateral exercise is an exercise of its own,
/// because the two are not comparable in weight (Leg Press and Leg Press
/// (Unilateral)). Training one side only, after an injury say, is a
/// unilateral exercise logged left and right with one side left empty.
nonisolated enum ExerciseSides: String, CaseIterable, Codable {
    /// Both sides at once. Logged as it is; nothing to choose. Where a new
    /// exercise starts.
    case both
    /// Not decided yet: an own exercise from before there were only two ways,
    /// until `SidesAssistant` settles it. Offers every mode meanwhile, as it
    /// always did. Never chosen, never in the catalog.
    case either
    /// One side at a time, logged with the same weight for both or each side
    /// on its own.
    case one

    /// The two an exercise can be.
    static let choosable: [ExerciseSides] = [.both, .one]

    var title: String {
        switch self {
        case .both: return "Bilateral"
        case .either: return "Undecided"
        case .one: return "Unilateral"
        }
    }

    /// The same in plain words, for someone who has not met the terms yet.
    var howTrained: String {
        switch self {
        case .both: return "Both sides at once"
        case .either: return "Undecided"
        case .one: return "One side at a time"
        }
    }

    /// The modes that fit an exercise trained this way.
    var modes: [UnilateralMode] {
        switch self {
        case .both: return [.bilateral]
        case .either: return UnilateralMode.allCases
        case .one: return [.oneSided, .perSide]
        }
    }

    /// The modes an entry's menu offers: the ones that fit, plus the one the
    /// entry already has if it does not — what is written down stays
    /// reachable, so it can be switched back. Empty when there is nothing to
    /// choose, and the entry needs no menu.
    func choices(current: UnilateralMode) -> [UnilateralMode] {
        let offered = Set(modes + [current])
        let choices = UnilateralMode.allCases.filter(offered.contains)
        return choices.count > 1 ? choices : []
    }

    /// The mode a new entry starts in: how the exercise was logged last time,
    /// so one always trained left and right apart does not have to be switched
    /// over every workout — as long as that still fits. In a superset,
    /// left/right gives way: it does not interleave with a partner's sets.
    func startMode(lastLogged: UnilateralMode?, inSuperset: Bool) -> UnilateralMode {
        var mode = lastLogged.flatMap { modes.contains($0) ? $0 : nil } ?? modes[0]
        if inSuperset, mode == .perSide {
            mode = supersetFallback
        }
        return mode
    }

    /// What left/right becomes when the entry joins a superset.
    var supersetFallback: UnilateralMode {
        self == .one ? .oneSided : .bilateral
    }

    /// Whether an exercise trained this way can be merged into one trained
    /// `other`'s way. Only bilateral and unilateral do not mix: their entries
    /// would end up in the same history, which is what the split is there to
    /// prevent. Undecided goes with both.
    func canMerge(into other: ExerciseSides) -> Bool {
        !(self == .both && other == .one) && !(self == .one && other == .both)
    }
}
