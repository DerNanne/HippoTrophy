import SwiftUI
import SwiftData

/// The Gyms tab's machines: every machine an exercise can be done at, and the
/// gyms each stands in.
struct MachinesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Machine.name) private var machines: [Machine]
    @State private var naming = false
    @State private var pendingDeletion: Machine?
    @ScaledMetric(relativeTo: .body) private var photoSize: CGFloat = 44

    var body: some View {
        List {
            if machines.isEmpty {
                ContentUnavailableView(
                    "No Machines",
                    image: "Machine",
                    description: Text("Add the machines you train on — two chest presses in one gym are two machines — then pick one for an exercise in a workout.")
                )
            }
            ForEach(machines) { machine in
                NavigationLink {
                    MachineDetailView(machine: machine)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(machine.name)
                            if !machine.gyms.isEmpty {
                                Text(machine.sortedGyms.map(\.name).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // At the trailing edge, so the names stay in line
                        // whether a machine has a photo or not.
                        if let photo = machine.photo {
                            Spacer()
                            MachinePhotoTile(photo: photo)
                                .frame(width: photoSize)
                        }
                    }
                }
            }
            .onDelete { offsets in pendingDeletion = offsets.first.map { machines[$0] } }
        }
        .navigationTitle("Machines")
        .toolbar {
            Button("Add Machine", systemImage: "plus") { naming = true }
        }
        .sheet(isPresented: $naming) { NewMachineSheet() }
        .confirmationDialog(
            pendingDeletion.map { "Delete \"\($0.name)\"?" } ?? "",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Machine", role: .destructive) {
                if let machine = pendingDeletion { modelContext.delete(machine) }
                try? modelContext.save()
                pendingDeletion = nil
            }
        } message: {
            let count = pendingDeletion?.entries.filter { $0.session?.isTemplate == false }.count ?? 0
            Text(count > 0
                 ? "\(CountFormat.text(count, "exercise in a workout was", "exercises in workouts were")) done at it; they keep everything but the machine."
                 : "It was not used in a workout.")
        }
    }
}

/// One machine: its name, its photo, and which gyms it stands in.
struct MachineDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var machine: Machine
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @Query(sort: \Machine.name) private var machines: [Machine]
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onSubmit(rename)
            } header: {
                Text("Name")
            } footer: {
                if let refusal = GymChoices.refusal(of: name, among: otherNames, kind: "machine") {
                    Text("\(refusal) Left like this, it stays \"\(machine.name)\".")
                }
            }
            PhotoSection(photo: photo, aspectRatio: 1)
            Section {
                if gyms.isEmpty {
                    Text("No gyms yet.").foregroundStyle(.secondary)
                }
                ForEach(gyms) { gym in
                    let isThere = machine.gyms.contains { $0.id == gym.id }
                    CheckRow(title: gym.name, isOn: isThere) {
                        if isThere { machine.gyms.removeAll { $0.id == gym.id } } else { machine.gyms.append(gym) }
                        try? modelContext.save()
                    }
                }
            } header: {
                Text("Stands In")
            } footer: {
                Text("The same kind of machine can stand in several gyms.")
            }
        }
        // The name it will have: a refused one is not it.
        .navigationTitle(GymChoices.newName(name, among: otherNames) ?? machine.name)
        .onAppear { name = machine.name }
        .onDisappear(perform: rename)
    }

    /// Straight onto the machine, like the gyms it stands in: this page has
    /// no Cancel.
    private var photo: Binding<PhotoDraft?> {
        Binding(
            get: { machine.photo.map { PhotoDraft(data: $0.data, framing: $0.framing) } },
            set: { data in
                machine.setPhoto(data, in: modelContext)
                try? modelContext.save()
            }
        )
    }

    private var otherNames: [String] {
        machines.filter { $0.id != machine.id }.map(\.name)
    }

    /// Takes the typed name if it is one: not empty, and no other machine's.
    private func rename() {
        if let valid = GymChoices.newName(name, among: otherNames) {
            machine.name = valid
            try? modelContext.save()
        }
        name = machine.name
    }
}
