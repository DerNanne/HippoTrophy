import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// What HippoTrophy Desk, the web app, takes from this app instead of
/// drawing or counting it a second time: the body outlines of the heat map,
/// and what the app makes of `CoverageBackup.json` — each workout's sets,
/// the sets a day, the sets per muscle for every period, the progress of
/// every exercise. The web app keeps a copy of `export/` and tests its own
/// counting against it, so the two cannot drift apart unnoticed.
///
/// `exportIsCurrent` goes red when the app counts or draws differently from
/// the files. Then the change is meant or it is not; if it is, write the
/// files anew and take them over into the web app:
///
///     TEST_RUNNER_WRITE_DESK_EXPORT=1 xcodebuild test … \
///         '-only-testing:HippoTrophyTests/DeskExportTests/writeTheExport()'
@MainActor
struct DeskExportTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent() // Export
            .deletingLastPathComponent() // HippoTrophyTests
            .deletingLastPathComponent() // the repository
            .appending(path: "export", directoryHint: .isDirectory)
    }

    @Test func exportIsCurrent() throws {
        for (name, data) in try DeskExport.files() {
            let written = try Data(contentsOf: Self.folder.appending(path: name))
            #expect(
                written == data,
                "export/\(name) is not what the app makes of it now. If that is meant, write it anew — see DeskExportTests."
            )
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WRITE_DESK_EXPORT"] != nil))
    func writeTheExport() throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        for (name, data) in try DeskExport.files() {
            try data.write(to: Self.folder.appending(path: name))
        }
    }

    /// The outlines are the ones the app draws: every muscle of every
    /// figure is there, mirrored, and nothing else.
    @Test func outlinesCarryEveryFigureAndMuscle() throws {
        let outlines = DeskExport.outlines()
        #expect(outlines.width == 200 && outlines.height == 440)
        #expect(outlines.figures.count == BodyFigure.allCases.count * BodySide.allCases.count)
        for figure in outlines.figures {
            let outline = BodyOutline.of(try #require(BodyFigure(rawValue: figure.figure)), figure.side == "front" ? .front : .back)
            #expect(figure.muscles.count == outline.muscles.count)
            #expect(figure.muscles.allSatisfy { $0.d.hasPrefix("M") && $0.d.hasSuffix("Z") })
        }
    }

    /// The counting starts from what the app shows: the busiest day is the
    /// sum of its workouts, and every period's start is before `now`.
    @Test func expectationsAddUp() throws {
        let expected = try DeskExport.expected()
        let byDay = Dictionary(grouping: expected.workouts, by: \.day).mapValues { $0.reduce(0) { $0 + $1.setCount } }
        #expect(expected.activity.map(\.sets) == expected.activity.map { byDay[$0.day] ?? -1 })
        #expect(expected.heat.count == HeatMapPeriod.allCases.count * 2)
        #expect(expected.progress.contains { !$0.metrics.isEmpty })
    }
}

// MARK: - What is written

/// The export, apart from the test that compares or writes it.
@MainActor
enum DeskExport {
    /// The moment the expectations are counted at: the time
    /// `CoverageBackup.json` was exported, two days after its last workout.
    static let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!

