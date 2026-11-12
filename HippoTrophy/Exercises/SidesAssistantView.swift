import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The sides assistant: every own exercise left undecided after the update is
/// sorted into bilateral or unilateral, once, before anything else. It
/// cannot be skipped — the rest of the app, and the review of My Exercises
/// after it, rely on every exercise having a side.
///
/// Exercises logged one way are swiped — left for bilateral, right for
/// unilateral — or set with the switch on their row. Those logged both ways
/// open to their entries, each already set to how it was logged.
///
/// It reads the store itself when it appears: a cover's view can be built
/// before it is shown, and state handed in then would be what it keeps.
///
/// A backup can be saved from here before anything is decided: bilateral
/// for an exercise logged left and right merges the two for good. The file
/// keeps the undecided ones undecided, so nothing is lost whatever is chosen.
struct SidesAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var assistant = SidesAssistant(exercises: [])
    @State private var isLoaded = false
    @State private var failure: String?
    @State private var exportDocument: BackupFileDocument?
    @State private var showExporter = false
    @State private var exportMessage: String?
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                SidesAssistantIntro()
                SidesAssistantExport(isEnabled: isLoaded, export: exportBackup)

                if !assistant.uniform.isEmpty {
                    Section {
                        ForEach(assistant.uniform) { exercise in
                            uniformRow(exercise)
                                // Toward the column it belongs in: left for
                                // bilateral, right for unilateral.
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Bilateral") { choose(.both, for: exercise) }
                                        .tint(.gray)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button("Unilateral") { choose(.one, for: exercise) }
                                        .tint(.blue)
                                }
                        }
                    } header: {
                        // The two columns an exercise is swiped toward, each
                        // with its pictogram after the word.
                        HStack(spacing: 6) {
                            Text("Bilateral")
                            LinePictogram(name: "SidesBilateral")
                            Spacer()
                            Text("Unilateral")
                            LinePictogram(name: "SidesUnilateral")
                        }
                    } footer: {
                        Text("Swipe an exercise left for bilateral or right for unilateral, or use its switch.")
                    }
                }

                if !assistant.mixed.isEmpty {
                    Section {
                        ForEach(assistant.mixed) { exercise in
                            NavigationLink {
                                SidesAssistantEntriesView(exercise: exercise, assistant: $assistant)
                            } label: {
                                mixedRow(exercise)
                            }
                        }
                    } header: {
                        Text("Logged Both Ways")
                    } footer: {
                        Text("Open each one before Done. Its entries start as they were logged; change single ones — a bilateral entry that was really one-legged, say — or delete what was only tried out.")
                    }
                }

                SidesAssistantHelp()
            }
            .navigationTitle("Bilateral or Unilateral?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish)
                        .disabled(!isLoaded || !assistant.isComplete)
                }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: exportDocument?.contentType ?? .json,
                defaultFilename: BackupFileDocument.defaultFilename()
            ) { result in
                switch result {
                case .success: exportMessage = "Backup saved."
                case .failure(let error): exportMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .alert("Backup", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportMessage ?? "")
            }
            .alert("Could Not Save", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
        .interactiveDismissDisabled()
        .task {
            assistant = SidesAssistant.load(in: modelContext)
            isLoaded = true
            // Nothing left to decide — settled elsewhere meanwhile.
            if assistant.exercises.isEmpty {
                onDone()
            }
        }
    }

    private func uniformRow(_ exercise: SidesAssistant.Exercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name)
                .font(.headline)
            Text(details(of: exercise))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Sides", selection: Binding(
                get: { assistant.choices[exercise.id] },
                set: { assistant.choices[exercise.id] = $0 }
            )) {
                ForEach(ExerciseSides.choosable, id: \.self) { sides in
                    Text(sides.title).tag(Optional(sides))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let outcome = assistant.outcome(for: exercise) {
                SidesOutcomeLines(outcome: outcome, name: exercise.name)
            }
        }
        .padding(.vertical, 4)
        // A warning's icon would otherwise pull the separator in after it.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    private func mixedRow(_ exercise: SidesAssistant.Exercise) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(exercise.name)
                    .font(.headline)
                if assistant.opened.contains(exercise.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Checked")
                } else {
                    Text("Open to check")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.signal)
                }
            }
            Text(details(of: exercise))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let outcome = assistant.outcome(for: exercise) {
                Text(result(of: outcome, name: exercise.name))
                    .font(.caption)
            }
        }
    }

    private func details(of exercise: SidesAssistant.Exercise) -> String {
        let muscles = exercise.muscleGroupNames.compactMap(MuscleGroup.from(raw:)).map(\.displayName)
        return (muscles + [exercise.history]).joined(separator: " · ")
    }

    private func result(of outcome: SidesAssistant.Outcome, name: String) -> String {
        if !outcome.split.isEmpty {
            return "Splits into \(name) and \(SideMigration.ownVariantName(of: name))"
        }
        return "Becomes \(outcome.sides.title)"
    }

    private func choose(_ sides: ExerciseSides, for exercise: SidesAssistant.Exercise) {
        withAnimation { assistant.choices[exercise.id] = sides }
    }

    /// Everything, as the Backup menu exports it with nothing turned off.
    private func exportBackup() {
        let definitions = (try? modelContext.fetch(FetchDescriptor<ExerciseDefinition>(sortBy: [SortDescriptor(\.orderIndex)]))) ?? []
        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>(
            predicate: WorkoutSession.trained, sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        let templates = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>(
            predicate: WorkoutSession.templates, sortBy: [SortDescriptor(\.templateOrder)]
        ))) ?? []
        let gyms = (try? modelContext.fetch(FetchDescriptor<Gym>())) ?? []
        let machines = (try? modelContext.fetch(FetchDescriptor<Machine>())) ?? []
        exportDocument = BackupFileDocument(package: BackupExporter.package(
            definitions: definitions, sessions: sessions, templates: templates, gyms: gyms, machines: machines
        ))
        showExporter = true
    }

    private func finish() {
        do {
            try assistant.apply(in: modelContext)
            onDone()
        } catch {
            modelContext.rollback()
            failure = error.localizedDescription
        }
    }
}

/// What a decision does, a line each; a change that cannot be taken back
/// gets the warning sign.
struct SidesOutcomeLines: View {
    let outcome: SidesAssistant.Outcome
    let name: String

    var body: some View {
        let lines = SidesAssistant.summary(of: outcome, name: name)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines.indices, id: \.self) { index in
                    let line = lines[index]
                    if line.isWarning {
                        Label {
                            Text(line.text)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                    } else {
                        Text(line.text)
                    }
                }
            }
            .font(.caption)
        }
    }
}
