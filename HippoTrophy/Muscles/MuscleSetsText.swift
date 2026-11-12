import SwiftUI

/// A muscle's sets as a line: the main ones as they are, the secondary ones
/// after them in grey — `3 sets · 2 secondary`. A set is never split in
/// two for showing; only the heat map's colour weighs them.
struct MuscleSetsText: View {
    let sets: MuscleSets

    var body: some View {
        if sets.main > 0 && sets.secondary > 0 {
            Text(CountFormat.text(sets.main, "set", "sets"))
                + Text(" · \(sets.secondary) secondary").foregroundStyle(.secondary)
        } else if sets.secondary > 0 {
            Text(CountFormat.text(sets.secondary, "secondary set", "secondary sets")).foregroundStyle(.secondary)
        } else {
            Text(CountFormat.text(sets.main, "set", "sets"))
        }
    }

    /// What VoiceOver reads for the same count.
    static func spoken(_ sets: MuscleSets) -> String {
        let main = CountFormat.text(sets.main, "set", "sets")
        guard sets.secondary > 0 else { return main }
        return "\(main), \(CountFormat.text(sets.secondary, "secondary set", "secondary sets"))"
    }
}
