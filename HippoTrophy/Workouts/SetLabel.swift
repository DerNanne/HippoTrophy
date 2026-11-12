import SwiftUI

/// The start of a logged set's line: "Set 3", and a trophy when the set is
/// the exercise's personal record.
struct SetLabel: View {
    let set: SetEntry
    var showsNumber = true
    var isRecord = false

    var body: some View {
        HStack(spacing: 6) {
            if showsNumber {
                Text("Set \(set.setNumber)")
            }
            if isRecord {
                PersonalRecordIcon()
            }
        }
    }
}

/// The trophy that marks a personal record.
struct PersonalRecordIcon: View {
    var body: some View {
        Image(systemName: "trophy.fill")
            .foregroundStyle(.yellow)
            .accessibilityLabel("Personal record")
    }
}
