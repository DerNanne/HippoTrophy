import SwiftUI

/// Where each field of one exercise goes when it is folded into another. The
/// same rows serve the import's merge and the settings merger.
struct FieldMappingView: View {
    let source: ExerciseRecord
    let target: ExerciseRecord
    @Binding var mapping: FieldMapping

    /// What the merge logic says about the mapping as it stands; `nil` when it
    /// holds up.
    var problem: DefinitionMerge.Problem? {
        if case .failure(let problem) = DefinitionMerge.merge(source: source, into: target, mapping: mapping) {
            return problem
        }
        return nil
    }

    var body: some View {
        Section {
            ForEach(source.fields, id: \.key) { field in
                row(for: field)
            }
        } header: {
            Text("Fields of \"\(source.name)\"")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Each field either means the same as a field of \"\(target.name)\" — then its values go there — or comes along as a new field. Nothing is dropped.")
                if let problem {
                    Text(problem.localizedDescription)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for field: FieldRecord) -> some View {
        let type = FieldType(rawValue: field.type)
        let candidates = target.fields.filter { $0.type == field.type }
        Picker(selection: binding(for: field.key)) {
            Text("New field on \"\(target.name)\"").tag(FieldMapping.Destination.newField)
            ForEach(candidates, id: \.key) { candidate in
                Text("Same as \"\(candidate.label)\"").tag(FieldMapping.Destination.field(targetKey: candidate.key))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                Text(type?.displayName ?? field.type)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for key: String) -> Binding<FieldMapping.Destination> {
        Binding(
            get: { mapping.destinations[key] ?? .newField },
            set: { mapping.destinations[key] = $0 }
        )
    }
}

