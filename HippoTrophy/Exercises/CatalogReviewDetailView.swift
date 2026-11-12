import SwiftUI
import SwiftData

/// One own exercise in the review: the catalog exercises it could move to,
/// and the choice to keep or delete it instead.
struct CatalogReviewDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]
    @AppStorage(SettingsKey.keptOwnExercises) private var keptStored = ""
    @AppStorage(SettingsKey.catalogMovedCount) private var movedCount = 0

    let definition: ExerciseDefinition

    @State private var pendingTarget: ExerciseDefinition?
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showDelete = false

    private var record: ExerciseRecord { BackupExporter.record(definition) }

    /// The catalog exercises it can move to, best guess first, with the
    /// stored definition behind each.
    private var targets: [ExerciseDefinition] {
        let catalog = definitions.filter(\.isCatalog)
        let byName = Dictionary(catalog.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return CatalogMigration.targets(for: record, among: catalog.map(BackupExporter.record)).compactMap { byName[$0.name] }
    }

    private var suggestedNames: Set<String> {
        let catalog = definitions.filter(\.isCatalog).map(BackupExporter.record)
        return Set(CatalogMigration.suggestions(for: record, among: catalog).map(\.name))
    }

    private var workoutCount: Int {
        ExerciseMerging.workoutCount(loggedFrom: definition, in: modelContext)
    }

    private var isKept: Bool {
        KeptOwnExercises(stored: keptStored).ids.contains(definition.id)
    }

    var body: some View {
        let targets = self.targets
        let suggested = targets.filter { suggestedNames.contains($0.name) }.prefix(3)
        let count = workoutCount

        List {
            Section {
                ExerciseDefinitionRow(definition: definition, amongCatalog: false)
                LabeledContent("Logged in", value: count == 1 ? "1 workout" : "\(count) workouts")
            }

            if !suggested.isEmpty {
                Section {
                    ForEach(Array(suggested)) { target in
                        moveButton(to: target)
                    }
                } header: {
                    Text("Move to the Catalog")
                } footer: {
                    Text("Its workouts move to the catalog exercise and keep every value; \"\(definition.name)\" is removed from My Exercises.")
                }
            }

            Section {
                if targets.isEmpty {
                    Text("No catalog exercise logs the same kinds of values.")
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink("Another Catalog Exercise…") {
                        List(targets) { target in
                            moveButton(to: target)
                        }
                        .navigationTitle("Move To")
                    }
                }
            }

            Section {
                Button(isKept ? "Ask Again" : "Keep as Mine") {
                    let keeping = !isKept
                    var kept = KeptOwnExercises(stored: keptStored)
                    if keeping { kept.ids.insert(definition.id) } else { kept.ids.remove(definition.id) }
                    keptStored = kept.stored
                    if keeping { dismiss() }
                }
                if count == 0 {
                    Button("Delete", role: .destructive) { showDelete = true }
                }
            } footer: {
                Text(count == 0
                     ? "Kept, it stays one of My Exercises and is not brought up again. Never logged, it can also go."
                     : "Kept, it stays one of My Exercises and is not brought up again.")
            }
        }
        .navigationTitle(definition.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { pendingTarget != nil }, set: { if !$0 { pendingTarget = nil } }), titleVisibility: .visible) {
            Button("Move") { move() }
            Button("Cancel", role: .cancel) { pendingTarget = nil }
        } message: {
            Text(count == 1
                 ? "The 1 workout logged with it moves over and keeps every value."
                 : "The \(count) workouts logged with it move over and keep every value.")
        }
        .confirmationDialog("Delete \"\(definition.name)\"?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        }
        .alert("Review", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var confirmationTitle: String {
        guard let pendingTarget else { return "" }
        return "Move \"\(definition.name)\" to \"\(pendingTarget.name)\"?"
    }

    private func moveButton(to target: ExerciseDefinition) -> some View {
        Button {
            pendingTarget = target
        } label: {
            ExerciseDefinitionRow(definition: target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func move() {
        guard let target = pendingTarget,
              let mapping = CatalogMigration.mapping(from: record, into: BackupExporter.record(target))
        else { return }
        pendingTarget = nil
        do {
            try ExerciseMerging.merge(definition, into: target, mapping: mapping, in: modelContext)
            try modelContext.save()
            movedCount += 1
            dismiss()
        } catch {
            modelContext.rollback()
            alertMessage = ModelContext.failureMessage("Could not move.", error)
            showAlert = true
        }
    }

    private func delete() {
        modelContext.delete(definition)
        if let failure = modelContext.save(reporting: "Could not delete exercise.") {
            alertMessage = failure
            showAlert = true
        } else {
            dismiss()
        }
    }
}
