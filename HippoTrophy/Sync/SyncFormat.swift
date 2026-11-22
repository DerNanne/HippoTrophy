import Foundation

/// The sync format: what HippoTrophy Desk sends this app, changes rather than
/// a whole backup. Kept apart from the backup format on purpose. A backup is
/// for any app and any person to read, and every one ever written is read
/// again, step by step; this one is spoken only between this app and Desk,
/// so it can say what a sync needs — which state a change was made on —
/// without a backup having to carry it.
///
/// Each version is read by exactly one type, as with the backup: a file of
/// another version is not half-read.
nonisolated enum SyncFormat {
    static let current = 1

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// One file in `HippoTrophy/inbox/`: what one save in Desk changed. Applied
/// whole or not at all.
nonisolated struct InboxFile: Codable, Equatable {
    var syncFormat: Int
    var createdAt: Date
    var operations: [SyncOperation]

    enum ReadError: Error, Equatable {
        /// Written by a newer Desk than this app understands.
        case tooNew(Int)
        case unreadable
    }

    static func read(from data: Data) -> Result<InboxFile, ReadError> {
        struct Version: Decodable { var syncFormat: Int }
        guard let version = try? SyncFormat.decoder.decode(Version.self, from: data) else { return .failure(.unreadable) }
        guard version.syncFormat == SyncFormat.current else {
            return .failure(version.syncFormat > SyncFormat.current ? .tooNew(version.syncFormat) : .unreadable)
        }
        guard let file = try? SyncFormat.decoder.decode(InboxFile.self, from: data) else {
            // A version this app knows, with an operation it does not: a newer
            // Desk that kept the number. Left for an update rather than guessed.
            return .failure(.unreadable)
        }
        return .success(file)
    }
}

/// What one change asks for. `base` is the record as Desk saw it in the
/// backup when the change was made; the change applies only while the
/// record here is still that.
nonisolated enum SyncOperation: Codable, Equatable {
    /// A new template (`base` nil) or a changed one, archiving included.
    case putTemplate(template: SyncTemplate, base: SyncTemplate?)
    case deleteTemplate(id: UUID, base: SyncTemplate)
    /// The templates' order, as Desk knew them.
    case orderTemplates(ids: [UUID])
    /// A workout logged in Desk (`base` nil) or a trained one changed.
    case putWorkout(workout: SyncWorkout, base: SyncWorkout?)
    case deleteWorkout(id: UUID, base: SyncWorkout)
    /// One of the user's own exercises, made in Desk (`base` nil) or changed.
    /// Found by `base`'s name, so a rename is a change like any other.
    case putExercise(exercise: SyncExercise, base: SyncExercise?)
    /// Deletes an own exercise; what was logged with it keeps its values.
    case deleteExercise(base: SyncExercise)
    /// A gym and the machines standing in it, found by `base`'s name.
    case putGym(gym: SyncGym, base: SyncGym?)
    /// Deletes a gym; the workouts trained there keep the rest of what they say.
    case deleteGym(base: SyncGym)
    /// A machine, found by `base`'s name; which gyms it stands in, the gyms say.
    case putMachine(machine: SyncMachine, base: SyncMachine?)
    /// Deletes a machine; the exercises done at it lose only the machine.
    case deleteMachine(base: SyncMachine)
    /// Folds one own exercise (`base`) into another or into a catalog
    /// exercise, as the iPhone's Merge Exercises does: what was logged with
    /// it moves over, its fields as `fields` says, and it goes.
    case mergeExercise(base: SyncExercise, into: SyncMergeTarget, fields: [SyncFieldMove])

    private enum CodingKeys: String, CodingKey {
        case op, template, workout, exercise, gym, machine, base, id, ids, into, fields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .op) {
        case "putTemplate":
            self = .putTemplate(
                template: try container.decode(SyncTemplate.self, forKey: .template),
                base: try container.decodeIfPresent(SyncTemplate.self, forKey: .base)
            )
        case "deleteTemplate":
            self = .deleteTemplate(id: try container.decode(UUID.self, forKey: .id), base: try container.decode(SyncTemplate.self, forKey: .base))
        case "orderTemplates":
            self = .orderTemplates(ids: try container.decode([UUID].self, forKey: .ids))
        case "putWorkout":
            self = .putWorkout(
                workout: try container.decode(SyncWorkout.self, forKey: .workout),
                base: try container.decodeIfPresent(SyncWorkout.self, forKey: .base)
            )
        case "deleteWorkout":
            self = .deleteWorkout(id: try container.decode(UUID.self, forKey: .id), base: try container.decode(SyncWorkout.self, forKey: .base))
        case "putExercise":
            self = .putExercise(
                exercise: try container.decode(SyncExercise.self, forKey: .exercise),
                base: try container.decodeIfPresent(SyncExercise.self, forKey: .base)
            )
        case "deleteExercise":
            self = .deleteExercise(base: try container.decode(SyncExercise.self, forKey: .base))
        case "putGym":
            self = .putGym(gym: try container.decode(SyncGym.self, forKey: .gym), base: try container.decodeIfPresent(SyncGym.self, forKey: .base))
        case "deleteGym":
            self = .deleteGym(base: try container.decode(SyncGym.self, forKey: .base))
        case "putMachine":
            self = .putMachine(
                machine: try container.decode(SyncMachine.self, forKey: .machine),
                base: try container.decodeIfPresent(SyncMachine.self, forKey: .base)
            )
        case "deleteMachine":
            self = .deleteMachine(base: try container.decode(SyncMachine.self, forKey: .base))
        case "mergeExercise":
            self = .mergeExercise(
                base: try container.decode(SyncExercise.self, forKey: .base),
                into: try container.decode(SyncMergeTarget.self, forKey: .into),
                fields: try container.decode([SyncFieldMove].self, forKey: .fields)
            )
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .op, in: container, debugDescription: "Unknown operation \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .putTemplate(let template, let base):
            try container.encode("putTemplate", forKey: .op)
            try container.encode(template, forKey: .template)
            try container.encodeIfPresent(base, forKey: .base)
        case .deleteTemplate(let id, let base):
            try container.encode("deleteTemplate", forKey: .op)
            try container.encode(id, forKey: .id)
            try container.encode(base, forKey: .base)
        case .orderTemplates(let ids):
            try container.encode("orderTemplates", forKey: .op)
            try container.encode(ids, forKey: .ids)
        case .putWorkout(let workout, let base):
            try container.encode("putWorkout", forKey: .op)
            try container.encode(workout, forKey: .workout)
            try container.encodeIfPresent(base, forKey: .base)
        case .deleteWorkout(let id, let base):
            try container.encode("deleteWorkout", forKey: .op)
            try container.encode(id, forKey: .id)
            try container.encode(base, forKey: .base)
        case .putExercise(let exercise, let base):
            try container.encode("putExercise", forKey: .op)
            try container.encode(exercise, forKey: .exercise)
            try container.encodeIfPresent(base, forKey: .base)
        case .deleteExercise(let base):
            try container.encode("deleteExercise", forKey: .op)
            try container.encode(base, forKey: .base)
        case .putGym(let gym, let base):
            try container.encode("putGym", forKey: .op)
            try container.encode(gym, forKey: .gym)
            try container.encodeIfPresent(base, forKey: .base)
        case .deleteGym(let base):
            try container.encode("deleteGym", forKey: .op)
            try container.encode(base, forKey: .base)
        case .putMachine(let machine, let base):
            try container.encode("putMachine", forKey: .op)
            try container.encode(machine, forKey: .machine)
            try container.encodeIfPresent(base, forKey: .base)
        case .deleteMachine(let base):
            try container.encode("deleteMachine", forKey: .op)
            try container.encode(base, forKey: .base)
        case .mergeExercise(let base, let into, let fields):
            try container.encode("mergeExercise", forKey: .op)
            try container.encode(base, forKey: .base)
            try container.encode(into, forKey: .into)
            try container.encode(fields, forKey: .fields)
        }
    }
}

