import Foundation

/// The activity graphs on the workout list, one category each, in the order
/// they are swiped through. Strength, then Cardio, unless the user sets up
/// others: those are the two kinds of training the app is mostly used for,
/// and a graph per category keeps a short run from looking like a rest day
/// next to a heavy leg day.
///
/// A category is shown at most once. "No Category" can have a graph of its
/// own, as it is an option of the heat map's filter — see `CategoryFilter`.
struct ActivityGraphs: Equatable {
    typealias Option = CategoryFilter.Option

    /// The folded ids of the graphs' categories, in order; `noCategoryID`
    /// stands for exercises without one.
    private(set) var ids: [String]

    static let standard = ActivityGraphs(ids: [
        ExerciseCategory.strength.id,
        ExerciseCategory.cardio.id,
    ])

    init(ids: [String]) {
        self.ids = ids
    }

    /// Read back from storage, a JSON list of ids. A category that is no
    /// longer on offer drops out, and so does a second graph of one already
    /// there; if nothing is left, or nothing readable was stored, the graphs
    /// are the standard ones.
    init(stored: String, options: [Option]) {
        let offered = Set(options.map { CategoryFilter.id(of: $0) })
        let ids = (try? JSONDecoder().decode([String].self, from: Data(stored.utf8))) ?? []
        var seen = Set<String>()
        let kept = ids.filter { offered.contains($0) && seen.insert($0).inserted }
        self = kept.isEmpty ? .standard : ActivityGraphs(ids: kept)
    }

    /// What goes into storage. Unlike `CategoryFilter`, not sorted: the order
    /// is the user's.
    var stored: String {
        let data = (try? JSONEncoder().encode(ids)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    var isStandard: Bool { self == .standard }

    /// The graphs' categories, in order, as `options` spells them.
    func categories(options: [Option]) -> [Option] {
        ids.compactMap { id in options.first { CategoryFilter.id(of: $0) == id } }
    }

    /// The categories without a graph yet, in menu order.
    func unshown(options: [Option]) -> [Option] {
        options.filter { !ids.contains(CategoryFilter.id(of: $0)) }
    }

    /// What the graph at `index` can be switched to: its own category and
    /// every one without a graph.
    func choices(at index: Int, options: [Option]) -> [Option] {
        options.filter { option in
            let id = CategoryFilter.id(of: option)
            return id == ids[index] || !ids.contains(id)
        }
    }

    /// Puts a graph of `option` right after `index` and returns where it
    /// landed, so the list can turn to it. Nothing happens for a category
    /// that already has one.
    @discardableResult
    mutating func add(_ option: Option, after index: Int) -> Int? {
        let id = CategoryFilter.id(of: option)
        guard !ids.contains(id) else { return nil }
        let position = min(index + 1, ids.count)
        ids.insert(id, at: position)
        return position
    }

    /// Switches the graph at `index` to `option`, unless another graph
    /// already shows it.
    mutating func replace(at index: Int, with option: Option) {
        let id = CategoryFilter.id(of: option)
        guard ids.indices.contains(index), !ids.contains(id) else { return }
        ids[index] = id
    }

    /// Takes the graph at `index` away. The last one stays: hiding the graph
    /// altogether is a setting of its own.
    mutating func remove(at index: Int) {
        guard ids.count > 1, ids.indices.contains(index) else { return }
        ids.remove(at: index)
    }

    /// Swaps the graph at `index` with its neighbour `offset` places away,
    /// and returns where it now is. Past either end it stays.
    @discardableResult
    mutating func move(at index: Int, by offset: Int) -> Int {
        let target = index + offset
        guard ids.indices.contains(index), ids.indices.contains(target) else { return index }
        ids.swapAt(index, target)
        return target
    }
}

extension ActivityGrid {
    /// What each workout is worth to the graph of `category`: the sets of
    /// those of its exercises filed under it, counted as
    /// `ExerciseEntry.setCount` counts them. As on the heat map, the category
    /// is the one the exercise carries today, found by name; an entry whose
    /// exercise is gone has none. A workout with nothing in the category is
    /// left out rather than counted as zero.
    static func activity(
        of sessions: [WorkoutSession],
        in category: CategoryFilter.Option,
        definitions: [ExerciseDefinition]
    ) -> [(date: Date, count: Int)] {
        var categoryNames: [ExerciseIdentity: String] = [:]
        for definition in definitions {
            categoryNames[definition.identity] = definition.categoryName
        }
        let filter = CategoryFilter(ids: [CategoryFilter.id(of: category)])

        return sessions.compactMap { session in
            let count = session.exercises
                .filter { filter.includes(categoryName: categoryNames[$0.identity]) }
                .reduce(0) { $0 + $1.setCount }
            return count > 0 ? (date: session.date, count: count) : nil
        }
    }
}
