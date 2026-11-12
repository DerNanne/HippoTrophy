import Testing
@testable import HippoTrophy

struct WhatsNewTests {
    private func build(_ number: Int, highlights: Int = 1) -> ReleaseNotes.Build {
        ReleaseNotes.Build(
            build: number,
            highlights: (0..<highlights).map {
                ReleaseNotes.Highlight(symbol: "star", title: "\(number)-\($0)", text: "", image: nil, page: nil)
            },
            changes: []
        )
    }

    private var notes: ReleaseNotes {
        ReleaseNotes(builds: [build(23), build(22, highlights: 0), build(21), build(20)])
    }

    private func shown(current: Int, lastSeen: Int?) -> [Int] {
        WhatsNew(notes: notes, currentBuild: current, lastSeen: lastSeen).builds.map(\.build)
    }

    /// To someone new everything is new: nothing at launch, and the build is
    /// remembered so the next update shows only what it brings.
    @Test func aFreshInstallShowsNothingAndRemembersItsBuild() {
        let whatsNew = WhatsNew(notes: notes, currentBuild: 21, lastSeen: nil)
        #expect(whatsNew.builds.isEmpty)
        #expect(whatsNew.seenBuild == 21)
    }

    /// An update from before builds remembered anything looks like a fresh
    /// install and is shown nothing either. Only early test builds had no
    /// memory, so only testers miss those notes.
    @Test func anUpdateFromBeforeBuildsRememberedIsShownNothingWithoutSayingSo() {
        #expect(shown(current: 23, lastSeen: nil).isEmpty)
    }

    @Test func theUpdateAfterAFreshInstallShowsWhatItBrings() {
        let installed = WhatsNew(notes: notes, currentBuild: 21, lastSeen: nil)
        #expect(shown(current: 23, lastSeen: installed.seenBuild) == [23])
    }

    @Test func theNextBuildShowsOnlyItself() {
        #expect(shown(current: 21, lastSeen: 20) == [21])
    }

    @Test func skippedBuildsAllShowNewestFirst() {
        #expect(shown(current: 23, lastSeen: 20) == [23, 21])
    }

    @Test func aBuildWithoutHighlightsShowsNothing() {
        let whatsNew = WhatsNew(notes: notes, currentBuild: 22, lastSeen: 21)
        #expect(whatsNew.builds.isEmpty)
        #expect(whatsNew.seenBuild == 22)
    }

    @Test func notesForABuildNotYetReleasedWait() {
        #expect(shown(current: 19, lastSeen: 18).isEmpty)
    }

    @Test func theSameBuildAgainShowsNothing() {
        #expect(shown(current: 21, lastSeen: 21).isEmpty)
    }

    @Test func anOlderBuildPutBackShowsNothingAndKeepsTheNewerOneSeen() {
        let whatsNew = WhatsNew(notes: notes, currentBuild: 20, lastSeen: 23)
        #expect(whatsNew.builds.isEmpty)
        #expect(whatsNew.seenBuild == 23)
    }
}
