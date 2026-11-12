import Foundation

/// A rest between sets, counting down to a moment rather than ticking: what
/// is left is always the distance to `endsAt`, so the bar on screen, the
/// notification and the Live Activity agree to the second, and a phone put
/// away for two minutes comes back to the right number.
///
/// Paused, it stops being a moment: what is left is kept as a number until
/// it resumes, and the end is set again from then.
///
/// Pure: every question takes the time it is asked at.
nonisolated struct RestTimer: Equatable, Codable {
    /// The rest as it stands, adjustments included — what the bar is a share
    /// of.
    private(set) var duration: TimeInterval
    private(set) var endsAt: Date
    /// The exercise the rest follows, for the bar and the lock screen.
    var exerciseName: String
    /// The set the rest follows, which shows it under itself; nil for a rest
    /// started by hand.
    var setID: UUID?
    /// What the rest is before: the next set, or the other side of this one.
    let kind: RestKind
    /// What was left when it was paused; nil while it runs.
    private(set) var pausedRemaining: TimeInterval?

    /// How far one tap on minus or plus moves the end.
    static let step: TimeInterval = 15

    init(seconds: Int, exerciseName: String, setID: UUID? = nil, kind: RestKind = .afterSet, from now: Date) {
        duration = TimeInterval(seconds)
        endsAt = now.addingTimeInterval(duration)
        self.exerciseName = exerciseName
        self.setID = setID
        self.kind = kind
    }

    /// The whole rest in whole seconds, adjustments included: the "2:00"
    /// the countdown runs down from.
    var totalSeconds: Int {
        Int(duration.rounded())
    }

    var isPaused: Bool {
        pausedRemaining != nil
    }

    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// Stops the countdown where it is. Pausing a paused rest changes
    /// nothing.
    mutating func pause(at now: Date) {
        guard !isPaused else { return }
        pausedRemaining = remaining(at: now)
    }

    /// Runs on with what was left when it was paused.
    mutating func resume(at now: Date) {
        guard let pausedRemaining else { return }
        endsAt = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }

    /// The share still to rest, 1 at the start and 0 at the end.
    func fractionLeft(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, remaining(at: now) / duration)
    }

    func isOver(at now: Date) -> Bool {
        remaining(at: now) <= 0
    }

    /// Moves the end by `seconds`, either way. Taking off more than is left
    /// ends the rest now rather than in the past.
    mutating func adjust(by seconds: TimeInterval, at now: Date) {
        let left = remaining(at: now)
        let change = max(seconds, -left)
        endsAt = now.addingTimeInterval(left + change)
        if isPaused { pausedRemaining = left + change }
        duration = max(0, duration + change)
    }
}

/// What a rest leads to, which is how it shows: a rest after a set ends on
/// the next set; a rest between sides on the other side of the same set.
nonisolated enum RestKind: Equatable, Codable {
    case afterSet
    case betweenSides

    var title: String {
        switch self {
        case .afterSet: return "Rest"
        case .betweenSides: return "Switch Sides"
        }
    }

    var symbolName: String {
        switch self {
        case .afterSet: return "timer"
        case .betweenSides: return "arrow.left.arrow.right"
        }
    }
}

/// How long a rest lasts, in whole seconds: what an exercise or the setting
/// says, and the choices offered for both.
nonisolated enum RestDuration {
    /// The setting until it is changed.
    static let defaultSeconds = 120

    /// The setting for the rest between two sides until it is changed. One
    /// side has just rested while the other worked, so it is short.
    static let defaultBetweenSidesSeconds = 30

    /// What the menus offer. 0 stands for no rest timer.
    static let choices = [0, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300]

    /// The rest after a set of an exercise: its own, or else the setting's.
    /// Nil when that comes to no timer.
    static func seconds(exercise: Int?, setting: Int) -> Int? {
        let seconds = exercise ?? setting
        return seconds > 0 ? seconds : nil
    }

    /// `120` → "2:00", `0` → "Off".
    static func text(_ seconds: Int) -> String {
        seconds > 0 ? DurationFormat.text(forSeconds: seconds) : "Off"
    }
}

/// Whether ticking a set off starts a rest. In a superset the two exercises
/// follow each other without one: a set followed by a set of the other
/// exercise rests only if it is not the one that leads the round — the
/// exercise of the first set.
nonisolated enum RestAfterSet {
    /// `members` is whose each set is, in the order they are trained; nil
    /// outside a superset, where every set rests.
    static func rests<Member: Equatable>(afterSetAt index: Int, in members: [Member]?) -> Bool {
        guard let members, members.indices.contains(index), let lead = members.first else { return true }
        let next = index + 1
        guard members.indices.contains(next) else { return true }
        return members[next] == members[index] || members[index] != lead
    }
}
