import SwiftUI

/// One row per exercise the planner could not settle: same exercise with a
/// detail that differs, or another exercise under a taken name.
struct ImportReviewView: View {
    let items: [ImportPlanner.ExerciseItem]
    @Binding var decisions: ImportDecisions
    let onImport: () -> Void

    @State private var mappingItem: ImportPlanner.ExerciseItem?

    /// What is on screen is what happens: an untouched conflict shows its
    /// first answer ticked, and the importer takes it (`?? .skip`), so it
    /// counts as answered. Only a rename without a name holds the import up.
    private var isComplete: Bool {
        items.allSatisfy { item in
            guard case .conflict = item.outcome else { return true }
            let resolution = decisions.resolution(for: item.record.name) ?? .skip
            if case .rename(let name) = resolution {
                return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
    }

    var body: some View {
        List {
            ForEach(items) { item in
                switch item.outcome {
                case .review(let local, let differences):
                    reviewSection(item, local: local, differences: differences)
                case .conflict(let local):
                    conflictSection(item, local: local)
                case .add, .same:
                    EmptyView()
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Import", action: onImport)
                    .disabled(!isComplete)
            }
        }
        .sheet(item: $mappingItem) { item in
            if case .conflict(let local) = item.outcome {
                MergeMappingSheet(source: item.record, target: local.record) { mapping in
                    decisions.conflicts[item.record.name.exerciseKey] = .merge(mapping)
                }
            }
        }
    }

    // MARK: - Same exercise, different details

    @ViewBuilder
    private func reviewSection(_ item: ImportPlanner.ExerciseItem, local: ImportPlanner.Existing, differences: [ImportPlanner.Difference]) -> some View {
        let mineLabel = Self.ownSide(of: local)
        ForEach(differences, id: \.self) { difference in
            Section {
                // A row each, so either can be tapped back to: one picker
                // spread over a single row took every tap as the same choice.
                choice("\(mineLabel): \(mine(difference))", side: .mine, item.record.name, difference)
                choice("File: \(theirs(difference))", side: .file, item.record.name, difference)
            } header: {
                Text("\(item.record.name) · \(title(for: difference))")
            } footer: {
                if difference == differences.last {
                    Text("The same exercise on both sides; pick which \(differences.count == 1 ? "value" : "values") it keeps.")
                }
            }
        }
    }

    private func choice(_ text: String, side: ImportDecisions.Side, _ name: String, _ difference: ImportPlanner.Difference) -> some View {
        let binding = sideBinding(name, difference)
        return Button {
            binding.wrappedValue = side
        } label: {
            HStack {
                Text(text)
                    .foregroundStyle(.primary)
                Spacer()
                if binding.wrappedValue == side {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(binding.wrappedValue == side ? .isSelected : [])
    }

    /// What the device's side is called: a catalog exercise is the catalog's,
    /// not the user's.
    private static func ownSide(of local: ImportPlanner.Existing) -> String {
        local.record.catalogKey == nil ? "Mine" : "Catalog"
    }

    private func title(for difference: ImportPlanner.Difference) -> String {
        switch difference {
        case .category: return "Category"
        case .muscles: return "Muscle groups"
        case .sides: return "Sides"
        case .assistance: return "Assistance"
        case .fieldOrder: return "Order of fields"
        }
    }

    private func mine(_ difference: ImportPlanner.Difference) -> String {
        switch difference {
        case .category(let local, _): return local.isEmpty ? "None" : local
        case .muscles(let local, _): return muscleText(local)
        case .sides(let local, _): return local.title
        case .assistance(let local, _): return assistanceText(local)
        case .fieldOrder(let local, _): return local.joined(separator: ", ")
        }
    }

    private func theirs(_ difference: ImportPlanner.Difference) -> String {
        switch difference {
        case .category(_, let file): return file.isEmpty ? "None" : file
        case .muscles(_, let file): return muscleText(file)
        case .sides(_, let file): return file.title
        case .assistance(_, let file): return assistanceText(file)
        case .fieldOrder(_, let file): return file.joined(separator: ", ")
        }
    }

    private func assistanceText(_ offered: Bool) -> String {
        offered ? "Can be assisted" : "Never assisted"
    }

    private func muscleText(_ filing: MuscleFiling) -> String {
        let names = { (raw: [String]) in raw.compactMap(MuscleGroup.from(raw:)).map(\.displayName) }
        let primary = names(filing.primary)
        let secondary = names(filing.secondary)
        guard !primary.isEmpty || !secondary.isEmpty else { return "None" }
        let main = primary.joined(separator: ", ")
        guard !secondary.isEmpty else { return main }
        return (main.isEmpty ? "" : main + "; ") + "secondary: " + secondary.joined(separator: ", ")
    }

    private func sideBinding(_ name: String, _ difference: ImportPlanner.Difference) -> Binding<ImportDecisions.Side> {
        Binding(
            get: { decisions.side(for: name, difference) },
            set: { decisions.attributes[name.exerciseKey, default: [:]][difference] = $0 }
        )
    }

    // MARK: - Another exercise under the same name

    @ViewBuilder
    private func conflictSection(_ item: ImportPlanner.ExerciseItem, local: ImportPlanner.Existing) -> some View {
        let key = item.record.name.exerciseKey
        Section {
            let isCatalog = local.record.catalogKey != nil
            LabeledContent(Self.ownSide(of: local), value: describe(local.record))
            LabeledContent("File", value: describe(item.record))
            // Same fields on both sides: what tells them apart is a detail,
            // and without it the two lines above read the same.
            if local.record.shape == item.record.shape {
                ForEach(ImportPlanner.differences(between: local.record, and: item.record), id: \.self) { difference in
                    // Stacked, not trailing: a muscle filing is long, and
                    // two wrapped lines side by side did not line up.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(for: difference))
                        Group {
                            Text("\(Self.ownSide(of: local)): \(mine(difference))")
                            Text("File: \(theirs(difference))")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // A catalog exercise keeps what the catalog says, so the file can
            // only be left to it or become an exercise of the user's own.
            Picker("What happens", selection: kindBinding(item)) {
                Text(isCatalog ? "Use the Catalog exercise (Recommended)" : "Skip the file's").tag(ConflictKind.skip)
                Text(isCatalog ? "Import as my own exercise" : "Import under another name").tag(ConflictKind.rename)
                if !isCatalog {
                    Text("Merge into mine").tag(ConflictKind.merge)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            if case .rename = decisions.conflicts[key] {
                TextField("New name", text: renameBinding(item))
            }
            if case .merge(let mapping) = decisions.conflicts[key] {
                Button {
                    mappingItem = item
                } label: {
                    LabeledContent("Fields", value: mappingSummary(mapping, source: item.record, target: local.record))
                }
            }
        } header: {
            Text(item.record.name)
        } footer: {
            Text(conflictFooter(for: key, catalog: local.record.catalogKey != nil))
        }
    }

    private func describe(_ record: ExerciseRecord) -> String {
        let fields = record.fields.map(\.label)
        let sets = record.tracksSets ? "sets" : "no sets"
        return fields.isEmpty ? sets : "\(sets) · \(fields.joined(separator: ", "))"
    }

    private enum ConflictKind: Hashable { case skip, rename, merge }

    private func kindBinding(_ item: ImportPlanner.ExerciseItem) -> Binding<ConflictKind> {
        let key = item.record.name.exerciseKey
        return Binding(
            get: {
                switch decisions.conflicts[key] {
                case .rename: return .rename
                case .merge: return .merge
                case .skip, nil: return .skip
                }
            },
            set: { kind in
                switch kind {
                case .skip:
                    decisions.conflicts[key] = .skip
                case .rename:
                    // One name, one exercise: the user's own needs a name of
                    // its own beside the catalog's.
                    let isCatalog: Bool = if case .conflict(let local) = item.outcome { local.record.catalogKey != nil } else { false }
                    decisions.conflicts[key] = .rename(isCatalog ? "\(item.record.name) (Mine)" : "\(item.record.name) (2)")
                case .merge:
                    guard case .conflict(let local) = item.outcome else { return }
                    decisions.conflicts[key] = .merge(.suggested(from: item.record, into: local.record))
                }
            }
        )
    }

    private func renameBinding(_ item: ImportPlanner.ExerciseItem) -> Binding<String> {
        let key = item.record.name.exerciseKey
        return Binding(
            get: {
                if case .rename(let name) = decisions.conflicts[key] { return name }
                return ""
            },
            set: { decisions.conflicts[key] = .rename($0) }
        )
    }

    private func mappingSummary(_ mapping: FieldMapping, source: ExerciseRecord, target: ExerciseRecord) -> String {
        if case .failure = DefinitionMerge.merge(source: source, into: target, mapping: mapping) {
            return "Needs a look"
        }
        let carried = mapping.destinations.values.filter { $0 == .newField }.count
        let mapped = source.fields.count - carried
        return "\(mapped) matched, \(carried) new"
    }

    private func conflictFooter(for key: String, catalog: Bool) -> String {
        if catalog {
            switch decisions.conflicts[key] {
            case .rename:
                return "Becomes one of My Exercises with the file's details, and the file's workouts are logged under it. The Catalog exercise stays as it is."
            case .skip:
                return "The file's workouts are logged under the Catalog exercise; its details stay the catalog's."
            default:
                return "The Catalog exercise keeps the catalog's details. Choose where the file's workouts go."
            }
        }
        switch decisions.conflicts[key] {
        case .rename:
            return "Both exercises exist afterwards. Merge them later from Settings if they turn out to be the same."
        case .merge:
            return "The file's fields fold into yours. Workouts from the file are logged under your exercise."
        case .skip, nil:
            return "The file's exercise is not brought in. Its workouts are still imported and logged under your exercise, with the values as they were."
        }
    }
}

/// The field mapping for one merge, in a sheet of its own so the review list
/// does not have to hold every picker for every conflict at once.
private struct MergeMappingSheet: View {
    let source: ExerciseRecord
    let target: ExerciseRecord
    let onDone: (FieldMapping) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mapping: FieldMapping

    init(source: ExerciseRecord, target: ExerciseRecord, onDone: @escaping (FieldMapping) -> Void) {
        self.source = source
        self.target = target
        self.onDone = onDone
        _mapping = State(initialValue: .suggested(from: source, into: target))
    }

    var body: some View {
        NavigationStack {
            Form {
                FieldMappingView(source: source, target: target, mapping: $mapping)
            }
            .navigationTitle("Merge Fields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(mapping)
                        dismiss()
                    }
                    .disabled(problem != nil)
                }
            }
        }
    }

    private var problem: DefinitionMerge.Problem? {
        if case .failure(let problem) = DefinitionMerge.merge(source: source, into: target, mapping: mapping) {
            return problem
        }
        return nil
    }
}
