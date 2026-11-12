import SwiftUI
import SwiftData

/// A new machine: its name, and its photo and the gyms it stands in if the
/// user wants to say. Ticking none leaves a machine that stands nowhere in
/// particular.
struct NewMachineSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @Query(sort: \Machine.name) private var machines: [Machine]
    @State private var name = ""
    @State private var ticked: Set<UUID> = []
    @State private var photo: PhotoDraft?
    @FocusState private var nameIsFocused: Bool

    /// `gym` starts ticked: the sheet was opened from that gym's page.
    init(standingIn gym: Gym? = nil) {
        _ticked = State(initialValue: gym.map { [$0.id] } ?? [])
    }

    private var existingNames: [String] { machines.map(\.name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameIsFocused)
                        .submitLabel(.done)
                } footer: {
                    if GymChoices.isTaken(name, among: existingNames) {
                        Text("There is a machine of this name already. Two of a kind in one gym are two machines: give each its own name.")
                    }
                }
                PhotoSection(photo: $photo, aspectRatio: 1)
                Section {
                    if gyms.isEmpty {
                        Text("No gyms yet.").foregroundStyle(.secondary)
                    }
                    ForEach(gyms) { gym in
                        CheckRow(title: gym.name, isOn: ticked.contains(gym.id)) {
                            if ticked.remove(gym.id) == nil { ticked.insert(gym.id) }
                        }
                    }
                } header: {
                    Text("Stands In")
                } footer: {
                    Text("Optional. The same kind of machine can stand in several gyms.")
                }
            }
            .navigationTitle("New Machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(GymChoices.newName(name, among: existingNames) == nil)
                }
            }
            .onAppear { nameIsFocused = true }
        }
    }

    private func add() {
        guard let valid = GymChoices.newName(name, among: existingNames) else { return }
        let machine = GymChoices.addMachine(named: valid, standingIn: gyms.filter { ticked.contains($0.id) }, in: modelContext)
        machine.setPhoto(photo, in: modelContext)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NewMachineSheet()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
