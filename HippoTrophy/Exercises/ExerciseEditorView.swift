import SwiftUI
import SwiftData

/// Configures one exercise: its name, what it logs, its muscles and category,
/// how it is trained and whether it can be assisted.
///
/// One question decides the fields, "What do you log?" — see `ExerciseLogKind`
/// — and a made-up workout under them shows what the answer means, which is
/// what keeps the footnotes short.
///
/// The same view creates one and edits one. Everything is held as a draft until
/// Save, so cancelling leaves nothing behind in the store — and so an edit can
/// show what saving would cost before anything is written.
///
/// Editing treats the definition as the truth for what follows it: a saved
/// rename or field change is pulled through every entry ever logged from it.
/// That is what `syncEntry(_:to:)` does, and why a structural change asks
/// first. Whether sets are tracked is the one thing that does *not* follow: an
/// entry was logged the way the exercise was at the time, and stays so.
struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]

    /// The definition being edited, `nil` while creating one.
    private let definition: ExerciseDefinition?
    /// Told about a new exercise once it is saved, before the editor goes.
    private let onCreated: ((ExerciseDefinition) -> Void)?

    @State private var name: String
    /// The picked category's name, "" for none.
    @State private var categoryName: String
    @State private var muscles: MuscleSelection
    @State private var tracksSets: Bool
    @State private var sides: ExerciseSides
    @State private var offersAssistance: Bool
    @State private var drafts: ExerciseFieldDrafts
    /// The picture as it would be saved, prepared by `PhotoFile`, and its
    /// framing.
    @State private var photo: PhotoDraft?
    @State private var kind: ExerciseLogKind
    /// A new exercise's category goes with what it logs until one is picked.
    @State private var categoryFollowsKind: Bool
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showNoMuscles = false
    @State private var showMusclePicker = false
    @State private var showConfirmation = false
    @State private var showDiscardConfirmation = false
    /// What the editor held once it opened, photo included; nil until then.
    @State private var opened: ExerciseEditorContent?
    /// The entries logged from this definition, read once when the editor opens.
    /// Their values are what `FieldChangeImpact` counts; they are what Save
    /// pulls into line.
    @State private var loggedEntries: [ExerciseEntry] = []

    init(definition: ExerciseDefinition? = nil, onCreated: ((ExerciseDefinition) -> Void)? = nil) {
        self.definition = definition
        self.onCreated = onCreated
        let stored = definition?.sortedFields ?? []
        _name = State(initialValue: definition?.name ?? "")
        _categoryName = State(initialValue: definition.map { ExerciseCategory.resolve($0.categoryName)?.name ?? "" } ?? ExerciseCategory.strength.name)
        _muscles = State(initialValue: MuscleSelection(
            primary: definition?.muscleGroupNames ?? [],
            secondary: definition?.secondaryMuscleGroupNames ?? []
        ))
        _tracksSets = State(initialValue: definition?.tracksSets ?? true)
        // Undecided is the assistant's to settle, never a choice here.
        _sides = State(initialValue: definition.map { $0.sides == .either ? .both : $0.sides } ?? .both)
        _offersAssistance = State(initialValue: definition?.offersAssistance ?? false)
        // A new exercise starts as the usual case, sets of weight and reps.
        _drafts = State(initialValue: ExerciseFieldDrafts(
            definition == nil ? FieldType.standard.map(FieldDraft.init(standard:)) : stored.map(FieldDraft.init(stored:)),
            keysInUse: stored.map(\.key)
        ))
        _kind = State(initialValue: definition.map { definition in
            ExerciseLogKind.of(fieldTypes: stored.map(\.type), tracksSets: definition.tracksSets)
        } ?? .weightAndReps)
        _categoryFollowsKind = State(initialValue: definition == nil)
    }

    /// A new exercise that starts as a copy of `template` — the way to change
    /// a catalog exercise, which itself stays as the catalog has it. The copy
    /// is the user's own and needs a name of its own: one name, one exercise.
    init(copying template: ExerciseDefinition) {
        self.init(definition: nil)
        _name = State(initialValue: template.name)
        _categoryName = State(initialValue: ExerciseCategory.resolve(template.categoryName)?.name ?? "")
        _categoryFollowsKind = State(initialValue: false)
        _muscles = State(initialValue: MuscleSelection(
            primary: template.muscleGroupNames,
            secondary: template.secondaryMuscleGroupNames
        ))
        _tracksSets = State(initialValue: template.tracksSets)
        _sides = State(initialValue: template.sides == .either ? .both : template.sides)
        _offersAssistance = State(initialValue: template.offersAssistance)
        let fields = template.sortedFields
        _drafts = State(initialValue: ExerciseFieldDrafts(
            fields.map { field in
                var draft = FieldDraft(key: field.key)
                draft.label = field.label
                draft.type = field.type
                return draft
            },
            keysInUse: fields.map(\.key)
        ))
        _kind = State(initialValue: ExerciseLogKind.of(fieldTypes: fields.map(\.type), tracksSets: template.tracksSets))
    }

    private var isEditing: Bool { definition != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var content: ExerciseEditorContent {
        ExerciseEditorContent(
            name: name,
            categoryName: categoryName,
            muscles: muscles,
            tracksSets: tracksSets,
            sides: sides,
            offersAssistance: offersAssistance,
            kind: kind,
            drafts: drafts,
            photo: photo
        )
    }

    private var hasChanges: Bool {
        opened.map { $0 != content } ?? false
    }

    /// Answers "What do you log?". The edits land in the draft rather than the
    /// store, so the impact lines count what saving would cost before anything
    /// happens.
    private func pick(_ picked: ExerciseLogKind) {
        guard picked != kind else { return }
        switch picked {
        case .weightAndReps:
            guard drafts.canBecomeWeightAndReps else {
                alertMessage = "Weight & Reps needs two fields of its own, and an exercise has room for \(ExerciseDefinition.maxFields). Remove one first."
                showAlert = true
                return
            }
            drafts.becomeWeightAndReps()
            tracksSets = true
        case .custom:
            drafts.becomeCustom()
        }
        kind = picked
        if categoryFollowsKind {
            categoryName = picked.startingCategory?.name ?? ""
        }
    }

    /// The category as the menu sets it: a pick of the user's own, which
    /// stops following what the exercise logs.
    private var pickedCategory: Binding<String> {
        Binding(
            get: { categoryName },
            set: {
                categoryName = $0
                categoryFollowsKind = false
            }
        )
    }

    /// The workouts turning sets off would split, 0 while nothing would.
    private var splitWorkoutCount: Int {
        guard let definition, definition.tracksSets, !tracksSets else { return 0 }
        return ExerciseSplitting.entriesWithSeveralSets(loggedEntries).trainedWorkoutCount
    }

    /// Help stands in for the weight, so there is none to offer without it —
    /// and none in an exercise logged once, which has no sets to help with.
    private var canOfferAssistance: Bool {
        tracksSets && drafts.active.contains { $0.type == .weight }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !drafts.hasUntitled && !drafts.labelled.isEmpty
    }

    /// Spelt out only once the name has actually changed and there is history to
    /// carry: on an exercise nobody has trained yet a rename costs nothing, and
    /// saying so would be noise on every visit.
    private var renameNote: String? {
        guard let definition, !trimmedName.isEmpty,
              definition.name.exerciseKey != trimmedName.exerciseKey
        else { return nil }

        let count = loggedEntries.trainedWorkoutCount
        guard count > 0 else { return nil }
        let subject = CountFormat.text(count, "workout", "workouts")
        let follows = count == 1 ? "It is renamed with it" : "They are renamed with it"
        return "\(subject) logged this exercise as \"\(definition.name)\". \(follows), so its history stays where you can find it."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(isEditing ? "Edit Exercise" : "New Own Exercise")
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    TextField("Name, e.g. Rowing", text: $name)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let renameNote {
                            Text(renameNote)
                        }
                        if ExerciseNaming.catalogExercise(named: trimmedName) != nil {
                            Text(ExerciseNaming.catalogNameHint)
                        }
                    }
                }

                PhotoSection(photo: $photo, aspectRatio: ExercisePictogram.aspectRatio)

                ExerciseLogKindSection(selection: kind, onPick: pick)

                ExerciseFieldsSection(kind: kind, drafts: $drafts, impact: impact)

                if kind == .custom {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Does it have sets?")
                            Picker("Does it have sets?", selection: $tracksSets) {
                                Text("Has sets").tag(true)
                                Text("No sets").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tracksSets ? "Add as many sets as you do." : "One entry, like a run or a stretch.")
                            if let splitNote = FieldChangeImpact.splitText(workouts: splitWorkoutCount) {
                                Text(splitNote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                ExercisePreviewSection(preview: preview)

                Section {
                    MuscleGroupsRow(selection: $muscles)
                    ExerciseCategoryRow(categoryName: pickedCategory)
                } footer: {
                    Text("The muscle heat map counts Strength unless you add more.")
                }

                // Sides divide the sets into a left and a right list, so an
                // exercise without sets has nothing to divide.
                if tracksSets {
                    ExerciseSidesSection(selection: $sides)
                }

                if canOfferAssistance {
                    ExerciseAssistanceSection(isOn: $offersAssistance)
                }
            }
            // The form draws its own large title, so it does not need the
            // inset a list normally leaves below a navigation bar.
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        if hasChanges {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .modifier(DiscardChangesConfirmation(
                isPresented: $showDiscardConfirmation,
                onDiscard: { dismiss() }
            ))
            .task {
                // Coming back from the muscles runs this again, and what was
                // picked in the meantime stays.
                guard opened == nil else { return }
                loadLoggedEntries()
                photo = definition?.ownPhoto.map { PhotoDraft(data: $0.data, framing: $0.framing) }
                opened = content
            }
            .alert("Exercise", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert("Save Without Muscle Groups?", isPresented: $showNoMuscles) {
                Button("Choose Muscle Groups") { showMusclePicker = true }
                Button("Save Anyway") { applyOrConfirm() }
            } message: {
                Text("Its sets won't count on the muscle heat map or under Muscle Groups.")
            }
            .navigationDestination(isPresented: $showMusclePicker) {
                MuscleGroupsPage(selection: $muscles)
            }
            .alert("Apply Changes?", isPresented: $showConfirmation) {
                Button("Apply", role: impact.losesData ? .destructive : nil) { commit() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(impact.message)
            }
        }
    }

    /// How the exercise will look in a workout, as far as it is set up.
    private var preview: ExercisePreview {
        ExercisePreview(
            fields: drafts.activeInSetOrder.map { (label: $0.label, type: $0.type) },
            tracksSets: tracksSets,
            weightSymbol: WeightUnit.current.symbol
        )
    }

    // MARK: - What saving would do

    /// What saving would do to what is already logged. Nothing while creating:
    /// a new exercise has no history to reach into.
    private var impact: FieldChangeImpact {
        guard isEditing else {
            return FieldChangeImpact(fields: [], loggedValues: [], loggedWorkoutCount: 0)
        }
        let values = loggedEntries.flatMap { entry in
            entry.sets.flatMap(\.values).map { value in
                FieldChangeImpact.LoggedValue(
                    fieldKey: value.fieldKey,
                    label: value.label,
                    type: value.type,
                    textValue: value.textValue,
                    numberValue: value.numberValue,
                    workoutID: entry.session?.id
                )
            }
        }
        return FieldChangeImpact(
            fields: drafts.all,
            loggedValues: values,
            loggedWorkoutCount: loggedEntries.trainedWorkoutCount,
            splitWorkoutCount: splitWorkoutCount
        )
    }

    private func loadLoggedEntries() {
        guard let definition else { return }
        loggedEntries = ExerciseHistory.fetch(in: modelContext).entries(loggedFrom: definition.id)
    }

    // MARK: - Saving

    private func save() {
        guard canSave else { return }

        // Only the user's own exercises compete for a name; a catalog exercise
        // of it may be there too.
        guard ExerciseNaming.isFree(
            trimmedName,
            amongOwn: definitions.filter { $0.id != definition?.id }.map { ($0.name, $0.catalogKey) }
        ) else {
            alertMessage = "An exercise named \"\(trimmedName)\" already exists."
            showAlert = true
            return
        }

        if muscles.asksBeforeSaving(categoryName: categoryName) {
            showNoMuscles = true
        } else {
            applyOrConfirm()
        }
    }

    private func applyOrConfirm() {
        // Renaming, refiling, retitling and reordering cost nothing and save
        // straight away. Adding, deleting or retyping a field reaches into what
        // is already logged, and is confirmed first.
        if impact.isEmpty {
            commit()
        } else {
            showConfirmation = true
        }
    }

    private func commit() {
        let wasTrackingSets = definition?.tracksSets ?? tracksSets
        let saved: ExerciseDefinition
        if let definition {
            saved = definition
        } else {
            saved = ExerciseDefinition(name: trimmedName, orderIndex: (definitions.map(\.orderIndex).max() ?? -1) + 1)
            modelContext.insert(saved)
        }
        saved.name = trimmedName
        saved.categoryName = ExerciseCategory.resolve(categoryName)?.name ?? ""
        saved.muscleGroupNames = muscles.primary
        saved.secondaryMuscleGroupNames = muscles.secondary
        saved.tracksSets = tracksSets
        saved.sides = sides
        saved.offersAssistance = offersAssistance && canOfferAssistance
        if photo != saved.ownPhoto.map({ PhotoDraft(data: $0.data, framing: $0.framing) }) {
            saved.setPhoto(photo, in: modelContext)
        }

        applyFields(drafts.labelledInSetOrder, to: saved)
        for entry in loggedEntries {
            syncEntry(entry, to: saved)
        }
        if wasTrackingSets, !tracksSets {
            ExerciseSplitting.splitIntoSingleSets(loggedEntries, in: modelContext)
        }

        if let failure = modelContext.save(reporting: "Could not save exercise.") {
            alertMessage = failure
            showAlert = true
        } else {
            if definition == nil {
                onCreated?(saved)
            }
            dismiss()
        }
    }

    /// Writes the drafts onto the stored fields: existing ones updated in place
    /// so their key survives, new ones inserted, dropped ones deleted by hand —
    /// the cascade only fires when the whole definition goes, and a field left
    /// behind would linger with no definition at all.
    private func applyFields(_ drafts: [FieldDraft], to definition: ExerciseDefinition) {
        var keptKeys = Set<String>()

        for (index, draft) in drafts.enumerated() {
            let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
            keptKeys.insert(draft.key)

            if let storedID = draft.storedID,
               let field = definition.fields.first(where: { $0.id == storedID }) {
                field.label = label
                field.type = draft.type
                field.orderIndex = index
            } else {
                let field = FieldDefinition(
                    key: draft.key,
                    label: label,
                    typeRawValue: draft.type.rawValue,
                    orderIndex: index,
                    definition: definition
                )
                definition.fields.append(field)
                modelContext.insert(field)
            }
        }

        for field in definition.fields.filter({ !keptKeys.contains($0.key) }) {
            definition.fields.removeAll { $0.id == field.id }
            modelContext.delete(field)
        }
    }

    /// Pulls one logged entry into line with the definition it came from: the
    /// name, and in every set the field titles and their order, a converted
    /// value where the type changed, an empty value where a field was added,
    /// and nothing at all where a field was deleted.
    private func syncEntry(_ entry: ExerciseEntry, to definition: ExerciseDefinition) {
        entry.name = definition.name
        entry.catalogKey = definition.catalogKey
        let fields = definition.sortedFields
        let keys = Set(fields.map(\.key))

        for set in entry.sets {
            // A field added later has nothing behind it in a workout that
            // predates it. It arrives empty, which is what says so — a zero
            // would claim something was measured.
            ExerciseMerging.align(set, to: definition, keyRewrite: [:], in: modelContext)
            for value in set.values.filter({ !keys.contains($0.fieldKey) }) {
                set.values.removeAll { $0.id == value.id }
                modelContext.delete(value)
            }
        }
    }
}

#Preview {
    ExerciseEditorView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
