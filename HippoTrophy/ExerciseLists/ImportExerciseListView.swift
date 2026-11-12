import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Picks a list to import from among the files the user opened during this
/// visit. What the app ships is the catalog and is there already.
struct ImportExerciseListView: View {
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]

    /// Called once exercises were actually added, so the whole flow can pop back
    /// to Manage Exercises in one step.
    var onImported: () -> Void

    @State private var fileLists: [ImportableExerciseList] = []
    @State private var selectedList: ImportableExerciseList?
    @State private var showFileImporter = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    /// Case-insensitive, because that is how the list treats duplicates.
    private var knownNames: Set<String> {
        Set(definitions.map(\.name.exerciseKey))
    }

    var body: some View {
        List {
            if !fileLists.isEmpty {
                Section {
                    ForEach(fileLists) { list in
                        row(for: list)
                    }
                } footer: {
                    Text("Importing adds them to My Exercises. Nothing is removed or overwritten, and you can pick individual exercises before importing.")
                }
            }

            Section {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import from File", systemImage: "folder")
                }
            } footer: {
                Text("Reads a JSON file with a list of exercises, each with a name and its muscle groups.")
            }
        }
        .navigationTitle("Import Exercise List")
        .navigationDestination(item: $selectedList) { list in
            ImportExerciseListDetailView(list: list, onImported: onImported)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            handleFileImport(result)
        }
        .alert("Import Exercise List", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private func row(for list: ImportableExerciseList) -> some View {
        let known = knownNames
        let newCount = list.exercises.filter { !known.contains($0.name.exerciseKey) }.count
        let alreadyCount = list.exercises.count - newCount
        let total = CountFormat.text(list.exercises.count, "exercise", "exercises")

        Button {
            selectedList = list
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(total) · \(newCount) new for you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if alreadyCount > 0 {
                        Text("\(alreadyCount) already in your list")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let canAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if canAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                // A list of exercise names is tiny; anything larger is the wrong
                // file and would only produce an unusable selection screen.
                guard data.count <= 1_000_000 else {
                    alertMessage = "This file is too large to be an exercise list."
                    showAlert = true
                    return
                }

                let lists = try ExerciseListLoader.lists(
                    fromFileAt: data,
                    fallbackName: url.deletingPathExtension().lastPathComponent
                )
                fileLists.append(contentsOf: lists)

                // One list is an unambiguous choice, so go straight to picking
                // exercises; several stay on screen to be chosen from.
                if lists.count == 1 {
                    selectedList = lists[0]
                }
            } catch {
                alertMessage = "Import failed: \(error.localizedDescription)"
                showAlert = true
            }
        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        ImportExerciseListView(onImported: {})
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
