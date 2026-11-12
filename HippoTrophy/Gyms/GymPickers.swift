import SwiftUI

/// Asks for the name of a new gym or machine, and hands it over on Add.
/// The workout editor's way to name a new gym or machine. A taken name picks
/// the one there is, so nothing here refuses one; the Gyms tab, where a taken
/// name is refused, uses `NewGymSheet` and `NewMachineSheet` instead.
private struct NameAlert: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let onAdd: (String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            TextField("Name", text: $name)
            Button("Add") { onAdd(name); name = "" }
            Button("Cancel", role: .cancel) { name = "" }
        }
    }
}

extension View {
    func nameAlert(_ title: String, isPresented: Binding<Bool>, onAdd: @escaping (String) -> Void) -> some View {
        modifier(NameAlert(title: title, isPresented: isPresented, onAdd: onAdd))
    }
}

/// A gym or machine in a list to tick: a machine standing in a gym, from either
/// side.
struct CheckRow: View {
    let title: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                // The colour itself: `.primary` is the button's own tint here,
                // and a name in blue reads as ticked.
                Text(title).foregroundStyle(Color.primary)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}

/// The capsule a picked gym or machine shows as, grey while there is none.
private struct PickerChip: View {
    let title: String
    let systemImage: String
    let isSet: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .lineLimit(1)
            // Cut in the middle: names of a kind often differ at the end.
            .truncationMode(.middle)
            .foregroundStyle(isSet ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
    }
}

/// Where a workout is trained: one of the user's gyms, none, or a new one
/// named on the spot.
struct GymMenu: View {
    let gym: Gym?
    /// By name.
    let gyms: [Gym]
    let onPick: (Gym?) -> Void
    let onAdd: (String) -> Void
    @State private var naming = false

    var body: some View {
        Menu {
            Picker("Gym", selection: Binding(get: { gym?.id }, set: { id in onPick(gyms.first { $0.id == id }) })) {
                Text("No Gym").tag(UUID?.none)
                ForEach(gyms) { gym in
                    Text(gym.name).tag(Optional(gym.id))
                }
            }
            Divider()
            Button("New Gym…", systemImage: "plus") { naming = true }
        } label: {
            PickerChip(title: gym?.name ?? "Gym", systemImage: "building.2", isSet: gym != nil)
        }
        // The chip draws its own colours; the menu's own button styling
        // would wash an empty one out.
        .buttonStyle(.plain)
        .accessibilityLabel(gym.map { "Gym: \($0.name)" } ?? "Gym: none")
        .nameAlert("New Gym", isPresented: $naming, onAdd: onAdd)
    }
}

/// The machine an exercise is done at: one standing in the workout's gym,
/// one from elsewhere — which then stands there too — none, or a new one.
/// What is offered is `GymChoices.machines`'s to say.
///
/// Shown as its icon alone, tinted once a machine is picked: beside Add Set
/// a name would be cut short to nothing. The menu names the one picked, and
/// the workout's page shows it in full.
struct MachineMenu: View {
    let machine: Machine?
    let choices: (here: [Machine], elsewhere: [Machine])
    /// The workout's gym, to say whose machines the first list holds.
    let gymName: String?
    let onPick: (Machine?) -> Void
    let onAdd: (String) -> Void
    @State private var naming = false
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 22

    var body: some View {
        Menu {
            if let machine {
                Text(machine.name)
            }
            Button {
                onPick(nil)
            } label: {
                if machine == nil { Label("No Machine", systemImage: "checkmark") } else { Text("No Machine") }
            }
            Section(gymName.map { "At \($0)" } ?? "Machines") {
                ForEach(choices.here) { item($0) }
            }
            if !choices.elsewhere.isEmpty {
                Menu("Other Machines") {
                    ForEach(choices.elsewhere) { item($0) }
                }
            }
            Divider()
            Button("New Machine…", systemImage: "plus") { naming = true }
        } label: {
            Image("Machine")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(machine != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(machine.map { "Machine: \($0.name)" } ?? "Machine: none")
        .nameAlert("New Machine", isPresented: $naming, onAdd: onAdd)
    }

    private func item(_ candidate: Machine) -> some View {
        Button {
            onPick(candidate)
        } label: {
            if candidate.id == machine?.id { Label(candidate.name, systemImage: "checkmark") } else { Text(candidate.name) }
        }
    }
}
