import SwiftUI

/// What an exercise in a past workout says besides its sets — where it was
/// done, the instructions it was done by, then the note on how it went — for
/// the workout's page and the exercise's history. Nothing shows for what is
/// empty.
struct EntryTextsView: View {
    let entry: ExerciseEntry
    /// The workout's gym too: in the history, where workouts from several
    /// gyms stand together. The workout's page names it once on top.
    var showsGym = false

    var body: some View {
        let place = [showsGym ? entry.session?.gym?.name : nil, entry.machine?.name].compactMap { $0 }
        if !place.isEmpty {
            Label {
                Text(place.joined(separator: " · "))
            } icon: {
                if entry.machine == nil { Image(systemName: "building.2") } else { Image("Machine") }
            }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        let instructions = entry.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            Label {
                Text(instructions)
            } icon: {
                Image(systemName: "list.bullet.clipboard")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Instructions: \(instructions)")
        }
        if !note.isEmpty {
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
