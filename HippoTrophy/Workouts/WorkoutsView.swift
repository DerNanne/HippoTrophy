import SwiftUI
import SwiftData

/// The first tab: the week, the templates and the history, and the way into
/// a workout.
struct WorkoutsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: WorkoutSession.trained, sort: \WorkoutSession.date, order: .reverse) private var allSessions: [WorkoutSession]
    private let runningWorkout = RunningWorkoutCenter.shared
    /// Whether the workout being trained is pushed. It is on the stack, not
    /// over it, so Back leaves it running behind the banner. Held by the root,
    /// whose other tabs go back into the workout too.
    @Binding var showRunningWorkout: Bool
    /// What the editor shows while it is open. One value rather than a
    /// session and a flag: a cover opened by a flag is built from whatever
    /// the session was at the last redraw, and opening a template to edit —
    /// which changes nothing else on screen — showed an empty page.
    @State private var editing: EditorTarget?

    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showSettings = false
    @AppStorage(SettingsKey.showActivityGraph) private var showActivityGraph = true
    // The chosen period outlives the session: reopening the app lands on the
    // list the user last left, including "All" when they cleared the filter.
    @AppStorage(SettingsKey.historyPeriod) private var historyPeriodRaw = HistoryPeriod.all.rawValue
    @AppStorage(SettingsKey.historyCustomStart) private var historyCustomStartInterval = 0.0
    @AppStorage(SettingsKey.historyCustomEnd) private var historyCustomEndInterval = 0.0
    @State private var showPeriodSheet = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The rows a swipe asked to delete, held until the dialog confirms it.
    /// Nothing else brings a deleted workout back.
    @State private var pendingDeletion: [WorkoutSession] = []

    /// The workouts done. The one being trained counts once it is finished;
    /// until then it is the banner.
    private var sessions: [WorkoutSession] {
        guard let running = runningWorkout.running else { return allSessions }
        return allSessions.filter { $0.id != running.sessionID }
    }

    /// The workout being trained, looked up in the store rather than in the
    /// query, which has not always caught up with one just started.
    private var runningSession: WorkoutSession? {
        runningWorkout.running.flatMap { workout(withID: $0.sessionID) }
    }

    private var weekSessions: [WorkoutSession] {
        let calendar = Calendar.current
        // The whole interval, not only its start: a workout dated next year
        // is not this week's.
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date.now) else { return [] }
        return sessions.filter { $0.date >= week.start && $0.date < week.end }
    }

    private var weekWorkoutCount: Int {
        weekSessions.count
    }

    private var weekSetCount: Int {
        weekSessions.reduce(0) { $0 + $1.setCount }
    }

    private var historyPeriod: HistoryPeriod {
        HistoryPeriod(rawValue: historyPeriodRaw) ?? .all
    }

    private var historyPeriodBinding: Binding<HistoryPeriod> {
        Binding(get: { historyPeriod }, set: { historyPeriodRaw = $0.rawValue })
    }

    private var historyCustomStart: Date? {
        guard historyCustomStartInterval > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: historyCustomStartInterval)
    }

    /// A range saved before the end date existed has no upper bound, which is
    /// the same thing an end of today meant back then.
    private var historyCustomEnd: Date? {
        guard historyCustomEndInterval > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: historyCustomEndInterval)
    }

    /// The sessions the history list shows. Unbounded on both sides means no
    /// filter, so the unfiltered list stays exactly the list it was before.
    private var visibleSessions: [WorkoutSession] {
        let bounds = HistoryPeriodRange.bounds(
            for: historyPeriod,
            customStart: historyCustomStart,
            customEnd: historyCustomEnd
        )
        guard bounds.start != nil || bounds.endExclusive != nil else { return sessions }
        return sessions.filter { bounds.contains($0.date) }
    }

    private var historyGroups: [HistoryGroup] {
        HistoryGrouper.groups(for: visibleSessions, grouping: historyPeriod.grouping)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // SwiftUI's large title has no trailing slot, so the title is
                    // drawn in the list and the navigation bar stays inline.
                    // Side by side, the week shrinking a little to fit; from
                    // extra large text on it goes under the title rather
                    // than losing its numbers.
                    Group {
                    if dynamicTypeSize >= .xLarge {
                        VStack(alignment: .leading, spacing: 4) {
                            appTitle
                            weekSummary
                        }
                    } else {
                        HStack(alignment: .bottom) {
                            appTitle
                                .layoutPriority(1)
                            Spacer(minLength: 8)
                            weekSummary
                                .padding(.bottom, 6)
                        }
                    }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 2, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if showActivityGraph {
                    // The pager draws its own cards, so they can slide in
                    // from the screen's edge rather than inside the section's.
                    Section {
                        ActivityGraphPager(sessions: sessions)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listSectionMargins(.horizontal, 0)
                    .listRowSeparator(.hidden)
                }

                TemplatesSection(canStart: runningSession == nil, open: { open($0, as: $1, usingUp: $2) })

                Section {
                    if sessions.isEmpty {
                        Text("No workouts yet. Tap Start Workout to begin.")
                            .foregroundStyle(.secondary)
                    } else if visibleSessions.isEmpty {
                        emptyPeriodRow
                    } else {
                        ForEach(historyGroups) { group in
                            if let title = group.title {
                                groupHeaderRow(title)
                            }
                            ForEach(group.sessions) { session in
                                sessionRow(session)
                            }
                            .onDelete { offsets in
                                pendingDeletion = offsets
                                    .filter { group.sessions.indices.contains($0) }
                                    .map { group.sessions[$0] }
                            }
                        }
                    }
                } header: {
                    historyHeader
                }
            }
            // The default grouped spacing leaves the activity graph floating on
            // its own; tightening it keeps the overview reading as one block.
            .listSectionSpacing(6)
            // The inline bar already provides the top gap; the list's own top
            // inset would otherwise push the title far down the screen.
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Before the toolbar below, so its "Backup" menu lands after the gear.
            .backupFlow()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    // One workout is trained at a time. "Resume Workout" no
                    // longer fits beside Backup and goes into the overflow.
                    if runningSession != nil {
                        Button("Resume") { showRunningWorkout = true }
                    } else {
                        Button("Start Workout") {
                            open(WorkoutSession(), as: .new(failure: "Could not create workout."))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                RunningWorkoutSlot { showRunningWorkout = true }
            }
            .navigationDestination(isPresented: $showRunningWorkout) {
                if let running = runningWorkout.running, let session = runningSession {
                    WorkoutEditorView(
                        session: session,
                        discardSessionOnCancel: true,
                        isBeingTrained: true,
                        usesUp: running.usesUpID.flatMap(workout(withID:))
                    )
                    // The bottom of the screen belongs to the rest timer.
                    .toolbar(.hidden, for: .tabBar)
                }
            }
            // Deleted elsewhere, or gone with a restored backup.
            .onChange(of: allSessions.map(\.id), initial: true) { _, _ in
                runningWorkout.forgetIfGone { workout(withID: $0) != nil }
            }
            .fullScreenCover(item: $editing) { target in
                WorkoutEditorView(
                    session: target.session,
                    discardSessionOnCancel: target.discardsOnCancel,
                    usesUp: target.usesUp
                )
            }

            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .whatsNewAtLaunch()
            .catalogReviewAtLaunch()
            .sheet(isPresented: $showPeriodSheet) {
                HistoryPeriodSheet(
                    currentStart: historyCustomStart,
                    currentEnd: historyCustomEnd,
                    earliestSessionDate: sessions.last?.date
                ) { start, end in
                    let calendar = Calendar.current
                    historyCustomStartInterval = calendar
                        .startOfDay(for: start)
                        .timeIntervalSinceReferenceDate
                    historyCustomEndInterval = calendar
                        .startOfDay(for: end)
                        .timeIntervalSinceReferenceDate
                    historyPeriodRaw = HistoryPeriod.custom.rawValue
                }
            }
            // An alert rather than a confirmation dialog: on the whole list the
            // dialog becomes a popover pointing at the activity graph, not at
            // the row, and it drops Cancel.
            .alert(
                deletionTitle,
                isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
            ) {
                Button("Delete", role: .destructive) { deletePendingSessions() }
                Button("Cancel", role: .cancel) { pendingDeletion = [] }
            } message: {
                Text(deletionMessage)
            }
            .alert("Workouts", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var appTitle: some View {
        Text("HippoTrophy")
            .font(.largeTitle.bold())
            .lineLimit(1)
    }

    private var weekSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This Week")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("\(CountFormat.text(weekWorkoutCount, "workout", "workouts")) · \(CountFormat.text(weekSetCount, "set", "sets"))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    /// The "History" header carries the period filter, so the control sits with
    /// the list it changes instead of in the crowded navigation bar.
    private var historyHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("History")
            Spacer(minLength: 8)
            HistoryPeriodMenu(
                period: historyPeriodBinding,
                customStart: historyCustomStart,
                customEnd: historyCustomEnd
            ) {
                showPeriodSheet = true
            }
        }
    }

    private func groupHeaderRow(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
    }

    private var emptyPeriodRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No workouts in this period.")
                .foregroundStyle(.secondary)
            Button("Show All") {
                historyPeriodRaw = HistoryPeriod.all.rawValue
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        NavigationLink {
            WorkoutDetailView(session: session)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    if session.name.isEmpty {
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                    } else {
                        Text(session.name)
                            .font(.headline)
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(session.gym.map { "\(session.summary) • \($0.name)" } ?? session.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .contextMenu {
            Button {
                duplicateWorkout(session)
            } label: {
                Label("Copy Workout", systemImage: "doc.on.doc")
            }
            // A copy is trained, and one workout is at a time.
            .disabled(runningSession != nil)
            if session.canBeKeptAsTemplate {
                Button {
                    keepTemplate(of: session)
                } label: {
                    Label("Save as Template", systemImage: "rectangle.stack.badge.plus")
                }
            }
        }
    }

    private var deletionTitle: String {
        guard pendingDeletion.count == 1, let session = pendingDeletion.first else {
            return "Delete \(pendingDeletion.count) Workouts?"
        }
        return session.name.isEmpty
            ? "Delete the Workout from \(session.date.formatted(date: .abbreviated, time: .shortened))?"
            : "Delete \"\(session.name)\"?"
    }

    private var deletionMessage: String {
        WorkoutDeletion.message(
            setCount: pendingDeletion.reduce(0) { $0 + $1.setCount },
            workoutCount: pendingDeletion.count
        )
    }

    private func deletePendingSessions() {
        for session in pendingDeletion {
            modelContext.delete(session)
        }
        pendingDeletion = []
        _ = saveContext("Could not delete workout.")
    }

    private func duplicateWorkout(_ session: WorkoutSession) {
        open(session.trainingCopy(dated: .now, in: modelContext), as: .new(failure: "Could not copy workout."))
    }

    /// Lands first on the template shelf, right above the list, where it is
    /// seen without opening anything.
    private func keepTemplate(of session: WorkoutSession) {
        withAnimation {
            TemplateShelf.keepTemplate(of: session, in: modelContext)
        }
        saveContext("Could not save template.")
    }

    /// Opens a workout or template in the editor. A new one is inserted
    /// first, and Cancel deletes it again.
    /// A new workout is the one being trained from then on, pushed rather
    /// than covering the screen.
    private func open(_ session: WorkoutSession, as opening: EditorOpening, usingUp dayVariant: WorkoutSession? = nil) {
        if case .new(let failure) = opening {
            guard session.isTemplate || runningSession == nil else { return }
            modelContext.insert(session)
            guard saveContext(failure) else {
                modelContext.delete(session)
                return
            }
            if !session.isTemplate {
                runningWorkout.start(
                    session.id,
                    at: .now,
                    usesUpID: dayVariant?.id,
                    initialSnapshot: WorkoutSnapshot(session: session)
                )
                showRunningWorkout = true
                return
            }
        }
        editing = EditorTarget(session: session, discardsOnCancel: opening != .existing, usesUp: dayVariant)
    }

    private func workout(withID id: UUID) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    @discardableResult
    private func saveContext(_ fallbackMessage: String) -> Bool {
        guard let failure = modelContext.save(reporting: fallbackMessage) else { return true }
        alertMessage = failure
        showAlert = true
        return false
    }
}

/// The template or workout opened again in the editor, whether Cancel
/// deletes it — it does for a template made for the editor, not for one
/// opened to edit — and the day variant Save uses up. A workout being trained is not here; it is pushed.
private struct EditorTarget: Identifiable {
    let session: WorkoutSession
    let discardsOnCancel: Bool
    let usesUp: WorkoutSession?

    var id: PersistentIdentifier { session.persistentModelID }
}

#Preview {
    WorkoutsView(showRunningWorkout: .constant(false))
        .modelContainer(for: AppSchema.models, inMemory: true)
}
