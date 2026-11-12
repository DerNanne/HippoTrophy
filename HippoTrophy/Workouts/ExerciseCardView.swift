import SwiftUI

/// One exercise's card in the workout editor: header with collapse, mode, note
/// and history; the last performance and side picker; its sets and their own
/// "Add Set". A superset has a card of its own, `SupersetCardView`.
///
/// The card shows and reports; `WorkoutEditorView` decides what is folded,
/// which side is picked and what a tap does to the store. Its body is several
/// list rows, so it belongs directly inside a `Section`.
struct ExerciseCardView: View {
    /// What a card can ask the editor to do.
    struct Actions {
        var toggleCollapsed: () -> Void
        var setMode: (UnilateralMode) -> Void
        var setAssistance: (Assistance) -> Void
        var openNote: () -> Void
        /// A tap on the history button — the editor opens the history or,
        /// without one, shows the hint.
        var tapHistory: () -> Void
        var openHistory: () -> Void
        var delete: () -> Void
        var convertToSuperset: () -> Void
        var setEffortScale: (EffortScale) -> Void
        var addSet: () -> Void
        /// Add Set in the list of both sides, where the side has to be said.
        var addSetOn: (ExerciseSide) -> Void
        var setStartSide: (ExerciseSide?) -> Void
        var deleteSet: (SetEntry) -> Void
        var copySet: (SetEntry) -> Void
        var effortChanged: () -> Void
        var moveSets: (IndexSet, Int) -> Void
        var setRest: (Int?) -> Void
    }

    let exercise: ExerciseEntry
    let isCollapsed: Bool
    let tracksSets: Bool
    /// The modes the menu offers; empty when the exercise has nothing to
    /// choose.
    let modeChoices: [UnilateralMode]
    /// The kinds of help the menu offers; empty when the exercise offers
    /// none.
    let assistanceChoices: [Assistance]
    let hasHistory: Bool
    let showsHistoryHint: Bool
    /// `nil` when there is none or the setting hides it.
    let lastPerformance: LastPerformance?
    let weightUnit: WeightUnit
    let canConvertToSuperset: Bool
    /// The sets of the side on screen, in order.
    let displayedSets: [SetEntry]
    /// The exercise's own rest, nil when it follows `defaultRest`.
    let restSeconds: Int?
    let defaultRest: Int
    /// The set to do next, when the editor guides through the workout.
    let currentSetID: UUID?
    @Binding var selectedSide: ExerciseSide
    /// How both sides show, read only on an exercise logged left and right.
    let sideLayout: SideLayout
    /// The side the exercise starts with, read likewise.
    let startSide: ExerciseSide
    /// The machine it is done at, built by the editor.
    let machineMenu: MachineMenu
    let actions: Actions

    @State private var reorderingSets = false

    var body: some View {
        // The name lives inside the section instead of in a header so the
        // grouped card frames the whole exercise, which keeps a collapsed
        // exercise looking like a card.
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: actions.toggleCollapsed) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        Text(exercise.name)
                            .font(.headline)
                            .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        if exercise.isUserDefined { UserDefinedBadge() }
                        Spacer(minLength: 8)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(exercise.name)
                .accessibilityHint(isCollapsed ? "Expand exercise" : "Collapse exercise")

