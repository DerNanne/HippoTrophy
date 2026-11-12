import SwiftUI
import SwiftData

/// The Gyms tab's gyms: the gyms a workout can be at, each with the machines
/// standing in it.
struct GymsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @State private var naming = false
    @State private var pendingDeletion: Gym?

    var body: some View {
        List {
            if gyms.isEmpty {
                ContentUnavailableView(
                    "No Gyms",
                    systemImage: "building.2",
                    description: Text("Add the gyms you train at, then pick one for a workout at the top of the editor.")
                )
            }
            ForEach(gyms) { gym in
                NavigationLink {
                    GymDetailView(gym: gym)
                } label: {
                    LabeledContent(gym.name, value: CountFormat.text(gym.machines.count, "machine", "machines"))
                }
            }
            .onDelete { offsets in pendingDeletion = offsets.first.map { gyms[$0] } }
        }
        .navigationTitle("Gyms")
        .toolbar {
            Button("Add Gym", systemImage: "plus") { naming = true }
        }
        .sheet(isPresented: $naming) { NewGymSheet() }
        .confirmationDialog(
            pendingDeletion.map { "Delete \"\($0.name)\"?" } ?? "",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Gym", role: .destructive) {
                if let gym = pendingDeletion { modelContext.delete(gym) }
                try? modelContext.save()
                pendingDeletion = nil
            }
        } message: {
            Text(deletionMessage)
        }
    }

    private var deletionMessage: String {
        let count = pendingDeletion?.workouts.filter { !$0.isTemplate }.count ?? 0
        let machines = "Its machines stay, in the other gyms they stand in."
        guard count > 0 else { return machines }
        return "\(CountFormat.text(count, "workout was", "workouts were")) trained here; they keep everything but the gym. \(machines)"
    }
}

/// One gym: its name, and which machines stand in it.
struct GymDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var gym: Gym
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @Query(sort: \Machine.name) private var machines: [Machine]
    @State private var name = ""
    @State private var naming = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onSubmit(rename)
            } header: {
                Text("Name")
            } footer: {
                if let refusal = GymChoices.refusal(of: name, among: otherNames, kind: "gym") {
                    Text("\(refusal) Left like this, it stays \"\(gym.name)\".")
                }
            }
            Section {
                // Above the list: with many machines it would be far down, and
                // the rows it stands beside are to tick, not to add.
                Button("New Machine…", systemImage: "plus") { naming = true }
                ForEach(machines) { machine in
                    let isHere = gym.machines.contains { $0.id == machine.id }
                    CheckRow(title: machine.name, isOn: isHere) {
                        toggle(machine, isHere: isHere)
                    }
                }
            } header: {
                Text("Machines")
            } footer: {
                Text("The machines standing here come first when you pick one for an exercise in a workout at this gym.")
            }
        }
        // The name it will have: a refused one is not it.
        .navigationTitle(GymChoices.newName(name, among: otherNames) ?? gym.name)
        .onAppear { name = gym.name }
        .onDisappear(perform: rename)
        // The same sheet as under Machines, this gym ticked: one form for
        // a new machine, with its photo and the other gyms it stands in.
        .sheet(isPresented: $naming) { NewMachineSheet(standingIn: gym) }
    }

    private var otherNames: [String] {
        gyms.filter { $0.id != gym.id }.map(\.name)
    }

    /// Takes the typed name if it is one: not empty, and no other gym's.
    private func rename() {
        if let valid = GymChoices.newName(name, among: otherNames) {
            gym.name = valid
            try? modelContext.save()
        }
        name = gym.name
    }

    private func toggle(_ machine: Machine, isHere: Bool) {
        if isHere {
            gym.machines.removeAll { $0.id == machine.id }
        } else {
            gym.machines.append(machine)
        }
        try? modelContext.save()
    }
}
