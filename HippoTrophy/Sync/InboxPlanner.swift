import Foundation

/// The templates as the inbox sees them: each by id, and their order, the
/// archived ones in it too — `templateOrder`, which an archived template
/// keeps while it is away.
nonisolated struct TemplateState: Equatable {
    var templates: [UUID: SyncTemplate]
    var order: [UUID]

    init(templates: [SyncTemplate] = []) {
        self.templates = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.order = templates.map(\.id)
    }

    var inOrder: [SyncTemplate] { order.compactMap { templates[$0] } }
}

/// What the inbox comes to, worked out before anything is written: which
/// files apply, which wait in Desk for a decision, and the templates after.
/// A file is one save in Desk, applied whole or not at all.
nonisolated enum InboxPlanner {
    struct File {
        var name: String
        var content: Result<InboxFile, InboxFile.ReadError>
    }

    enum Change: Equatable {
        case added(String)
        case changed(String)
        case archived(String)
        case restored(String)
        case deleted(String)
        case reordered
    }

    /// Why a file waits in Desk. Named by the template it is about.
    enum Conflict: Equatable {
        /// Changed here since Desk read it.
        case changedHere(String)
        /// Deleted here since Desk read it.
        case deletedHere(String)
        /// A new template whose id is already one here, and not the same —
        /// only a copied file could do that.
        case alreadyHere(String)
    }

    enum Outcome: Equatable {
        case apply([Change])
        case conflict(Conflict)
        /// Written by a newer Desk: left in the inbox for an updated app.
        case tooNew(Int)
        /// Nothing this app can read; left where it is.
        case unreadable
    }

    struct Plan: Equatable {
        var outcomes: [(name: String, outcome: Outcome)]
        var result: TemplateState

        static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.result == rhs.result && lhs.outcomes.map(\.name) == rhs.outcomes.map(\.name)
                && lhs.outcomes.map(\.outcome) == rhs.outcomes.map(\.outcome)
        }

        var changes: [Change] {
            outcomes.flatMap { item -> [Change] in
                if case .apply(let changes) = item.outcome { return changes }
                return []
            }
        }

        var conflicts: [Conflict] {
            outcomes.compactMap { item -> Conflict? in
                if case .conflict(let conflict) = item.outcome { return conflict }
                return nil
            }
        }
    }

    /// The files in their order — Desk names them by time, so by name — each
    /// on the state the ones before it left.
    static func plan(_ files: [File], on state: TemplateState) -> Plan {
        var state = state
        var outcomes: [(name: String, outcome: Outcome)] = []
        for file in files.sorted(by: { $0.name < $1.name }) {
            switch file.content {
            case .failure(.tooNew(let version)):
                outcomes.append((file.name, .tooNew(version)))
            case .failure(.unreadable):
                outcomes.append((file.name, .unreadable))
            case .success(let inbox):
                var trial = state
                switch apply(inbox.operations, to: &trial) {
                case .success(let changes):
                    state = trial
                    outcomes.append((file.name, .apply(changes)))
                case .failure(let conflict):
                    outcomes.append((file.name, .conflict(conflict.conflict)))
                }
            }
        }
        return Plan(outcomes: outcomes, result: state)
    }

    private struct Refused: Error {
        var conflict: Conflict
    }

    private static func apply(_ operations: [SyncOperation], to state: inout TemplateState) -> Result<[Change], Refused> {
        var changes: [Change] = []
        for operation in operations {
            switch operation {
            case .putTemplate(let template, let base):
                let current = state.templates[template.id]?.normalized
                let wanted = template.normalized
                if current == wanted { continue } // already so: a file applied twice changes nothing
                guard let base else {
                    // New in Desk.
                    if current != nil { return .failure(Refused(conflict: .alreadyHere(template.name))) }
                    state.templates[template.id] = wanted
                    state.order.insert(template.id, at: 0)
                    changes.append(.added(template.name))
                    continue
                }
                guard let current else { return .failure(Refused(conflict: .deletedHere(base.name))) }
                guard current == base.normalized else { return .failure(Refused(conflict: .changedHere(current.name))) }
                state.templates[template.id] = wanted
                changes.append(change(from: current, to: wanted))
            case .deleteTemplate(let id, let base):
                guard let current = state.templates[id]?.normalized else { continue } // gone already
                guard current == base.normalized else { return .failure(Refused(conflict: .changedHere(current.name))) }
                state.templates[id] = nil
                state.order.removeAll { $0 == id }
                changes.append(.deleted(current.name))
            case .orderTemplates(let ids):
                // The order Desk gave for the templates it knew; one made here
                // since stays in front, as a new template stands first.
                let known = ids.filter { state.templates[$0] != nil }
                let unknown = state.order.filter { !ids.contains($0) }
                let order = unknown + known
                if order != state.order {
                    state.order = order
                    changes.append(.reordered)
                }
            }
        }
        return .success(changes)
    }

    /// Archiving is a change like any other, but says itself.
    private static func change(from old: SyncTemplate, to new: SyncTemplate) -> Change {
        var unarchived = new
        unarchived.archived = old.archived
        if unarchived == old, old.archived != new.archived {
            return new.archived ? .archived(new.name) : .restored(new.name)
        }
        return .changed(new.name)
    }
}

extension InboxPlanner.Change {
    var text: String {
        switch self {
        case .added(let name): "\(name) added"
        case .changed(let name): "\(name) changed"
        case .archived(let name): "\(name) archived"
        case .restored(let name): "\(name) back from the archive"
        case .deleted(let name): "\(name) deleted"
        case .reordered: "templates reordered"
        }
    }
}

extension InboxPlanner.Conflict {
    var text: String {
        switch self {
        case .changedHere(let name): "\(name) was changed on this iPhone in the meantime"
        case .deletedHere(let name): "\(name) was deleted on this iPhone in the meantime"
        case .alreadyHere(let name): "\(name) is here already as another template"
        }
    }
}
