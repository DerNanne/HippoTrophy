import SwiftUI
import SwiftData

/// Puts the review of My Exercises in front of the user at launch, when
/// `CatalogReviewPrompt` says so — after What's New, never on top of it, and
/// after the sides assistant, which comes first whenever an own exercise is
/// still undecided and cannot be skipped: the review compares exercises by
/// their side.
///
/// The assistant also comes after an import that brought undecided
/// exercises in — a backup saved from the assistant itself, say — instead of
/// waiting for the next launch.
struct CatalogReviewAtLaunch: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.whatsNewSeenBuild) private var whatsNewSeen = 0
    @AppStorage(SettingsKey.keptOwnExercises) private var keptStored = ""
    @AppStorage(SettingsKey.catalogMovedCount) private var movedCount = 0
    @AppStorage(SettingsKey.catalogReviewDontShow) private var dontShowAgain = false
    @AppStorage(SettingsKey.catalogReviewLastShown) private var lastShownInterval = 0.0
    @State private var asked = false
    @State private var showReview = false
    @State private var showSides = false

    func body(content: Content) -> some View {
        content
            .task {
                // What's New decides the same way at the same moment; while it
                // has something to show, this waits for it to close.
                let whatsNew = WhatsNew(
                    notes: .bundled,
                    currentBuild: Bundle.main.buildNumber,
                    lastSeen: whatsNewSeen == 0 ? nil : whatsNewSeen
                )
                if whatsNew.builds.isEmpty {
                    await ask()
                }
            }
            .onChange(of: whatsNewSeen) { _, _ in
                Task { await ask() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .backupImported)) { _ in
                Task { await askAfterImport() }
            }
            .sheet(isPresented: $showReview) {
                NavigationStack {
                    CatalogReviewView(isPrompt: true)
                }
            }
            .fullScreenCover(isPresented: $showSides) {
                SidesAssistantView {
                    showSides = false
                    Task { await ask() }
                }
            }
    }

    /// An import brings exercises the launch did not ask about: asked anew,
    /// the assistant first if needed, then the review. Its wait also lets
    /// the import's message leave; a cover presented on top of that does
    /// not appear.
    private func askAfterImport() async {
        guard !showSides, !showReview else { return }
        asked = false
        await ask()
    }

    private func ask() async {
        guard !asked else { return }
        if SidesAssistant.isNeeded(in: modelContext) {
            // Asked again once it is done, for the review behind it.
            try? await Task.sleep(for: .milliseconds(700))
            showSides = true
            return
        }
        asked = true
        let definitions = (try? modelContext.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        let prompt = CatalogReviewPrompt(
            pending: CatalogReview.pendingCount(in: definitions, kept: KeptOwnExercises(stored: keptStored).ids),
            moved: movedCount,
            dontShowAgain: dontShowAgain,
            lastShown: lastShownInterval > 0 ? Date(timeIntervalSinceReferenceDate: lastShownInterval) : nil
        )
        guard prompt.shouldShow(at: .now) else { return }
        // A sheet that has just closed is still leaving; one presented on
        // top of that does not appear.
        try? await Task.sleep(for: .milliseconds(700))
        lastShownInterval = Date.now.timeIntervalSinceReferenceDate
        showReview = true
    }
}

extension View {
    func catalogReviewAtLaunch() -> some View {
        modifier(CatalogReviewAtLaunch())
    }
}