                // Mode, note and history describe the exercise itself rather
                // than its sets, so folding it away keeps them in reach. Folded,
                // the mode is only worth a line when it is not the ordinary
                // two-sided one — but it stays tappable, so it can be switched
                // back.
                if !modeChoices.isEmpty, !isCollapsed || exercise.unilateralMode != .bilateral {
                    modeMenu
                }
                if !assistanceChoices.isEmpty, !isCollapsed || exercise.assistance.isAssisted {
                    AssistanceMenu(assistance: exercise.assistance, choices: assistanceChoices, onChange: actions.setAssistance)
                }
                noteButton
                historyButton
            }

            // The hint belongs to the history button, so it follows it into
            // the folded state.
            if showsHistoryHint {
                Text("No history yet for this exercise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            // Folded away with the sets: the instructions, the note and the
            // number to beat belong to the exercise being worked on, and a
            // collapsed card is one that is out of the way.
            if !isCollapsed {
                ExerciseTextsLines(instructions: exercise.instructions, note: exercise.notes, action: actions.openNote)
                lastPerformanceRow

                if exercise.unilateralMode != .bilateral {
                    StartSideMenu(exercise: exercise, onChange: actions.setStartSide)
                }
                if exercise.unilateralMode == .perSide {
                    if sideLayout == .tabs {
                        Picker("Side", selection: $selectedSide) {
                            ForEach(ExerciseSide.allCases, id: \.self) { side in
                                Text(side == firstTab ? "\(side.title) · 1st" : side.title).tag(side)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
        .listRowSeparator(isCollapsed ? .hidden : .visible)
        // The long press works on the exercise's own rows but not on its sets,
        // which keep their own minus button for a single set.
        .contextMenu {
            Button(role: .destructive, action: actions.delete) {
                Label("Delete Exercise", systemImage: "trash")
            }
            if canConvertToSuperset {
                Button(action: actions.convertToSuperset) {
                    Label("Convert to Superset…", systemImage: "link")
                }
            }
            EffortScaleMenu(scale: exercise.effortScale, onChange: actions.setEffortScale)
            // An exercise that logs once has one row and nothing to reorder
            // it against.
            if tracksSets, displayedSets.count > 1 {
                Button { reorderingSets = true } label: {
                    Label("Reorder Sets…", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .sheet(isPresented: $reorderingSets) {
            SetReorderView(title: reorderTitle, rows: displayedSets.map(reorderRow), onMove: actions.moveSets)
        }

        if !isCollapsed {
            sets
        }
    }

    @ViewBuilder
    private var sets: some View {
        if displayedSets.isEmpty {
            Text("No sets yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(displayedSets) { set in
                VStack(alignment: .leading, spacing: 4) {
                    if listsBothSides {
                        Text("\(set.side == .left ? "Left" : "Right") · Set \(set.setNumber)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    SetRowView(setEntry: set, showsSetControls: tracksSets) {
                        actions.deleteSet(set)
                    } onCopy: {
                        actions.copySet(set)
                    } onEffortChange: {
                        actions.effortChanged()
                    }
                }
                .listRowBackground(set.id == currentSetID ? GuideHighlight() : nil)
            }
        }

        if tracksSets || displayedSets.isEmpty {
            HStack {
                if listsBothSides {
                    ForEach(ExerciseSide.allCases, id: \.self) { side in
                        Button {
                            actions.addSetOn(side)
                        } label: {
                            Label(side.title, systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add Set on the \(side.title)")
                    }
                } else {
                    Button(action: actions.addSet) {
                        Label("Add Set", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 8)
                machineMenu
                Spacer(minLength: 8)
                // A rest follows a set, so an exercise logged once has none.
                if tracksSets {
                    RestMenu(seconds: restSeconds, defaultSeconds: defaultRest, onChange: actions.setRest)
                }
            }
        }
    }

    /// The side marked as first. A template that prescribes nothing marks none.
    private var firstTab: ExerciseSide? {
        exercise.isInTemplate ? exercise.statedStartSide : startSide
    }

    /// The side on screen is the one reordered, so the list says which.
    private var reorderTitle: String {
        exercise.unilateralMode == .perSide && !listsBothSides ? "\(exercise.name) · \(selectedSide.title)" : exercise.name
    }

    private func reorderRow(_ set: SetEntry) -> SetReorderRow {
        let name = listsBothSides ? "\(set.side == .left ? "Left" : "Right") · Set \(set.setNumber)" : "Set \(set.setNumber)"
        return SetReorderRow(set, name: name, unit: weightUnit)
    }

    private var listsBothSides: Bool {
        exercise.unilateralMode == .perSide && sideLayout == .list
    }

    /// Whether the set to do next is this exercise's, on either side.
    private var isCurrent: Bool {
        currentSetID.map { id in exercise.sets.contains { $0.id == id } } ?? false
    }

    private var noteButton: some View {
        let hasNote = exercise.hasInstructionsOrNote
        return Button(action: actions.openNote) {
            Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                .foregroundStyle(hasNote ? Color.blue : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var historyButton: some View {
        Button(action: actions.tapHistory) {
            Image(systemName: "chart.xyaxis.line")
                .foregroundStyle(hasHistory ? Color.blue : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    /// The last time this exercise was logged, spelled out under its name. It
    /// opens the full history on a tap, so the line is a shortcut into the same
    /// place the chart icon leads to rather than a dead end.
    @ViewBuilder
    private var lastPerformanceRow: some View {
        if let lastPerformance {
            Button(action: actions.openHistory) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                    Text(lastPerformance.summary(unit: weightUnit))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lastPerformance.spokenSummary(unit: weightUnit))
            .accessibilityHint("Opens the full history")
        }
    }

    /// The capsule doubles as its own switch: it shows how the exercise was
    /// trained and opens the choice, so the common two-sided case costs the row
    /// nothing more than one small label.
    private var modeMenu: some View {
        Menu {
            Picker("Trained", selection: Binding(get: { exercise.unilateralMode }, set: actions.setMode)) {
                ForEach(modeChoices, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } label: {
            UnilateralModeBadge(mode: exercise.unilateralMode)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trained: \(exercise.unilateralMode.title)")
    }
}

/// Which side a unilateral exercise starts with, above its sets. A template
/// prescribes a side or leaves it to the last time; a workout always has one.
struct StartSideMenu: View {
    let exercise: ExerciseEntry
    let onChange: (ExerciseSide?) -> Void

    private var title: String {
        if exercise.isInTemplate, exercise.statedStartSide == nil { return "Last Time" }
        return exercise.startSide.title
    }

    private var selection: Binding<ExerciseSide?> {
        Binding(
            get: { exercise.isInTemplate ? exercise.statedStartSide : exercise.startSide },
            set: onChange
        )
    }

    var body: some View {
        Menu {
            Picker("Starts with", selection: selection) {
                if exercise.isInTemplate {
                    Text("Last Time").tag(ExerciseSide?.none)
                }
                ForEach(ExerciseSide.allCases, id: \.self) { side in
                    Text(side.title).tag(ExerciseSide?.some(side))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Starts with \(title)")
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.caption)
        }
        .buttonStyle(.borderless)
    }
}
