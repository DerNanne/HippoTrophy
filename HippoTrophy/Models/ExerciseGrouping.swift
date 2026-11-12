import Foundation

/// What `ExerciseGrouping` needs to know of an exercise: which one it is, and
/// which superset it belongs to. The store's entries have it, and so do the
/// values the report reads out of them — one rule for both.
protocol SupersetGroupable {
    var id: UUID { get }
    var supersetID: UUID? { get }
}

extension ExerciseEntry: SupersetGroupable {}

/// Groups a workout's exercises for display: entries that share a
/// `supersetID` belong together, wherever they sit in the order. A superset's
/// pairing survives a reorder that moves something else between its members,
/// or moves one member without the other — it is found by id, not by
/// adjacency. A group's position is where its first member's is.
enum ExerciseGrouping {
    static func groups<Exercise: SupersetGroupable>(_ exercises: [Exercise]) -> [[Exercise]] {
        var seen = Set<UUID>()
        var groups: [[Exercise]] = []
        for exercise in exercises {
            guard !seen.contains(exercise.id) else { continue }
            if let supersetID = exercise.supersetID {
                let members = exercises.filter { $0.supersetID == supersetID }
                groups.append(members)
                seen.formUnion(members.map(\.id))
            } else {
                groups.append([exercise])
                seen.insert(exercise.id)
            }
        }
        return groups
    }

    /// The workout's order after moving whole groups, as a list's drag hands
    /// them over: `source` and `destination` count groups, not entries. A
    /// superset moves as the one card it is shown as, so the order cannot
    /// split it into something the editor does not draw.
    static func reordered<Exercise: SupersetGroupable>(
        _ exercises: [Exercise], movingGroups source: IndexSet, to destination: Int
    ) -> [Exercise] {
        let all = groups(exercises)
        let moved = source.filter { all.indices.contains($0) }.map { all[$0] }
        var rest = all.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertion = min(destination - source.count(in: 0..<destination), rest.count)
        rest.insert(contentsOf: moved, at: max(insertion, 0))
        return rest.flatMap { $0 }
    }
}
