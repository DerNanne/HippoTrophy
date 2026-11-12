import SwiftUI

/// The exercises to look through, in the Exercises tab and in the picker alike:
/// a search, a muscle, a category, and the choice between a list and big
/// pictures. What a caller does with an exercise goes in the slot beside it.
struct ExerciseBrowser<Accessory: View>: View {
    @AppStorage(SettingsKey.exercisesAsGrid) private var asGrid = false

    private let definitions: [ExerciseDefinition]
    @Binding private var filter: ExerciseFilter
    private let searchFocused: FocusState<Bool>.Binding
    private let onNew: (() -> Void)?
    private let onAdd: ((String) -> Void)?
    private let onOpen: (ExerciseDefinition) -> Void
    private let onDelete: ((ExerciseDefinition) -> Void)?
    private let isDimmed: (ExerciseDefinition) -> Bool
    private let accessory: (ExerciseDefinition) -> Accessory

    /// - Parameters:
    ///   - onNew: opens an editor for a new exercise; `nil` hides the row.
    ///   - onAdd: makes a plain exercise of the name searched for; `nil` hides
    ///     the row.
    ///   - onDelete: offered for an exercise of the user's own. A catalog one
    ///     comes with the app and is back at the next launch.
    ///   - accessory: the slot beside an exercise.
    init(
        definitions: [ExerciseDefinition],
        filter: Binding<ExerciseFilter>,
        searchFocused: FocusState<Bool>.Binding,
        onNew: (() -> Void)? = nil,
        onAdd: ((String) -> Void)? = nil,
        onOpen: @escaping (ExerciseDefinition) -> Void,
        onDelete: ((ExerciseDefinition) -> Void)? = nil,
        isDimmed: @escaping (ExerciseDefinition) -> Bool = { _ in false },
        @ViewBuilder accessory: @escaping (ExerciseDefinition) -> Accessory
    ) {
        self.definitions = definitions
        _filter = filter
        self.searchFocused = searchFocused
        self.onNew = onNew
        self.onAdd = onAdd
        self.onOpen = onOpen
        self.onDelete = onDelete
        self.isDimmed = isDimmed
        self.accessory = accessory
    }

    var body: some View {
        let shown = filter.apply(to: definitions)
        Group {
            if asGrid {
                grid(shown)
            } else {
                list(shown)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .top) {
            // The page's colour, not a material: the soft edge alone leaves
            // names legible behind the search and chips. A hard edge
            // (`scrollEdgeEffectStyle`) would hide them too, but it leaves the
            // title and the status bar in the old colours when the phone
            // changes between light and dark.
            ExerciseBrowserHeader(definitions: definitions, filter: $filter, searchFocused: searchFocused)
                .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: List

    private func list(_ shown: [ExerciseDefinition]) -> some View {
        List {
            Section {
                if let onNew {
                    Button(action: onNew) {
                        Label("New Exercise", systemImage: "plus")
                    }
                }
                if shown.isEmpty {
                    nothingShown
                } else {
                    ForEach(shown) { definition in
                        row(definition)
                    }
                }
            }
            if let onAdd, let name = filter.newName(among: definitions) {
                Section {
                    Button {
                        onAdd(name)
                    } label: {
                        Label("Add \"\(name)\"", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("A plain sets-and-reps exercise. Muscles and category can be set afterwards by tapping the exercise.")
                }
            }
        }
        .listSectionSpacing(.compact)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private func row(_ definition: ExerciseDefinition) -> some View {
        HStack {
            Button {
                onOpen(definition)
            } label: {
                ExerciseDefinitionRow(definition: definition)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            accessory(definition)
        }
        .opacity(isDimmed(definition) ? 0.4 : 1)
        .swipeActions(edge: .trailing) {
            if let onDelete, !definition.isCatalog {
                Button(role: .destructive) {
                    onDelete(definition)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var nothingShown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No exercises found")
                .foregroundStyle(.secondary)
            if filter.isNarrowed {
                Button("Clear Filters") {
                    filter = ExerciseFilter()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: Grid

    private func grid(_ shown: [ExerciseDefinition]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                if let onNew {
                    Button(action: onNew) {
                        Label("New Exercise", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(cardBackground)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                if shown.isEmpty {
                    nothingShown
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(cardBackground)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(shown) { definition in
                            tile(definition)
                        }
                    }
                }
                if let onAdd, let name = filter.newName(among: definitions) {
                    Button {
                        onAdd(name)
                    } label: {
                        Label("Add \"\(name)\"", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(cardBackground)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    /// The picture and the name lead to the exercise. The line under them says
    /// what it trains, with the same slot as a row beside it.
    private func tile(_ definition: ExerciseDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onOpen(definition)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    ExerciseTilePicture(definition: definition)
                    Text(definition.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 4) {
                ExerciseTileSummary(definition: definition)
                Spacer(minLength: 0)
                accessory(definition)
            }
            .frame(minHeight: 28)
        }
        // Down to the height of the row, so the lines under the names stay level.
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(8)
        .background(cardBackground)
        .opacity(isDimmed(definition) ? 0.4 : 1)
        .contextMenu {
            if let onDelete, !definition.isCatalog {
                Button(role: .destructive) {
                    onDelete(definition)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

/// A tile's picture: the pictogram of a catalog exercise, the photo of an
/// exercise of the user's own. One without a photo shows its category's symbol,
/// at the same size, so the tiles stay in line.
private struct ExerciseTilePicture: View {
    let definition: ExerciseDefinition

    var body: some View {
        if definition.isCatalog {
            ExercisePictogram(definition: definition)
        } else if let photo = definition.ownPhoto {
            ExercisePhotoTile(photo: photo)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .overlay {
                    Image(systemName: definition.category?.symbolName ?? "dumbbell")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(ExercisePictogram.aspectRatio, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}

/// One line of what the exercise trains. Without muscles, what it logs, so the
/// line is not empty for a cardio exercise.
private struct ExerciseTileSummary: View {
    let definition: ExerciseDefinition

    var body: some View {
        Group {
            if definition.muscleGroups.isEmpty {
                Text(definition.fieldSummary ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                MuscleGroupSummary(groups: definition.muscleGroups)
            }
        }
        .lineLimit(1)
    }
}

/// Between the list and the big pictures, for a caller's toolbar: the place
/// beside the others there is the caller's to choose. One button rather than
/// two, showing where a tap leads. It narrows nothing, so it stands apart from
/// what does.
struct ExerciseGridToggle: View {
    @AppStorage(SettingsKey.exercisesAsGrid) private var asGrid = false

    var body: some View {
        Button {
            asGrid.toggle()
        } label: {
            Image(systemName: asGrid ? "list.bullet" : "square.grid.2x2")
        }
        .accessibilityLabel(asGrid ? "Show as List" : "Show as Grid")
    }
}

/// An exercise's own page: a catalog one is shown, an own one edited.
struct ExerciseDetailView: View {
    let definition: ExerciseDefinition

    var body: some View {
        if definition.isCatalog {
            CatalogExerciseView(definition: definition)
        } else {
            ExerciseEditorView(definition: definition)
        }
    }
}
