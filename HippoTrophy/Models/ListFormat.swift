import Foundation

/// Things run together the way a sentence lists them: `A`, `A and B`,
/// `A, B and C` — without a comma before the "and", and the same on every
/// device, which the system's list format is not.
enum ListFormat {
    static func text(_ items: [String]) -> String {
        guard items.count > 2, let last = items.last else { return items.joined(separator: " and ") }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}
