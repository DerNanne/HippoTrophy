import Foundation
import SwiftData

/// What turning "Track Sets" off does to what was already logged.
///
/// An exercise that does not track sets logs exactly one set per entry, so an
/// entry with several sets cannot stay as it is. Nothing is lost: each set
/// becomes an entry of its own, in the same order, right behind the first —
/// the same thing as adding the exercise to the workout several times.
@MainActor
enum ExerciseSplitting {
    /// The entries a switch to "one set" would split, for saying so first.
    static func entriesWithSeveralSets(_ entries: [ExerciseEntry]) -> [ExerciseEntry] {
        entries.filter { $0.sets.count > 1 }
    }

    /// Splits every entry with several sets into one entry per set. The
    /// caller saves.
    static func splitIntoSingleSets(_ entries: [ExerciseEntry], in context: ModelContext) {
        for entry in entriesWithSeveralSets(entries) {
            guard let session = entry.session else { continue }
            let sets = entry.sortedSets
            let extra = sets.count - 1

            // Make room right behind the entry, so the sets stay together and
            // in order.
            for other in session.exercises where other.id != entry.id && other.orderIndex > entry.orderIndex {
                other.orderIndex += extra
            }

            for (offset, set) in sets.dropFirst().enumerated() {
                let split = ExerciseEntry(
                    name: entry.name,
                    instructions: entry.instructions,
                    orderIndex: entry.orderIndex + offset + 1,
                    definitionID: entry.definitionID,
                    tracksUnilateral: entry.tracksUnilateral,
                    logsSidesSeparately: entry.logsSidesSeparately,
                    effortScale: entry.effortScale,
                    catalogKey: entry.catalogKey,
                assistance: entry.assistance,
                    session: session
                )
                split.machine = entry.machine
                split.startSideRawValue = entry.startSideRawValue
                context.insert(split)
                session.exercises.append(split)
                entry.sets.removeAll { $0.id == set.id }
                set.exercise = split
                split.sets.append(set)
                set.setNumber = 1
                set.supersetPosition = nil
                set.sideOrder = nil
            }
            sets.first?.setNumber = 1
            sets.first?.sideOrder = nil
            // One set per entry leaves nothing to interleave: an exercise that
            // logs once is not trained in rounds.
            if let supersetID = entry.supersetID {
                for member in session.exercises where member.supersetID == supersetID {
                    SupersetPair.dissolve(member)
                }
            }
        }
    }
}
