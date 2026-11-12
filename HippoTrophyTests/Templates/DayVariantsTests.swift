import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// Templates adjusted for one day: what a variant is made of, how long an
/// unused one stays, what its badge says, and where it goes.
@MainActor
struct DayVariantsTests {
    private nonisolated static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private nonisolated static func day(_ month: Int, _ day: Int, hour: Int = 12, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func template(_ name: String, order: Int, plannedFor: Date? = nil) -> WorkoutSession {
        let template = WorkoutSession(name: name)
        template.isTemplate = true
        template.templateOrder = order
        template.plannedFor = plannedFor
        return template
    }

    private func container() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// The variant plans what the template does, under its name, for the
    /// day it was made on; the template is left as it was.
    @Test func aVariantCopiesItsTemplateForTheDay() throws {
        let context = try container()
        let legs = template("Legs", order: 0)
        context.insert(legs)
        context.insert(ExerciseEntry(name: "Squat", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: legs))

        let variant = DayVariants.variant(of: legs, on: Self.day(10, 27, hour: 7), calendar: Self.calendar)
        context.insert(variant)
        try context.save()

        #expect(variant.isTemplate)
        #expect(variant.name == "Legs")
        #expect(variant.exercises.map(\.name) == ["Squat"])
        #expect(variant.plannedFor == Self.day(10, 27, hour: 0))
        #expect(legs.plannedFor == nil)
        #expect(variant.id != legs.id)
    }

    /// A duplicate of a variant is another variant for the same day; a
    /// workout started from one is a workout, and one kept as a template is
    /// kept for good.
    @Test func onlyACopyAsTemplateKeepsTheDay() {
        let day = Self.day(10, 27, hour: 0)
        let variant = template("Legs", order: 0, plannedFor: day)
        #expect(variant.templateCopy(named: "Legs Copy").plannedFor == day)

        let started = variant.copy(dated: .now)
        #expect(started.plannedFor == nil)
        #expect(started.templateCopy(named: "Legs").plannedFor == nil)
    }

    /// An unused variant stays a week, its own day counted: made on a
    /// Tuesday, it goes on the Tuesday after. Templates kept for good never
    /// expire, and archived ones are already away.
    @Test(arguments: [
        (Self.day(10, 20, hour: 23), true),
        (Self.day(10, 21, hour: 0), false),
        (Self.day(10, 27), false)
    ])
    func aVariantExpiresAfterAWeek(plannedFor: Date, expired: Bool) {
        let variant = template("Variant", order: 0, plannedFor: Self.calendar.startOfDay(for: plannedFor))
        let archived = template("Archived", order: 0, plannedFor: Self.day(9, 1, hour: 0))
        archived.isArchived = true
        let shelf = TemplateShelf([variant, template("Kept", order: 1), archived])

        let now = Self.day(10, 27, hour: 6)
        #expect(DayVariants.expired(on: shelf, at: now, calendar: Self.calendar).map(\.name) == (expired ? ["Variant"] : []))
    }

    @Test func theBadgeSaysTodayYesterdayOrTheDay() {
        let now = Self.day(10, 27, hour: 8)
        let english = Locale(identifier: "en_US")
        func label(_ day: Date) -> String {
            DayVariants.label(for: day, now: now, calendar: Self.calendar, locale: english)
        }
        #expect(label(Self.day(10, 27, hour: 0)) == "Today")
        #expect(label(Self.day(10, 26, hour: 0)) == "Yesterday")
        #expect(label(Self.day(10, 20, hour: 0)) == "Oct 20")
        #expect(label(Self.day(12, 30, hour: 0, year: 2025)) == "Dec 30, 2025")
    }

    /// The variants whose week is over leave together; the rest close up
    /// without a gap.
    @Test func severalLeaveTheShelfAtOnce() {
        let sessions = [template("A", order: 0), template("B", order: 1), template("C", order: 2), template("D", order: 3)]
        TemplateShelf(sessions).archive([sessions[0], sessions[2]])
        let shelf = TemplateShelf(sessions)
        #expect(shelf.templates.map(\.name) == ["B", "D"])
        #expect(shelf.templates.map(\.templateOrder) == [0, 1])
        #expect(shelf.archived.map(\.name) == ["A", "C"])
    }

    /// Back from the archive, a variant is today's, or it would be put away
    /// again at once; a template kept for good comes back as it was.
    @Test func aRestoredVariantIsTodays() {
        let variant = template("Variant", order: 0, plannedFor: Self.day(9, 1, hour: 0))
        let kept = template("Kept", order: 0)
        variant.isArchived = true
        kept.isArchived = true
        let sessions = [variant, kept, template("A", order: 0)]

        TemplateShelf(sessions).restore(variant, on: Self.day(10, 27, hour: 9), calendar: Self.calendar)
        TemplateShelf(sessions).restore(kept, on: Self.day(10, 27, hour: 9), calendar: Self.calendar)

        #expect(variant.plannedFor == Self.day(10, 27, hour: 0))
        #expect(kept.plannedFor == nil)
        #expect(TemplateShelf(sessions).templates.map(\.name) == ["Kept", "Variant", "A"])
    }

    /// A variant trained is gone for good, and the shelf closes up behind it.
    @Test func aVariantRemovedLeavesNoGap() throws {
        let context = try container()
        let sessions = [template("A", order: 0), template("Variant", order: 1, plannedFor: Self.day(10, 27, hour: 0)), template("B", order: 2)]
        sessions.forEach(context.insert)
        try context.save()

        TemplateShelf.remove(sessions[1], in: context)
        try context.save()

        let left = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))
        #expect(TemplateShelf(left).templates.map(\.name) == ["A", "B"])
        #expect(TemplateShelf(left).templates.map(\.templateOrder) == [0, 1])
        #expect(TemplateShelf(left).archived.isEmpty)
    }

    /// What runs when the shelf shows and after an import: a variant whose
    /// week is over is archived, the rest close up, a template kept for good
    /// and this week's variant stay.
    @Test func anExpiredVariantIsPutAway() throws {
        let context = try container()
        let sessions = [
            template("Old", order: 0, plannedFor: Self.day(10, 3, hour: 0)),
            template("Kept", order: 1),
            template("Fresh", order: 2, plannedFor: Self.day(11, 5, hour: 0))
        ]
        sessions.forEach(context.insert)
        try context.save()

        let wentAway = DayVariants.putAwayExpired(in: context, deleting: false, at: Self.day(11, 7), calendar: Self.calendar)

        let left = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))
        #expect(wentAway)
        #expect(TemplateShelf(left).templates.map(\.name) == ["Kept", "Fresh"])
        #expect(TemplateShelf(left).templates.map(\.templateOrder) == [0, 1])
        #expect(TemplateShelf(left).archived.map(\.name) == ["Old"])
    }

    /// With "Delete Unused Variants" on, it is gone instead.
    @Test func anExpiredVariantIsDeletedWhenTheSettingSaysSo() throws {
        let context = try container()
        let sessions = [template("Old", order: 0, plannedFor: Self.day(10, 3, hour: 0)), template("Kept", order: 1)]
        sessions.forEach(context.insert)
        try context.save()

        DayVariants.putAwayExpired(in: context, deleting: true, at: Self.day(11, 7), calendar: Self.calendar)
        try context.save()

        let left = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))
        #expect(left.map(\.name) == ["Kept"])
    }

    /// Nothing expired, nothing changes — and the caller has nothing to save.
    @Test func withoutAnExpiredVariantNothingGoes() throws {
        let context = try container()
        context.insert(template("Fresh", order: 0, plannedFor: Self.day(11, 5, hour: 0)))
        try context.save()

        #expect(!DayVariants.putAwayExpired(in: context, deleting: true, at: Self.day(11, 7), calendar: Self.calendar))
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates)).count == 1)
    }
}
