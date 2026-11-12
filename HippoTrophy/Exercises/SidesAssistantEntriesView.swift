import SwiftUI

/// One exercise logged both ways, entry by entry.
struct SidesAssistantEntriesView: View {
    let exercise: SidesAssistant.Exercise
    @Binding var assistant: SidesAssistant

    var body: some View {
        List {
            Section {
                HStack {
                    Button("All Bilateral") { assistant.decideAll(of: exercise, as: .both) }
                    Spacer()
                    Button("All Unilateral") { assistant.decideAll(of: exercise, as: .one) }
                }
                .buttonStyle(.borderless)
                let changed = assistant.isChanged(exercise)
                Button("Reset to As Logged", systemImage: "arrow.uturn.backward") {
                    assistant.resetAsLogged(exercise)
                }
                .disabled(!changed)
                .buttonStyle(.borderless)
                // The list does not grey a disabled button by itself.
                .foregroundStyle(changed ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let outcome = assistant.outcome(for: exercise) {
                        SidesOutcomeLines(outcome: outcome, name: exercise.name)
                    }
                    // Back keeps the choices here; nothing reaches the
                    // workouts before Done on the assistant's first page.
                    Text("Nothing is saved until you tap Done.")
                }
            }

            Section {
                ForEach(exercise.entries) { entry in
                    let isDeleted = assistant.deleted.contains(entry.id)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.date, format: .dateTime.day().month().year())
                                .font(.subheadline.weight(.semibold))
                                .strikethrough(isDeleted)
                            if !entry.workout.isEmpty {
                                Text(entry.workout)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Text("Logged \(entry.mode.title) · \(CountFormat.text(entry.sets, "set", "sets"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isDeleted {
                            Label("Deleted on Done", systemImage: "trash")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        } else {
                            Picker("Sides", selection: Binding(
                                get: { assistant.entrySides[entry.id] ?? SidesAssistant.Exercise.side(of: entry) },
                                set: { assistant.entrySides[entry.id] = $0 }
                            )) {
                                ForEach(ExerciseSides.choosable, id: \.self) { sides in
                                    Text(sides.title).tag(sides)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if isDeleted {
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                withAnimation { assistant.toggleDeleted(entry) }
                            }
                            .tint(.gray)
                        } else {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation { assistant.toggleDeleted(entry) }
                            }
                        }
                    }
                }
            } header: {
                Text("Entries")
            } footer: {
                Text("Swipe an entry to delete it — something tried out, not trained.")
            }
        }
        .onAppear { assistant.markOpened(exercise) }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
