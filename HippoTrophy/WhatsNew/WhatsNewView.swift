import SwiftUI

/// The sheet after an update or a fresh install: the highlights of every
/// build since the one last seen, newest first.
struct WhatsNewView: View {
    let builds: [ReleaseNotes.Build]

    @Environment(\.dismiss) private var dismiss

    private var subtitle: String {
        guard let newest = builds.first?.build, let oldest = builds.last?.build else { return "" }
        return newest == oldest ? "Build \(newest)" : "Builds \(oldest) to \(newest)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 6) {
                    Text("What's New")
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

                ForEach(builds) { build in
                    // Only worth saying when more than one build is shown.
                    if builds.count > 1 {
                        Text("Build \(build.build)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    ForEach(build.highlights) { highlight in
                        HighlightRow(highlight: highlight)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 8)
        }
    }
}

/// One highlight: its symbol beside the title and what it does, and below
/// them the picture, if it has one.
struct HighlightRow: View {
    let highlight: ReleaseNotes.Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: highlight.symbol)
                .font(.title2)
                .foregroundStyle(highlight.isImportant ? AnyShapeStyle(Color.signal) : AnyShapeStyle(.tint))
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.title)
                    .font(.headline)
                Text(highlight.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let points = highlight.points, !points.isEmpty {
                    BulletList(points: points)
                        .padding(.top, 2)
                }
                if let image = highlight.image {
                    // A light ground: a pictogram is drawn for one and has
                    // no background of its own.
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .background(Color(white: 0.96))
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.separator, lineWidth: 0.5)
                        }
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                }
            }
        }
        // Every card as wide as the sheet, whatever its longest line.
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ImportantHighlight(isImportant: highlight.isImportant))
        .accessibilityElement(children: .combine)
    }
}

/// An important highlight on a card in the signal colour.
private struct ImportantHighlight: ViewModifier {
    let isImportant: Bool

    func body(content: Content) -> some View {
        if isImportant {
            content.signalCard()
        } else {
            content
        }
    }
}

/// Shows `WhatsNewView` once after an update, and remembers the build when
/// it is closed. What to show is `WhatsNew`'s to decide.
struct WhatsNewAtLaunch: ViewModifier {
    /// 0 means no build was ever remembered.
    @AppStorage(SettingsKey.whatsNewSeenBuild) private var seenBuild = 0
    @State private var decided = false
    /// Set while the sheet is up. Handed over as the sheet's item, so the
    /// sheet gets what was decided rather than what its closure last saw.
    @State private var shown: WhatsNew?
    /// Remembered when the sheet closes, by which time `shown` is gone.
    @State private var seenOnClose = 0

    func body(content: Content) -> some View {
        content
            .task {
                guard !decided else { return }
                decided = true
                let decision = WhatsNew(
                    notes: .bundled,
                    currentBuild: Bundle.main.buildNumber,
                    lastSeen: seenBuild == 0 ? nil : seenBuild
                )
                if decision.builds.isEmpty {
                    seenBuild = decision.seenBuild
                } else {
                    seenOnClose = decision.seenBuild
                    shown = decision
                }
            }
            .sheet(item: $shown, onDismiss: { seenBuild = seenOnClose }) { whatsNew in
                WhatsNewView(builds: whatsNew.builds)
            }
    }
}

extension View {
    func whatsNewAtLaunch() -> some View {
        modifier(WhatsNewAtLaunch())
    }
}
