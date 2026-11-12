import Foundation

/// The one step after the update that brought bilateral and unilateral: what
/// becomes of the user's own exercises, decided here, applied once by
/// `SidesSettlement.runOnce`.
///
/// - An own exercise never used — no entry with a filled set, none with a
///   note — goes, with its empty entries. Beta data: lists imported once,
///   names typed and forgotten.
/// - Every other own exercise that logs sets, Cardio aside, is undecided,
///   whatever its old switch said: a Bulgarian Split Squat of one's own may
///   have been entered with the switch off. `SidesAssistant` asks.
/// - The rest of the own ones — Cardio, and what is logged once per
///   workout — are bilateral: they have no sides to log, whatever the old
///   switch said, so there is nothing to ask.
/// - Catalog exercises are the catalog's, and an own exercise that is
///   one-sided already stays so: no store from before the update can hold
///   one, so it was made in this launch by `CatalogSync`, for the
///   one-sided entries of a catalog exercise without a one-sided form —
///   "Chest Press Machine (Unilateral)". The update test from build 20
///   found the assistant asking about it.
nonisolated enum SidesSettlement {
    struct Exercise: Equatable {
        var id: UUID
        var isCatalog: Bool
        var tracksSets: Bool
        var isCardio: Bool
        var isOneSided: Bool = false
        /// Waiting for the assistant.
        var isUndecided: Bool = false
        /// A set with something in it, or a note, in any of its entries.
        var isUsed: Bool
    }

    struct Plan: Equatable {
        var deletions: Set<UUID> = []
        var undecided: Set<UUID> = []
        var bilateral: Set<UUID> = []
    }

    static func plan(_ exercises: [Exercise]) -> Plan {
        var plan = Plan()
        for exercise in exercises where !exercise.isCatalog && !exercise.isOneSided {
            if !exercise.isUsed {
                plan.deletions.insert(exercise.id)
            } else if exercise.tracksSets, !exercise.isCardio {
                plan.undecided.insert(exercise.id)
            } else {
                plan.bilateral.insert(exercise.id)
            }
        }
        return plan
    }

    /// An own exercise still undecided and never used, at any launch after
    /// the first: one plan above left alone because it came later — from an
    /// import, or from a store whose settlement ran before it was there. The
    /// assistant would ask about it, though nothing hangs on the answer.
    /// Nobody makes one by hand: the editor never offers Undecided.
    static func leftovers(_ exercises: [Exercise]) -> Set<UUID> {
        Set(exercises.filter { !$0.isCatalog && $0.isUndecided && !$0.isUsed }.map(\.id))
    }

    /// Every own exercise never used, whatever its side — for the one more
    /// clean-up with build 22. Not at every launch: an exercise made
    /// yesterday to be trained tomorrow is unused too.
    static func unused(_ exercises: [Exercise]) -> Set<UUID> {
        Set(exercises.filter { !$0.isCatalog && !$0.isUsed }.map(\.id))
    }
}
