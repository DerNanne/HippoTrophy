import SwiftUI
import SwiftData

/// A new gym: its name. A sheet rather than an alert, like `NewMachineSheet`,
/// so that a name that is taken says so while it is typed and Add waits —
/// an alert's text cannot change as the field does.
struct NewGymSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @State private var name = ""
    @FocusState private var nameIsFocused: Bool

    private var existingNames: [String] { gyms.map(\.name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameIsFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                } footer: {
                    if GymChoices.isTaken(name, among: existingNames) {
                        Text("There is a gym of this name already.")
                    }
                }
            }
            .navigationTitle("New Gym")
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
        // A name and two buttons: half the screen is plenty.
        .presentationDetents([.medium])
    }

    private func add() {
        guard let valid = GymChoices.newName(name, among: existingNames) else { return }
        GymChoices.addGym(named: valid, in: modelContext)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NewGymSheet()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
