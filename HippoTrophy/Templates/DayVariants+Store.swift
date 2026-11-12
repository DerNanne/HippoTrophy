import Foundation
import SwiftData

extension DayVariants {
    /// The variants whose week is over leave the shelf: archived, or deleted
    /// when `deleting`. Runs when the shelf shows and right after an import,
    /// which can bring a variant whose week ended long ago. Not saved: the
    /// caller saves. Whether any went.
    @discardableResult
    static func putAwayExpired(in context: ModelContext, deleting: Bool, at date: Date = .now, calendar: Calendar = .current) -> Bool {
        let shelf = TemplateShelf((try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))) ?? [])
        let expired = expired(on: shelf, at: date, calendar: calendar)
        guard !expired.isEmpty else { return false }
        shelf.archive(expired)
        if deleting {
            expired.forEach(context.delete)
        }
        return true
    }
}
