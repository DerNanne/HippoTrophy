import SwiftUI
import SwiftData

/// Picks an exercise for a workout, or makes a new one on the spot. The same
/// exercises to look through as the Exercises tab: the plus adds one, a tap on
/// it shows it first.
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]

    var onSelect: (ExerciseDefinition) -> Void
    /// Offered only when the caller can act on it — a superset needs two
    /// exercises picked together, which is not something every picker call
    /// site has a use for.
    var onSelectSuperset: (([ExerciseDefinition]) -> Void)?

    @State private var filter = ExerciseFilter()
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var selectingSuperset = false
    /// In tap order, so the first pick is "A" and the second "B" — the order
    /// they end up alternating in once the superset is in the workout.
    @State private var supersetPicks: [ExerciseDefinition] = []
    /// Whether the search field is active. Picking a superset's second
    /// exercise closes it, so what is picked and "Create" are in view at once.
    @FocusState private var isSearching: Bool
    @State private var openedDefinition: ExerciseDefinition?
    @State private var showNewEditor = false
    /// What the editor just made, picked once its sheet is gone.
    @State private var createdDefinition: ExerciseDefinition?
    @AppStorage(SettingsKey.pickerMuscleFilter) private var storedMuscle = ""

    init(onSelect: @escaping (ExerciseDefinition) -> Void, onSelectSuperset: (([ExerciseDefinition]) -> Void)? = nil) {
        self.onSelect = onSelect
        self.onSelectSuperset = onSelectSuperset
    }

    /// The muscle is remembered across openings: the picker opens anew for
    /// every exercise, and a chest day should not mean picking Chest each time.
    private var rememberedFilter: Binding<ExerciseFilter> {
        Binding(
            get: {
                var remembered = filter
                remembered.muscle = MuscleFilter(stored: storedMuscle)
                return remembered
            },
            set: {
                filter = $0
                storedMuscle = $0.muscle?.stored ?? ""
            }
        )
    }

    var body: some View {
        NavigationStack {
            // Whether an exercise is trained one-sided is not decided here:
            // a picked exercise arrives with the mode it was last logged
            // with, and is switched over on its row in the editor.
            ExerciseBrowser(
                definitions: definitions,
                filter: rememberedFilter,
                searchFocused: $isSearching,
                onNew: selectingSuperset ? nil : { showNewEditor = true },
                onAdd: selectingSuperset ? nil : { addExercise(named: $0) },
                onOpen: { definition in
                    if selectingSuperset {
                        toggleSupersetPick(definition)
                    } else {
                        openedDefinition = definition
                    }
                },
                isDimmed: { selectingSuperset && supersetPicks.count == 2 && supersetPickIndex($0) == nil },
                accessory: accessory
            )
            .navigationTitle(selectingSuperset ? "\(supersetPicks.count) of 2 for a Superset" : "Add Exercise")
            // Inline: above a bar the large title has no room to stand.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ExerciseGridToggle()
                }
                if selectingSuperset {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            selectingSuperset = false
                            supersetPicks = []
                        }
                    }
                } else {
                    if onSelectSuperset != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                selectingSuperset = true
                            } label: {
                                Label("Superset", systemImage: "link")
                            }
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selectingSuperset {
                    supersetBar
                }
            }
            .sheet(item: $openedDefinition) { definition in
                ExerciseDetailView(definition: definition)
            }
            .sheet(isPresented: $showNewEditor, onDismiss: pickCreated) {
                ExerciseEditorView(onCreated: { createdDefinition = $0 })
            }
            .alert("Add Exercise", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    /// The plus, or while picking a superset the letter it would alternate as.
    @ViewBuilder
    private func accessory(_ definition: ExerciseDefinition) -> some View {
        if selectingSuperset {
            Button {
                toggleSupersetPick(definition)
            } label: {
                supersetMarker(for: definition)
            }
            .buttonStyle(.borderless)
        } else {
            Button {
                onSelect(definition)
                dismiss()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add \(definition.name)")
        }
    }

    private func pickCreated() {
        guard let createdDefinition else { return }
        onSelect(createdDefinition)
        dismiss()
    }

    /// The letter a pick would alternate as once the superset is in the
    /// workout — "A" first, "B" second — or an empty circle before it is picked.
    @ViewBuilder
    private func supersetMarker(for definition: ExerciseDefinition) -> some View {
        if let index = supersetPickIndex(definition) {
            Text(index == 0 ? "A" : "B")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
        } else {
            Circle()
                .strokeBorder(Color(.tertiaryLabel), lineWidth: 1.5)
                .frame(width: 22, height: 22)
        }
    }

    private func supersetPickIndex(_ definition: ExerciseDefinition) -> Int? {
        supersetPicks.firstIndex { $0.id == definition.id }
    }

    /// A pick while searching clears the search, because the next thing to
    /// look for is the other exercise; the second pick also closes it, so the
    /// bar with "Create" is not hidden behind the keyboard.
    private func toggleSupersetPick(_ definition: ExerciseDefinition) {
        if let index = supersetPickIndex(definition) {
            supersetPicks.remove(at: index)
            return
        }
        guard supersetPicks.count < 2 else { return }
        supersetPicks.append(definition)
        filter.query = ""
        if supersetPicks.count == 2 {
            isSearching = false
        }
    }

    /// What is picked so far and the way to make it a superset, pinned above
    /// the keyboard so it stays in reach while searching.
    private var supersetBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                pickLine("A", supersetPicks.first)
                pickLine("B", supersetPicks.dropFirst().first)
            }
            Spacer(minLength: 8)
            Button("Create") {
                onSelectSuperset?(supersetPicks)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(supersetPicks.count != 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func pickLine(_ letter: String, _ definition: ExerciseDefinition?) -> some View {
        HStack(spacing: 6) {
            Text(letter)
                .font(.caption2.weight(.bold))
                .foregroundStyle(definition == nil ? Color.secondary : Color.accentColor)
            Text(definition?.name ?? "Pick an exercise")
                .font(.subheadline)
                .foregroundStyle(definition == nil ? .secondary : .primary)
                .lineLimit(1)
        }
    }

    /// A typed name that matches an existing exercise picks that one; anything
    /// else becomes a new definition first, so every entry has one to follow.
    private func addExercise(named trimmed: String) {
        // The user's own exercise of that name before the catalog's: it is
        // the one they made.
        if let index = ExerciseNaming.match(
            identity: .own(trimmed.exerciseKey), name: trimmed,
            among: definitions.map { (identity: $0.identity, name: $0.name) }
        ) {
            let existing = definitions[index]
            onSelect(existing)
            dismiss()
            return
        }

        let definition = ExerciseDefinition.insertPlainSetsAndReps(
            name: trimmed, orderIndex: (definitions.map(\.orderIndex).max() ?? -1) + 1, in: modelContext
        )
        if let failure = modelContext.save(reporting: "\"\(trimmed)\" could not be saved to your exercise list.") {
            // Only the row that failed is taken back. A `rollback()` would
            // reach the whole context, and the editor behind this sheet holds
            // reps and weights that are typed straight onto the model and not
            // saved on every keystroke.
            modelContext.delete(definition)
            alertMessage = failure
            showAlert = true
            return
        }
        onSelect(definition)
        dismiss()
    }
}

/// Name, category, muscles and what gets logged — the same row in the picker
/// and the settings list, so an exercise reads the same in both.
///
/// A catalog exercise leads with its pictogram. Among catalog exercises an
/// own one keeps the space empty, so the names stay in one column; a list of
/// own exercises only gives none.
struct ExerciseDefinitionRow: View {
    let definition: ExerciseDefinition
    var amongCatalog = true
    @ScaledMetric(relativeTo: .body) private var pictogramWidth: CGFloat = 54

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if definition.isCatalog {
                ExercisePictogram(definition: definition)
                    .frame(width: pictogramWidth)
            } else if let photo = definition.ownPhoto {
                ExercisePhotoTile(photo: photo)
                    .frame(width: pictogramWidth)
            } else if amongCatalog {
                Color.clear
                    .aspectRatio(ExercisePictogram.aspectRatio, contentMode: .fit)
                    .frame(width: pictogramWidth)
            }
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(definition.name)
                    .foregroundStyle(.primary)
                if let category = definition.category, category != .strength {
                    ExerciseCategoryBadge(category: category)
                }
            }
            if let summary = definition.fieldSummary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // The badge right of the muscle groups; on a line of its own when
            // the two do not fit side by side.
            if definition.isUserDefined {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        MuscleGroupSummary(groups: definition.muscleGroups, secondary: definition.secondaryMuscleGroups).lineLimit(1)
                        UserDefinedBadge()
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        MuscleGroupSummary(groups: definition.muscleGroups, secondary: definition.secondaryMuscleGroups)
                        UserDefinedBadge()
                    }
                }
            } else {
                MuscleGroupSummary(groups: definition.muscleGroups, secondary: definition.secondaryMuscleGroups)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
