import SwiftUI

/// A superset's card in the workout editor: the fold row, a line per exercise
/// with its own mode, note and history, then every set of both in the order
/// they were done. A is the upper exercise, B the lower; B's name and sets are
/// tinted in the accent colour; both carry a bar on the leading edge, grey
/// for A and accent for B, so a set reads as belonging to one or the other without a label.
///
/// Like `ExerciseCardView`, the card shows and reports; its body is several
/// list rows and belongs directly inside a `Section`.
struct SupersetCardView: View {
    /// One of the two exercises, as the card needs it.
    struct Member {
        let exercise: ExerciseEntry
        let tracksSets: Bool
        /// The modes the exercise's menu offers outside a superset; empty
        /// when there is nothing to choose.
        let modeChoices: [UnilateralMode]
        /// The kinds of help on offer; empty when the exercise offers none.
        let assistanceChoices: [Assistance]
        let hasHistory: Bool
        let showsHistoryHint: Bool
        let lastPerformance: LastPerformance?
        /// The machine it is done at, built by the editor.
        let machineMenu: MachineMenu
        let actions: MemberActions
    }

    struct MemberActions {
        var setMode: (UnilateralMode) -> Void
        var setAssistance: (Assistance) -> Void
        var openNote: () -> Void
        var tapHistory: () -> Void
        var openHistory: () -> Void
        var delete: () -> Void
        var addSet: () -> Void
        var setEffortScale: (EffortScale) -> Void
        var setStartSide: (ExerciseSide?) -> Void
    }

    struct SetActions {
        var deleteSet: (SetEntry) -> Void
        var copySet: (SetEntry) -> Void
        var effortChanged: () -> Void
        var moveSets: (IndexSet, Int) -> Void
    }

    let a: Member
    let b: Member
    let isCollapsed: Bool
    /// Both exercises' sets, in the order they were done.
    let orderedSets: [SetEntry]
    let weightUnit: WeightUnit
    /// B's own rest, nil when it follows `defaultRest`: a round ends with B,
    /// so the rest after it is B's.
    let restSeconds: Int?
    let defaultRest: Int
    /// The set to do next, when the editor guides through the workout.
    let currentSetID: UUID?
    let setRest: (Int?) -> Void
    let toggleCollapsed: () -> Void
    let setActions: SetActions

    @State private var reorderingSets = false

    /// A's rows: the card as it is, with a grey bar on the leading edge — the
    /// same mark as B's, without the tint, so the two read as a pair.
    static var aBackground: some View {
        rowBackground(tint: .clear, bar: Color(.systemGray3))
    }

    /// B's rows: a faint accent over the card and an accent bar. Grey read
    /// like the page showing through the card; the accent is used nowhere
    /// else as a row background and matches the Add buttons. The bars still
    /// mark the rows for anyone who tells the tint apart poorly.
    static var bBackground: some View {
        rowBackground(tint: Color.accentColor.opacity(0.09), bar: .accentColor)
    }

    /// Laid over the card, so it holds up in dark mode.
    private static func rowBackground(tint: Color, bar: Color) -> some View {
        ZStack(alignment: .leading) {
            Color(.secondarySystemGroupedBackground)
            tint
            bar.frame(width: 3)
        }
    }

    var body: some View {
        // Once for the card: either member's menu opens it.
        foldRow
            .sheet(isPresented: $reorderingSets) {
                SetReorderView(
                    title: "\(a.exercise.name) + \(b.exercise.name)",
                    rows: orderedSets.map { set in
                        let name = set.exercise?.id == b.exercise.id ? b.exercise.name : a.exercise.name
                        return SetReorderRow(set, name: "\(name) · Set \(set.setNumber)", unit: weightUnit)
                    },
                    onMove: setActions.moveSets
                )
            }

        memberRow(a)
            .listRowBackground(Self.aBackground)
        memberRow(b)
            .listRowBackground(Self.bBackground)

        if !isCollapsed {
            if orderedSets.isEmpty {
                Text("No sets yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(orderedSets) { set in
                    let member = set.exercise?.id == b.exercise.id ? b : a
                    SetRowView(setEntry: set, showsSetControls: member.tracksSets) {
                        setActions.deleteSet(set)
                    } onCopy: {
                        setActions.copySet(set)
                    } onEffortChange: {
                        setActions.effortChanged()
                    }
                    .listRowBackground(
                        set.id == currentSetID ? AnyView(GuideHighlight())
                            : member.exercise.id == b.exercise.id ? AnyView(Self.bBackground) : AnyView(Self.aBackground)
                    )
                    .accessibilityLabel("\(member.exercise.name), set \(set.setNumber)")
                }
            }

            addButtons
        }
    }

