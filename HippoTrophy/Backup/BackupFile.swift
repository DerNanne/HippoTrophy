import Foundation

/// A backup file. Every section is optional on both sides: an export writes
/// only what the user picked, and an import reads whatever is there.
///
/// The file carries no ids for exercises. An entry in a workout names its
/// exercise, and whether two exercises are the same is decided by what they
/// are — see `ExerciseRecord.shape` — not by a number that happened to be
/// generated on one device. Workouts keep an id, because a workout is history:
/// importing the same file twice must not log the same session twice.
/// Templates keep one for the same reason: the same template twice is clutter.
nonisolated struct BackupFile: Codable {
    /// What this app writes. It reads back to format 11, each older format
    /// with a frozen type of its own brought up step by step; files from
    /// before the sides assistant are refused with a pointer to support,
    /// which converts them by hand, and anything newer is refused rather
    /// than half-read.
    static let currentFormatVersion = 26

    /// The oldest format read.
    static let oldestReadFormatVersion = 11

    var formatVersion: Int
    var exportedAt: Date
    var exercises: [ExerciseRecord]?
    var workouts: [WorkoutRecord]?
    /// In the order they stand on the start screen, archived ones included.
    /// Since format 14.
    var templates: [TemplateRecord]?
    /// The user's gyms, each with the machines standing in it. Since format 20.
    var gyms: [GymRecord]?
    /// Every machine, those in no gym too. Since format 20.
    var machines: [MachineRecord]?

    init(
        exportedAt: Date,
        exercises: [ExerciseRecord]? = nil,
        workouts: [WorkoutRecord]? = nil,
        templates: [TemplateRecord]? = nil,
        gyms: [GymRecord]? = nil,
        machines: [MachineRecord]? = nil,
        formatVersion: Int = BackupFile.currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.exercises = exercises
        self.workouts = workouts
        self.templates = templates
        self.gyms = gyms
        self.machines = machines
    }

    var isEmpty: Bool {
        (exercises?.isEmpty ?? true) && (workouts?.isEmpty ?? true) && (templates?.isEmpty ?? true)
            && (gyms?.isEmpty ?? true) && (machines?.isEmpty ?? true)
    }

    /// The exercises of the user's own the file carries, one per name, as
    /// the planner reads them. Catalog exercises are in the file too, so an
    /// entry can find its exercise on an app without them, but every app
    /// brings its own: counting them would promise an import of a hundred
    /// exercises when a handful are the user's.
    var ownExerciseCount: Int {
        Set((exercises ?? []).filter { $0.catalogKey == nil }.map(\.name.exerciseKey).filter { !$0.isEmpty }).count
    }

    /// How many exercises and machines the file gives a photo.
    var photoCount: Int {
        photoNames.count
    }

    /// Where each photo the file names lies in its package, exercises' first.
    var photoNames: [String] {
        (exercises ?? []).compactMap(\.photo) + (machines ?? []).compactMap(\.photo)
    }

    /// Whether an import of this file could bring anything: catalog
    /// exercises alone cannot, the app has them.
    var bringsNothing: Bool {
        ownExerciseCount == 0 && (workouts?.isEmpty ?? true) && (templates?.isEmpty ?? true)
            && (gyms?.isEmpty ?? true) && (machines?.isEmpty ?? true)
    }
}

/// An exercise definition as the file spells it. Also the shape the importer
/// compares, so the file and the comparison cannot drift apart.
nonisolated struct ExerciseRecord: Codable, Hashable {
    var name: String
    /// The category's plain name, "" for none. Since format 22 only one the
    /// app ships with; a file that says another imports without a category.
    /// Isometrics since format 26: an app that does not know it refuses the
    /// file rather than dropping the category.
    var category: String
    /// The muscles it mainly trains.
    var muscleGroupNames: [String]
    /// The muscles it trains along the way. Since format 12, and read as
    /// strictly as the rest: the default is for building a record, never for
    /// a file without the key.
    var secondaryMuscleGroupNames: [String] = []
    var tracksSets: Bool
    /// An `ExerciseSides` raw value: how the exercise is trained, which
    /// decides the modes its entries offer. Since format 11.
    var sides: String
    /// Whether its entries can be logged assisted — see `Assistance`. Since
    /// format 13, and read as strictly as the rest, like the muscles above.
    var offersAssistance: Bool = false
    /// In display order.
    var fields: [FieldRecord]
    /// The catalog exercise this is (`CatalogExercise.key`); absent for the
    /// user's own. Since format 9.
    var catalogKey: String?
    /// How long to rest after a set of it, in seconds, 0 for no rest timer;
    /// absent when the exercise follows the setting. Not part of `shape` or
    /// of the review's differences: a rest is how the user trains it, not
    /// what the exercise is — see `BackupImporter` for which one is kept.
    /// Since format 16.
    var restSeconds: Int?
    /// Where its photo lies in the package, `photos/1.jpg` — see
    /// `BackupPackage`; absent without one. A pointer into this one file and
    /// no part of `shape`, like the rest. Since format 23.
    var photo: String?
    /// Which part of the photo a tile shows; absent when it shows the middle,
    /// unzoomed, and always without a photo. Since format 25.
    var photoFraming: FramingRecord?

    /// Which exercise this is — see `ExerciseIdentity`.
    var identity: ExerciseIdentity {
        ExerciseIdentity(name: name, catalogKey: catalogKey)
    }

    var muscleFiling: MuscleFiling {
        MuscleFiling(primary: muscleGroupNames, secondary: secondaryMuscleGroupNames)
    }

    /// What two exercises found to be the same one — by `identity`, or failing
    /// that by name — must also agree on to be taken as one: whether they log
    /// sets, and which fields they log, as a set, because the order of fields
    /// is a layout, not a meaning. Category and muscles are attributes of one
    /// exercise that two devices may disagree on, which is a question for the
    /// user rather than a reason to see two exercises. Neither name nor key is
    /// part of it: which exercise is meant is the match's to say.
    var shape: ExerciseShape {
        ExerciseShape(
            tracksSets: tracksSets,
            fields: Set(fields.map { FieldShape(labelKey: $0.label.exerciseKey, type: $0.type) })
        )
    }
}