// MARK: - Records

/// A template as the sync format carries it. Its own type, not the backup's
/// `TemplateRecord`: the two formats change apart.
nonisolated struct SyncTemplate: Codable, Equatable {
    var id: UUID
    var name: String
    var notes: String
    var archived: Bool
    /// Set on a day variant only.
    var plannedFor: Date?
    var gym: String?
    var exercises: [SyncEntry]
}

/// A trained workout as the sync format carries it — its own type, not the
/// backup's `WorkoutRecord`, like a template.
nonisolated struct SyncWorkout: Codable, Equatable {
    var id: UUID
    var name: String
    var date: Date
    var notes: String
    /// In whole seconds; absent when it was not timed.
    var durationSeconds: Int?
    var gym: String?
    var exercises: [SyncEntry]
}

/// One of the user's own exercises as the sync format carries it: what it
/// is, without its photo, which stays the iPhone's. Catalog exercises are
/// the catalog's and not in it.
nonisolated struct SyncExercise: Codable, Equatable {
    var name: String
    var category: String
    var muscleGroupNames: [String]
    var secondaryMuscleGroupNames: [String]
    var tracksSets: Bool
    var sides: String
    var offersAssistance: Bool
    var fields: [SyncField]
    var restSeconds: Int?

    /// What a new entry logs and how: changed only while nothing is logged
    /// with it, since logged sets would have to follow.
    var shape: Shape {
        Shape(tracksSets: tracksSets, sides: sides, offersAssistance: offersAssistance, fields: fields)
    }

    struct Shape: Equatable {
        var tracksSets: Bool
        var sides: String
        var offersAssistance: Bool
        var fields: [SyncField]
    }
}

