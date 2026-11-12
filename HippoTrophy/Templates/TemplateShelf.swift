import Foundation

/// The templates on the start screen, in their order, and the moves that
/// change it.
///
/// The order is `templateOrder`, numbered 0, 1, 2 … across the shelf after
/// every move, so it has no gaps and no ties to break. An archived template
/// keeps its number while it is away and stands first when it comes back,
/// like a new one: what was just picked is what is wanted next.
struct TemplateShelf {
    /// On the shelf, in order.
    let templates: [WorkoutSession]
    /// Put away, by name.
    let archived: [WorkoutSession]

    /// Picks the templates out of `sessions`; workouts are ignored.
    init(_ sessions: [WorkoutSession]) {
        let all = sessions.filter(\.isTemplate)
        templates = all
            .filter { !$0.isArchived }
            // Ties only come from outside the shelf's own moves; the newer
            // template goes first, as it would have.
            .sorted { ($0.templateOrder, $1.date) < ($1.templateOrder, $0.date) }
        archived = all
            .filter(\.isArchived)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The name a template made from a workout starts with: the workout's,
    /// or a placeholder that asks to be renamed.
    static func name(forTemplateOf workoutName: String) -> String {
        let trimmed = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Template" : trimmed
    }

    /// The name of a duplicate, told apart from its original.
    static func duplicateName(of name: String) -> String {
        "\(name) Copy"
    }

    /// What a card lists under the name: the exercises, in their order.
    static func exerciseLine(of template: WorkoutSession) -> String {
        ListFormat.text(template.exercises.sorted { $0.orderIndex < $1.orderIndex }.map(\.name))
    }

    /// The line under a template's name where a workout's says what was
    /// done: here what is planned, every exercise and every set.
    static func summary(of template: WorkoutSession) -> String {
        let exercises = CountFormat.text(template.exercises.count, "exercise", "exercises")
        let sets = CountFormat.text(template.exercises.reduce(0) { $0 + $1.sets.count }, "set", "sets")
        return "\(exercises) • \(sets)"
    }

    /// Puts a template first: a new one, or one back from the archive.
    func placeFirst(_ template: WorkoutSession) {
        template.isArchived = false
        number([template] + templates.filter { $0 !== template })
    }

    /// Puts a new template right behind `original` — where a duplicate is
    /// looked for.
    func place(_ template: WorkoutSession, after original: WorkoutSession) {
        var order = templates.filter { $0 !== template }
        let index = order.firstIndex { $0 === original }.map { $0 + 1 } ?? order.endIndex
        order.insert(template, at: index)
        number(order)
    }

    /// Moves a dragged template to where `target` stands; `target` makes
    /// room in the direction the drag came from.
    func move(_ template: WorkoutSession, to target: WorkoutSession) {
        guard template !== target,
              let from = templates.firstIndex(where: { $0 === template }),
              let to = templates.firstIndex(where: { $0 === target })
        else { return }
        var order = templates
        order.remove(at: from)
        order.insert(template, at: to)
        number(order)
    }

    /// Takes a template off the shelf; the rest close up.
    func archive(_ template: WorkoutSession) {
        archive([template])
    }

    /// Takes several off the shelf at once — the day variants whose week is
    /// over; the rest close up.
    func archive(_ leaving: [WorkoutSession]) {
        for template in leaving {
            template.isArchived = true
        }
        number(templates.filter { template in !leaving.contains { $0 === template } })
    }

    /// Brings a template back from the archive, first in line. A day
    /// variant comes back as today's: brought back on its old day, it would
    /// be put away again at once.
    func restore(_ template: WorkoutSession, on date: Date, calendar: Calendar = .current) {
        if template.plannedFor != nil {
            template.plannedFor = calendar.startOfDay(for: date)
        }
        placeFirst(template)
    }

    /// Which way a dragged card moves along the row: one place right (1)
    /// or left (-1) once it is half a place (`stride`) off its own and
    /// there is a place to go, otherwise none (0).
    static func step(offset: CGFloat, stride: CGFloat, index: Int, count: Int) -> Int {
        if offset > stride / 2, index + 1 < count { return 1 }
        if offset < -stride / 2, index > 0 { return -1 }
        return 0
    }

    private func number(_ order: [WorkoutSession]) {
        for (index, template) in order.enumerated() where template.templateOrder != index {
            template.templateOrder = index
        }
    }
}

extension WorkoutSession {
    /// A template of this workout, or of another template: everything `copy`
    /// keeps, under `name`. A copy of a day variant is one for the same day.
    /// Not inserted, and not on the shelf yet — `TemplateShelf` says where
    /// it stands.
    func templateCopy(named name: String) -> WorkoutSession {
        let template = copy(dated: .now)
        template.name = name
        template.isTemplate = true
        template.plannedFor = isTemplate ? plannedFor : nil
        // The side a workout happened to start with prescribes nothing; an
        // order chosen freely, or another template's side, does.
        if !isTemplate {
            for entry in template.exercises where !entry.hasChosenOrder {
                entry.startSideRawValue = nil
            }
        }
        return template
    }
}
