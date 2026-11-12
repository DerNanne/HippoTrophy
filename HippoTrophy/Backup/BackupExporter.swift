import Foundation

/// Turns what the store holds into what the file carries. Pure: it is handed
/// the objects and returns records, so a test can check the spelling of a
/// file without a store.
enum BackupExporter {
    /// The whole file: the parts handed in, a part left nil left out.
    /// `sessions` are workouts trained, `templates` in the order they stand.
    @MainActor
    static func file(
        definitions: [ExerciseDefinition]?,
        sessions: [WorkoutSession]?,
        templates: [WorkoutSession]? = nil,
        gyms: [Gym]? = nil,
        machines: [Machine]? = nil,
        at date: Date = .now
    ) -> BackupFile {
        BackupFile(
            exportedAt: date,
            exercises: definitions?.map(record),
            workouts: sessions?.map(record),
            templates: templates?.map(templateRecord),
            gyms: gyms.map { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(record) },
            machines: machines.map { byName($0).map(record) }
        )
    }

    /// Machines in the order the file lists them.
    @MainActor
    private static func byName(_ machines: [Machine]) -> [Machine] {
        machines.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The file and the photos it names, the exercises' and the machines'.
    /// Each photo gets a name that means nothing beyond this package: the
    /// file carries no ids for exercises or machines. `includingPhotos` off
    /// gives the JSON alone, naming none.
    @MainActor
    static func package(
        definitions: [ExerciseDefinition]?,
        sessions: [WorkoutSession]?,
        templates: [WorkoutSession]? = nil,
        gyms: [Gym]? = nil,
        machines: [Machine]? = nil,
        includingPhotos: Bool = true,
        at date: Date = .now
    ) -> BackupPackage {
        var package = BackupPackage(file: file(
            definitions: definitions, sessions: sessions, templates: templates, gyms: gyms, machines: machines, at: date
        ))
        guard includingPhotos else { return package }
        // Named before the record takes the name: adding and naming in one
        // statement would change the package twice at once.
        func add(_ data: Data) -> String {
            let name = "\(BackupPackage.photoFolder)\(package.photos.count + 1).jpg"
            package.photos[name] = data
            return name
        }
        for (index, definition) in (definitions ?? []).enumerated() {
            guard let photo = definition.ownPhoto else { continue }
            let name = add(photo.data)
            package.file.exercises?[index].photo = name
            package.file.exercises?[index].photoFraming = FramingRecord(photo.framing)
        }
        for (index, machine) in byName(machines ?? []).enumerated() {
            guard let photo = machine.photo else { continue }
            let name = add(photo.data)
            package.file.machines?[index].photo = name
            package.file.machines?[index].photoFraming = FramingRecord(photo.framing)
        }
        return package
    }

    @MainActor
    static func record(_ gym: Gym) -> GymRecord {
        GymRecord(name: gym.name, machines: gym.sortedMachines.map(\.name))
    }

    @MainActor
    static func record(_ machine: Machine) -> MachineRecord {
        MachineRecord(name: machine.name)
    }

    @MainActor
    static func record(_ definition: ExerciseDefinition) -> ExerciseRecord {
        ExerciseRecord(
            name: definition.name,
            category: definition.categoryName,
            muscleGroupNames: definition.muscleGroupNames,
            secondaryMuscleGroupNames: definition.secondaryMuscleGroupNames,
            tracksSets: definition.tracksSets,
            sides: definition.sides.rawValue,
            offersAssistance: definition.offersAssistance,
            fields: definition.sortedFields.map {
                FieldRecord(key: $0.key, label: $0.label, type: $0.typeRawValue)
            },
            catalogKey: definition.catalogKey,
            restSeconds: definition.restSeconds
        )
    }

    @MainActor
    static func record(_ session: WorkoutSession) -> WorkoutRecord {
        WorkoutRecord(
            id: session.id,
            name: session.name,
            date: session.date,
            notes: session.notes,
            durationSeconds: session.durationSeconds,
            gym: session.gym?.name,
            exercises: entryRecords(of: session)
        )
    }

    @MainActor
    static func templateRecord(_ template: WorkoutSession) -> TemplateRecord {
        TemplateRecord(
            id: template.id,
            name: template.name,
            notes: template.notes,
            archived: template.isArchived,
            plannedFor: template.plannedFor,
            gym: template.gym?.name,
            exercises: entryRecords(of: template)
        )
    }

    @MainActor
    private static func entryRecords(of session: WorkoutSession) -> [EntryRecord] {
        let sorted = session.exercises.sorted { $0.orderIndex < $1.orderIndex }

        // A superset's id means nothing outside this workout, so it is
        // renumbered 1, 2, … in the order its first member appears.
        var groupNumbers: [UUID: Int] = [:]
        func groupNumber(for entry: ExerciseEntry) -> Int? {
            guard let supersetID = entry.supersetID else { return nil }
            if let known = groupNumbers[supersetID] { return known }
            let number = groupNumbers.count + 1
            groupNumbers[supersetID] = number
            return number
        }

        return sorted.map { record($0, supersetGroup: groupNumber(for: $0)) }
    }

    @MainActor
    static func record(_ entry: ExerciseEntry, supersetGroup: Int? = nil) -> EntryRecord {
        EntryRecord(
            exercise: entry.name,
            catalogKey: entry.catalogKey,
            notes: entry.notes,
            instructions: entry.instructions,
            mode: entry.unilateralMode.rawValue,
            assistance: entry.assistance.rawValue,
            effortScale: entry.effortScale.rawValue,
            supersetGroup: supersetGroup,
            machine: entry.machine?.name,
            startSide: entry.startSideRawValue,
            sets: entry.sortedSets.map(record)
        )
    }

    @MainActor
    static func record(_ set: SetEntry) -> SetRecord {
        SetRecord(
            side: set.sideRawValue,
            effort: set.effortValue,
            supersetPosition: set.supersetPosition,
            sideOrder: set.sideOrder,
            done: set.isDone,
            values: set.sortedValues.map {
                ValueRecord(key: $0.fieldKey, label: $0.label, type: $0.typeRawValue, text: $0.textValue, number: $0.numberValue)
            }
        )
    }
}
