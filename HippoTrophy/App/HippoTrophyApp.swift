import SwiftUI
import SwiftData

@main
struct HippoTrophyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// The store, with the catalog brought in before anything reads it, and
    /// the own exercises settled the first time after the update that
    /// brought bilateral and unilateral, every own exercise never used
    /// dropped once more with build 22, and any undecided one never used
    /// dropped every time after. Any of them failing leaves the app as it
    /// was, not unusable.
    private let store = Result { try AppSchema.openStore() }.map { container in
        try? CatalogSync.run(in: container.mainContext)
        try? SidesSettlement.runOnce(in: container.mainContext)
        try? SidesSettlement.dropUnusedOnce(in: container.mainContext)
        try? SidesSettlement.dropLeftovers(in: container.mainContext)
        return container
    }

    var body: some Scene {
        WindowGroup {
            switch store {
            case .success(let container):
                RootView()
                    .modelContainer(container)
                    // A rest may have ended while the app was away.
                    .onChange(of: scenePhase, initial: true) { _, phase in
                        if phase == .active { RestTimerCenter.shared.refresh() }
                        sync(on: phase, in: container.mainContext)
                    }
                    // A workout finished or discarded: what it changed goes
                    // to the server.
                    .onChange(of: RunningWorkoutCenter.shared.running == nil) { _, ended in
                        if ended, !Self.hostsTests { SyncCenter.shared.syncInBackground(.automatic, in: container.mainContext) }
                    }
            case .failure(let error):
                StoreUnavailableView(error: error)
            }
        }
    }

    /// Whether this launch only hosts the unit tests. Then the app leaves
    /// the server alone: a simulator connected to one would otherwise take
    /// what waits in its inbox in the middle of a test run, and never upload.
    static let hostsTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Going away, the sync puts up what changed. Coming back, it tries again
    /// if the last upload failed, or takes what Desk left in the inbox.
    private func sync(on phase: ScenePhase, in context: ModelContext) {
        guard !Self.hostsTests else { return }
        let center = SyncCenter.shared
        switch phase {
        case .background: center.syncInBackground(.automatic, in: context)
        case .active where center.owesUpload: center.syncInBackground(.automatic, in: context)
        case .active: center.syncIfInboxHasMail(in: context)
        default: break
        }
    }
}
