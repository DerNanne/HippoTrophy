import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// Which entries an exercise's history lists: anything with a value in it, and
/// an entry whose only content is a note — a warm-up, or a skipped exercise and
/// why. A note is history, but it is not a logged set.
@MainActor
struct ExerciseEntryHistoryTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func entry(notes: String = "", duration: Double? = nil, in context: ModelContext) -> ExerciseEntry {
        let entry = ExerciseEntry(name: "Bike", notes: notes, orderIndex: 0, definitionID: UUID(), effortScale: .off)
        context.insert(entry)
        let set = SetEntry(setNumber: 1, exercise: entry)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "f1", label: "Duration", typeRawValue: "time", orderIndex: 0, numberValue: duration, set: set))
        return entry
    }

    @Test func aLoggedValueBelongs() throws {
        let entry = entry(duration: 600, in: try context())
        #expect(entry.hasLoggedData)
        #expect(entry.belongsInHistory)
    }

    /// The warm-up from the old backup: nothing measured, "Warm up" in the note.
    @Test func aNoteAloneBelongsButIsNoLoggedData() throws {
        let entry = entry(notes: "Warm up", in: try context())
        #expect(!entry.hasLoggedData)
        #expect(entry.belongsInHistory)
    }

    @Test func anEmptyEntryStaysOut() throws {
        #expect(!entry(in: try context()).belongsInHistory)
    }

    @Test func aBlankNoteIsNoNote() throws {
        #expect(!entry(notes: "  \n ", in: try context()).belongsInHistory)
    }

    /// Left and right each have a set 1 and a set 2: the side breaks the tie,
    /// whatever order the store hands them in, so a backup of the same entry
    /// reads the same every time.
    @Test func setsOfBothSidesSortTheSameEveryTime() throws {
        let context = try context()
        let entry = ExerciseEntry(name: "Lunge", orderIndex: 0, definitionID: UUID(), effortScale: .off)
        context.insert(entry)
        for (number, side) in [(2, "right"), (1, "right"), (2, "left"), (1, "left")] {
            context.insert(SetEntry(setNumber: number, sideRawValue: side, exercise: entry))
        }
        let order = entry.sortedSets.map { "\($0.setNumber)\($0.sideRawValue)" }
        #expect(order == ["1left", "1right", "2left", "2right"])
    }
}
