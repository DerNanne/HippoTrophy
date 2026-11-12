import SwiftUI
import SwiftData
import UIKit

struct WorkoutEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query private var definitions: [ExerciseDefinition]

    let session: WorkoutSession
    var discardSessionOnCancel = false
    /// The workout being trained, pushed onto the start screen: Back leaves
    /// it running, the clock and the rest are its, and Discard sits in the
    /// menu. Otherwise the editor covers the screen with Cancel and Save.
    var isBeingTrained = false
    /// The day variant the workout was started from: removed when the
    /// workout is saved, in the same save, as it has been trained. Cancel
    /// leaves it for another go.
    var usesUp: WorkoutSession?

    @State private var showExercisePicker = false
    @State private var workoutName = ""
    @State private var notes = ""
    @State private var didInitialize = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showExerciseReorder = false
    @State private var showDatePicker = false
    @State private var selectedSides: [UUID: ExerciseSide] = [:]
    @State private var pendingModeChange: PendingModeChange?
    @State private var pendingEffortScaleChange: PendingEffortScaleChange?
    @State private var noteExerciseID: UUID?
    @State private var draftExerciseNote = ""
    @State private var draftExerciseInstructions = ""
    @State private var historyExerciseID: UUID?
    @State private var historyHintExerciseID: UUID?
    @State private var convertingExerciseID: UUID?
    @State private var identitiesWithHistory: Set<ExerciseIdentity> = []
    /// The last logged entry per lowercased exercise name, collected with
    /// `identitiesWithHistory` from the same fetch.
    @State private var lastPerformances: [ExerciseIdentity: LastPerformance] = [:]
    @State private var keyboardVisible = false
    /// Folded cards, by `foldKey(for:)`: a standalone exercise's own id, or
    /// its superset's id — a superset folds as one card, like an exercise.
    @State private var collapsedExerciseIDs: Set<UUID> = []
    @State private var initialSnapshot: WorkoutSnapshot?
    @State private var showDiscardConfirmation = false
    /// When Finish was tapped, which ends the workout even while Finish
    /// still asks about its open sets.
    @State private var finishedAt: Date?
    /// The sets not ticked off when a new workout is first saved, while
    /// Save asks what becomes of them.
    @State private var openSetsOnSave: [SetEntry] = []
    @AppStorage(SettingsKey.collapseOtherExercises) private var collapseOtherExercises = false
    @AppStorage(SettingsKey.showLastPerformance) private var showLastPerformance = true
    @AppStorage(SettingsKey.showExerciseTexts) private var showExerciseTexts = true
    @AppStorage(SettingsKey.startWithOneSet) private var startWithOneSet = false
    /// What this editor changed for itself, while it is not on a workout
    /// being trained; see `editorOverrides`.
    @State private var localEditorOverrides = EditorSettingsOverrides()
    @State private var showEditorSettings = false
    @AppStorage(SettingsKey.weightUnit) private var weightUnitRaw = WeightUnit.kilograms.rawValue
    @AppStorage(SettingsKey.defaultRestSeconds) private var defaultRest = RestDuration.defaultSeconds
    @AppStorage(SettingsKey.betweenSidesRestSeconds) private var betweenSidesRest = RestDuration.defaultBetweenSidesSeconds
    @AppStorage(SettingsKey.guideThroughWorkout) private var guideThroughWorkout = true
    @AppStorage(SettingsKey.sideLayout) private var sideLayout = SideLayout.standard
    /// The set field the cursor is in, by its value's id.
    @FocusState private var focusedField: UUID?
    /// A set the guide moves to: its card opens, the list scrolls to it and
    /// the cursor goes into its first field.
    @State private var guideTarget: UUID?
    /// Whether the guide also puts the cursor in the target set. Only Next
    /// on the keyboard does: the keyboard is up then, and stays. A tick on a
    /// set, or the end of a rest, only shows where to go on — a keyboard that
    /// comes up unasked covers the screen for someone who just ticks.
    @State private var guideFocusesField = false
    private let restTimer = RestTimerCenter.shared
    private let runningWorkout = RunningWorkoutCenter.shared
    @State private var keyboardFreeListSize: CGSize = .zero
    @FocusState private var notesFocused: Bool

    private static let notesFieldID = "notes-field"
    // How much of the list the note may claim at most. A fixed share, rather
    // than "whatever the keyboard leaves over", keeps the field's height the
    // same whether the keyboard is up or not: a field that resizes underneath
    // an open keyboard leaves the list row and the text inside it out of step,
    // which shows up as a dead strip that swallows a line of text. The quarter
    // that stays list is what is left to tap and scroll once the note fills
    // everything else.
    private static let notesFieldHeightShare: CGFloat = 0.75

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .kilograms
    }

    /// What the editor goes by: Settings, and what this workout changed.
    private var settings: EditorSettings {
        editorOverrides.wrappedValue.applied(to: editorDefaults)
    }

    private var editorDefaults: EditorSettings {
        EditorSettings(
            collapseOtherExercises: collapseOtherExercises,
            showLastPerformance: showLastPerformance,
            showExerciseTexts: showExerciseTexts,
            startWithOneSet: startWithOneSet,
            guideThroughWorkout: guideThroughWorkout,
            defaultRestSeconds: defaultRest,
            betweenSidesRestSeconds: betweenSidesRest,
            effortScale: .forNewEntries,
            sideLayout: sideLayout
        )
    }

    /// A workout being trained keeps its changes with it, as the editor may
    /// be left and the app quit meanwhile; anything else only while open.
    private var editorOverrides: Binding<EditorSettingsOverrides> {
        Binding(
            get: { isBeingTrained ? runningWorkout.running?.editorOverrides ?? EditorSettingsOverrides() : localEditorOverrides },
            set: { overrides in
                if isBeingTrained {
                    runningWorkout.setEditorOverrides(overrides)
                } else {
                    localEditorOverrides = overrides
                }
            }
        )
    }

    private var sortedExercises: [ExerciseEntry] {
        session.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Whether the editor guides through the sets: a workout being trained,
    /// with the setting on. A workout opened again was trained already.
    private var guides: Bool {
        settings.guideThroughWorkout && isBeingTrained
    }

    /// When the workout being trained began, for the clock at the top and
    /// the duration Finish keeps. Nil for one not timed: a template, a
    /// workout opened again, or one whose date was moved, which is being
    /// logged afterwards.
    private var startedAt: Date? {
        isBeingTrained ? runningWorkout.running?.startedAt : nil
    }

    /// The set to do next, highlighted while the editor guides.
    private var currentSetID: UUID? {
        guard guides else { return nil }
        let order = guideOrder
        return WorkoutGuide.current(done: order.map(\.isDone)).map { order[$0].id }
    }

    private func definition(of exercise: ExerciseEntry) -> ExerciseDefinition? {
        definitions.first { $0.id == exercise.definitionID }
    }

    private func tracksSets(_ exercise: ExerciseEntry) -> Bool {
        exercise.tracksSets(among: definitions)
    }

    /// The modes an entry's menu offers, empty for none: what fits how the
    /// exercise is trained, plus whatever the entry already has — what is
    /// written down stays reachable. Without its definition, an entry offers
    /// only a way back to two-sided.
    private func modeChoices(_ exercise: ExerciseEntry) -> [UnilateralMode] {
        guard tracksSets(exercise) else { return [] }
        let sides = definition(of: exercise)?.sides ?? .both
        return sides.choices(current: exercise.unilateralMode)
    }

    /// The kinds of help an entry's menu offers, empty for none — see
    /// `Assistance.choices`.
    private func assistanceChoices(_ exercise: ExerciseEntry) -> [Assistance] {
        guard tracksSets(exercise) else { return [] }
        return Assistance.choices(offered: definition(of: exercise)?.offersAssistance ?? false, current: exercise.assistance)
    }

    // Keeps the caret in sight: the list has to be told to follow the field as
    // it grows, otherwise the newest line ends up behind the keyboard.
    private func scrollToNotesField(_ proxy: ScrollViewProxy) {
        guard notesFocused else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.notesFieldID, anchor: .bottom)
        }
    }

    // How far the notes field may grow before a long note starts scrolling
    // inside it instead of stretching the list further.
    private var noteLineLimit: Int {
        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        guard keyboardFreeListSize.height > 0, lineHeight > 0 else { return 12 }

        return max(3, Int(keyboardFreeListSize.height * Self.notesFieldHeightShare / lineHeight))
    }

    // Pulled out of the list so the body stays small enough for the
    // compiler to type-check quickly.
    private var exerciseGroups: [[ExerciseEntry]] {
        ExerciseGrouping.groups(sortedExercises)
    }

    @ViewBuilder private var exerciseSections: some View {
        if sortedExercises.isEmpty {
            Section("Exercises") {
                Text("Add your first exercise to start logging sets.")
                    .foregroundStyle(.secondary)
            }
            // Match the air the last exercise card leaves above the action row.
            .listSectionSpacing(24)
        }

        if !sortedExercises.isEmpty {
            let groups = exerciseGroups
            ForEach(Array(groups.enumerated()), id: \.offset) { offset, group in
                groupSection(group, isFirst: offset == 0, isLast: offset == groups.count - 1)
            }
        }
    }

    /// One exercise's own card, or a superset's. Its own function so the
    /// type-checker meets one section at a time instead of the whole list.
    @ViewBuilder
    private func groupSection(_ group: [ExerciseEntry], isFirst: Bool, isLast: Bool) -> some View {
        Section {
            if let pair = SupersetPair(group) {
                supersetCard(pair)
            } else {
                ForEach(group) { exercise in
                    exerciseCard(exercise)
                }
            }
        } header: {
            if isFirst {
                Text("Exercises")
            }
        }
        // The exercise cards sit close together as one group, but the
        // action row below them starts something new and needs air.
        .listSectionSpacing(isLast ? 24 : 8)
    }

    private func supersetCard(_ pair: SupersetPair) -> some View {
        SupersetCardView(
            a: supersetMember(pair.a),
            b: supersetMember(pair.b),
            isCollapsed: collapsedExerciseIDs.contains(foldKey(for: pair.a)),
            orderedSets: pair.orderedSets,
            weightUnit: weightUnit,
            restSeconds: definition(of: pair.b)?.restSeconds,
            defaultRest: settings.defaultRestSeconds,
            currentSetID: currentSetID,
            setRest: { setRest($0, on: pair.b) },
            toggleCollapsed: { toggleCollapsed(key: foldKey(for: pair.a)) },
            setActions: SupersetCardView.SetActions(
                deleteSet: { set in
                    pair.deleteSet(set, in: modelContext)
                    _ = saveContext("Could not delete set.")
                },
                copySet: { set in
                    pair.copySet(set, in: modelContext)
                    _ = saveContext("Could not copy set.")
                },
                effortChanged: { _ = saveContext("Could not update set effort.") },
                moveSets: { source, destination in
                    pair.moveSets(from: source, to: destination)
                    _ = saveContext("Could not reorder sets.")
                }
            )
        )
    }

    private func supersetMember(_ exercise: ExerciseEntry) -> SupersetCardView.Member {
        SupersetCardView.Member(
            exercise: exercise,
            tracksSets: tracksSets(exercise),
            modeChoices: modeChoices(exercise),
            assistanceChoices: assistanceChoices(exercise),
            hasHistory: hasHistory(for: exercise),
            showsHistoryHint: historyHintExerciseID == exercise.id,
            lastPerformance: settings.showLastPerformance ? lastPerformances[exercise.identity] : nil,
            machineMenu: machineMenu(for: exercise),
            actions: SupersetCardView.MemberActions(
                setMode: { setMode($0, on: exercise) },
                setAssistance: { setAssistance($0, on: exercise) },
                openNote: { openNote(for: exercise) },
                tapHistory: { tapHistory(for: exercise) },
                openHistory: { historyExerciseID = exercise.id },
                delete: { deleteExercise(exercise) },
                addSet: { addSet(to: exercise) },
                setEffortScale: { setEffortScale($0, on: exercise) },
                setStartSide: { setStartSide($0, of: exercise) }
            )
        )
    }

    private func openNote(for exercise: ExerciseEntry) {
        noteExerciseID = exercise.id
        draftExerciseNote = exercise.notes
        draftExerciseInstructions = exercise.instructions
    }

    private func tapHistory(for exercise: ExerciseEntry) {
        if hasHistory(for: exercise) {
            historyExerciseID = exercise.id
        } else {
            withAnimation { historyHintExerciseID = exercise.id }
        }
    }

    /// The superset an entry belongs to, when it is one of two.
    private func pair(for exercise: ExerciseEntry) -> SupersetPair? {
        guard let supersetID = exercise.supersetID else { return nil }
        return SupersetPair(sortedExercises.filter { $0.supersetID == supersetID })
    }

    /// Whether an exercise can join a superset: not already in one, and not
    /// holding sets on both sides — left/right does not interleave, and
    /// merging the two sides on the way in would decide that silently.
    private func canJoinSuperset(_ exercise: ExerciseEntry) -> Bool {
        exercise.supersetID == nil && !exercise.holdsBothSides
    }

    /// The machine an exercise is done at, picked from those in the workout's
    /// gym first.
    private func machineMenu(for exercise: ExerciseEntry) -> MachineMenu {
        MachineMenu(
            machine: exercise.machine,
            choices: GymChoices.machines(at: session.gym, among: machines),
            gymName: session.gym?.name
        ) { machine in
            GymChoices.pick(machine, for: exercise)
            _ = saveContext("Could not save the machine.")
        } onAdd: { typed in
            if let name = GymChoices.newName(typed, among: machines.map(\.name)) {
                GymChoices.pick(GymChoices.addMachine(named: name, at: session.gym, in: modelContext), for: exercise)
            } else if let existing = machines.first(where: { $0.name.exerciseKey == typed.exerciseKey }) {
                GymChoices.pick(existing, for: exercise)
            }
            _ = saveContext("Could not save the machine.")
        }
    }

    /// A gym named in the menu: a new one, or the one of that name already
    /// there.
    private func addGym(named typed: String) {
        if let name = GymChoices.newName(typed, among: gyms.map(\.name)) {
            session.gym = GymChoices.addGym(named: name, in: modelContext)
        } else if let existing = gyms.first(where: { $0.name.exerciseKey == typed.exerciseKey }) {
            session.gym = existing
        }
        _ = saveContext("Could not save the gym.")
    }

    /// What folds together: a superset's members share one key, everything
    /// else folds on its own.
    private func foldKey(for exercise: ExerciseEntry) -> UUID {
        exercise.supersetID ?? exercise.id
    }

    /// One exercise's card, given what the editor knows about it and what a
    /// tap on it does here.
    private func exerciseCard(_ exercise: ExerciseEntry) -> some View {
        ExerciseCardView(
            exercise: exercise,
            isCollapsed: collapsedExerciseIDs.contains(foldKey(for: exercise)),
            tracksSets: tracksSets(exercise),
            modeChoices: modeChoices(exercise),
            assistanceChoices: assistanceChoices(exercise),
            hasHistory: hasHistory(for: exercise),
            showsHistoryHint: historyHintExerciseID == exercise.id,
            lastPerformance: settings.showLastPerformance ? lastPerformances[exercise.identity] : nil,
            weightUnit: weightUnit,
            canConvertToSuperset: canJoinSuperset(exercise)
                && sortedExercises.contains { $0.id != exercise.id && canJoinSuperset($0) },
            displayedSets: displayedSets(in: exercise),
            restSeconds: definition(of: exercise)?.restSeconds,
            defaultRest: settings.defaultRestSeconds,
            currentSetID: currentSetID,
            selectedSide: sideBinding(for: exercise),
            sideLayout: settings.sideLayout,
            startSide: exercise.startSide,
            machineMenu: machineMenu(for: exercise),
            actions: ExerciseCardView.Actions(
                toggleCollapsed: { toggleCollapsed(key: foldKey(for: exercise)) },
                setMode: { setMode($0, on: exercise) },
                setAssistance: { setAssistance($0, on: exercise) },
                openNote: { openNote(for: exercise) },
                tapHistory: { tapHistory(for: exercise) },
                openHistory: { historyExerciseID = exercise.id },
                delete: { deleteExercise(exercise) },
                convertToSuperset: { convertingExerciseID = exercise.id },
                setEffortScale: { setEffortScale($0, on: exercise) },
                addSet: { addSet(to: exercise) },
                addSetOn: { addSet(to: exercise, on: $0) },
                setStartSide: { setStartSide($0, of: exercise) },
                deleteSet: { deleteSet($0, from: exercise) },
                copySet: { copySet($0, in: exercise) },
                effortChanged: { _ = saveContext("Could not update set effort.") },
                moveSets: { moveSets(in: exercise, from: $0, to: $1) },
                setRest: { setRest($0, on: exercise) }
            )
        )
    }

    // Pushed, the editor is in the start screen's stack; covering it, it
    // brings its own.
    var body: some View {
        if isBeingTrained {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
            ScrollViewReader { scrollProxy in
                List {
                    Section {
                        // The large title is drawn in the list instead of the
                        // navigation bar, because the bar has no trailing slot next
                        // to a large title for the date pill to sit in.
                        HStack(alignment: .lastTextBaseline) {
                            Text(session.isTemplate ? "Template" : "Workout")
                                .font(.largeTitle.bold())

                            Spacer(minLength: 8)

                            // A template is never trained, so it has no date.
                            if !session.isTemplate {
                                datePill
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    Section {
                        HStack(spacing: 8) {
                            TextField(session.isTemplate ? "Name" : "Name (optional)", text: $workoutName)
                            GymMenu(gym: session.gym, gyms: gyms) { gym in
                                session.gym = gym
                                _ = saveContext("Could not save the gym.")
                            } onAdd: { typed in
                                addGym(named: typed)
                            }
                        }
                    }

                    exerciseSections

                    Section {
                        HStack(spacing: 12) {
                            Button {
                                showExercisePicker = true
                            } label: {
                                Label("Add Exercise", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderless)

                            Divider()

                            Button {
                                showExerciseReorder = true
                            } label: {
                                // Reorder only claims the width it needs, so the far more
                                // common Add Exercise keeps the rest of the row — and the
                                // narrow tap target makes an accidental reorder unlikely.
                                Label("Reorder", systemImage: "arrow.up.arrow.down")
                                    .foregroundStyle(sortedExercises.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                            }
                            .buttonStyle(.borderless)
                            // The row keeps its shape from the start; reordering just has
                            // nothing to act on until an exercise exists.
                            .disabled(sortedExercises.isEmpty)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Section("Notes") {
                        // The field grows with the note, but never past one screen:
                        // beyond that it is unpleasant to look at and the list can no
                        // longer show anything else, so the text scrolls inside instead.
                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .lineLimit(3...noteLineLimit)
                            .focused($notesFocused)
                            .id(Self.notesFieldID)
                    }
                }
                .listSectionSpacing(8)
                // The list shrinks while the keyboard is up, and a field sized
                // off the shrunken list would change height every time the
                // keyboard comes and goes. The tallest list seen at the current
                // width is the one without a keyboard; a different width means
                // the device turned, so the measurement starts over.
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    if size.width == keyboardFreeListSize.width {
                        keyboardFreeListSize.height = max(keyboardFreeListSize.height, size.height)
                    } else {
                        keyboardFreeListSize = size
                    }
                }
                // The list draws its own large title, so it does not need the
                // inset a list normally leaves below a navigation bar.
                .contentMargins(.top, 0, for: .scrollContent)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                // The list does not follow a growing field on its own, so every line
                // the note gains would push the caret behind the keyboard.
                .onChange(of: notes) { _, _ in
                    scrollToNotesField(scrollProxy)
                }
                // The workout being trained is in the store as it goes, so a
                // name and a note outlast leaving it, and a quit app.
                .onChange(of: workoutName) { _, name in
                    if isBeingTrained { session.name = name }
                }
                .onChange(of: notes) { _, notes in
                    if isBeingTrained { session.notes = notes }
                }
                .onChange(of: notesFocused) { _, _ in
                    scrollToNotesField(scrollProxy)
                }
                .onChange(of: keyboardVisible) { _, _ in
                    scrollToNotesField(scrollProxy)
                }
                .overlay(alignment: .bottomTrailing) {
                    if keyboardVisible {
                        HStack(spacing: 10) {
                            // Beside the button that puts the keyboard away
                            // rather than on the keyboard's own bar, which
                            // the number pad does not reliably show.
                            if guides, focusedField != nil {
                                nextButton
                            }
                            keyboardDismissButton
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    keyboardVisible = true
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    keyboardVisible = false
                }
                .onChange(of: guideTarget) { _, id in
                    guard let id else { return }
                    guideTarget = nil
                    moveCursor(to: id, scrolling: scrollProxy)
                }
            }
            .environment(\.setFieldFocus, guides ? $focusedField : nil)
            .environment(\.setTicked, startRest(after:))
            .environment(\.setSideTicked, startRestBetweenSides(of:))
            .environment(\.showsExerciseTexts, settings.showExerciseTexts)
            // A template is never trained, so nothing in it rests.
            .safeAreaInset(edge: .bottom) {
                if isBeingTrained, let timer = restTimer.timer {
                    RestTimerBar(timer: timer, onAdjust: restTimer.adjust(by:), onPause: restTimer.pause, onResume: restTimer.resume) {
                        restTimer.stop()
                        guideAfterRest(of: timer.setID)
                    }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: restTimer.timer == nil)
            .sensoryFeedback(.success, trigger: restTimer.finishedCount)
            .onChange(of: restTimer.finishedCount) { _, _ in
                guideAfterRest(of: restTimer.lastFinishedSetID)
            }
            .toolbar {
                // Being trained, the place on the left is Back's.
                if !isBeingTrained {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel", role: .cancel) {
                            cancelWorkout()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Editor Settings", systemImage: "slider.horizontal.3") {
                            showEditorSettings = true
                        }
                    }
                }

                if isBeingTrained {
                    ToolbarItem(placement: .topBarTrailing) {
                        restStartMenu
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Editor Settings", systemImage: "slider.horizontal.3") {
                                showEditorSettings = true
                            }
                            Button("Discard Workout", systemImage: "trash", role: .destructive) {
                                cancelWorkout()
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More")
                    }
                }

                if let startedAt {
                    ToolbarItem(placement: .principal) {
                        Text(startedAt, style: .timer)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Workout time")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    // A workout being trained ends; one opened again, or a
                    // template, is only saved.
                    if isBeingTrained {
                        Button("Finish", action: finish)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                    } else {
                        Button("Save", action: finish)
                    }
                }

            }
            .sheet(isPresented: $showEditorSettings) {
                EditorSettingsSheet(overrides: editorOverrides, defaults: editorDefaults, isBeingTrained: isBeingTrained)
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView { definition in
                    addExercise(from: definition)
                } onSelectSuperset: { definitions in
                    addSuperset(from: definitions)
                }
            }
            .sheet(isPresented: $showExerciseReorder) {
                ExerciseReorderView(session: session) { errorMessage in
                    alertMessage = errorMessage
                    showAlert = true
                }
            }
            .sheet(item: historyExerciseBinding) { exercise in
                ExerciseHistoryView(exerciseName: exercise.name, identity: exercise.identity, currentSessionID: session.id)
            }
            .sheet(item: convertingExerciseBinding) { exercise in
                ConvertToSupersetSheet(
                    exercise: exercise,
                    candidates: sortedExercises.filter { $0.id != exercise.id && canJoinSuperset($0) }
                ) { partner in
                    convertToSuperset(exercise, partner)
                }
            }
            .sheet(item: noteExerciseBinding) { exercise in
                ExerciseNoteSheet(
                    exerciseName: exercise.name,
                    isTemplate: session.isTemplate,
                    instructions: $draftExerciseInstructions,
                    note: $draftExerciseNote
                ) {
                    noteExerciseID = nil
                    draftExerciseNote = ""
                    draftExerciseInstructions = ""
                } onSave: {
                    exercise.instructions = draftExerciseInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    exercise.notes = draftExerciseNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    if saveContext("Could not save exercise note.") {
                        noteExerciseID = nil
                        draftExerciseNote = ""
                        draftExerciseInstructions = ""
                    }
                }
            }
            .onAppear {
                if !didInitialize {
                    workoutName = session.name
                    notes = session.notes
                    // The workout being trained was left and opened again
                    // since its start, which is what Discard compares with.
                    initialSnapshot = isBeingTrained ? runningWorkout.initialSnapshot : WorkoutSnapshot(session: session)
                    didInitialize = true
                }
                loadNamesWithHistory()
            }
            .task(id: historyHintExerciseID) {
                guard historyHintExerciseID != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation { historyHintExerciseID = nil }
            }
            .alert("Save Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert(
                CountFormat.text(openSetsOnSave.count, "Set Not Done", "Sets Not Done"),
                isPresented: Binding(get: { !openSetsOnSave.isEmpty }, set: { if !$0 { openSetsOnSave = [] } })
            ) {
                Button("Keep as Not Done") { settleOpenSets(.keep) }
                Button("Count as Done") { settleOpenSets(.markDone) }
                Button("Remove", role: .destructive) { settleOpenSets(.remove) }
                Button("Back to Workout", role: .cancel) { openSetsOnSave = [] }
            } message: {
                Text("Kept, they stay in the workout greyed out and count nowhere — a record of what was planned.")
            }
            .modifier(DiscardChangesConfirmation(
                isPresented: $showDiscardConfirmation,
                trainedSetCount: isBeingTrained && discardSessionOnCancel ? session.setCount : nil,
                onDiscard: discardWorkout
            ))
            .alert(
                "Merge Left and Right?",
                isPresented: Binding(
                    get: { pendingModeChange != nil },
                    set: { if !$0 { pendingModeChange = nil } }
                ),
                presenting: pendingModeChange
            ) { change in
                Button("Cancel", role: .cancel) { pendingModeChange = nil }
                Button("Merge", role: .destructive) {
                    if let exercise = sortedExercises.first(where: { $0.id == change.exerciseID }) {
                        applyMode(change.mode, to: exercise)
                    }
                    pendingModeChange = nil
                }
            } message: { _ in
                Text("The left and right sets become one list, and which side a set belonged to cannot be recovered.")
            }
            .alert(
                "Change Effort Rating?",
                isPresented: Binding(
                    get: { pendingEffortScaleChange != nil },
                    set: { if !$0 { pendingEffortScaleChange = nil } }
                ),
                presenting: pendingEffortScaleChange
            ) { change in
                Button("Cancel", role: .cancel) { pendingEffortScaleChange = nil }
                Button("Discard Ratings", role: .destructive) {
                    if let exercise = sortedExercises.first(where: { $0.id == change.exerciseID }) {
                        applyEffortScale(change.scale, to: exercise)
                    }
                    pendingEffortScaleChange = nil
                }
            } message: { change in
                Text(change.message)
            }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var keyboardDismissButton: some View {
        Button(action: dismissKeyboard) {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.title3.weight(.semibold))
                .padding(12)
                .background(.regularMaterial, in: Circle())
                .shadow(radius: 3)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 8)
    }

    private var nextButton: some View {
        Button(action: next) {
            Text("Next")
                .font(.headline)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .shadow(radius: 3)
        .padding(.bottom, 8)
        .accessibilityHint("Goes to the next value, or ticks the set off")
    }

    private var datePill: some View {
        Button {
            showDatePicker = true
        } label: {
            HStack(spacing: 8) {
                Text(session.date, format: .dateTime.day().month(.abbreviated).year())
                    .foregroundStyle(.primary)
                Text(session.date, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 15))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDatePicker) {
            WorkoutDateSheet(date: dateBinding)
        }
    }

    /// Save. A workout being trained is asked about its sets not ticked off;
    /// nothing else is asked. A template of a workout is kept from the
    /// history's menu, not at Finish: training goes from a template, and one
    /// started without is mostly a one-off.
    private func finish() {
        finishedAt = .now
        if isBeingTrained {
            let open = session.plannedSets
            if !open.isEmpty {
                openSetsOnSave = open
                return
            }
        }
        saveWorkout()
    }

    private enum OpenSetsChoice {
        case keep, markDone, remove
    }

    private func settleOpenSets(_ choice: OpenSetsChoice) {
        let open = openSetsOnSave
        openSetsOnSave = []
        switch choice {
        case .keep:
            break
        case .markDone:
            open.forEach { $0.isDone = true }
        case .remove:
            for set in open {
                guard let exercise = set.exercise else { continue }
                if let pair = pair(for: exercise) {
                    pair.deleteSet(set, in: modelContext)
                } else {
                    exercise.deleteSet(set, in: modelContext)
                }
            }
        }
        // Saved once this alert is gone.
        Task { @MainActor in saveWorkout() }
    }

    /// Saves the workout, or the template.
    private func saveWorkout() {
        let trimmedName = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        // A template without a name would be a blank card.
        session.name = session.isTemplate ? TemplateShelf.name(forTemplateOf: trimmedName) : trimmedName
        session.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let startedAt, !session.isTemplate {
            session.durationSeconds = Int((finishedAt ?? .now).timeIntervalSince(startedAt).rounded())
        }
        // Deleted already when its week ran out while it was being trained.
        if let usesUp, !session.isTemplate, !usesUp.isDeleted {
            TemplateShelf.remove(usesUp, in: modelContext)
        }
        if saveContext(session.isTemplate ? "Could not save template." : "Could not save workout.") {
            endTraining()
            dismiss()
        }
    }

    /// Without a start to compare with — a workout carried over from an
    /// earlier launch — Discard asks.
    private func cancelWorkout() {
        if initialSnapshot?.differs(from: session, workoutName: workoutName, notes: notes) ?? true {
            showDiscardConfirmation = true
        } else {
            discardWorkout()
        }
    }

    private func discardWorkout() {
        if discardSessionOnCancel {
            modelContext.delete(session)
        } else if let initialSnapshot,
                  initialSnapshot.differs(from: session, workoutName: workoutName, notes: notes) {
            // Restoring rebuilds every entry, set and value of the workout, so
            // it only happens when there is something to take back.
            initialSnapshot.restore(session, in: modelContext)
        }

        if saveContext("Could not discard workout changes.") {
            endTraining()
            dismiss()
        }
    }

    /// The rest and the clock are the workout's being trained; an editor
    /// on anything else leaves them running.
    private func endTraining() {
        guard isBeingTrained else { return }
        restTimer.stop()
        OneSideTicks.shared.removeAll()
        runningWorkout.end()
    }

    // MARK: - Rest

    /// A tick on a set starts the rest after it: the exercise's own, or the
    /// setting's. In a superset only a round rests, on B's rest.
    private func startRest(after set: SetEntry) {
        guard isBeingTrained, let exercise = set.exercise else { return }
        // The set is over, so its sides' rest is, whether another follows or not.
        if let timer = restTimer.timer, timer.kind == .betweenSides, timer.setID == set.id {
            restTimer.stop()
        }
        if exercise.restKind(after: set) == .betweenSides {
            startRestBetweenSides(of: set)
            // With that rest turned off, nothing ends to lead to the other
            // side, whose tab may not even be open.
            if restTimer.timer?.setID != set.id { guideAfterRest(of: set.id) }
            return
        }
        let pair = pair(for: exercise)
        let ordered = pair?.orderedSets ?? []
        let index = ordered.firstIndex { $0.id == set.id } ?? 0
        guard RestAfterSet.rests(afterSetAt: index, in: pair.map { pair in ordered.map(pair.member(of:)) }),
              let seconds = RestDuration.seconds(exercise: definition(of: pair?.b ?? exercise)?.restSeconds, setting: settings.defaultRestSeconds)
        else { return }
        restTimer.start(seconds: seconds, exerciseName: exercise.name, setID: set.id)
    }

    /// The rest before a set's other side: after the first tick of a Same
    /// Weight set, in a superset too, as the partner's set comes after both
    /// sides; and after one side of a set logged left and right.
    private func startRestBetweenSides(of set: SetEntry) {
        guard isBeingTrained, let exercise = set.exercise,
              let seconds = RestDuration.seconds(exercise: nil, setting: settings.betweenSidesRestSeconds)
        else { return }
        restTimer.start(seconds: seconds, exerciseName: exercise.name, setID: set.id, kind: .betweenSides)
    }

    // MARK: - Guide

    /// Next on the keyboard: on to the set's next field, or from its last
    /// one tick the set off. A rest that starts takes the keyboard away,
    /// and its end only shows the next set, without bringing the keyboard
    /// back; without a rest, the cursor goes on into the next set at once.
    private func next() {
        let order = guideOrder
        guard let field = focusedField,
              let set = order.first(where: { $0.sortedValues.contains { $0.id == field } })
        else { return }
        if let following = WorkoutGuide.field(after: field, in: WorkoutGuide.typedFields(of: set).map(\.id)) {
            focusedField = following
            return
        }
        if !set.isDone {
            set.isDone = true
            _ = saveContext("Could not tick the set off.")
            startRest(after: set)
        }
        if restTimer.timer?.setID == set.id {
            focusedField = nil
        } else {
            guide(after: set.id, focusing: true)
        }
    }

    /// After a rest. A Same Weight set with one side ticked is still the one
    /// to do, so the guide stays.
    private func guideAfterRest(of setID: UUID?) {
        if let setID, guideOrder.first(where: { $0.id == setID })?.isDone == false { return }
        guide(after: setID)
    }

    /// After a set and its rest: on to the next set not done. After a rest
    /// started by hand, `setID` is nil and the guide goes to the set to do.
    private func guide(after setID: UUID?, focusing: Bool = false) {
        guard guides else { return }
        guideFocusesField = focusing
        let order = guideOrder
        let done = order.map(\.isDone)
        let index = setID.flatMap { id in order.firstIndex { $0.id == id } }
        let next = index.map { WorkoutGuide.next(after: $0, done: done) } ?? WorkoutGuide.current(done: done)
        guideTarget = next.map { order[$0].id }
    }

    /// Opens the set's card and side and scrolls to it, and when the guide
    /// focuses, puts the cursor in its first field — each a moment after the
    /// last, so the row is there to scroll to and its field there to focus.
    private func moveCursor(to setID: UUID, scrolling proxy: ScrollViewProxy) {
        guard let set = guideOrder.first(where: { $0.id == setID }),
              let exercise = set.exercise
        else { return }
        let key = foldKey(for: exercise)
        if collapsedExerciseIDs.contains(key) {
            toggleCollapsed(key: key)
        }
        if exercise.unilateralMode == .perSide {
            selectedSides[exercise.id] = set.side == .right ? .right : .left
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation { proxy.scrollTo(setID, anchor: .center) }
            try? await Task.sleep(for: .milliseconds(300))
            if guideFocusesField {
                focusedField = WorkoutGuide.typedFields(of: set).first?.id
            }
        }
    }

    private func setRest(_ seconds: Int?, on exercise: ExerciseEntry) {
        guard let definition = definition(of: exercise) else { return }
        definition.restSeconds = seconds
        _ = saveContext("Could not save the rest.")
    }

    /// A rest started by hand, for one no set started — after a warm-up, or
    /// a longer one than the exercise has.
    private var restStartMenu: some View {
        Menu {
            Section("Start Rest") {
                ForEach(RestDuration.choices.filter { $0 > 0 }, id: \.self) { seconds in
                    Button(RestDuration.text(seconds)) {
                        restTimer.start(seconds: seconds, exerciseName: "")
                    }
                }
            }
        } label: {
            Image(systemName: "timer")
        }
        .accessibilityLabel("Start rest")
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { session.date },
            set: {
                session.date = $0
                // A workout dated by hand is logged afterwards: the clock
                // would time the logging.
                runningWorkout.stopClock()
            }
        )
    }

    /// Adds an exercise from its definition. An exercise that logs once per
    /// workout arrives with its one set; one that tracks sets arrives empty,
    /// or with a first set when the setting asks for it. Sets come with the
    /// mode the exercise was last logged in, if it still fits — see
    /// `ExerciseSides.startMode`.
    private func addExercise(from definition: ExerciseDefinition) {
        let exercise = insertEntry(from: definition, supersetID: nil)
        collapseOthers(except: exercise)
        _ = saveContext("Could not add exercise.")
    }

    /// Adds two exercises paired as a superset: trained by alternating between
    /// them, A then B then A again, rather than finishing one before starting
    /// the other. Sharing an id is the whole of what pairs them — see
    /// `ExerciseGrouping` for how that is read back into one card.
    private func addSuperset(from definitions: [ExerciseDefinition]) {
        guard definitions.count == 2 else { return }
        let supersetID = UUID()
        let entries = definitions.map { insertEntry(from: $0, supersetID: supersetID) }
        SupersetPair(entries)?.interleaveExisting()
        if let last = entries.last {
            collapseOthers(except: last)
        }
        _ = saveContext("Could not add superset.")
    }

    /// Pairs two exercises already in the workout. Whichever was added first
    /// keeps its place as "A"; the other becomes "B" right behind it, the same
    /// order a new superset's two picks would end up in.
    private func convertToSuperset(_ exercise: ExerciseEntry, _ partner: ExerciseEntry) {
        let supersetID = UUID()
        let pair = [exercise, partner].sorted { $0.orderIndex < $1.orderIndex }
        // The new card is open if either half was, so nothing being worked
        // on folds away under the user's hands.
        let wasOpen = pair.contains { !collapsedExerciseIDs.contains($0.id) }
        for entry in pair {
            collapsedExerciseIDs.remove(entry.id)
            // Only one side holds sets here (see `canJoinSuperset`), so
            // leaving left/right merges nothing. A one-sided exercise stays
            // one-sided.
            if entry.unilateralMode == .perSide {
                applyMode((definition(of: entry)?.sides ?? .either).supersetFallback, to: entry)
            }
            entry.supersetID = supersetID
        }
        SupersetPair(pair)?.interleaveExisting()
        if !wasOpen {
            collapsedExerciseIDs.insert(supersetID)
        }

        // Bring the pair adjacent, right after wherever the earlier one
        // already was — the stored order then matches the display, and a
        // later drag in "Reorder" moves the two rows it already looks like.
        var ordered = sortedExercises.filter { $0.id != pair[0].id && $0.id != pair[1].id }
        if let insertionIndex = ordered.firstIndex(where: { $0.orderIndex > pair[0].orderIndex }) {
            ordered.insert(contentsOf: pair, at: insertionIndex)
        } else {
            ordered.append(contentsOf: pair)
        }
        for (index, entry) in ordered.enumerated() {
            entry.orderIndex = index
        }
        _ = saveContext("Could not convert to superset.")
    }

    /// Inserts one entry from its definition — the shared half of adding a
    /// single exercise and adding a superset's two.
    @discardableResult
    private func insertEntry(from definition: ExerciseDefinition, supersetID: UUID?) -> ExerciseEntry {
        let nextIndex = (sortedExercises.last?.orderIndex ?? -1) + 1
        let exercise = ExerciseEntry(
            name: definition.name,
            orderIndex: nextIndex,
            definitionID: definition.id,
            supersetID: supersetID,
            effortScale: settings.effortScale,
            catalogKey: definition.catalogKey,
            session: session
        )
        session.exercises.append(exercise)
        modelContext.insert(exercise)

        if definition.tracksSets {
            // How the same exercise was logged last time — its mode and its
            // help — so one always trained one-sided or on the machine does
            // not have to be switched over on every single workout.
            let lastLogged = ExerciseHistory.fetch(in: modelContext, excludingSession: session.id)
                .lastLogged(of: definition.identity)
            let mode = definition.sides.startMode(
                lastLogged: lastLogged?.unilateralMode,
                inSuperset: supersetID != nil
            )
            exercise.unilateralMode = mode
            // In a template nothing is said until it is prescribed.
            if mode != .bilateral, !session.isTemplate {
                exercise.startSideRawValue = ExerciseSide.suggested(lastLogged: lastLogged).rawValue
            }
            exercise.assistance = Assistance.start(offered: definition.offersAssistance, lastLogged: lastLogged?.assistance)
            if mode == .perSide {
                selectedSides[exercise.id] = exercise.startSide
            }
        }
        // At a gym, the machine it was last done at there.
        exercise.machine = GymChoices.suggestedMachine(
            for: definition.identity,
            at: session.gym,
            in: ExerciseHistory.fetch(in: modelContext, excludingSession: session.id)
        )
        if !definition.tracksSets || settings.startWithOneSet {
            addSet(to: exercise)
        }
        return exercise
    }

    private func collapseOthers(except exercise: ExerciseEntry) {
        guard settings.collapseOtherExercises else { return }
        // A new exercise arrives expanded, so the ones already there fold away
        // to keep a single exercise open. The relationship already holds the
        // new entry, so its own id has to stay out of the collapsed set.
        let key = foldKey(for: exercise)
        collapsedExerciseIDs = Set(sortedExercises.map(foldKey(for:))).subtracting([key])
    }

    /// Folds or opens one card — an exercise, or a superset as a whole.
    private func toggleCollapsed(key: UUID) {
        let hintedKey = sortedExercises.first { $0.id == historyHintExerciseID }.map(foldKey(for:))
        withAnimation {
            if collapsedExerciseIDs.contains(key) {
                if settings.collapseOtherExercises {
                    // With the setting on, expanding one card means every other
                    // one folds away, so only the one being worked on is open.
                    collapsedExerciseIDs = Set(sortedExercises.map(foldKey(for:)))
                    if let hintedKey, hintedKey != key {
                        historyHintExerciseID = nil
                    }
                }
                collapsedExerciseIDs.remove(key)
            } else {
                collapsedExerciseIDs.insert(key)
                if hintedKey == key {
                    historyHintExerciseID = nil
                }
            }
        }
    }

    private func deleteExercise(_ exercise: ExerciseEntry) {
        // A superset of one is no superset: the member left behind goes back
        // to being an exercise of its own, keeping the fold state it had, and
        // can be paired again.
        if let supersetID = exercise.supersetID {
            let rest = sortedExercises.filter { $0.id != exercise.id && $0.supersetID == supersetID }
            if rest.count == 1, let partner = rest.first {
                SupersetPair.dissolve(partner)
                if collapsedExerciseIDs.remove(supersetID) != nil {
                    collapsedExerciseIDs.insert(partner.id)
                }
            }
        }
        modelContext.delete(exercise)
        selectedSides.removeValue(forKey: exercise.id)
        collapsedExerciseIDs.remove(exercise.id)
        normalizeOrderIndexes()
        _ = saveContext("Could not delete exercise.")
    }

    private func normalizeOrderIndexes() {
        for (index, exercise) in sortedExercises.enumerated() {
            exercise.orderIndex = index
        }
    }

    private func addSet(to exercise: ExerciseEntry) {
        if let pair = pair(for: exercise) {
            pair.addSet(to: exercise, definition: definition(of: exercise), in: modelContext)
        } else {
            exercise.addSet(on: setSide(for: exercise), definition: definition(of: exercise), in: modelContext)
        }
        _ = saveContext("Could not add set.")
    }

    private func addSet(to exercise: ExerciseEntry, on side: ExerciseSide) {
        exercise.addSet(on: side.setSide, definition: definition(of: exercise), in: modelContext)
        _ = saveContext("Could not add set.")
    }

    private func deleteSet(_ set: SetEntry, from exercise: ExerciseEntry) {
        exercise.deleteSet(set, in: modelContext)
        _ = saveContext("Could not delete set.")
    }

    private func copySet(_ set: SetEntry, in exercise: ExerciseEntry) {
        exercise.copySet(set, in: modelContext)
        _ = saveContext("Could not copy set.")
    }

    private func moveSets(in exercise: ExerciseEntry, from source: IndexSet, to destination: Int) {
        if listsBothSides(exercise) {
            exercise.moveSetsInList(from: source, to: destination)
        } else {
            exercise.moveSets(on: setSide(for: exercise), from: source, to: destination)
        }
        _ = saveContext("Could not reorder sets.")
    }

    private func setSide(for exercise: ExerciseEntry) -> SetSide {
        guard exercise.unilateralMode == .perSide else { return .both }
        return (selectedSides[exercise.id] ?? exercise.startSide).setSide
    }

    private func displayedSets(in exercise: ExerciseEntry) -> [SetEntry] {
        listsBothSides(exercise)
            ? exercise.setsInOrder()
            : exercise.sets(on: setSide(for: exercise))
    }

    private func listsBothSides(_ exercise: ExerciseEntry) -> Bool {
        exercise.unilateralMode == .perSide && settings.sideLayout == .list
    }

    /// The tab goes along: the side it starts with is where it starts.
    private func setStartSide(_ side: ExerciseSide?, of exercise: ExerciseEntry) {
        exercise.setStartSide(side)
        if let side, exercise.unilateralMode == .perSide {
            selectedSides[exercise.id] = side
        }
        _ = saveContext("Could not change the starting side.")
    }

    private var guideOrder: [SetEntry] {
        WorkoutGuide.order(of: session.exercises)
    }

    /// Leaving the split log is the one change that cannot be undone, so it asks
    /// first — but only when both sides actually hold sets and there is something
    /// to lose. Every other switch moves sets around reversibly and just happens.
    private func setMode(_ mode: UnilateralMode, on exercise: ExerciseEntry) {
        let previous = exercise.unilateralMode
        guard previous != mode else { return }

        if previous == .perSide, exercise.holdsBothSides {
            pendingModeChange = PendingModeChange(exerciseID: exercise.id, mode: mode)
            return
        }
        applyMode(mode, to: exercise)
    }

    /// Switching the help moves every set's weight over and back again, so it
    /// just happens.
    private func setAssistance(_ assistance: Assistance, on exercise: ExerciseEntry) {
        exercise.applyAssistance(assistance)
        _ = saveContext("Could not change the assistance.")
    }

    private func setEffortScale(_ scale: EffortScale, on exercise: ExerciseEntry) {
        let discarded = exercise.ratingsDiscarded(bySwitchingTo: scale)
        if discarded > 0 {
            pendingEffortScaleChange = PendingEffortScaleChange(exerciseID: exercise.id, scale: scale, discarded: discarded)
            return
        }
        applyEffortScale(scale, to: exercise)
    }

    private func applyEffortScale(_ scale: EffortScale, to exercise: ExerciseEntry) {
        exercise.switchEffortScale(to: scale)
        _ = saveContext("Could not change the effort scale.")
    }

    private func applyMode(_ mode: UnilateralMode, to exercise: ExerciseEntry) {
        exercise.applyMode(mode)
        if mode != .bilateral, exercise.startSideRawValue == nil, !session.isTemplate {
            let lastLogged = ExerciseHistory.fetch(in: modelContext, excludingSession: session.id).lastLogged(of: exercise.identity)
            exercise.startSideRawValue = ExerciseSide.suggested(lastLogged: lastLogged).rawValue
        }
        if mode == .perSide {
            selectedSides[exercise.id] = exercise.startSide
        } else {
            selectedSides.removeValue(forKey: exercise.id)
        }
        _ = saveContext("Could not change how this exercise is trained.")
    }

    private func sideBinding(for exercise: ExerciseEntry) -> Binding<ExerciseSide> {
        Binding(
            get: { selectedSides[exercise.id] ?? exercise.startSide },
            set: { selectedSides[exercise.id] = $0 }
        )
    }

    @discardableResult
    private func saveContext(_ fallbackMessage: String) -> Bool {
        guard let failure = modelContext.save(reporting: fallbackMessage) else { return true }
        alertMessage = failure
        showAlert = true
        return false
    }

    private var noteExerciseBinding: Binding<ExerciseEntry?> {
        Binding(
            get: { sortedExercises.first(where: { $0.id == noteExerciseID }) },
            set: { noteExerciseID = $0?.id }
        )
    }

    private func hasHistory(for exercise: ExerciseEntry) -> Bool {
        identitiesWithHistory.contains(exercise.identity)
    }

    /// Collects what was logged in other sessions once, so each header can check
    /// for history with a dictionary lookup instead of its own fetch.
    ///
    /// Read once when the editor opens: everything it looks at belongs to other
    /// sessions, which cannot change while this one is being edited.
    private func loadNamesWithHistory() {
        let history = ExerciseHistory.fetch(in: modelContext, excludingSession: session.id)
        identitiesWithHistory = history.identitiesWithHistory
        lastPerformances = history.lastPerformances
    }

    private var historyExerciseBinding: Binding<ExerciseEntry?> {
        Binding(
            get: { sortedExercises.first(where: { $0.id == historyExerciseID }) },
            set: { historyExerciseID = $0?.id }
        )
    }

    private var convertingExerciseBinding: Binding<ExerciseEntry?> {
        Binding(
            get: { sortedExercises.first(where: { $0.id == convertingExerciseID }) },
            set: { convertingExerciseID = $0?.id }
        )
    }
}
