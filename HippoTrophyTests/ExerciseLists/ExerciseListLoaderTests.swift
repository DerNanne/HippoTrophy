import Foundation
import Testing
@testable import HippoTrophy

struct ExerciseListLoaderTests {
    /// A file in the shape the app once shipped still reads; the lists it
    /// held are the catalog now, but people may have kept such a file.
    @Test func aFileInTheOldBundledShapeReads() throws {
        let data = Data(#"{ "lists": [ { "id": "x", "name": "Mine", "exercises": [ { "name": "Push-Up", "muscleGroupNames": ["chest", "elbows"] } ] } ] }"#.utf8)
        let lists = try ExerciseListLoader.lists(fromFileAt: data, fallbackName: "file")
        #expect(lists.map(\.name) == ["Mine"])
        #expect(lists.first?.exercises == [ExerciseListEntry(name: "Push-Up", muscleGroupNames: ["chest"])])
    }
}
