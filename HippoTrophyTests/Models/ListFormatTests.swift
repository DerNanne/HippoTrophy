import Testing
@testable import HippoTrophy

struct ListFormatTests {
    @Test(arguments: [
        ([], ""),
        (["Squat"], "Squat"),
        (["Squat", "Bench"], "Squat and Bench"),
        (["Squat", "Bench", "Row"], "Squat, Bench and Row")
    ])
    func listsTheWaySentencesDo(items: [String], expected: String) {
        #expect(ListFormat.text(items) == expected)
    }
}
