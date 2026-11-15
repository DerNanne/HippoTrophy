import Foundation
import Testing
@testable import HippoTrophy

/// What the inbox comes to, without a store: which file applies, which waits
/// in Desk, and the templates after.
struct InboxPlannerTests {
    private func template(_ name: String, id: UUID = UUID(), notes: String = "", archived: Bool = false) -> SyncTemplate {
        SyncTemplate(id: id, name: name, notes: notes, archived: archived, plannedFor: nil, gym: nil, exercises: [
            SyncEntry(
                exercise: "Back Squat", catalogKey: "back-squat", notes: "", instructions: "", mode: "bilateral",
                assistance: "unassisted", effortScale: "off", supersetGroup: nil, machine: nil, startSide: nil,
                sets: [SyncSet(side: "both", effort: nil, supersetPosition: nil, sideOrder: nil, done: false, values: [
                    SyncValue(key: "weight", label: "Weight", type: "weight", text: nil, number: 100),
                    SyncValue(key: "reps", label: "Reps", type: "reps", text: nil, number: 5),
                ])]
            ),
        ])
    }

    private func file(_ name: String, _ operations: SyncOperation...) -> InboxPlanner.File {
        InboxPlanner.File(name: name, content: .success(InboxFile(syncFormat: 1, createdAt: .now, operations: operations)))
    }

    private let legs = SyncTemplate(id: UUID(), name: "Legs", notes: "", archived: false, plannedFor: nil, gym: nil, exercises: [])

    @Test func aNewTemplateStandsFirst() {
        let state = TemplateState(templates: [legs])
        let push = template("Push")
        let plan = InboxPlanner.plan([file("1.json", .putTemplate(template: push, base: nil))], on: state)
        #expect(plan.outcomes.map(\.outcome) == [.apply([.added("Push")])])
        #expect(plan.result.order == [push.id, legs.id])
        #expect(plan.result.templates[push.id] == push)
    }

    @Test func aChangeAppliesWhileTheTemplateIsAsDeskSawIt() {
        let push = template("Push")
        var changed = push
        changed.notes = "Slow negatives"
        let plan = InboxPlanner.plan([file("1.json", .putTemplate(template: changed, base: push))], on: TemplateState(templates: [legs, push]))
        #expect(plan.outcomes.map(\.outcome) == [.apply([.changed("Push")])])
        #expect(plan.result.templates[push.id]?.notes == "Slow negatives")
        #expect(plan.result.order == [legs.id, push.id])
    }

    @Test func aChangeWaitsWhenTheTemplateChangedHere() {
        let push = template("Push")
        var here = push
        here.name = "Push A"
        var desk = push
        desk.notes = "Slow negatives"
        let state = TemplateState(templates: [here])
        let plan = InboxPlanner.plan([file("1.json", .putTemplate(template: desk, base: push))], on: state)
        #expect(plan.outcomes.map(\.outcome) == [.conflict(.changedHere("Push A"))])
        #expect(plan.result == state)
    }

    @Test func aChangeWaitsWhenTheTemplateWasDeletedHere() {
        let push = template("Push")
        var desk = push
        desk.notes = "Slow negatives"
        let plan = InboxPlanner.plan([file("1.json", .putTemplate(template: desk, base: push))], on: TemplateState(templates: [legs]))
        #expect(plan.outcomes.map(\.outcome) == [.conflict(.deletedHere("Push"))])
    }

    @Test func archivingSaysItself() {
        let push = template("Push")
        var archived = push
        archived.archived = true
        let plan = InboxPlanner.plan([file("1.json", .putTemplate(template: archived, base: push))], on: TemplateState(templates: [push]))
        #expect(plan.changes == [.archived("Push")])
        var back = archived
        back.archived = false
        #expect(InboxPlanner.plan([file("2.json", .putTemplate(template: back, base: archived))], on: plan.result).changes == [.restored("Push")])
    }

    @Test func deletesOnlyWhatDeskSaw() {
        let push = template("Push")
        let plan = InboxPlanner.plan([file("1.json", .deleteTemplate(id: push.id, base: push))], on: TemplateState(templates: [legs, push]))
        #expect(plan.changes == [.deleted("Push")])
        #expect(plan.result.order == [legs.id])

        var here = push
        here.notes = "Changed on the phone"
        let refused = InboxPlanner.plan([file("1.json", .deleteTemplate(id: push.id, base: push))], on: TemplateState(templates: [here]))
        #expect(refused.conflicts == [.changedHere("Push")])
        #expect(refused.result.templates[push.id] != nil)
    }

