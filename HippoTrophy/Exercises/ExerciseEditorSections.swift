import SwiftUI

/// "What do you log?": the editor's one question about the fields.
struct ExerciseLogKindSection: View {
    let selection: ExerciseLogKind
    let onPick: (ExerciseLogKind) -> Void

    var body: some View {
        Section("What do you log?") {
            ForEach(ExerciseLogKind.allCases, id: \.self) { kind in
                Button {
                    onPick(kind)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kind.symbolName)
                            .foregroundStyle(kind == .weightAndReps ? Color.green : Color.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.title)
                                .foregroundStyle(.primary)
                            Text(kind.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if kind == selection {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(kind == selection ? .isSelected : [])
            }
        }
    }
}

/// How an exercise is trained, with the pictures of the sides assistant: a
/// barbell squat and a Bulgarian split squat say it before the words do.
struct ExerciseSidesSection: View {
    @Binding var selection: ExerciseSides

    private func pictogram(of sides: ExerciseSides) -> String {
        sides == .one ? "SidesUnilateral" : "SidesBilateral"
    }

    var body: some View {
        Section("Sides") {
            ForEach(ExerciseSides.choosable, id: \.self) { sides in
                Button {
                    selection = sides
                } label: {
                    HStack(spacing: 10) {
                        LinePictogram(name: pictogram(of: sides), size: 26)
                            .foregroundStyle(.primary)
                        Text(sides.howTrained)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if sides == selection {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sides == selection ? .isSelected : [])
            }
        }
    }
}

/// Whether a workout can log an exercise with a machine's help. What that does
/// has to be said here: the choice itself only comes up later, in the workout.
struct ExerciseAssistanceSection: View {
    @Binding var isOn: Bool

    var body: some View {
        Section {
            Toggle(isOn: $isOn) {
                HStack(spacing: 10) {
                    LinePictogram(name: "AssistedPullUp", size: 26)
                    Text("Can Be Assisted")
                }
            }
        } footer: {
            Text("Lets you swap Weight for Assistance in a workout: how much a machine takes off, e.g. for dips or pull-ups. Less help counts as progress.")
        }
    }
}

/// The fields an exercise logs. Under Weight & Reps those two are locked; the
/// rest can be titled, retyped and taken out.
struct ExerciseFieldsSection: View {
    let kind: ExerciseLogKind
    @Binding var drafts: ExerciseFieldDrafts
    let impact: FieldChangeImpact

    @FocusState private var focusedField: FieldDraft.ID?

    private func isLocked(_ draft: FieldDraft) -> Bool {
        kind == .weightAndReps && draft.type.isStandard
    }

    var body: some View {
        Section {
            ForEach(drafts.allInSetOrder) { draft in
                row(draft)
            }
            addButton
        } header: {
            Text(kind == .weightAndReps ? "Fields" : "Your fields")
        } footer: {
            if drafts.hasUntitled {
                Text("Every field needs a title. Give it one, or remove the field with the minus button.")
                    .foregroundStyle(.red)
            } else if drafts.labelled.isEmpty {
                Text("An exercise needs at least one field.")
            } else if drafts.isFull {
                Text("An exercise can have up to \(ExerciseDefinition.maxFields) fields.")
            }
        }
    }

    private var addButton: some View {
        Menu {
            ForEach(drafts.addableTypes(for: kind), id: \.self) { type in
                Button(type.displayName) {
                    let added = drafts.add(type)
                    if type.isStandard == false {
                        focusedField = added?.id
                    }
                }
            }
        } label: {
            Label("Add Field", systemImage: "plus")
        }
        .disabled(drafts.isFull)
    }

    private func row(_ draft: FieldDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if isLocked(draft) {
                    Text(draft.label)
                    Spacer(minLength: 8)
                    Image(systemName: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Fixed")
                } else {
                    removeButton(draft)
                    if draft.type.isStandard {
                        Text(draft.label)
                            .strikethrough(draft.isRemoved)
                            .foregroundStyle(draft.isRemoved ? .secondary : .primary)
                        Spacer(minLength: 8)
                        Text("Fixed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    } else {
                        ownField(draft)
                    }
                }
            }

            if let line = impact.line(for: draft) {
                Text(line.text)
                    .font(.footnote)
                    .foregroundStyle(line.isDestructive ? Color.red : Color.orange)
            }
        }
    }

    private func removeButton(_ draft: FieldDraft) -> some View {
        Button(role: draft.isRemoved ? nil : .destructive) {
            drafts.remove(draft.id)
        } label: {
            Image(systemName: draft.isRemoved ? "arrow.uturn.backward.circle" : "minus.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(draft.isRemoved ? "Keep field" : "Remove field")
    }

    @ViewBuilder
    private func ownField(_ draft: FieldDraft) -> some View {
        let field = Binding(
            get: { drafts.all.first { $0.id == draft.id } ?? draft },
            set: { drafts.update($0) }
        )
        TextField("Field title", text: field.label)
            .focused($focusedField, equals: draft.id)
            .strikethrough(draft.isRemoved)
            .foregroundStyle(draft.isRemoved ? .secondary : .primary)
            .disabled(draft.isRemoved)
        if !draft.isRemoved {
            Picker("Field Type", selection: field.type) {
                ForEach(FieldType.custom, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// How a set will look: an answer in place of a footnote.
struct ExercisePreviewSection: View {
    let preview: ExercisePreview

    var body: some View {
        Section("In a workout") {
            if preview.rows.isEmpty {
                Text("Add a field to see it here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(preview.rows.indices, id: \.self) { index in
                        rowView(preview.rows[index])
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Example of how it looks in a workout")
            }
        }
    }

    private func rowView(_ row: ExercisePreview.Row) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let number = row.number {
                Text("\(number)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .padding(.top, 5)
            }
            // Three per row, as a set row lays them out.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(row.cells.indices, id: \.self) { index in
                    cellView(row.cells[index])
                }
            }
        }
    }

    private func cellView(_ cell: ExercisePreview.Cell) -> some View {
        VStack(spacing: 0) {
            if let title = cell.title {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(cell.value)
                .font(.subheadline)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 32)
        .padding(.vertical, 2)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// An exercise's category, a menu like the sides of a workout's gym: every
/// exercise has one, and few have a reason to look at it twice.
struct ExerciseCategoryRow: View {
    @Binding var categoryName: String

    var body: some View {
        Picker("Category", selection: $categoryName) {
            Label("None", systemImage: "circle.slash").tag("")
            ForEach(ExerciseCategory.allCases) { category in
                Label { Text(category.name) } icon: { category.coloredSymbol }.tag(category.name)
            }
        }
    }
}
