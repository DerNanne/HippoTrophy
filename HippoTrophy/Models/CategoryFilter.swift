import Foundation
import SwiftUI

/// Which exercise categories the heat map counts. Strength alone unless the
/// user picks more: the app is made for hypertrophy and strength, and a bike
/// ride counts a full set for every muscle it is filed under, so letting it in
/// by default would shade the legs for training they did not get.
///
/// Exercises with no category are an option of their own ("No Category"), as
/// are entries whose exercise is gone: neither has a category to be counted
/// under, so they are counted only when that option is picked.
struct CategoryFilter: Equatable {
    /// One option in the menu: a category, or `nil` for none.
    typealias Option = ExerciseCategory?

    /// The folded ids of the picked categories; `noCategoryID` stands for
    /// exercises without one.
    private(set) var ids: Set<String>

    static let noCategoryID = ""
    static let standard = CategoryFilter(ids: [ExerciseCategory.strength.id])

    init(ids: Set<String>) {
        self.ids = ids
    }

    /// Read back from storage, a JSON list of ids. A category that is no
    /// longer on offer drops out; if
    /// nothing is left, or nothing readable was stored, the filter is the
    /// standard one.
    init(stored: String, options: [Option]) {
        let offered = Set(options.map { Self.id(of: $0) })
        let ids = (try? JSONDecoder().decode([String].self, from: Data(stored.utf8))) ?? []
        let kept = Set(ids).intersection(offered)
        self = kept.isEmpty ? .standard : CategoryFilter(ids: kept)
    }

    /// What goes into storage. Sorted, so the same choice is the same string.
    var stored: String {
        let data = (try? JSONEncoder().encode(ids.sorted())) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Everything the menu offers: the categories, then "No Category".
    static var options: [Option] {
        ExerciseCategory.allCases.map(Option.some) + [nil]
    }

    static func id(of option: Option) -> String {
        option?.id ?? noCategoryID
    }

    static func name(of option: Option) -> String {
        option?.name ?? "No Category"
    }

    /// The chips' symbol, which they tint themselves.
    static func symbolName(of option: Option) -> String {
        option?.symbolName ?? "circle.slash"
    }

    /// The menus' symbol and the heading's, in the category's colour — see
    /// `ExerciseCategory.coloredSymbol`. No Category has none and stays plain.
    static func icon(of option: Option) -> Image {
        option?.coloredSymbol ?? Image(systemName: symbolName(of: option))
    }

    /// Whether an exercise filed under `categoryName` counts; `nil` for an
    /// entry whose exercise is gone.
    func includes(categoryName: String?) -> Bool {
        ids.contains(categoryName.flatMap { ExerciseCategory.resolve($0) }?.id ?? Self.noCategoryID)
    }

    func contains(_ option: Option) -> Bool {
        ids.contains(Self.id(of: option))
    }

    /// Picks or drops `option`. The last one picked stays: a heat map that
    /// counts nothing answers no question.
    mutating func toggle(_ option: Option) {
        let id = Self.id(of: option)
        if ids.contains(id) {
            guard ids.count > 1 else { return }
            ids.remove(id)
        } else {
            ids.insert(id)
        }
    }

    /// The picked options in menu order when the heading names them one by
    /// one — up to two, and not all there are — otherwise `nil`.
    func named(options: [Option]) -> [Option]? {
        let picked = options.filter(contains)
        return picked.count < options.count && picked.count <= 2 ? picked : nil
    }

    /// For the heading: the picked names, "All Categories" when nothing is
    /// left out, a count when the names would not fit.
    func label(options: [Option]) -> String {
        if let named = named(options: options) {
            return named.map { Self.name(of: $0) }.joined(separator: ", ")
        }
        let picked = options.filter(contains)
        return picked.count == options.count ? "All Categories" : "\(picked.count) Categories"
    }
}
