import SwiftUI
import SwiftData

/// Folds one exercise into another: "Rudermaschine" and "Rowing" turn out to
/// be the same thing, so one goes and its history moves over. The user maps
/// the fields, because behind every field is a title they wrote.
struct MergeExercisesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]

    @State private var sourceID: UUID?
    @State private var targetID: UUID?
    @State private var mapping = FieldMapping()
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showConfirmation = false

    private var source: ExerciseDefinition? { definitions.first { $0.id == sourceID } }
    private var target: ExerciseDefinition? { definitions.first { $0.id == targetID } }

    /// Sets and no sets are different kinds of entry; the mode and the
    /// per-set effort of one would mean nothing on the other. Bilateral and
    /// unilateral are different kinds too: their histories are kept apart.
    private var kindsMatch: Bool {
        guard let source, let target else { return true }
        return source.tracksSets == target.tracksSets && source.sides.canMerge(into: target.sides)
    }

    private var problem: DefinitionMerge.Problem? {
        guard let source, let target else { return nil }
        if case .failure(let problem) = DefinitionMerge.merge(
            source: BackupExporter.record(source), into: BackupExporter.record(target), mapping: mapping
        ) {
            return problem
        }
        return nil
    }

    /// A catalog exercise keeps the catalog's fields, so a field of the
    /// first exercise can move onto it only into one it already has.
    private var addsFieldsToCatalog: Bool {
        target?.isCatalog == true && mapping.destinations.values.contains(.newField)
    }

    /// Fields of the first exercise the catalog exercise has nothing for:
    /// then no mapping helps, and the footer says so instead of asking for one.
    private var fieldsCatalogCannotTake: [String] {
        guard let source, let target, target.isCatalog else { return [] }
        return DefinitionMerge.fieldsWithoutCounterpart(
            source: BackupExporter.record(source), target: BackupExporter.record(target)
        )
    }

    private var canMerge: Bool {
        source != nil && target != nil && sourceID != targetID && kindsMatch && problem == nil && !addsFieldsToCatalog
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // A catalog exercise cannot go: it comes with the app.
                    picker("Merge", selection: $sourceID, from: definitions.filter { !$0.isCatalog })
                    picker("Into", selection: $targetID, from: definitions)
                } footer: {
                    if let source, let target, source.tracksSets != target.tracksSets {
                        Text("One of these tracks sets and the other does not. An exercise can only be merged into one of the same kind.")
                            .foregroundStyle(.red)
                    } else if !kindsMatch {
                        Text("One of these is bilateral and the other unilateral. Their weights are not comparable, so they keep separate histories.")
                            .foregroundStyle(.red)
                    } else if !fieldsCatalogCannotTake.isEmpty {
                        let fields = ListFormatter.localizedString(byJoining: fieldsCatalogCannotTake.map { "\"\($0)\"" })
                        Text("\"\(target?.name ?? "")\" comes with the app and keeps its fields. It has no field for \(fields), so these two cannot be merged.")
                            .foregroundStyle(.red)
                    } else if addsFieldsToCatalog {
                        Text("\"\(target?.name ?? "")\" comes with the app and keeps its fields. Map every field to one it has.")
                            .foregroundStyle(.red)
                    } else {
                        Text("The first exercise goes; everything ever logged with it moves to the second, which keeps its name, category and muscles.")
                    }
                }

                if let source, let target, sourceID != targetID, kindsMatch, fieldsCatalogCannotTake.isEmpty, !source.fields.isEmpty {
                    FieldMappingView(
                        source: BackupExporter.record(source),
                        target: BackupExporter.record(target),
                        mapping: $mapping
                    )
                }
            }
            .navigationTitle("Merge Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") { showConfirmation = true }
                        .disabled(!canMerge)
                }
            }
            .onChange(of: sourceID) { _, _ in resetMapping() }
            .onChange(of: targetID) { _, _ in resetMapping() }
            .alert("Merge Exercises", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog(confirmationTitle, isPresented: $showConfirmation, titleVisibility: .visible) {
                Button("Merge", role: .destructive) { merge() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
        }
    }

    private func picker(_ title: String, selection: Binding<UUID?>, from definitions: [ExerciseDefinition]) -> some View {
        Picker(title, selection: selection) {
            Text("Choose…").tag(UUID?.none)
            ForEach(definitions) { definition in
                Text(definition.name).tag(UUID?.some(definition.id))
            }
        }
    }

    private func resetMapping() {
        guard let source, let target else { mapping = FieldMapping(); return }
        mapping = .suggested(from: BackupExporter.record(source), into: BackupExporter.record(target))
    }

    private var confirmationTitle: String {
        guard let source, let target else { return "" }
        return "Merge \"\(source.name)\" into \"\(target.name)\"?"
    }

    private var confirmationMessage: String {
        guard let source else { return "" }
        let count = ExerciseMerging.workoutCount(loggedFrom: source, in: modelContext)
        let moved = count == 1
            ? "The 1 workout logged with it moves over and keeps every value."
            : "The \(count) workouts logged with it move over and keep every value."
        let photoGoes = source.ownPhoto != nil && (target?.photo != nil || target?.isCatalog == true)
        return "\"\(source.name)\" is removed from your list. \(moved)\(photoGoes ? " ⚠️ Its photo is removed with it." : "")"
    }

    private func merge() {
        guard let source, let target else { return }
        do {
            try ExerciseMerging.merge(source, into: target, mapping: mapping, in: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            alertMessage = ModelContext.failureMessage("Could not merge.", error)
            showAlert = true
        }
    }
}

#Preview {
    MergeExercisesView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
