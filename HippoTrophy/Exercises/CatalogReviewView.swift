import SwiftUI
import SwiftData

/// My Exercises next to the catalog, one at a time: for each, move it to the
/// catalog exercise it really is, keep it as the user's own, or delete it.
/// What fits where is `CatalogMigration`'s to decide; this only asks.
struct CatalogReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]
    @AppStorage(SettingsKey.keptOwnExercises) private var keptStored = ""
    @AppStorage(SettingsKey.catalogReviewDontShow) private var dontShowAgain = false

    /// Put in front of the user at launch rather than opened from the list:
    /// it says why, offers to stop asking, and closes with Later.
    var isPrompt = false

    private var kept: Set<UUID> { KeptOwnExercises(stored: keptStored).ids }

    private var own: [ExerciseDefinition] {
        definitions.filter { !$0.isCatalog }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let open = CatalogReview.open(in: definitions, kept: kept)
        let others = own.filter { definition in !kept.contains(definition.id) && !open.contains { $0.id == definition.id } }
        let keptOnes = own.filter { kept.contains($0.id) }

        List {
            if isPrompt {
                Section {
                    // Kept short and led by what to do: most read only the
                    // first line.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Use catalog exercises wherever you can!")
                            .font(.headline)
                        Text("Features like the heat map depend on exercises being set up right, muscle groups included. Catalog exercises come set up.")
                        Text("Please check below which of your own exercises you can move to a catalog exercise. Their workouts move with them.")
                    }
                    .font(.subheadline)
                    .padding(.vertical, 2)
                }
            }
            if own.isEmpty {
                Section {
                    Text("All your exercises are catalog exercises.")
                        .foregroundStyle(.secondary)
                }
            }
            section("Might Be in the Catalog", open, footer: "A catalog exercise logs the same kinds of values.")
            section("Others", others, footer: nil)
            section("Kept as Mine", keptOnes, footer: nil)
            if isPrompt {
                Section {
                    Toggle("Don't Show This Again", isOn: $dontShowAgain)
                } footer: {
                    Text("The review stays in the Exercises tab.")
                }
            }
        }
        .navigationTitle("Review My Exercises")
        .toolbar {
            if isPrompt {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Later") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ definitions: [ExerciseDefinition], footer: String?) -> some View {
        if !definitions.isEmpty {
            Section {
                ForEach(definitions) { definition in
                    NavigationLink {
                        CatalogReviewDetailView(definition: definition)
                    } label: {
                        ExerciseDefinitionRow(definition: definition, amongCatalog: false)
                    }
                }
            } header: {
                Text(title)
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }
}

/// What the exercise list and the review ask about the own exercises.
@MainActor
enum CatalogReview {
    /// The own exercises still open for the review, by name: not kept, and
    /// able to move to some catalog exercise — see `CatalogMigration.isOpen`.
    /// The review's first section, and what the menu's dot and the launch count.
    static func open(in definitions: [ExerciseDefinition], kept: Set<UUID>) -> [ExerciseDefinition] {
        let catalog = definitions.filter(\.isCatalog).map(BackupExporter.record)
        return definitions
            .filter { !$0.isCatalog && !kept.contains($0.id) && CatalogMigration.isOpen(BackupExporter.record($0), among: catalog) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func pendingCount(in definitions: [ExerciseDefinition], kept: Set<UUID>) -> Int {
        open(in: definitions, kept: kept).count
    }
}
