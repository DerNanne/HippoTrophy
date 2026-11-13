import Foundation
import SwiftData

/// One exercise inside a workout, logged from an `ExerciseDefinition`.
///
/// Everything logged is in its sets: an exercise that tracks sets holds as
/// many as were done, one that does not holds exactly one. Whether it tracks
/// sets is the definition's to say — see `ExerciseDefinition.tracksSets` —
/// and switching that converts the entries, so there is one answer.
///
/// What the definition said at the time is copied onto the entry and its
/// values — the name, the label and type of every field — so the entry still
/// reads correctly after the definition was renamed, reshaped or deleted.
/// `definitionID` is the link back for the things that *should* follow the
/// definition: renames, field changes, and merging two definitions.
@Model
final class ExerciseEntry {
    var id: UUID
    var name: String
    /// What happened this time — a report, kept with this workout only. A
    /// copy, a template or a workout started from one starts without it.
    var notes: String
    /// How the exercise is to be done this time — tempo, range, intensity —
    /// a plan that a copy, a template and a workout started from one take
    /// along. Added in `SchemaV12`; empty for everything before, except in a
    /// template, whose notes became its instructions.
    var instructions: String = ""
    var orderIndex: Int
    var definitionID: UUID
    /// Shared by every exercise of the same superset, in the same workout;
    /// `nil` for an exercise trained on its own. Grouping is by this id alone,
    /// wherever the entries sit in the workout's order — see
    /// `ExerciseGrouping`.
    var supersetID: UUID?
    var tracksUnilateral: Bool
    /// Read only while `tracksUnilateral` is set, and never written directly —
    /// `unilateralMode` is the way in.
    var logsSidesSeparately: Bool
    /// An `EffortScale` raw value — how this entry's sets are rated. Never
    /// written directly; `effortScale` is the way in.
    var effortScaleRawValue: String
    /// The catalog exercise this was logged from, kept like `name`: a copy
    /// taken when it was logged and pulled along by whatever renames or
    /// moves its definition. nil for the user's own. Together with the name
    /// it is the entry's `identity`, which history and "last time" go by.
    var catalogKey: String?
    /// An `Assistance` raw value — whether the sets were helped up. Never
    /// written directly; `assistance` is the way in. Added in `SchemaV6`,
    /// unassisted for everything before.
    var assistanceRawValue: String = Assistance.unassisted.rawValue
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.exercise)
    var sets: [SetEntry]
    var session: WorkoutSession?
    /// The machine it was done at; nil where it was not said. Travels with
    /// copies and templates like the instructions. Added in `SchemaV13`.
    var machine: Machine?
    /// An `ExerciseSide` raw value: the side a unilateral entry started with,
    /// proposed from the last time and changed for this workout. nil where it
    /// was not said — bilateral, or logged before there was a place for it.
    /// `startSide` reads it; `setStartSide` sets it. Added in `SchemaV14`.
    var startSideRawValue: String?

    init(
        name: String,
        notes: String = "",
        instructions: String = "",
        orderIndex: Int,
        definitionID: UUID,
        supersetID: UUID? = nil,
        tracksUnilateral: Bool = false,
        logsSidesSeparately: Bool = true,
        effortScale: EffortScale,
        catalogKey: String? = nil,
        assistance: Assistance = .unassisted,
        sets: [SetEntry] = [],
        session: WorkoutSession? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.instructions = instructions
        self.orderIndex = orderIndex
        self.definitionID = definitionID
        self.supersetID = supersetID
        self.tracksUnilateral = tracksUnilateral
        self.logsSidesSeparately = logsSidesSeparately
        self.effortScaleRawValue = effortScale.rawValue
        self.catalogKey = catalogKey
        self.assistanceRawValue = assistance.rawValue
        self.sets = sets
        self.session = session
    }

    var identity: ExerciseIdentity {
        ExerciseIdentity(name: name, catalogKey: catalogKey)
    }

    /// Whether this is part of a template rather than of a workout trained:
    /// it follows its exercise like any entry, but is no history, no "last
    /// time" and no set done.
    var isInTemplate: Bool {
        session?.isTemplate == true
    }

    /// By number, and where left and right each have a set 1, the side
    /// after it — left before right. Without that tie broken, the same entry
    /// could read in another order next time, and so could its backup, whose
    /// fingerprint the sync compares.
    var sortedSets: [SetEntry] {
        sets.sorted { ($0.setNumber, $0.sideRawValue) < ($1.setNumber, $1.sideRawValue) }
    }

    /// The sets done, in order — what progress and "last time" read. A
    /// planned set's values are a plan, not a performance.
    var doneSets: [SetEntry] {
        sortedSets.filter(\.isDone)
    }

    /// Whether this entry's exercise logs sets — its definition's to say,
    /// found among `definitions`. Without one, what the entry holds is the only
    /// evidence left.
    func tracksSets(among definitions: [ExerciseDefinition]) -> Bool {
        definitions.first { $0.id == definitionID }?.tracksSets ?? (sets.count > 1)
    }

    /// The single way to read or set how this entry was trained.
    var unilateralMode: UnilateralMode {
        get {
            guard tracksUnilateral else { return .bilateral }
            return logsSidesSeparately ? .perSide : .oneSided
        }
        set {
            tracksUnilateral = newValue != .bilateral
            logsSidesSeparately = newValue != .oneSided
        }
    }

    /// Whether the sets were helped up. Setting it says what the sets hold;
    /// switching an entry that already has sets is `applyAssistance`, which
    /// moves their values along.
    var assistance: Assistance {
        get { Assistance(rawValue: assistanceRawValue) ?? .unassisted }
        set { assistanceRawValue = newValue.rawValue }
    }

    /// How this entry's sets are rated. Set on creation; changing it is a
    /// decision about the ratings already given, and not this property's.
    var effortScale: EffortScale {
        get { EffortScale(rawValue: effortScaleRawValue) ?? .off }
        set { effortScaleRawValue = newValue.rawValue }
    }

    /// Whether the entry holds anything worth showing in a history list: a set
    /// with a value in it.
    var hasLoggedData: Bool {
        sets.contains { $0.hasLoggedData }
    }

    /// Whether the entry belongs in its exercise's history: anything with a
    /// value in it, and also an entry whose only content is a note — a warm-up
    /// written down as such, or an exercise skipped with the reason why. That
    /// the exercise was on the plan that day is worth seeing even when nothing
    /// was measured. An entry with neither is an exercise added and forgotten,
    /// and stays out.
    ///
    /// "Last time" and the counts keep asking `hasLoggedData`: a note is not a
    /// performance to beat, and not an exercise trained.
    var belongsInHistory: Bool {
        hasLoggedData || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// How many of its sets count: those with something logged in them — see
    /// `WorkoutSession.setCount`.
    var setCount: Int {
        sets.filter(\.hasLoggedData).count
    }

    /// Whether every set is a set of weight training, which is what the report
    /// and the volume figures can work with — assisted ones included, which
    /// add nothing to a volume.
    var logsWeightAndReps: Bool {
        !sets.isEmpty && sets.allSatisfy { $0.logsWeightAndReps }
    }
}
