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
                    }
            case .failure(let error):
                StoreUnavailableView(error: error)
            }
        }
    }
}
