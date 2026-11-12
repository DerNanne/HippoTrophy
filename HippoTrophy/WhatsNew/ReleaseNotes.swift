import Foundation

/// What each build brought, as shipped in `ReleaseNotes.json`. The app shows
/// a build's highlights once after an update and everything in Settings; the
/// feature page reads the same file from the build's tag, so the two never
/// tell different stories.
///
/// A feature branch writes its own lines, under the build that comes next.
/// What only developers notice — the data model, tests, tools — stays out.
nonisolated struct ReleaseNotes: Decodable, Equatable {
    /// Newest first.
    let builds: [Build]

    struct Build: Decodable, Equatable, Identifiable {
        let build: Int
        /// What someone using the app would want pointed out: something new,
        /// or a change to how a thing looks or works.
        let highlights: [Highlight]
        /// The smaller things — fixes, polish — for the release notes only.
        let changes: [String]

        var id: Int { build }
    }

    struct Highlight: Decodable, Equatable, Identifiable {
        /// An SF Symbol.
        let symbol: String
        let title: String
        let text: String
        /// An image in the asset catalog, for a feature whose place words
        /// alone do not show.
        let image: String?
        /// The feature's entry on the feature page, for the release notes
        /// there to link to. The app does not use it.
        let page: String?
        /// Short points under `text`, read as a bulleted list — for a
        /// highlight that says several things at once.
        var points: [String]? = nil
        /// Set apart from the rest: what everyone updating has to read or do.
        var important: Bool? = nil

        var isImportant: Bool { important == true }

        var id: String { title }
    }

    /// The file shipped with the app. A file that does not read is a broken
    /// build, which a test catches; the app then shows no notes rather than
    /// stopping.
    static let bundled: ReleaseNotes = {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let notes = try? JSONDecoder().decode(ReleaseNotes.self, from: data)
        else { return ReleaseNotes(builds: []) }
        return notes
    }()
}

extension Bundle {
    /// `CFBundleVersion` as a number; 0 if it is not one.
    nonisolated var buildNumber: Int {
        Int(object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }
}