/// The muscles an exercise is filed under, main and secondary, as raw
/// names. Two filings are the same when they name the same muscles at the
/// same level; the order they were picked in is not a meaning.
nonisolated struct MuscleFiling: Hashable {
    var primary: [String]
    var secondary: [String]

    static func == (lhs: MuscleFiling, rhs: MuscleFiling) -> Bool {
        Set(lhs.primary) == Set(rhs.primary) && Set(lhs.secondary) == Set(rhs.secondary)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(Set(primary))
        hasher.combine(Set(secondary))
    }
}

nonisolated struct ExerciseShape: Hashable {
    var tracksSets: Bool
    var fields: Set<FieldShape>
}

nonisolated struct FieldShape: Hashable {
    var labelKey: String
    var type: String
}

nonisolated struct FieldRecord: Codable, Hashable {
    /// Stable across renames, and what a logged value refers to.
    var key: String
    var label: String
    /// A `FieldType` raw value.
    var type: String
}

nonisolated struct WorkoutRecord: Codable {
    var id: UUID
    var name: String
    var date: Date
    var notes: String
    /// How long it took, in seconds; absent when it was not timed. Since
    /// format 17.
    var durationSeconds: Int?
    /// The gym's name; absent when it was not said. Since format 20.
    var gym: String?
    var exercises: [EntryRecord]
}

/// A template: a workout's exercises, sets and values, kept to start one
/// from. Its date means nothing, so it has none.
nonisolated struct TemplateRecord: Codable {
    var id: UUID
    var name: String
    var notes: String
    /// Put away: kept, but off the start screen.
    var archived: Bool
    /// The day a day variant was adjusted for; absent on a template kept
    /// for good. Since format 18.
    var plannedFor: Date?
    /// The gym a workout from it is trained at; absent when it was not
    /// said. Since format 20.
    var gym: String?
    var exercises: [EntryRecord]
}

nonisolated struct EntryRecord: Codable {
    /// The exercise's name at the time of export. For an own exercise, how the
    /// entry finds its definition on import.
    var exercise: String
    /// The catalog exercise it was logged from; absent for an own one. How a
    /// catalog exercise's entry finds its definition on import, whatever the
    /// catalog calls it on that device. Since format 10.
    var catalogKey: String?
    /// What happened this time, a report; empty in a template.
    var notes: String
    /// How the exercise is to be done this time, a plan. Since format 19,
    /// and read as strictly as the rest.
    var instructions: String = ""

    var identity: ExerciseIdentity {
        ExerciseIdentity(name: exercise, catalogKey: catalogKey)
    }
    /// A `UnilateralMode` raw value.
    var mode: String
    /// An `Assistance` raw value: whether the sets were helped up, which
    /// their weight field then logs as a value of type `assistance`. Since
    /// format 13, and read as strictly as the rest.
    var assistance: String = Assistance.unassisted.rawValue
    /// An `EffortScale` raw value: what every set's `effort` in this entry
    /// means.
    var effortScale: String
    /// Entries sharing a number, within this workout, are one superset — the
    /// number means nothing outside it and is assigned fresh on import.
    var supersetGroup: Int?
    /// The machine's name; absent when it was not said. Since format 20.
    var machine: String?
    /// An `ExerciseSide` raw value: the side a unilateral entry started with;
    /// absent where it was not said. Since format 21.
    var startSide: String?
    /// In set order; the set number is the position. An exercise that logs
    /// once per workout has exactly one. In a superset, `supersetPosition`
    /// says how the two exercises' sets interleave.
    var sets: [SetRecord]
}

/// A gym, and the machines standing in it by name. Since format 20.
nonisolated struct GymRecord: Codable {
    var name: String
    var machines: [String]
}

/// A machine. Which gyms it stands in, the gyms say. Since format 20.
nonisolated struct MachineRecord: Codable {
    var name: String
    /// Where its photo lies in the package, like an exercise's; absent
    /// without one. Since format 24.
    var photo: String?
    /// Like an exercise's. Since format 25.
    var photoFraming: FramingRecord?
}