    /// UTC, weeks from Monday: a day is the same day wherever the test runs,
    /// and the web app counts with the same calendar.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func files() throws -> [(String, Data)] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return [
            ("outlines.json", try encoder.encode(outlines()) + Data("\n".utf8)),
            ("coverage-expected.json", try encoder.encode(expected()) + Data("\n".utf8)),
        ]
    }

    // MARK: Outlines

    struct Outlines: Encodable {
        let width: Double
        let height: Double
        let figures: [Figure]
    }

    struct Figure: Encodable {
        let figure: String
        let side: String
        /// Drawn first, then `body`, then the muscles, then `hair`.
        let hairBehind: String?
        let body: [String]
        let muscles: [Muscle]
        let hair: String
    }

    struct Muscle: Encodable {
        let group: String
        let d: String
    }

    static func outlines() -> Outlines {
        let figures = BodyFigure.allCases.flatMap { figure in
            BodySide.allCases.map { side in
                let outline = BodyOutline.of(figure, side)
                return Figure(
                    figure: figure.rawValue,
                    side: side == .front ? "front" : "back",
                    hairBehind: outline.hairBehind.map(svg),
                    body: outline.body.map(svg),
                    muscles: outline.muscles.map { Muscle(group: $0.group.rawValue, d: svg($0.path)) },
                    hair: svg(outline.hair)
                )
            }
        }
        return Outlines(width: BodyOutline.size.width, height: BodyOutline.size.height, figures: figures)
    }

    /// A path as SVG path data, to two decimals: finer than a pixel at any
    /// size the map is drawn.
    static func svg(_ path: CGPath) -> String {
        var parts: [String] = []
        func point(_ p: CGPoint) -> String { "\(number(p.x)) \(number(p.y))" }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: parts.append("M\(point(e.points[0]))")
            case .addLineToPoint: parts.append("L\(point(e.points[0]))")
            case .addQuadCurveToPoint: parts.append("Q\(point(e.points[0])) \(point(e.points[1]))")
            case .addCurveToPoint: parts.append("C\(point(e.points[0])) \(point(e.points[1])) \(point(e.points[2]))")
            case .closeSubpath: parts.append("Z")
            @unknown default: break
            }
        }
        return parts.joined()
    }

    private static func number(_ value: CGFloat) -> String {
        let rounded = (Double(value) * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    // MARK: Expectations

    struct Expected: Encodable {
        let source = "HippoTrophyTests/Backup/CoverageBackup.json"
        let now: Date
        let timeZone = "UTC"
        let firstWeekday = "monday"
        let workouts: [Workout]
        let activity: [Day]
        let heat: [Heat]
        let progress: [Progress]
    }

    struct Workout: Encodable {
        let id: UUID
        let name: String
        let day: String
        /// What the workout is worth in the activity graph — see
        /// `WorkoutSession.setCount`.
        let setCount: Int
    }

    struct Day: Encodable {
        let day: String
        let sets: Int
    }

    struct Heat: Encodable {
        /// The `HeatMapPeriod` case: "all", "year", "sixMonths",
        /// "threeMonths", "month".
        let period: String
        /// "all" for every category, "standard" for Strength alone, the
        /// heat map's own choice.
        let categories: String
        let start: Date?
        /// Every muscle group, also the untrained ones.
        let muscles: [MuscleCount]
    }

    struct MuscleCount: Encodable {
        let group: String
        let main: Int
        let secondary: Int
        /// Of the most trained one, 0 to 1: what the colour is made of.
        let share: Double
    }

    struct Progress: Encodable {
        /// `catalog:<key>` or `own:<folded name>` — see `ExerciseIdentity`.
        let identity: String
        let metrics: [String]
        let points: [Series]
    }

    struct Series: Encodable {
        let metric: String
        let points: [Point]
    }

    struct Point: Encodable {
        let date: Date
        let line: String
        let mode: String
        let value: Double
        let setCount: Int
    }

    static func expected() throws -> Expected {
        let context = ModelContext(try ModelContainer(
            for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
        try CoverageBackup.importFile(CoverageBackup.read(), into: context)
        // As after any import in the app.
        try CatalogSync.run(in: context)
        try context.save()

        let calendar = Self.calendar
        func day(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }

        let sessions = try context.fetch(FetchDescriptor(
            predicate: WorkoutSession.trained, sortBy: [SortDescriptor(\.date)]
        ))
        let workouts = sessions.map { Workout(id: $0.id, name: $0.name, day: day($0.date), setCount: $0.setCount) }
        var byDay: [String: Int] = [:]
        for workout in workouts { byDay[workout.day, default: 0] += workout.setCount }
        let activity = byDay.keys.sorted().map { Day(day: $0, sets: byDay[$0]!) }

        let entries = try context.fetch(FetchDescriptor<ExerciseEntry>())
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        var heat: [Heat] = []
        for (name, categories) in [("all", nil), ("standard", CategoryFilter.standard)] as [(String, CategoryFilter?)] {
            let history = MuscleGroupHistory(entries: entries, definitions: definitions, categories: categories)
            for period in HeatMapPeriod.allCases {
                let map = MuscleHeat(history: history, period: period, now: now, calendar: calendar)
                heat.append(Heat(
                    period: String(describing: period),
                    categories: name,
                    start: map.start,
                    muscles: MuscleGroup.allCases.map { group in
                        let sets = map.sets(for: group)
                        return MuscleCount(group: group.rawValue, main: sets.main, secondary: sets.secondary, share: map.share(for: group))
                    }
                ))
            }
        }

        let history = ExerciseHistory.fetch(in: context)
        let progress = history.identitiesWithHistory.map { identity in
            let progress = ExerciseProgress(entries: history.entries(of: identity))
            return Progress(
                identity: text(identity),
                metrics: progress.metrics.map(\.rawValue),
                points: progress.metrics.map { metric in
                    Series(metric: metric.rawValue, points: progress.points(for: metric).map {
                        Point(date: $0.date, line: $0.line.rawValue, mode: $0.mode.rawValue, value: $0.value, setCount: $0.setCount)
                    })
                }
            )
        }
        .sorted { $0.identity < $1.identity }

        return Expected(now: now, workouts: workouts, activity: activity, heat: heat, progress: progress)
    }

    private static func text(_ identity: ExerciseIdentity) -> String {
        switch identity {
        case .catalog(let key): "catalog:\(key)"
        case .own(let key): "own:\(key)"
        }
    }
}
