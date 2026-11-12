import Foundation
import Testing
import UIKit
@testable import HippoTrophy

struct ReleaseNotesTests {
    private let notes = ReleaseNotes.bundled

    private var currentBuild: Int { Bundle.main.buildNumber }

    /// `bundled` falls back to no notes at all, which the app would show as
    /// nothing new rather than as an error.
    @Test func theShippedFileReads() {
        #expect(!notes.builds.isEmpty)
    }

    @Test func buildsAreNewestFirstAndEachOnce() {
        let numbers = notes.builds.map(\.build)
        #expect(numbers == numbers.sorted(by: >))
        #expect(Set(numbers).count == numbers.count)
    }

    /// A feature branch writes under the build that comes next; anything
    /// further ahead is a typo that would wait for a build that never comes.
    @Test func nothingIsWrittenPastTheNextBuild() {
        let newest = notes.builds.map(\.build).max() ?? 0
        #expect(newest <= currentBuild + 1)
    }

    @Test func everyBuildSaysSomething() {
        for build in notes.builds {
            #expect(!build.highlights.isEmpty || !build.changes.isEmpty, "build \(build.build)")
        }
    }

    @Test func everyHighlightHasItsSymbolAndImage() {
        for highlight in notes.builds.flatMap(\.highlights) {
            #expect(UIImage(systemName: highlight.symbol) != nil, "\(highlight.title): \(highlight.symbol)")
            #expect(!highlight.title.isEmpty && !highlight.text.isEmpty, "\(highlight.title)")
            if let image = highlight.image {
                #expect(UIImage(named: image) != nil, "\(highlight.title): \(image)")
            }
        }
    }
}
