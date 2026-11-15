import SwiftUI
import SwiftData

/// What came from Desk, above the tab bar until it is closed: the changes,
/// Undo for all of them, and what waits in Desk instead.
struct InboxNoticeBanner: View {
    @Environment(\.modelContext) private var modelContext
    private let center = SyncCenter.shared

    /// So many lines name a change; the rest is counted.
    private let shown = 4

    var body: some View {
        if let notice = center.inboxNotice {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Label("From Desk", systemImage: "desktopcomputer")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !notice.touched.isEmpty || notice.reordered {
                        Button("Undo") { center.undoInbox(in: modelContext) }
                            .font(.subheadline.weight(.semibold))
                    }
                    Button {
                        center.dismissInboxNotice()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
                ForEach(Array(notice.changes.prefix(shown).enumerated()), id: \.offset) { _, change in
                    Text(change.text.prefix(1).uppercased() + change.text.dropFirst())
                        .font(.subheadline)
                }
                if notice.changes.count > shown {
                    Text("and \(notice.changes.count - shown) more")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(notice.conflicts.enumerated()), id: \.offset) { _, conflict in
                    warning("Waits in Desk: \(conflict.text).")
                }
                if notice.needsUpdate {
                    warning("Desk sent a change this version of the app cannot read. Update HippoTrophy to take it.")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .font(.subheadline)
    }
}
