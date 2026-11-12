import SwiftUI

/// The long-press menu's way to change how one exercise of this workout rates
/// its sets. The current scale carries the checkmark; whether a change needs
/// asking first is the editor's to decide.
struct EffortScaleMenu: View {
    let scale: EffortScale
    let onChange: (EffortScale) -> Void

    var body: some View {
        Menu {
            Picker("Rate Effort", selection: Binding(get: { scale }, set: onChange)) {
                ForEach(EffortScale.allCases) { scale in
                    Text(scale.name).tag(scale)
                }
            }
        } label: {
            Label("Rate Effort", systemImage: "gauge.with.dots.needle.67percent")
        }
    }
}
