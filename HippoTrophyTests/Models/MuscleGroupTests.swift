import Testing
@testable import HippoTrophy

/// The muscle set is the app's to define, so reading a list off a file is a
/// filter, not a parser: what is not in the set is reported rather than invented.
struct MuscleGroupTests {
    @Test func readsSpellingAndCasingAsTheyCome() {
        #expect(MuscleGroup.from(raw: "Chest") == .chest)
        #expect(MuscleGroup.from(raw: "  hamstrings  ") == .hamstrings)
        #expect(MuscleGroup.from(raw: "QUADS") == .quads)
        #expect(MuscleGroup.from(raw: "") == nil)
        #expect(MuscleGroup.from(raw: "neck") == nil)
    }

    /// The first entry is the main muscle, so order survives — and a repeat does
    /// not push a muscle down the list a second time.
    @Test func orderSurvivesAndDuplicatesCollapse() {
        let read = MuscleGroup.read(["Back", "chest", "BACK"])
        #expect(read.muscles == ["back", "chest"])
        #expect(read.unknown.isEmpty)
    }

    /// Reported in the file's own spelling, so the import can name what it
    /// dropped — but only once, however often and however cased it appears.
    @Test func anUnknownNameIsReportedOnceInItsOwnSpelling() {
        let read = MuscleGroup.read(["Neck", "Chest", "neck", "NECK"])
        #expect(read.muscles == ["chest"])
        #expect(read.unknown == ["Neck"])
    }

    @Test func blankEntriesAreNeitherKeptNorReported() {
        let read = MuscleGroup.read(["", "   ", "\n"])
        #expect(read.muscles.isEmpty)
        #expect(read.unknown.isEmpty)
    }

    @Test func trapsIsUpperBodyAndNotArms() {
        #expect(MuscleRegion.upperBody.muscles.contains(.traps))
        #expect(!MuscleRegion.arms.muscles.contains(.traps))
    }

    @Test func everyCaseIsReadableByItsOwnRawValue() {
        for muscle in MuscleGroup.allCases {
            #expect(MuscleGroup.from(raw: muscle.rawValue) == muscle)
        }
    }
}