/// What an own exercise is merged into: another own exercise, found by its
/// name, or a catalog exercise, found by `catalogKey`. `exercise` is it as
/// Desk saw it, for telling whether it changed on the iPhone since.
nonisolated struct SyncMergeTarget: Codable, Equatable {
    var catalogKey: String?
    var exercise: SyncExercise
}

/// Where the values of one field of the merged exercise go: under the key
/// of a field of the target of the same type (`to`), or, `to` absent, onto
/// the target as a new field — as `FieldMapping` says it on the iPhone.
nonisolated struct SyncFieldMove: Codable, Equatable {
    var from: String
    var to: String?
}

/// A gym and the names of the machines standing in it. Two gyms are the
/// same when their machines are, in whatever order they are listed.
nonisolated struct SyncGym: Codable, Equatable {
    var name: String
    var machines: [String]

    static func == (lhs: SyncGym, rhs: SyncGym) -> Bool {
        lhs.name == rhs.name && lhs.machines.map(\.exerciseKey).sorted() == rhs.machines.map(\.exerciseKey).sorted()
    }
}

/// A machine, without its photo, which stays the iPhone's.
nonisolated struct SyncMachine: Codable, Equatable {
    var name: String
}

nonisolated struct SyncField: Codable, Equatable {
    var key: String
    var label: String
    var type: String
}

nonisolated struct SyncEntry: Codable, Equatable {
    /// The exercise's name, and its catalog key for a catalog exercise —
    /// together what `ExerciseIdentity` reads.
    var exercise: String
    var catalogKey: String?
    var notes: String
    var instructions: String
    var mode: String
    var assistance: String
    var effortScale: String
    /// Entries of one superset share the number; it means nothing beyond
    /// this template.
    var supersetGroup: Int?
    var machine: String?
    var startSide: String?
    var sets: [SyncSet]
}

nonisolated struct SyncSet: Codable, Equatable {
    var side: String
    var effort: Double?
    var supersetPosition: Int?
    var sideOrder: Int?
    var done: Bool
    var values: [SyncValue]
}

nonisolated struct SyncValue: Codable, Equatable {
    var key: String
    var label: String
    var type: String
    var text: String?
    var number: Double?
}

// MARK: - To and from the backup's records

/// The importer writes templates and the exporter reads them; the sync goes
/// through both rather than having a writer of its own.
extension SyncTemplate {
    init(_ record: TemplateRecord) {
        self.init(
            id: record.id, name: record.name, notes: record.notes, archived: record.archived,
            plannedFor: record.plannedFor, gym: record.gym, exercises: record.exercises.map(SyncEntry.init)
        )
    }

    var record: TemplateRecord {
        TemplateRecord(
            id: id, name: name, notes: notes, archived: archived, plannedFor: plannedFor, gym: gym,
            exercises: exercises.map(\.record)
        )
    }

