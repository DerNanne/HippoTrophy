import SwiftUI
import SwiftData

/// Picks which exercises of a list to add. New ones come first and start checked.
/// An exercise already in the list is offered again only when the file can
/// still give it something — its muscle groups, when none are picked yet; one
/// that is already filed sits at the bottom and cannot be selected. The import
/// is always a merge, never a replace.
struct ImportExerciseListDetailView: View {
    let list: ImportableExerciseList
    var onImported: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]

    /// Holds the lowercased names, so a selection survives the list changing
    /// underneath and matches the way duplicates are detected.
    @State private var selected: Set<String> = []
    @State private var didPreselect = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var knownNames: Set<String> {
        Set(definitions.map(\.name.exerciseKey))
    }

    /// The definitions this list could still file, by lowercased name.
    private var fileable: [String: ExerciseDefinition] {
        var result: [String: ExerciseDefinition] = [:]
        for definition in definitions where definition.muscleGroupNames.isEmpty {
            result[definition.name.exerciseKey] = definition
        }
        return result
    }

    /// New exercises first, then the ones already here that muscle groups can
    /// still be added to, then the ones with nothing left to give. All in list
    /// order, so the list reads the way it is written.
    private var groupedExercises: (new: [ExerciseListEntry], fillable: [ExerciseListEntry], done: [ExerciseListEntry]) {
        let known = knownNames
        let open = fileable
        var new: [ExerciseListEntry] = []
        var fillable: [ExerciseListEntry] = []
        var done: [ExerciseListEntry] = []
        for exercise in list.exercises {
            let key = exercise.name.exerciseKey
            if !known.contains(key) {
                new.append(exercise)
            } else if open[key] != nil, !exercise.muscleGroupNames.isEmpty {
                fillable.append(exercise)
            } else {
                done.append(exercise)
            }
        }
        return (new, fillable, done)
    }

    var body: some View {
        let groups = groupedExercises
        let selectable = groups.new + groups.fillable
        let allSelected = !selectable.isEmpty && selected.count == selectable.count

        List {
            Section {
                ForEach(groups.new, id: \.name) { exercise in
                    selectableRow(exercise, note: nil)
                }

                ForEach(groups.fillable, id: \.name) { exercise in
                    selectableRow(exercise, note: "Already in your list · adds muscle groups only")
                }

                ForEach(groups.done, id: \.name) { exercise in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .foregroundStyle(.secondary)
                            Text("Already in your list")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    // Not a target: these rows have nothing to toggle.
                    .allowsHitTesting(false)
                }
            } footer: {
                if selectable.isEmpty {
                    Text("Every exercise in this list is already in your list, with its muscle groups.")
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        selected.removeAll()
                    } else {
                        selected = Set(selectable.map(\.name.exerciseKey))
                    }
                }
                .disabled(selectable.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            importButton(selectable: selectable, fillable: groups.fillable)
        }
        .onAppear {
            // New exercises start checked; only once, so returning to this screen
            // does not undo the user's deselections.
            guard !didPreselect else { return }
            didPreselect = true
            selected = Set(selectable.map(\.name.exerciseKey))
        }
        .alert("Import Exercise List", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func selectableRow(_ exercise: ExerciseListEntry, note: String?) -> some View {
        Button {
            toggle(exercise.name)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected(exercise.name) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected(exercise.name) ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .foregroundStyle(.primary)
                    MuscleGroupSummary(groups: exercise.muscleGroupNames.compactMap(MuscleGroup.from(raw:)))
                    if let note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func importButton(selectable: [ExerciseListEntry], fillable: [ExerciseListEntry]) -> some View {
        let count = selected.count
        // Counted apart, because the two do different things: only the new ones
        // make the list longer. Saying "Import 42" when 40 of them are already
        // there would promise the wrong thing.
        let fillCount = fillable.filter { selected.contains($0.name.exerciseKey) }.count
        let newCount = count - fillCount
        let title = importTitle(newCount: newCount, fillCount: fillCount)

        Button {
            performImport(selectable: selectable)
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                // The mixed label names both halves and does not fit on one
                // line, so it wraps — centred, or the second line hangs left.
                .multilineTextAlignment(.center)
                .foregroundStyle(count == 0 ? Color.secondary : Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    count == 0 ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Color.accentColor),
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func importTitle(newCount: Int, fillCount: Int) -> String {
        let imported = "Import \(CountFormat.text(newCount, "Exercise", "Exercises"))"
        let filed = "Add Muscle Groups to \(fillCount)"
        switch (newCount, fillCount) {
        case (0, 0):
            return "Nothing Selected"
        case (0, _):
            return "Add Muscle Groups to \(CountFormat.text(fillCount, "Exercise", "Exercises"))"
        case (_, 0):
            return imported
        default:
            // "existing" rather than a second "Exercises": both halves count
            // exercises, and the word that matters is which ones are already here.
            return "\(imported) · \(filed) existing"
        }
    }

    private func isSelected(_ name: String) -> Bool {
        selected.contains(name.exerciseKey)
    }

    private func toggle(_ name: String) {
        let key = name.exerciseKey
        if selected.contains(key) {
            selected.remove(key)
        } else {
            selected.insert(key)
        }
    }

    private func performImport(selectable: [ExerciseListEntry]) {
        // Re-check against the list at the moment of writing: the selection
        // was made against an older snapshot of it.
        let known = knownNames
        let open = fileable
        let picked = selectable.filter { selected.contains($0.name.exerciseKey) }

        var nextIndex = (definitions.map(\.orderIndex).max() ?? -1) + 1
        var inserted: [ExerciseDefinition] = []
        var filled: [ExerciseDefinition] = []

        for exercise in picked {
            let key = exercise.name.exerciseKey
            let muscles = exercise.muscleGroupNames

            if let existing = open[key] {
                // Only ever fills a gap: an entry that already carries muscle
                // groups is never offered here in the first place.
                guard !muscles.isEmpty, existing.muscleGroupNames.isEmpty else { continue }
                existing.muscleGroupNames = muscles
                filled.append(existing)
            } else if !known.contains(key) {
                let definition = ExerciseDefinition.insertPlainSetsAndReps(
                    name: exercise.name, orderIndex: nextIndex, muscleGroupNames: muscles, in: modelContext
                )
                inserted.append(definition)
                nextIndex += 1
            }
        }

        guard !inserted.isEmpty || !filled.isEmpty else {
            onImported()
            return
        }

        guard let failure = modelContext.save(reporting: "Could not add the exercises.") else {
            onImported()
            return
        }
        for entry in inserted {
            modelContext.delete(entry)
        }
        for entry in filled {
            entry.muscleGroupNames = []
        }
        alertMessage = failure
        showAlert = true
    }
}

#Preview {
    NavigationStack {
        ImportExerciseListDetailView(
            list: ImportableExerciseList(
                id: "preview",
                name: "Starter List",
                exercises: [
                    ExerciseListEntry(name: "Barbell Bench Press", muscleGroupNames: ["chest", "triceps"]),
                    ExerciseListEntry(name: "Pec Deck", muscleGroupNames: ["chest"]),
                    ExerciseListEntry(name: "Back Squat", muscleGroupNames: ["quads", "glutes"])
                ]
            ),
            onImported: {}
        )
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
