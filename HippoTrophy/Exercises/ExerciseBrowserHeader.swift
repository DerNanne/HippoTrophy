import SwiftUI

/// What narrows `ExerciseBrowser`: the search, the own exercises and the muscle
/// menu in a line, the category chips under it.
struct ExerciseBrowserHeader: View {
    let definitions: [ExerciseDefinition]
    @Binding var filter: ExerciseFilter
    let searchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                searchField
                if filter.offersOnlyOwn(among: definitions) {
                    ownToggle
                }
                muscleMenu
            }
            .padding(.horizontal, 16)
            chips
        }
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search exercise", text: $filter.query)
                .focused(searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !filter.query.isEmpty {
                Button {
                    filter.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private var ownToggle: some View {
        Button {
            filter.onlyOwn.toggle()
        } label: {
            circle(isOn: filter.onlyOwn) {
                Image(systemName: "person.fill")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Only My Exercises")
        .accessibilityAddTraits(filter.onlyOwn ? .isSelected : [])
    }

    private var muscleMenu: some View {
        Menu {
            Picker("Muscle", selection: $filter.muscle) {
                Text("All Muscles").tag(MuscleFilter?.none)
                // First and marked, so they are seen and get filed.
                if filter.muscle == .unfiled || definitions.contains(where: { $0.muscleGroups.isEmpty }) {
                    Label(MuscleFilter.unfiled.name, systemImage: "exclamationmark.triangle.fill")
                        .tag(MuscleFilter?.some(.unfiled))
                }
                ForEach(MuscleGroup.allCases) { muscle in
                    Text(muscle.displayName).tag(MuscleFilter?.some(.muscle(muscle)))
                }
            }
        } label: {
            circle(isOn: filter.muscle != nil) {
                Image("MuscleFilterIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityLabel("By Muscle")
    }

    private func circle<Picture: View>(isOn: Bool, @ViewBuilder picture: () -> Picture) -> some View {
        picture()
            .foregroundStyle(isOn ? Color.white : Color.secondary)
            .frame(width: 38, height: 38)
            .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Circle())
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if let muscle = filter.muscle {
                    Button {
                        filter.muscle = nil
                    } label: {
                        HStack(spacing: 4) {
                            Text(muscle.name)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                        }
                        .chipStyle(fill: Color.accentColor, text: .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show all muscles, not only \(muscle.name)")
                }
                chip("All", isOn: filter.categoryID == nil) {
                    filter.categoryID = nil
                }
                ForEach(filter.categoryOptions(among: definitions), id: \.self) { option in
                    let id = CategoryFilter.id(of: option)
                    chip(
                        CategoryFilter.name(of: option),
                        symbol: CategoryFilter.symbolName(of: option),
                        tint: option?.tint ?? .secondary,
                        isOn: filter.categoryID == id
                    ) {
                        filter.categoryID = id
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    /// The symbol in its category's colour, as in the editor. On the dark fill
    /// of a picked chip it takes the colour of the text, so it stays legible.
    private func chip(
        _ title: String,
        symbol: String? = nil,
        tint: Color = .secondary,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let text = isOn ? Color(.systemBackground) : Color.primary
        return Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(isOn ? text : tint)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .chipStyle(fill: isOn ? Color.primary : Color(.tertiarySystemFill), text: text)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private extension View {
    func chipStyle(fill: Color, text: Color) -> some View {
        font(.subheadline)
            .foregroundStyle(text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(fill, in: Capsule())
    }
}
