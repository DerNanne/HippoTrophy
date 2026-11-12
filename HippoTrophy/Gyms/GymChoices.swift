import Foundation

/// What the gym and machine menus offer, and the machine an exercise starts
/// with. Decides only; `GymChoices+Store` creates, links and deletes.
///
/// A gym and a machine are told apart by `name.exerciseKey`, like exercises:
/// there is one of a name.
enum GymChoices {
    /// A name as typed, trimmed — nil when nothing is left, or when one of
    /// `existing` has it already.
    static func newName(_ typed: String, among existing: [String]) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isTaken(name, among: existing) else { return nil }
        return name
    }

    /// Why `newName` refuses a name, for the line under the field it was
    /// typed in: nil when it takes it. `kind` is "gym" or "machine".
    static func refusal(of typed: String, among existing: [String], kind: String) -> String? {
        if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "A \(kind) needs a name."
        }
        return isTaken(typed, among: existing) ? "There is a \(kind) of this name already." : nil
    }

    /// Whether one of `existing` has the name as typed already.
    static func isTaken(_ typed: String, among existing: [String]) -> Bool {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return existing.contains { $0.exerciseKey == name.exerciseKey }
    }

    /// The machines to offer for an exercise in a workout at `gym`: those
    /// standing there, then every other one, each by name. Without a gym,
    /// every machine is in the first list.
    static func machines(at gym: Gym?, among all: [Machine]) -> (here: [Machine], elsewhere: [Machine]) {
        let sorted = all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard let gym else { return (sorted, []) }
        let here = Set(gym.machines.map(\.id))
        return (sorted.filter { here.contains($0.id) }, sorted.filter { !here.contains($0.id) })
    }

    /// The machine an exercise starts with in a workout at `gym`: the one it
    /// was last done at there. Nil without a gym, or when it was never done
    /// at a machine there — a guess from another gym would be a machine that
    /// is not in the room.
    static func suggestedMachine(for identity: ExerciseIdentity, at gym: Gym?, in history: ExerciseHistory) -> Machine? {
        guard let gym else { return nil }
        return history.entries(of: identity)
            .first { $0.session?.gym?.id == gym.id && $0.machine != nil }?
            .machine
    }
}
