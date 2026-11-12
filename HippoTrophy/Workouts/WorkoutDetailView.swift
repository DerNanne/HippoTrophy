import SwiftUI
import SwiftData

/// A workout as it was trained, or — for a template — what it plans. A
/// template is looked at to start from it, so it offers Start Workout where
/// a workout offers Edit and Share.
struct WorkoutDetailView: View {
    let session: WorkoutSession
    /// Whether Start Workout works: not while another workout is being
    /// trained.
    var canStartWorkout = true
    /// Starts a workout from the template on screen; unused for a workout.
    var startWorkout: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Query private var definitions: [ExerciseDefinition]
    @AppStorage(SettingsKey.weightUnit) private var weightUnitRaw = WeightUnit.kilograms.rawValue
    @State private var showEditor = false
    @State private var historyExerciseID: UUID?
    @State private var identitiesWithHistory: Set<ExerciseIdentity> = []
    @State private var showExportOptions = false
    /// Set by the export sheet on its way out, read once it has closed: the share
    /// sheet cannot be presented while the sheet it replaces is still on screen.
    @State private var exportConfirmed = false
    /// The unit the export sheet is set to. Reset to the app's setting each time
    /// the sheet opens, so a one-off choice does not quietly outlive it.
    @State private var exportUnit = WeightUnit.kilograms
    /// The rendered report, kept only while the share sheet is up. Rendering runs
    /// on demand rather than with the view: most visits to this screen never share.
    @State private var reportFile: SharedFile?
    @State private var reportError: String?

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .kilograms
    }

    private var sortedExercises: [ExerciseEntry] {
        session.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    private func tracksSets(_ exercise: ExerciseEntry) -> Bool {
        exercise.tracksSets(among: definitions)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    if !session.name.isEmpty {
                        Text(session.name)
                            .font(.headline)
                    }
                    // A template was never trained: no date, and its sets
                    // are counted as planned rather than as done.
                    if session.isTemplate {
                        Text(TemplateShelf.summary(of: session))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(session.date.formatted(date: .complete, time: .shortened))
                        if let seconds = session.durationSeconds {
                            Label(
                                Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)),
                                systemImage: "stopwatch"
                            )
                            .font(.subheadline)
                            .accessibilityLabel("Took \(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide)))")
                        }
                        if let gym = session.gym {
                            Label(gym.name, systemImage: "building.2")
                                .font(.subheadline)
                                .accessibilityLabel("At \(gym.name)")
                        }
                        Text(session.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(ExerciseGrouping.groups(sortedExercises), id: \.first?.id) { group in
                if let pair = SupersetPair(group) {
                    supersetSection(pair)
                } else {
                    ForEach(group) { exercise in
                        exerciseSection(exercise)
                    }
                }
            }

            if !session.notes.isEmpty {
                Section("Notes") {
                    Text(session.notes)
                }
            }
        }
        .navigationTitle(session.isTemplate ? "Template" : "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isTemplate {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start Workout", action: startWorkout)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canStartWorkout)
                }
            } else {
                workoutToolbar
            }
        }
        .fullScreenCover(isPresented: $showEditor) {
            WorkoutEditorView(session: session)
        }
        .sheet(item: historyExerciseBinding) { exercise in
            ExerciseHistoryView(exerciseName: exercise.name, identity: exercise.identity, currentSessionID: session.id)
        }
        .onAppear(perform: loadNamesWithHistory)
        .sheet(isPresented: $showExportOptions, onDismiss: exportIfConfirmed) {
            WorkoutExportSheet(session: session, confirmed: $exportConfirmed, unit: $exportUnit)
        }
        .sheet(item: $reportFile) { file in
            ShareSheet(url: file.url)
        }
        .alert(
            "Export failed",
            isPresented: Binding(get: { reportError != nil }, set: { if !$0 { reportError = nil } })
        ) {
            Button("OK", role: .cancel) { reportError = nil }
        } message: {
            Text(reportError ?? "")
        }
    }

    @ToolbarContentBuilder
    private var workoutToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Edit") {
                showEditor = true
            }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                exportUnit = weightUnit
                showExportOptions = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share workout report")
        }
    }

    private func exerciseSection(_ exercise: ExerciseEntry) -> some View {
        let groups = SetGroup.groups(of: exercise)
        let layout = SetValuesLayout(sets: groups.flatMap(\.sets), tracksSets: tracksSets(exercise))
        return Section {
            EntryTextsView(entry: exercise)
            if let order = exercise.sideOrderSummary {
                Text(order)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // An exercise skipped with a note has no sets, and no row for them.
            if groups.contains(where: { !$0.sets.isEmpty }) {
                SetValuesBlock(
                    layout: layout,
                    groups: groups,
                    unit: weightUnit,
                    effortScale: exercise.effortScale,
                    showsNumber: tracksSets(exercise)
                )
                .listRowInsets(.vertical, 0)
            }
        } header: {
            HStack {
                Text(exercise.name)
                if exercise.isUserDefined { UserDefinedBadge() }
                nameLineTrailing(exercise)
            }
            .textCase(nil)
        }
    }

    /// A superset as the editor shows it: a line per exercise with its mode,
    /// history and note, then the sets of both in the order they were done,
    /// marked as A's or B's by the editor's bars and tint. When one line of
    /// labels can name the columns of both, it stands once above the sets.
    private func supersetSection(_ pair: SupersetPair) -> some View {
        let shared = SetValuesColumn.shared(
            by: SetValuesColumn.columns(of: pair.a.sortedSets),
            and: SetValuesColumn.columns(of: pair.b.sortedSets)
        )
        return Section {
            supersetMemberRow(pair.a)
                .listRowBackground(SupersetCardView.aBackground)
            supersetMemberRow(pair.b)
                .listRowBackground(SupersetCardView.bBackground)
            if let shared, !shared.isEmpty {
                // Closer to the sets it names than to the exercises above.
                SetCellsHeader(columns: shared)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .listRowInsets(.bottom, 4)
                    .listRowSeparator(.hidden)
            }
            ForEach(pair.orderedSets) { set in
                let isB = pair.member(of: set) == .b
                let exercise = isB ? pair.b : pair.a
                supersetSetRow(set, of: exercise, shared: shared)
                    .listRowBackground(isB ? AnyView(SupersetCardView.bBackground) : AnyView(SupersetCardView.aBackground))
                    .accessibilityLabel { label in
                        Text(exercise.name)
                        label
                    }
            }
        } header: {
            Label("Superset", systemImage: "link")
                .textCase(nil)
        }
    }

    /// A set of a superset in its own row, so it keeps its member's tint. Its
    /// values stand in cells of a fixed width, so they line up under the
    /// superset's one header; without one, each carries its label.
    private func supersetSetRow(_ set: SetEntry, of exercise: ExerciseEntry, shared: [SetValuesColumn]?) -> some View {
        SetCellsRow(
            set: set,
            columns: shared ?? SetValuesColumn.columns(of: exercise.sortedSets),
            unit: weightUnit,
            showsNumber: tracksSets(exercise),
            showsLabels: shared == nil
        )
    }

    private func supersetMemberRow(_ exercise: ExerciseEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(exercise.name)
                    .font(.headline)
                if exercise.isUserDefined { UserDefinedBadge() }
                nameLineTrailing(exercise)
            }
            EntryTextsView(entry: exercise)
            if let order = exercise.sideOrderSummary {
                Text(order)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What follows an exercise's name, on its section header or its line in
    /// a superset: its mode and its help when it has them, then its history.
    @ViewBuilder
    private func nameLineTrailing(_ exercise: ExerciseEntry) -> some View {
        if exercise.unilateralMode != .bilateral {
            UnilateralModeBadge(mode: exercise.unilateralMode)
        }
        if exercise.assistance.isAssisted {
            AssistanceBadge(assistance: exercise.assistance)
        }
        Spacer()
        historyButton(for: exercise)
    }

    private func exportIfConfirmed() {
        guard exportConfirmed else { return }
        exportConfirmed = false
        do {
            reportFile = SharedFile(url: try WorkoutReportRenderer.pdfFile(for: session, unit: exportUnit))
        } catch {
            reportError = error.localizedDescription
        }
    }

    /// Always shown so the header does not change shape between exercises;
    /// greyed out and inert when this exercise was never logged elsewhere.
    private func historyButton(for exercise: ExerciseEntry) -> some View {
        let hasHistory = identitiesWithHistory.contains(exercise.identity)
        return Button {
            historyExerciseID = exercise.id
        } label: {
            Image(systemName: "chart.xyaxis.line")
                .foregroundStyle(hasHistory ? Color.blue : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!hasHistory)
        .accessibilityLabel("History for \(exercise.name)")
    }

    private var historyExerciseBinding: Binding<ExerciseEntry?> {
        Binding(
            get: { sortedExercises.first(where: { $0.id == historyExerciseID }) },
            set: { historyExerciseID = $0?.id }
        )
    }

    /// Collects the names logged in other sessions once, so each header can check
    /// for history with a set lookup instead of its own fetch.
    private func loadNamesWithHistory() {
        identitiesWithHistory = ExerciseHistory.fetch(in: modelContext, excludingSession: session.id).identitiesWithHistory
    }
}
