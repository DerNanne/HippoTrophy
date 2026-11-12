import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// How the read-only lists lay out what an entry logged: a table under the
/// field labels, labelled cells past three columns, a list for an entry logged
/// once per workout — the columns each of them shows, and the one header a
/// superset's sets can share.
@MainActor
struct SetValuesLayoutTests {
    private let context: ModelContext

    init() throws {
        context = ModelContext(
            try ModelContainer(
                for: Schema(AppSchema.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }

    private enum Logged {
        case number(Double)
        case text(String)
        case empty
    }

    private func entry(effortScale: EffortScale = .off, mode: UnilateralMode = .bilateral) -> ExerciseEntry {
        let entry = ExerciseEntry(name: "Exercise", orderIndex: 0, definitionID: UUID(), effortScale: effortScale, session: nil)
        entry.unilateralMode = mode
        context.insert(entry)
        return entry
    }

    /// A set with one value per field, in the order given.
    @discardableResult
    private func set(
        _ number: Int,
        of entry: ExerciseEntry,
        side: SetSide = .both,
        _ fields: [(key: String, label: String, type: FieldType, logged: Logged)]
    ) -> SetEntry {
        let set = SetEntry(setNumber: number, sideRawValue: side.rawValue, exercise: entry)
        context.insert(set)
        for (index, field) in fields.enumerated() {
            var number: Double?
            var text: String?
            switch field.logged {
            case .number(let value): number = value
            case .text(let value): text = value
            case .empty: break
            }
            context.insert(FieldValue(
                fieldKey: field.key, label: field.label, typeRawValue: field.type.rawValue,
                orderIndex: index, textValue: text, numberValue: number, set: set
            ))
        }
        return set
    }

    private func layout(of entry: ExerciseEntry, tracksSets: Bool = true) -> SetValuesLayout {
        SetValuesLayout(sets: entry.sortedSets, tracksSets: tracksSets)
    }

    private func keys(_ layout: SetValuesLayout) -> [String] {
        layout.columns.map(\.key)
    }

    // MARK: - Which layout

    /// Weight and reps get their labels on top like any field, so a set
    /// reads `80 kg` and `8` under them rather than `80 kg x8`.
    @Test func weightAndRepsMakeATableToo() {
        let bench = entry()
        set(1, of: bench, [("weight", "Weight", .weight, .number(80)), ("reps", "Reps", .reps, .number(8))])

        #expect(layout(of: bench) == .table([
            SetValuesColumn(key: "weight", label: "Weight", type: .weight),
            SetValuesColumn(key: "reps", label: "Reps", type: .reps),
        ]))
    }

    /// A custom field that nothing was logged in leaves nothing to label.
    @Test func aCustomFieldLeftEmptyEverywhereHasNoColumn() {
        let row = entry()
        set(1, of: row, [("weight", "Weight", .weight, .number(20)), ("reps", "Reps", .reps, .number(12)), ("f1", "Tempo", .text, .text("  "))])

        #expect(keys(layout(of: row)) == ["weight", "reps"])
    }

    /// A table without columns: no header, and each set reads as a dash.
    @Test func setsWithNothingInThemMakeATableWithoutColumns() {
        let carry = entry()
        set(1, of: carry, [("weight", "Weight", .weight, .empty), ("f1", "Distance (m)", .number, .empty)])

        #expect(layout(of: carry) == .table([]))
        #expect(layout(of: carry, tracksSets: false) == .table([]))
    }

