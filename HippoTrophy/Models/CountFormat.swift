import Foundation

/// A number with the word it counts: `1 set`, `3 sets`, `0 sets`. Every count
/// the app writes out in words goes through here, so "1 sets" has one place to
/// be wrong in rather than one per screen.
///
/// Both forms are spelled out instead of appending an "s": the words are often
/// a noun with its verb — "exercise was" / "exercises were" — and that only
/// reads right as a pair someone wrote down.
enum CountFormat {
    /// `text(1, "exercise was", "exercises were")` → `"1 exercise was"`.
    static func text(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(number == 1 ? singular : plural)"
    }
}
