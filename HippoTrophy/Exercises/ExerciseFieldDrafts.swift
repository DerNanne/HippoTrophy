import Foundation

/// The one question the exercise editor asks about what gets logged. Weight
/// and Reps are worth a choice of their own because volume, "3×8 @ 60 kg" and
/// the report look for exactly those two fields.
enum ExerciseLogKind: CaseIterable {
    /// Sets of Weight and Reps, which stay, and fields of its own beside them.
    case weightAndReps
    /// The fields picked, and whether it has sets at all.
    case custom

    var title: String {
        switch self {
        case .weightAndReps: return "Weight & Reps + Additional Fields"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .weightAndReps: return "Records and progress need these two. Add more if you like."
        case .custom: return "Only the fields you pick"
        }
    }

    var symbolName: String {
        switch self {
        case .weightAndReps: return "dumbbell"
        case .custom: return "slider.horizontal.3"
        }
    }

    /// Where a new exercise's category starts, until the user picks one.
    var startingCategory: ExerciseCategory? {
        switch self {
        case .weightAndReps: return .strength
        case .custom: return nil
        }
    }

    /// An exercise opens as what it already is. Weight and Reps both there, in
    /// sets, is the first kind whatever else it logs.
    static func of(fieldTypes: [FieldType], tracksSets: Bool) -> ExerciseLogKind {
        tracksSets && FieldType.standard.allSatisfy(fieldTypes.contains) ? .weightAndReps : .custom
    }
}

/// The fields as the exercise editor holds them until Save.
///
/// A field that only exists as a draft simply goes when removed; one that is
/// already in the store is marked instead, so what is about to be thrown away
/// stays on screen — and can be put back by tapping again.
struct ExerciseFieldDrafts {
    private(set) var all: [FieldDraft]
    private var nextKeyNumber: Int

    /// - Parameter keysInUse: the keys the exercise holds. Reusing one a
    ///   deleted field once had would hang old values under a different field,
    ///   so the counter only ever moves forward.
    init(_ drafts: [FieldDraft], keysInUse: [String]) {
        all = drafts
        let numbers = keysInUse.compactMap { key -> Int? in
            guard key.hasPrefix("f") else { return nil }
            return Int(key.dropFirst())
        }
        nextKeyNumber = (numbers.max() ?? 1) + 1
    }

    /// The fields as they would be saved: the ones not marked for deletion.
    var active: [FieldDraft] {
        all.filter { !$0.isRemoved }
    }

    var labelled: [FieldDraft] {
        active.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A field left without a title. Saving one is never what was meant: on a
    /// stored field it would delete logged values, and on a new one it would
    /// drop the row silently, so Save stays out of reach either way.
    var hasUntitled: Bool {
        active.contains { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Standard fields lead, in their fixed order, whatever order they were
    /// switched on in; the user's own follow in the order they were added. It
    /// is the order a set shows them in, and the order Save writes.
    private func inSetOrder(_ drafts: [FieldDraft]) -> [FieldDraft] {
        drafts.sorted { lhs, rhs in
            (FieldType.standard.firstIndex(of: lhs.type) ?? Int.max) < (FieldType.standard.firstIndex(of: rhs.type) ?? Int.max)
        }
    }

    var allInSetOrder: [FieldDraft] { inSetOrder(all) }
    var activeInSetOrder: [FieldDraft] { inSetOrder(active) }
    var labelledInSetOrder: [FieldDraft] { inSetOrder(labelled) }

    var isFull: Bool {
        active.count >= ExerciseDefinition.maxFields
    }

    /// What Add Field offers. Under Weight & Reps those two are there already,
    /// and a standard field is had once.
    func addableTypes(for kind: ExerciseLogKind) -> [FieldType] {
        let standard = kind == .custom ? FieldType.standard.filter { type in !active.contains { $0.type == type } } : []
        return standard + FieldType.custom
    }

    /// Adds a field of `type`, unless the exercise has all it can hold; a
    /// standard one marked for deletion comes back instead.
    /// - Returns: the field, for the editor to put the cursor in.
    @discardableResult
    mutating func add(_ type: FieldType) -> FieldDraft? {
        guard !isFull else { return nil }
        if type.isStandard {
            return addStandard(type)
        }
        // A definition out of a backup can carry any key at all, so the counter
        // alone is not enough to be sure the new one is free.
        var number = nextKeyNumber
        while all.contains(where: { $0.key == "f\(number)" }) {
            number += 1
        }
        nextKeyNumber = number + 1
        var draft = FieldDraft(key: "f\(number)")
        draft.type = type
        all.append(draft)
        return draft
    }

    private mutating func addStandard(_ type: FieldType) -> FieldDraft? {
        if let index = all.firstIndex(where: { $0.type == type && $0.isRemoved }) {
            all[index].isRemoved = false
            return all[index]
        }
        guard !active.contains(where: { $0.type == type }) else { return nil }
        let draft = FieldDraft(standard: type)
        all.append(draft)
        return draft
    }

    /// Takes a field out, or puts back one marked for deletion.
    mutating func remove(_ id: FieldDraft.ID) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        if all[index].storedID == nil {
            all.remove(at: index)
        } else {
            all[index].isRemoved.toggle()
        }
    }

    mutating func update(_ draft: FieldDraft) {
        guard let index = all.firstIndex(where: { $0.id == draft.id }) else { return }
        all[index] = draft
    }

    /// Whether there is room for whichever of Weight and Reps are missing.
    var canBecomeWeightAndReps: Bool {
        let missing = FieldType.standard.filter { type in !active.contains { $0.type == type } }
        return active.count + missing.count <= ExerciseDefinition.maxFields
    }

    /// Brings in Weight and Reps. The user's own fields stay, as additional
    /// ones. Nothing happens without room for them: see `canBecomeWeightAndReps`.
    mutating func becomeWeightAndReps() {
        guard canBecomeWeightAndReps else { return }
        for type in FieldType.standard {
            _ = addStandard(type)
        }
    }

    /// Custom is only the fields picked. Weight and Reps nobody has logged yet
    /// go, so a new exercise starts empty; stored ones stay until they are
    /// taken out on purpose, because that reaches into what is logged.
    mutating func becomeCustom() {
        all.removeAll { $0.type.isStandard && $0.storedID == nil }
    }
}