    @Test func customFieldsMakeATable() {
        let carry = entry()
        for number in 1...3 {
            set(number, of: carry, [
                ("weight", "Weight", .weight, .number(30)),
                ("f1", "Distance (m)", .number, .number(40)),
                ("f2", "Duration", .time, .number(35)),
            ])
        }

        #expect(layout(of: carry) == .table([
            SetValuesColumn(key: "weight", label: "Weight", type: .weight),
            SetValuesColumn(key: "f1", label: "Distance (m)", type: .number),
            SetValuesColumn(key: "f2", label: "Duration", type: .time),
        ]))
    }

    /// Its length is open, but a short text sits in a column like any value;
    /// one too long for the screen sends the table to cells where it is drawn.
    @Test func aTextFieldIsAColumnToo() {
        let backExtension = entry()
        set(1, of: backExtension, [("weight", "Weight", .weight, .number(20)), ("reps", "Reps", .reps, .number(12)), ("f1", "Tempo", .text, .text("3-1-1"))])

        #expect(keys(layout(of: backExtension)) == ["weight", "reps", "f1"])
        #expect(layout(of: backExtension) == .table(layout(of: backExtension).columns))
    }

    @Test func pastThreeColumnsEveryValueCarriesItsLabel() {
        let sled = entry()
        set(1, of: sled, [
            ("weight", "Weight", .weight, .number(60)),
            ("f1", "Distance (m)", .number, .number(20)),
            ("f2", "Duration", .time, .number(30)),
            ("f3", "Incline", .number, .number(2)),
        ])

        #expect(layout(of: sled) == .cells(layout(of: sled).columns))
        #expect(layout(of: sled).columns.count == 4)
    }

    @Test func anEntryLoggedOncePerWorkoutListsItsFields() {
        let rowing = entry(effortScale: .levels)
        set(1, of: rowing, [
            ("f1", "Duration", .time, .number(600)),
            ("f2", "Distance (m)", .number, .number(2500)),
            ("f3", "Avg. Watts", .number, .number(187)),
            ("f4", "Stroke Rate", .number, .number(24)),
            ("f5", "Damper", .number, .number(5.5)),
            ("f6", "Feel", .text, .text("zäh, aber ok")),
        ])

        #expect(layout(of: rowing, tracksSets: false) == .list(layout(of: rowing, tracksSets: false).columns))
        #expect(keys(layout(of: rowing, tracksSets: false)) == ["f1", "f2", "f3", "f4", "f5", "f6"])
    }

    @Test func weightAndRepsOncePerWorkoutAreListedLikeAnyField() {
        let test = entry()
        set(1, of: test, [("weight", "Weight", .weight, .number(100)), ("reps", "Reps", .reps, .number(1))])

        #expect(layout(of: test, tracksSets: false) == .list(layout(of: test, tracksSets: false).columns))
        #expect(keys(layout(of: test, tracksSets: false)) == ["weight", "reps"])
    }

    /// Switching an exercise to once per workout converts its entries, so this
    /// only happens to an entry whose definition is gone or was never found.
    /// A list could show only one set; the table shows them all.
    @Test func severalSetsOfAnEntryLoggedOncePerWorkoutStillMakeATable() {
        let rowing = entry()
        set(1, of: rowing, [("f1", "Distance (m)", .number, .number(2000))])
        set(2, of: rowing, [("f1", "Distance (m)", .number, .number(1000))])

        #expect(layout(of: rowing, tracksSets: false) == .table(layout(of: rowing, tracksSets: false).columns))
    }

    // MARK: - Which columns

    /// A field filled in one set is a column for all of them; the others leave
    /// its cell blank.
    @Test func aFieldLoggedInOneSetIsAColumnForEverySet() {
        let backExtension = entry()
        set(1, of: backExtension, [("weight", "Weight", .weight, .empty), ("reps", "Reps", .reps, .number(15)), ("f1", "Tempo", .text, .empty)])
        set(2, of: backExtension, [("weight", "Weight", .weight, .number(20)), ("reps", "Reps", .reps, .number(12)), ("f1", "Tempo", .text, .text("langsam"))])

        #expect(keys(layout(of: backExtension)) == ["weight", "reps", "f1"])
    }

    @Test func aFieldEmptyInEverySetHasNoColumn() {
        let carry = entry()
        set(1, of: carry, [("weight", "Weight", .weight, .number(30)), ("f1", "Distance (m)", .number, .empty), ("f2", "Duration", .time, .number(35))])

        #expect(keys(layout(of: carry)) == ["weight", "f2"])
    }

    /// The order is the exercise's, from its fields — not the order a set
    /// happened to store them in.
    @Test func columnsFollowTheFieldOrder() {
        let carry = entry()
        let first = set(1, of: carry, [("weight", "Weight", .weight, .number(30)), ("f1", "Distance (m)", .number, .number(40))])
        first.values.first { $0.fieldKey == "weight" }?.orderIndex = 5

        #expect(keys(layout(of: carry)) == ["f1", "weight"])
    }

    @Test func aColumnReadsItsValueFromEachSet() {
        let carry = entry()
        let first = set(1, of: carry, [("weight", "Weight", .weight, .number(30)), ("f1", "Duration", .time, .number(35))])
        let second = set(2, of: carry, [("weight", "Weight", .weight, .number(32.5)), ("f1", "Duration", .time, .empty)])
        let duration = SetValuesColumn(key: "f1", label: "Duration", type: .time)

        #expect(duration.value(in: first)?.numberValue == 35)
        #expect(duration.value(in: second) == nil)
    }

    // MARK: - Supersets

    private let weight = SetValuesColumn(key: "weight", label: "Weight", type: .weight)
    private let reps = SetValuesColumn(key: "reps", label: "Reps", type: .reps)

    @Test func twoExercisesWithWeightAndRepsShareOneHeader() {
        #expect(SetValuesColumn.shared(by: [weight, reps], and: [weight, reps]) == [weight, reps])
    }

    /// A pull-up without weight leaves its weight cell blank under the header.
    @Test func anExerciseThatLogsLessGoesUnderTheOthersHeader() {
        #expect(SetValuesColumn.shared(by: [reps], and: [weight, reps]) == [weight, reps])
    }

    /// Squats and bouldering: Weight, Reps and Tops over the sets, half of
    /// them blank in every other row, would explain nothing.
    @Test func exercisesThatEachLogSomethingOfTheirOwnGetNoHeader() {
        let grade = SetValuesColumn(key: "f1", label: "Hardest Grade", type: .text)
        let tops = SetValuesColumn(key: "f2", label: "Tops", type: .number)

        #expect(SetValuesColumn.shared(by: [weight, reps], and: [grade, tops]) == nil)
        #expect(SetValuesColumn.shared(by: [weight, reps], and: [reps, tops]) == nil)
    }

    @Test func aKeyThatMeansSomethingElseInEachGetsNoHeader() {
        let distance = SetValuesColumn(key: "f1", label: "Distance (m)", type: .number)
        let tops = SetValuesColumn(key: "f1", label: "Tops", type: .number)

        #expect(SetValuesColumn.shared(by: [weight, distance], and: [weight, tops]) == nil)
    }

    @Test func moreColumnsThanALineOfCellsGetNoHeader() {
        let distance = SetValuesColumn(key: "f1", label: "Distance (m)", type: .number)
        let duration = SetValuesColumn(key: "f2", label: "Duration", type: .time)

        #expect(SetValuesColumn.shared(by: [weight, reps, distance, duration], and: [weight, reps]) == nil)
    }

    /// A text has a line of its own beneath its set, so it takes no cell.
    @Test func aTextDoesNotCountAgainstTheLine() {
        let tempo = SetValuesColumn(key: "f1", label: "Tempo", type: .text)
        let distance = SetValuesColumn(key: "f2", label: "Distance (m)", type: .number)

        #expect(SetValuesColumn.shared(by: [weight, reps, distance, tempo], and: [weight, reps]) == [weight, reps, distance, tempo])
    }

    // MARK: - What VoiceOver reads

    @Test func aSetIsReadAsOneSentence() {
        let carry = entry(effortScale: .levels)
        let first = set(1, of: carry, [("weight", "Weight", .weight, .number(30)), ("f1", "Distance (m)", .number, .number(40)), ("f2", "Duration", .time, .empty)])
        first.effort = .level(.hard)

        let text = SetValuesColumn.spokenText(for: first, columns: layout(of: carry).columns, unit: .kilograms, showsNumber: true)

        #expect(text == "Set 1, Weight \(WeightUnit.kilograms.formatted(kilograms: 30)), Distance (m) 40, Effort Hard")
    }

    @Test func aSetWithoutItsNumberStartsWithItsValues() {
        let rowing = entry()
        let only = set(1, of: rowing, [("f1", "Tops", .number, .number(7))])

        let text = SetValuesColumn.spokenText(for: only, columns: layout(of: rowing, tracksSets: false).columns, unit: .kilograms, showsNumber: false)

        #expect(text == "Tops 7")
    }

    // MARK: - Sides

    @Test func anEntryLoggedPerSideShowsEachSideUnderItsTitle() {
        let stretch = entry(mode: .perSide)
        set(1, of: stretch, side: .left, [("f1", "Hold", .time, .number(90))])
        set(2, of: stretch, side: .right, [("f1", "Hold", .time, .number(90))])
        set(3, of: stretch, side: .left, [("f1", "Hold", .time, .number(60))])

        let groups = SetGroup.groups(of: stretch)

        #expect(groups.map(\.title) == ["Left", "Right"])
        #expect(groups.map { $0.sets.map(\.setNumber) } == [[1, 3], [2]])
    }

    @Test func aSideWithoutSetsIsLeftOut() {
        let stretch = entry(mode: .perSide)
        set(1, of: stretch, side: .right, [("f1", "Hold", .time, .number(90))])

        #expect(SetGroup.groups(of: stretch).map(\.title) == ["Right"])
    }

    @Test func anEntryLoggedOnBothSidesIsOneRunWithoutATitle() {
        let carry = entry()
        set(1, of: carry, [("f1", "Distance (m)", .number, .number(40))])
        set(2, of: carry, [("f1", "Distance (m)", .number, .number(40))])

        let groups = SetGroup.groups(of: carry)

        #expect(groups.count == 1)
        #expect(groups.first?.title == nil)
        #expect(groups.first?.sets.count == 2)
    }

    // MARK: - Done only

    @Test func doneOnlyLeavesThePlannedSetsOutAndKeepsTheNumbers() {
        let press = entry()
        set(1, of: press, [("f1", "Weight", .weight, .number(80))])
        set(2, of: press, [("f1", "Weight", .weight, .number(82.5))]).isDone = false
        set(3, of: press, [("f1", "Weight", .weight, .number(85))])

        #expect(SetGroup.groups(of: press).first?.sets.map(\.setNumber) == [1, 2, 3])
        #expect(SetGroup.groups(of: press, doneOnly: true).first?.sets.map(\.setNumber) == [1, 3])
    }

    @Test func doneOnlyDropsASideWithNothingDone() {
        let stretch = entry(mode: .perSide)
        set(1, of: stretch, side: .left, [("f1", "Hold", .time, .number(90))])
        set(2, of: stretch, side: .right, [("f1", "Hold", .time, .number(90))]).isDone = false

        #expect(SetGroup.groups(of: stretch, doneOnly: true).map(\.title) == ["Left"])
    }
}
