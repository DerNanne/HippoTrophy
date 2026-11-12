import Foundation
import SwiftData

extension TemplateShelf {
    /// Keeps a template of `workout`, under its name, first on the shelf —
    /// what Save offers for a new workout and the history's menu does for
    /// any. Not saved: the caller saves, and says what failed.
    @discardableResult
    static func keepTemplate(of workout: WorkoutSession, in context: ModelContext) -> WorkoutSession {
        let templates = (try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))) ?? []
        let template = workout.templateCopy(named: name(forTemplateOf: workout.name))
        context.insert(template)
        TemplateShelf(templates).placeFirst(template)
        return template
    }

    /// Removes a template for good, the rest closing up behind it — a day
    /// variant once a workout was saved from it. Not saved: the caller saves.
    static func remove(_ template: WorkoutSession, in context: ModelContext) {
        let templates = (try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))) ?? []
        TemplateShelf(templates).archive(template)
        context.delete(template)
    }
}
