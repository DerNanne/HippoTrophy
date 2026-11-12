import SwiftUI

/// What the sides assistant is about, in the signal colour and in short
/// points, the way What's New says it.
struct SidesAssistantIntro: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Every exercise is now bilateral or unilateral", systemImage: "exclamationmark.circle")
                    .font(.headline)
                    .labelStyle(SignalLabelStyle())
                BulletList(points: [
                    "Bilateral: both sides at once, one way to log it.",
                    "Unilateral: one side at a time, logged with the same weight for both sides or each side on its own.",
                    "Sort your own exercises once. Catalog exercises already know theirs.",
                ])
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.signalGround)
        }
    }
}

/// Save everything before deciding, so nothing is lost whatever is chosen.
/// The file keeps the undecided exercises undecided; what a later build does
/// with them on import is that build's to decide.
struct SidesAssistantExport: View {
    let isEnabled: Bool
    let export: () -> Void

    var body: some View {
        Section {
            Button(action: export) {
                Label("Export Backup First", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.signal)
            .disabled(!isEnabled)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            Text("Not sure yet? Save a backup first, so nothing is lost whatever you choose here.")
        }
    }
}

/// The way out for someone stuck: send the backup, get help.
struct SidesAssistantHelp: View {
    var body: some View {
        Section {
            Text("Export a backup with the button above and send it to \(Support.address). I'll help you sort it out.")
                .font(.subheadline)
                .textSelection(.enabled)
            SupportMailButton(
                subject: "Help with the migration",
                message: "Please attach the backup you just exported (hippotrophy-backup-….json) and tell me which exercises you're unsure about.\n\n"
            )
        } header: {
            Text("I Need Help with the Migration")
        }
    }
}

/// The symbol in the signal colour, the title as it is.
struct SignalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .foregroundStyle(Color.signal)
            configuration.title
        }
    }
}

/// Short points under a sentence, as What's New writes them.
struct BulletList: View {
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(point)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
