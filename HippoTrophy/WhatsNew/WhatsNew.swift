import Foundation

/// What "What's New" shows at launch: the highlights of every build since the
/// one last seen, newest first. A fresh install is shown nothing: to someone
/// new everything is new, and a list of changes they never went through says
/// nothing. Settings → What's New has every build all the same.
nonisolated struct WhatsNew: Equatable, Identifiable {
    /// Empty when there is nothing to show.
    let builds: [ReleaseNotes.Build]
    /// The build to remember as seen: once the sheet is closed, or straight
    /// away when there is nothing to show.
    let seenBuild: Int

    var id: Int { seenBuild }

    /// - Parameter lastSeen: the build remembered last time, nil if none ever
    ///   was — a fresh install, or one from before builds remembered anything.
    ///   Both are shown nothing; the current build is remembered, so the next
    ///   update shows what it brings.
    init(notes: ReleaseNotes, currentBuild: Int, lastSeen: Int?) {
        // Never lowered: a build put back on top of a newer one would show
        // the newer one's notes again once that returns.
        seenBuild = max(currentBuild, lastSeen ?? 0)
        guard let since = lastSeen else {
            builds = []
            return
        }
        builds = notes.builds
            .filter { $0.build > since && $0.build <= currentBuild && !$0.highlights.isEmpty }
            .sorted { $0.build > $1.build }
    }
}
