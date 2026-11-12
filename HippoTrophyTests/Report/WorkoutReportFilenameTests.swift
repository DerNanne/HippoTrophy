import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The name the exported report file gets. The date in it is the day the
/// workout was trained where the user trains, not in UTC.
@MainActor
struct WorkoutReportFilenameTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// 11 September 2026, 01:07 in Berlin — 23:07 the day before in UTC.
    private func lateNightSession(name: String = "") throws -> WorkoutSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 1, minute: 7))!
        let session = WorkoutSession(name: name, date: date)
        try context().insert(session)
        return session
    }

    @Test func anEarlyMorningWorkoutKeepsItsOwnDay() throws {
        let session = try lateNightSession()
        #expect(WorkoutReportRenderer.filename(for: session, timeZone: berlin) == "Workout 2026-09-11.pdf")
    }

    @Test func aWorkoutWithANameLeadsWithIt() throws {
        let session = try lateNightSession(name: "Push A")
        #expect(WorkoutReportRenderer.filename(for: session, timeZone: berlin) == "Push A 2026-09-11.pdf")
    }

    @Test func anotherTimeZoneCanPutItOnAnotherDay() throws {
        let session = try lateNightSession()
        #expect(WorkoutReportRenderer.filename(for: session, timeZone: TimeZone(identifier: "UTC")!) == "Workout 2026-09-10.pdf")
    }

    /// Slashes and colons would be read as path separators.
    @Test func separatorsInTheNameBecomeDashes() throws {
        let session = try lateNightSession(name: " Push/Pull: A ")
        #expect(WorkoutReportRenderer.filename(for: session, timeZone: berlin) == "Push-Pull- A 2026-09-11.pdf")
    }
}
