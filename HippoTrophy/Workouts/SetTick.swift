import Foundation
import Observation

/// Where a set's tick stands. In `UnilateralMode.oneSided` a row stands for
/// two sides logged once, so its tick takes two taps, one per side. Which side
/// came first does not matter and is not kept. One side done is not done: the
/// set stays planned, and nothing counts it until the second tap.
enum SetTick: Equatable {
    case open
    case oneSideDone
    case done

    /// `oneSideDone` only means something in the mode that has two taps: a set
    /// whose exercise was switched over meanwhile has one tick again.
    init(isDone: Bool, oneSideDone: Bool, mode: UnilateralMode) {
        if isDone {
            self = .done
        } else if oneSideDone, mode == .oneSided {
            self = .oneSideDone
        } else {
            self = .open
        }
    }

    /// What a tap on the tick makes of it. From done it goes back to open in
    /// one tap, so taking a tick out does not ask for two.
    func tapped(mode: UnilateralMode) -> SetTick {
        switch self {
        case .open: return mode == .oneSided ? .oneSideDone : .done
        case .oneSideDone: return .done
        case .done: return .open
        }
    }
}

/// The sets with one side ticked off, for the whole app: the editor can be
/// left while a workout goes on, and comes back to them. Only a step on the
/// way to `SetEntry.isDone`, so it stays out of the store and a backup; a quit
/// app starts those sets over.
@MainActor
@Observable
final class OneSideTicks {
    static let shared = OneSideTicks()

    private var setIDs: Set<UUID> = []

    func contains(_ setID: UUID) -> Bool {
        setIDs.contains(setID)
    }

    func set(_ setID: UUID, oneSideDone: Bool) {
        if oneSideDone {
            setIDs.insert(setID)
        } else {
            setIDs.remove(setID)
        }
    }

    func removeAll() {
        setIDs.removeAll()
    }
}