/// The part of a photo a tile shows — see `PhotoFraming`: its centre as
/// fractions of the photo's width and height from the top left, and the zoom,
/// 1 to 4. Since format 25.
nonisolated struct FramingRecord: Codable, Hashable {
    var x: Double
    var y: Double
    var zoom: Double

    /// Nil for the middle, unzoomed, which the file leaves out.
    init?(_ framing: PhotoFraming) {
        guard !framing.isCentered else { return nil }
        self.init(x: framing.x, y: framing.y, zoom: framing.zoom)
    }

    init(x: Double, y: Double, zoom: Double) {
        self.x = x
        self.y = y
        self.zoom = zoom
    }

    var framing: PhotoFraming {
        PhotoFraming(x: x, y: y, zoom: zoom)
    }
}

nonisolated struct SetRecord: Codable {
    /// A `SetSide` raw value.
    var side: String
    /// The rating as the entry's `effortScale` reads it — for `levels` 0, 1
    /// or 2 for easy, normal, hard; for `rir` the reps in reserve, 0 to 10 in
    /// halves; `nil` for a set that was not rated.
    var effort: Double?
    /// Where the set falls in its superset's shared order, 1…n across both
    /// exercises; `nil` outside a superset.
    var supersetPosition: Int?
    /// Where the set falls across both sides of a left/right log whose order
    /// was chosen freely; absent while it follows from `startSide` and how
    /// many sets each side has. Since format 21.
    var sideOrder: Int?
    /// Whether the set was trained, or only planned and kept to show what was
    /// meant. Since format 15, and read as strictly as the rest.
    var done: Bool = true
    /// In display order. A weight is kilograms, and so is the help logged in
    /// its place; a duration whole seconds.
    var values: [ValueRecord]
}

nonisolated struct ValueRecord: Codable {
    var key: String
    var label: String
    /// A `FieldType` raw value.
    var type: String
    /// One of the two is set, by type; both `nil` is an empty field.
    var text: String?
    var number: Double?
}

/// Why a backup file was refused before anything was read out of it.
enum BackupReadError: LocalizedError, Equatable {
    case otherFormat(Int)
    /// A ZIP file without a `backup.json`.
    case notABackup

    private var isOlder: Bool {
        switch self {
        case .otherFormat(let version): return version < BackupFile.oldestReadFormatVersion
        case .notABackup: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .otherFormat(let version) where isOlder:
            return "⚠️ This backup was written by an older version of HippoTrophy (format \(version)) and can no longer be read here. Send it to \(Support.address) and it will be converted for you."
        case .otherFormat(let version):
            return "⚠️ This backup was written by a newer version of HippoTrophy (format \(version)) and cannot be read by this one."
        case .notABackup:
            return "⚠️ This ZIP file is not a HippoTrophy backup: it has no \(BackupPackage.fileName) inside."
        }
    }

    /// A mail to support for a file only support can convert; nil when an
    /// update of the app is the answer.
    var supportMail: URL? {
        switch self {
        case .otherFormat(let version):
            return isOlder ? Support.mail(subject: "Old backup (format \(version))") : nil
        case .notABackup:
            return nil
        }
    }
}

/// One encoder and one decoder for the whole backup path, so the file the app
/// writes and the file it reads can never drift apart on a setting.
enum BackupCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Only the version, read before anything else.
    private struct Version: Decodable {
        var formatVersion: Int
    }

    /// The one way into a backup file. Decoding alone is not enough: a file
    /// from another version may decode *fine*, with unknown keys dropped and
    /// missing ones defaulted, and would import as something else than what
    /// was written. So the version is read first, and each version is read
    /// by its own type and brought forward from there.
    static func readBackup(from data: Data) throws -> BackupFile {
        let version = try decoder.decode(Version.self, from: data).formatVersion
        switch version {
        case BackupFile.currentFormatVersion:
            return try decoder.decode(BackupFile.self, from: data)
        case 25:
            return try decoder.decode(BackupFileV25.self, from: data).upgraded()
        case 24:
            return try decoder.decode(BackupFileV24.self, from: data).upgraded().upgraded()
        case 23:
            return try decoder.decode(BackupFileV23.self, from: data).upgraded().upgraded().upgraded()
        case 22:
            return try decoder.decode(BackupFileV22.self, from: data).upgraded().upgraded().upgraded().upgraded()
        case 21:
            return try decoder.decode(BackupFileV21.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded()
        case 20:
            return try decoder.decode(BackupFileV20.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        case 19:
            return try decoder.decode(BackupFileV19.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        case 18:
            return try decoder.decode(BackupFileV18.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        case 17:
            return try decoder.decode(BackupFileV17.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        case 16:
            return try decoder.decode(BackupFileV16.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        case 15:
            return try decoder.decode(BackupFileV15.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        case 14:
            return try decoder.decode(BackupFileV14.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        case 13:
            return try decoder.decode(BackupFileV13.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        case 12:
            return try decoder.decode(BackupFileV12.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        case 11:
            return try decoder.decode(BackupFileV11.self, from: data).upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded().upgraded()
        default:
            throw BackupReadError.otherFormat(version)
        }
    }
}