    private var foldRow: some View {
        Button(action: toggleCollapsed) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Label("Superset", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilityLabel("Superset")
        .accessibilityHint(isCollapsed ? "Expand superset" : "Collapse superset")
    }

    /// The exercise's name with its own mode, note and history — the two can
    /// be trained differently and each has a history of its own.
    private func memberRow(_ member: Member) -> some View {
        let exercise = member.exercise
        let hasNote = exercise.hasInstructionsOrNote
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(currentSetID.map { id in exercise.sets.contains { $0.id == id } } == true ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                if exercise.isUserDefined { UserDefinedBadge() }
                Spacer(minLength: 8)
                if supersetChoices(member).count > 1, !isCollapsed || exercise.unilateralMode != .bilateral {
                    modeMenu(member)
                } else if exercise.unilateralMode != .bilateral {
                    // A one-sided exercise has one mode left here, but how it
                    // is logged still deserves its label.
                    UnilateralModeBadge(mode: exercise.unilateralMode)
                }
                if !member.assistanceChoices.isEmpty, !isCollapsed || exercise.assistance.isAssisted {
                    AssistanceMenu(assistance: exercise.assistance, choices: member.assistanceChoices, onChange: member.actions.setAssistance)
                }
                Button(action: member.actions.openNote) {
                    Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                        .foregroundStyle(hasNote ? Color.blue : Color.secondary)
                }
                .buttonStyle(.plain)
                Button(action: member.actions.tapHistory) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(member.hasHistory ? Color.blue : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            if member.showsHistoryHint {
                Text("No history yet for this exercise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            if !isCollapsed {
                ExerciseTextsLines(instructions: exercise.instructions, note: exercise.notes, action: member.actions.openNote)
                if exercise.unilateralMode != .bilateral {
                    StartSideMenu(exercise: exercise, onChange: member.actions.setStartSide)
                }
                HStack {
                    member.machineMenu
                    Spacer(minLength: 0)
                }
            }

            if !isCollapsed, let performance = member.lastPerformance {
                Button(action: member.actions.openHistory) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                        Text(performance.summary(unit: weightUnit))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(performance.spokenSummary(unit: weightUnit))
                .accessibilityHint("Opens the full history")
            }
        }
        .listRowSeparator(.hidden)
        .contextMenu {
            Button(role: .destructive, action: member.actions.delete) {
                Label("Delete Exercise", systemImage: "trash")
            }
            EffortScaleMenu(scale: member.exercise.effortScale, onChange: member.actions.setEffortScale)
            // The rounds share one order, so either exercise's menu moves
            // the sets of both.
            if orderedSets.count > 1 {
                Button { reorderingSets = true } label: {
                    Label("Reorder Sets…", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    /// Left/Right is not offered: it splits one exercise's sets into two
    /// lists, which does not fit one shared order of rounds.
    private func supersetChoices(_ member: Member) -> [UnilateralMode] {
        member.modeChoices.filter { $0 != .perSide }
    }

    private func modeMenu(_ member: Member) -> some View {
        let exercise = member.exercise
        return Menu {
            Picker("Trained", selection: Binding(get: { exercise.unilateralMode }, set: member.actions.setMode)) {
                ForEach(supersetChoices(member), id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } label: {
            UnilateralModeBadge(mode: exercise.unilateralMode)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trained: \(exercise.unilateralMode.title)")
    }

    /// One button per exercise, each adding a set at the end of the order.
    private var addButtons: some View {
        HStack(spacing: 24) {
            if a.tracksSets || !orderedSets.contains(where: { $0.exercise?.id == a.exercise.id }) {
                addButton("Add A", accessibility: a.exercise.name, action: a.actions.addSet)
            }
            if b.tracksSets || !orderedSets.contains(where: { $0.exercise?.id == b.exercise.id }) {
                addButton("Add B", accessibility: b.exercise.name, action: b.actions.addSet)
            }
            Spacer(minLength: 0)
            if a.tracksSets || b.tracksSets {
                RestMenu(seconds: restSeconds, defaultSeconds: defaultRest, onChange: setRest)
            }
        }
    }

    private func addButton(_ title: String, accessibility name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Add set to \(name)")
    }
}
