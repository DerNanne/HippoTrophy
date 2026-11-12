import SwiftUI

/// An exercise's instructions and note under its name in the workout editor,
/// where they are read while training — the plan, then how it is going. A
/// tap opens them to edit. Nothing shows for what is empty, and nothing at
/// all with Show Instructions and Notes turned off, in Settings or for this
/// workout: the note button still opens them.
struct ExerciseTextsLines: View {
    let instructions: String
    let note: String
    let action: () -> Void
    @Environment(\.showsExerciseTexts) private var showsTexts

    var body: some View {
        if showsTexts {
            line(instructions, systemImage: "list.bullet.clipboard", spoken: "Instructions")
            line(note, systemImage: "note.text", spoken: "Note")
        }
    }

    @ViewBuilder
    private func line(_ raw: String, systemImage: String, spoken: String) -> some View {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                    Text(text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .font(.footnote)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(spoken): \(text)")
            .accessibilityHint("Opens the instructions and the note")
        }
    }
}

extension ExerciseEntry {
    /// Whether the note sheet has anything in it — instructions or a note —
    /// which the note button shows by its tint.
    var hasInstructionsOrNote: Bool {
        !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