    @Test func deletingWhatIsGoneAlreadyChangesNothing() {
        let push = template("Push")
        let plan = InboxPlanner.plan([file("1.json", .deleteTemplate(id: push.id, base: push))], on: TemplateState(templates: [legs]))
        #expect(plan.outcomes.map(\.outcome) == [.apply([])])
    }

    @Test func theOrderFromDeskLeavesTemplatesMadeHereInFront() {
        let a = template("A"), b = template("B"), new = template("New here")
        let state = TemplateState(templates: [new, a, b])
        let plan = InboxPlanner.plan([file("1.json", .orderTemplates(ids: [b.id, a.id, UUID()]))], on: state)
        #expect(plan.result.order == [new.id, b.id, a.id])
        #expect(plan.changes == [.reordered])
    }

    @Test func aFileTakenTwiceChangesNothingTheSecondTime() {
        let push = template("Push")
        var changed = push
        changed.notes = "Slow negatives"
        let files = [
            file("1.json", .putTemplate(template: push, base: nil), .putTemplate(template: changed, base: push)),
        ]
        let once = InboxPlanner.plan(files, on: TemplateState())
        let twice = InboxPlanner.plan(files, on: once.result)
        #expect(twice.result == once.result)
        #expect(twice.changes.isEmpty)
    }

    @Test func aFileAppliesWholeOrNotAtAll() {
        let push = template("Push")
        let other = template("Other")
        var stale = other
        stale.notes = "As Desk saw it"
        let plan = InboxPlanner.plan(
            [file("1.json", .putTemplate(template: push, base: nil), .deleteTemplate(id: other.id, base: stale))],
            on: TemplateState(templates: [other])
        )
        #expect(plan.conflicts == [.changedHere("Other")])
        #expect(plan.result.templates[push.id] == nil)
    }

    @Test func aLaterFileBuildsOnAnEarlierOne() {
        let push = template("Push")
        var changed = push
        changed.notes = "Second save"
        let plan = InboxPlanner.plan(
            [file("2.json", .putTemplate(template: changed, base: push)), file("1.json", .putTemplate(template: push, base: nil))],
            on: TemplateState()
        )
        #expect(plan.outcomes.map(\.name) == ["1.json", "2.json"])
        #expect(plan.changes == [.added("Push"), .changed("Push")])
    }

    @Test func leavesWhatItCannotReadAndSaysWhatIsNewer() {
        let plan = InboxPlanner.plan([
            InboxPlanner.File(name: "1.json", content: .failure(.tooNew(2))),
            InboxPlanner.File(name: "2.json", content: .failure(.unreadable)),
        ], on: TemplateState(templates: [legs]))
        #expect(plan.outcomes.map(\.outcome) == [.tooNew(2), .unreadable])
        #expect(plan.result == TemplateState(templates: [legs]))
    }

    @Test func comparesDatesToTheSecondAsTheFileHasThem() {
        var here = template("Variant")
        here.plannedFor = Date(timeIntervalSinceReferenceDate: 800_000_000.4)
        var desk = here
        desk.plannedFor = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var changed = desk
        changed.notes = "Lighter today"
        let plan = InboxPlanner.plan([file("1.json", .putTemplate(template: changed, base: desk))], on: TemplateState(templates: [here]))
        #expect(plan.changes == [.changed("Variant")])
    }
}

struct InboxFileTests {
    @Test func readsWhatItWrites() throws {
        let template = SyncTemplate(id: UUID(), name: "Push", notes: "", archived: false, plannedFor: nil, gym: "Home", exercises: [])
        let file = InboxFile(syncFormat: 1, createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000), operations: [
            .putTemplate(template: template, base: nil),
            .deleteTemplate(id: template.id, base: template),
            .orderTemplates(ids: [template.id]),
        ])
        #expect(InboxFile.read(from: try SyncFormat.encoder.encode(file)) == .success(file))
    }

    @Test func leavesANewerFormatAlone() {
        #expect(InboxFile.read(from: Data(#"{"syncFormat": 2, "createdAt": "2026-11-15T10:00:00Z", "operations": []}"#.utf8)) == .failure(.tooNew(2)))
    }

    @Test func doesNotGuessAnOperationItDoesNotKnow() {
        let json = #"{"syncFormat": 1, "createdAt": "2026-11-15T10:00:00Z", "operations": [{"op": "putWorkout"}]}"#
        #expect(InboxFile.read(from: Data(json.utf8)) == .failure(.unreadable))
        #expect(InboxFile.read(from: Data("<html>".utf8)) == .failure(.unreadable))
    }
}