    /// As it reads after a trip through the format: dates to the second, as
    /// the file carries them. A record from the store compares with one from
    /// Desk only so.
    var normalized: SyncTemplate {
        let encoded = try? SyncFormat.encoder.encode(self)
        return encoded.flatMap { try? SyncFormat.decoder.decode(SyncTemplate.self, from: $0) } ?? self
    }
}

extension SyncWorkout {
    init(_ record: WorkoutRecord) {
        self.init(
            id: record.id, name: record.name, date: record.date, notes: record.notes,
            durationSeconds: record.durationSeconds, gym: record.gym, exercises: record.exercises.map(SyncEntry.init)
        )
    }

    var record: WorkoutRecord {
        WorkoutRecord(
            id: id, name: name, date: date, notes: notes, durationSeconds: durationSeconds, gym: gym,
            exercises: exercises.map(\.record)
        )
    }

    /// As it reads after a trip through the format: the date to the second.
    var normalized: SyncWorkout {
        let encoded = try? SyncFormat.encoder.encode(self)
        return encoded.flatMap { try? SyncFormat.decoder.decode(SyncWorkout.self, from: $0) } ?? self
    }
}

extension SyncExercise {
    init(_ record: ExerciseRecord) {
        self.init(
            name: record.name, category: record.category, muscleGroupNames: record.muscleGroupNames,
            secondaryMuscleGroupNames: record.secondaryMuscleGroupNames, tracksSets: record.tracksSets,
            sides: record.sides, offersAssistance: record.offersAssistance,
            fields: record.fields.map { SyncField(key: $0.key, label: $0.label, type: $0.type) },
            restSeconds: record.restSeconds
        )
    }
}

extension SyncExercise {
    /// As the backup spells it, for `DefinitionMerge`: the user's own, or the
    /// catalog's under `catalogKey`.
    func record(catalogKey: String? = nil) -> ExerciseRecord {
        ExerciseRecord(
            name: name, category: category, muscleGroupNames: muscleGroupNames,
            secondaryMuscleGroupNames: secondaryMuscleGroupNames, tracksSets: tracksSets, sides: sides,
            offersAssistance: offersAssistance, fields: fields.map { FieldRecord(key: $0.key, label: $0.label, type: $0.type) },
            catalogKey: catalogKey, restSeconds: restSeconds
        )
    }
}

extension FieldMapping {
    /// The mapping a merge from Desk carries.
    init(_ moves: [SyncFieldMove]) {
        self.init(destinations: Dictionary(
            moves.map { ($0.from, $0.to.map { .field(targetKey: $0) } ?? .newField) },
            uniquingKeysWith: { first, _ in first }
        ))
    }
}

extension SyncGym {
    init(_ record: GymRecord) {
        self.init(name: record.name, machines: record.machines)
    }
}

extension SyncEntry {
    init(_ record: EntryRecord) {
        self.init(
            exercise: record.exercise, catalogKey: record.catalogKey, notes: record.notes, instructions: record.instructions,
            mode: record.mode, assistance: record.assistance, effortScale: record.effortScale,
            supersetGroup: record.supersetGroup, machine: record.machine, startSide: record.startSide,
            sets: record.sets.map(SyncSet.init)
        )
    }

    var record: EntryRecord {
        EntryRecord(
            exercise: exercise, catalogKey: catalogKey, notes: notes, instructions: instructions, mode: mode,
            assistance: assistance, effortScale: effortScale, supersetGroup: supersetGroup, machine: machine,
            startSide: startSide, sets: sets.map(\.record)
        )
    }
}

extension SyncSet {
    init(_ record: SetRecord) {
        self.init(
            side: record.side, effort: record.effort, supersetPosition: record.supersetPosition,
            sideOrder: record.sideOrder, done: record.done,
            values: record.values.map { SyncValue(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number) }
        )
    }

    var record: SetRecord {
        SetRecord(
            side: side, effort: effort, supersetPosition: supersetPosition, sideOrder: sideOrder, done: done,
            values: values.map { ValueRecord(key: $0.key, label: $0.label, type: $0.type, text: $0.text, number: $0.number) }
        )
    }
}
