import SwiftUI
import SwiftData
import UIKit

/// The exercise list: everything that can be added to a workout, and the way
/// to tidy it up. Beside an exercise is the way into its history.
struct ManageExercisesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]
    @Query private var loggedExercises: [ExerciseEntry]

    @State private var filter: ExerciseFilter
    @FocusState private var isSearching: Bool
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showNewEditor = false
    @State private var openedDefinition: ExerciseDefinition?
    @State private var historyDefinition: ExerciseDefinition?
    @State private var showImportFlow = false
    @State private var showReview = false
    @State private var showMerge = false
    /// The exercise a swipe asked to delete, held until the alert confirms it.
    @State private var pendingDeletion: ExerciseDefinition?
    @AppStorage(SettingsKey.keptOwnExercises) private var keptStored = ""

    /// - Parameter opensUnfiled: whether only the exercises without a muscle
    ///   group are shown on arrival — the muscle group overview sends people
    ///   here for the exercises it cannot count.
    init(opensUnfiled: Bool = false) {
        _filter = State(initialValue: ExerciseFilter(muscle: opensUnfiled ? .unfiled : nil))
    }

    /// Names with a history, so a row can offer it with a set lookup. Read
    /// from the query, so a workout logged elsewhere shows up without a reload.
    private var identitiesWithHistory: Set<ExerciseIdentity> {
        ExerciseHistory(entries: loggedExercises).identitiesWithHistory
    }

    var body: some View {
        // Built once rather than per row: every row asks the same question
        // of the same entries.
        let historyNames = identitiesWithHistory

        ExerciseBrowser(
            definitions: definitions,
            filter: $filter,
            searchFocused: $isSearching,
            onAdd: { addDefinition(named: $0) },
            onOpen: { openedDefinition = $0 },
            onDelete: { pendingDeletion = $0 },
            accessory: { historyButton($0, historyNames: historyNames) }
        )
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showNewEditor = true
                } label: {
                    // Not a `Label`: the bar would keep only its icon, and a
                    // plus alone does not say what it adds.
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Own")
                    }
                    .fixedSize()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ExerciseGridToggle()
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
            }
        }
        .navigationDestination(isPresented: $showImportFlow) {
            ImportExerciseListView(onImported: { showImportFlow = false })
        }
        .navigationDestination(isPresented: $showReview) {
            CatalogReviewView()
        }
        .sheet(item: $historyDefinition) { definition in
            ExerciseHistoryView(exerciseName: definition.name, identity: definition.identity, currentSessionID: nil)
        }
        .sheet(isPresented: $showNewEditor) {
            ExerciseEditorView()
        }
        .sheet(isPresented: $showMerge) {
            MergeExercisesView()
        }
        .sheet(item: $openedDefinition) { definition in
            ExerciseDetailView(definition: definition)
        }
        .alert(
            "Delete \"\(pendingDeletion?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let definition = pendingDeletion { delete(definition) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(deletionMessage)
        }
        .alert("Exercises", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    /// How many own exercises may be catalog ones with nobody having said
    /// otherwise. The menu's dot and its first line say so.
    private var pendingReview: Int {
        CatalogReview.pendingCount(in: definitions, kept: KeptOwnExercises(stored: keptStored).ids)
    }

    /// What is done to the list rather than to one exercise.
    private var moreMenu: some View {
        let pending = pendingReview
        return Menu {
            if definitions.contains(where: { !$0.isCatalog }) {
                Button {
                    showReview = true
                } label: {
                    Text("Review My Exercises…")
                    Text(pending == 0
                         ? "Move one to the catalog exercise it is, keep it, or delete it."
                         : pending == 1
                         ? "1 of your exercises may be in the catalog."
                         : "\(pending) of your exercises may be in the catalog.")
                    if pending > 0 {
                        Self.yellowTriangle
                    } else {
                        Image(systemName: "books.vertical")
                    }
                }
            }
            Button {
                showImportFlow = true
            } label: {
                Label("Import Exercise List…", systemImage: "square.and.arrow.down")
            }
            if definitions.count > 1 {
                Button {
                    showMerge = true
                } label: {
                    Text("Merge Two Exercises…")
                    Text("For two names that turned out to be one exercise.")
                    Image(systemName: "arrow.triangle.merge")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .overlay(alignment: .topTrailing) {
                    if pending > 0 {
                        Circle()
                            .fill(.yellow)
                            .frame(width: 9, height: 9)
                            .offset(x: 6, y: -5)
                    }
                }
                .accessibilityLabel(pending > 0 ? "More, exercises to review" : "More")
        }
    }

    /// A menu draws a symbol in one colour of its own, whatever the view asks
    /// for; only an image that brings its colour along stays yellow.
    private static var yellowTriangle: Image {
        let symbol = UIImage(systemName: "exclamationmark.triangle.fill") ?? UIImage()
        return Image(uiImage: symbol.withTintColor(.systemYellow, renderingMode: .alwaysOriginal))
    }

    /// The way into an exercise's history.
    ///
    /// Always there and greyed out while nothing has been logged under this
    /// name — the same way the workout detail shows it. Hiding it made a row
    /// change shape for a reason that has nothing to do with the exercise, and
    /// read as if only some kinds of exercise had a history.
    private func historyButton(_ definition: ExerciseDefinition, historyNames: Set<ExerciseIdentity>) -> some View {
        let hasHistory = historyNames.contains(definition.identity)
        return Button {
            historyDefinition = definition
        } label: {
            Image(systemName: "chart.xyaxis.line")
                .foregroundStyle(hasHistory ? Color.blue : Color.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(!hasHistory)
        .accessibilityLabel("History for \(definition.name)")
    }

    private func addDefinition(named trimmed: String) {
        guard ExerciseNaming.isFree(trimmed, amongOwn: definitions.map { ($0.name, $0.catalogKey) }) else {
            alertMessage = "An exercise named \"\(trimmed)\" already exists."
            showAlert = true
            return
        }

        let nextIndex = (definitions.map(\.orderIndex).max() ?? -1) + 1
        ExerciseDefinition.insertPlainSetsAndReps(name: trimmed, orderIndex: nextIndex, in: modelContext)
        if saveContext("Could not add exercise.") {
            filter.query = ""
        }
    }

    /// Deleting a definition leaves logged entries intact: they carry their own
    /// name, labels and types, so past workouts keep rendering unchanged.
    /// What deleting leaves behind: the workouts keep what was logged, so the
    /// question is only whether the exercise stays in the list.
    private var deletionMessage: String {
        guard let definition = pendingDeletion else { return "" }
        let workouts = loggedExercises
            .filter { $0.identity == definition.identity }
            .trainedWorkoutCount
        switch workouts {
        case 0: return "It leaves your list. It was never logged."
        case 1: return "It leaves your list. The 1 workout logged with it keeps its values."
        default: return "It leaves your list. The \(workouts) workouts logged with it keep their values."
        }
    }

    private func delete(_ definition: ExerciseDefinition) {
        modelContext.delete(definition)
        _ = saveContext("Could not delete exercise.")
    }

    @discardableResult
    private func saveContext(_ fallbackMessage: String) -> Bool {
        guard let failure = modelContext.save(reporting: fallbackMessage) else { return true }
        alertMessage = failure
        showAlert = true
        return false
    }
}

#Preview {
    NavigationStack {
        ManageExercisesView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
