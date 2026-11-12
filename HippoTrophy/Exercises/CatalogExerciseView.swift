import SwiftUI
import SwiftData

/// A catalog exercise, shown rather than edited: it comes with the app, and
/// its name, muscles and fields follow the catalog. Anything else is a copy —
/// a new exercise of the user's own, started from this one.
struct CatalogExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    let definition: ExerciseDefinition

    @State private var showCopy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .lastTextBaseline) {
                        Text(definition.name)
                            .font(.largeTitle.bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        ExerciseShapeBadge(isPlain: definition.isPlainSetsAndReps)
                            .padding(.bottom, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if ExercisePictogram.image(for: definition) != nil {
                    Section {
                        ExercisePictogram(definition: definition)
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section("Muscle Groups") {
                    if definition.muscleGroups.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Main", value: definition.muscleGroups.map(\.displayName).joined(separator: ", "))
                        if !definition.secondaryMuscleGroups.isEmpty {
                            LabeledContent("Secondary", value: definition.secondaryMuscleGroups.map(\.displayName).joined(separator: ", "))
                        }
                    }
                }

                Section("Logs") {
                    ForEach(definition.sortedFields) { field in
                        LabeledContent(field.label, value: field.type.displayName)
                    }
                    if let category = definition.category {
                        LabeledContent("Category", value: category.name)
                    }
                }

                Section {
                    Button {
                        showCopy = true
                    } label: {
                        Label("Copy to My Exercises", systemImage: "doc.on.doc")
                    }
                } header: {
                    Label("Catalog", systemImage: "books.vertical")
                } footer: {
                    Text("This exercise comes with the app and stays as the catalog has it. To change it, make a copy of your own and use that instead.")
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCopy) {
                ExerciseEditorView(copying: definition)
            }
        }
    }
}
