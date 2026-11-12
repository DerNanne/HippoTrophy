import Foundation
import SwiftData

/// Which parts of a backup file to read back, and how to treat the workouts.
struct ImportSelection {
    var exercises = true
    var workouts = true
    var templates = true
    /// Merge is the default everywhere; replacing is a deliberate "this device
    /// starts over from the file" and only ever applies to workouts —
    /// templates are not history, and are only ever added to.
    var replaceWorkouts = false

    var isEmpty: Bool { !exercises && !workouts && !templates }
}

/// What an import did, for the one alert that reports it.
struct ImportSummary {
    var exercisesAdded = 0
    var exercisesUpdated = 0
    var exercisesMerged = 0
    var exercisesRenamed = 0
    var exercisesSkipped = 0
    /// Conflicts with a catalog exercise left to the catalog: not left out,
    /// their workouts are logged under it.
    var exercisesMatchedToCatalog = 0
    var exercisesUnchanged = 0
    var workoutsAdded = 0
    var workoutsSkipped = 0
    var templatesAdded = 0
    var templatesSkipped = 0
    var gymsAdded = 0
    var machinesAdded = 0
    var unknownMuscles: [String] = []
    var photosAdded = 0
    /// Photos the file names that were not there or were no pictures.
    var photosMissing = 0

    var message: String {
        var lines: [String] = []
        var added: [String] = []
        if exercisesAdded > 0 { added.append(CountFormat.text(exercisesAdded, "exercise", "exercises")) }
        if workoutsAdded > 0 { added.append(CountFormat.text(workoutsAdded, "workout", "workouts")) }
        if templatesAdded > 0 { added.append(CountFormat.text(templatesAdded, "template", "templates")) }
        if gymsAdded > 0 { added.append(CountFormat.text(gymsAdded, "gym", "gyms")) }
        if machinesAdded > 0 { added.append(CountFormat.text(machinesAdded, "machine", "machines")) }
        if photosAdded > 0 { added.append(CountFormat.text(photosAdded, "photo", "photos")) }
        lines.append(added.isEmpty ? "Nothing was added." : "Added \(ListFormat.text(added)).")

        var changed: [String] = []
        if exercisesUpdated > 0 { changed.append("\(CountFormat.text(exercisesUpdated, "exercise", "exercises")) took the file's details") }
        if exercisesMerged > 0 { changed.append("\(CountFormat.text(exercisesMerged, "exercise was", "exercises were")) merged into yours") }
        if exercisesRenamed > 0 { changed.append("\(CountFormat.text(exercisesRenamed, "exercise was", "exercises were")) imported under another name") }
        if !changed.isEmpty { lines.append(changed.joined(separator: ", ").capitalizedFirst + ".") }

        if exercisesMatchedToCatalog > 0 {
            lines.append("\(CountFormat.text(exercisesMatchedToCatalog, "exercise is", "exercises are")) the catalog's here; the workouts use those.")
        }
        if exercisesSkipped > 0 {
            lines.append("Left out \(CountFormat.text(exercisesSkipped, "exercise", "exercises")) of the file; the workouts use yours.")
        }

        var skipped: [String] = []
        if exercisesUnchanged > 0 { skipped.append("\(CountFormat.text(exercisesUnchanged, "exercise", "exercises")) already here") }
        if workoutsSkipped > 0 { skipped.append("\(CountFormat.text(workoutsSkipped, "workout", "workouts")) already here") }
        if templatesSkipped > 0 { skipped.append("\(CountFormat.text(templatesSkipped, "template", "templates")) already here") }
        if !skipped.isEmpty { lines.append("Skipped \(skipped.joined(separator: ", ")).") }

        if !unknownMuscles.isEmpty {
            let quoted = unknownMuscles.prefix(4).map { "\"\($0)\"" }.joined(separator: ", ")
            let rest = unknownMuscles.count - 4
            lines.append("⚠️ Dropped \(CountFormat.text(unknownMuscles.count, "muscle group", "muscle groups")) the app does not know: \(rest > 0 ? "\(quoted) and \(rest) more" : quoted).")
        }
        if photosMissing > 0 {
            lines.append("⚠️ \(CountFormat.text(photosMissing, "photo", "photos")) named in the file could not be read, so \(photosMissing == 1 ? "its exercise or machine has" : "their exercises or machines have") none.")
        }
        return lines.joined(separator: "\n\n")
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// Writes a plan and the decisions made on it into the store. Nothing is
/// half-imported: the caller saves once at the end, and rolls back on failure.
@MainActor
struct BackupImporter {
    let context: ModelContext

    /// Where an entry from the file ends up.
    private struct Target {
        var definition: ExerciseDefinition
        /// The file's field keys → the definition's, where that is known.
        var keyRewrite: [String: String]
        /// Whether the entry's values are lined up with the definition's
        /// fields. False when the file's exercise was not brought in: its
        /// values then stay exactly as they were logged.
        var aligns: Bool
    }

    func apply(_ plan: ImportPlan, decisions: ImportDecisions, selection: ImportSelection, photos: [String: Data] = [:]) -> ImportSummary {
        var summary = ImportSummary()
        var definitions = (try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        /// A file exercise's identity → the definition its entries hang on.
        var resolved: [ExerciseIdentity: Target] = [:]
        var unknownMuscleKeys = Set<String>()

        func nextIndex() -> Int { (definitions.map(\.orderIndex).max() ?? -1) + 1 }

        func muscles(_ raw: [String]) -> [String] {
            let read = MuscleGroup.read(raw)
            for name in read.unknown where unknownMuscleKeys.insert(name.exerciseKey).inserted {
                summary.unknownMuscles.append(name)
            }
            return read.muscles
        }

        func insert(_ record: ExerciseRecord, named name: String) -> ExerciseDefinition {
            let definition = ExerciseDefinition(
                name: name,
                orderIndex: nextIndex(),
                categoryName: ExerciseCategory.resolve(record.category)?.name ?? "",
                muscleGroupNames: muscles(record.muscleGroupNames),
                secondaryMuscleGroupNames: muscles(record.secondaryMuscleGroupNames),
                tracksSets: record.tracksSets,
                sides: ExerciseSides(rawValue: record.sides) ?? .either,
                offersAssistance: record.offersAssistance,
                // A catalog exercise this store lacks — only if nothing here
                // holds the key already; `CatalogSync` sorts out the rest.
                catalogKey: record.catalogKey.flatMap { key in
                    definitions.contains { $0.catalogKey == key } ? nil : key
                },
                restSeconds: record.restSeconds
            )
            context.insert(definition)
            for (index, field) in record.fields.enumerated() {
                let stored = FieldDefinition(
                    key: field.key, label: field.label, typeRawValue: field.type, orderIndex: index, definition: definition
                )
                definition.fields.append(stored)
                context.insert(stored)
            }
            definitions.append(definition)
            return definition
        }

        func existing(_ id: UUID) -> ExerciseDefinition? {
            definitions.first { $0.id == id }
        }

        /// A rest is how the user trains an exercise, so it is never a
        /// question: one set here stays, and one the device lacks comes
        /// from the file.
        func adoptRest(of record: ExerciseRecord, into definition: ExerciseDefinition) {
            if definition.restSeconds == nil {
                definition.restSeconds = record.restSeconds
            }
        }

        /// A photo is the same kind of thing as a rest: never a question. One
        /// here stays, and one the device lacks comes from the file. A catalog
        /// exercise has the catalog's picture.
        func adoptPhoto(of record: ExerciseRecord, into definition: ExerciseDefinition) {
            guard let name = record.photo, definition.photo == nil, !definition.isCatalog else { return }
            guard let data = photos[name].flatMap(PhotoFile.arriving) else {
                summary.photosMissing += 1
                return
            }
            definition.setPhoto(data, framing: record.photoFraming?.framing ?? .centered, in: context)
            summary.photosAdded += 1
        }

        /// Two devices key the same field differently, so a value coming in
        /// finds its field by title and type, not by key.
        func byTitle(_ record: ExerciseRecord, _ definition: ExerciseDefinition) -> Target {
            var rewrite: [String: String] = [:]
            for field in record.fields {
                if let match = definition.fields.first(where: {
                    $0.label.exerciseKey == field.label.exerciseKey && $0.typeRawValue == field.type
                }) {
                    rewrite[field.key] = match.key
                }
            }
            return Target(definition: definition, keyRewrite: rewrite, aligns: true)
        }

        if selection.exercises {
            for item in plan.exercises {
                let key = item.record.identity
                switch item.outcome {
                case .add:
                    let added = insert(item.record, named: item.record.name)
                    adoptPhoto(of: item.record, into: added)
                    resolved[key] = Target(definition: added, keyRewrite: [:], aligns: true)
                    summary.exercisesAdded += 1

                case .same(let local):
                    guard let definition = existing(local.id) else { continue }
                    adoptRest(of: item.record, into: definition)
                    adoptPhoto(of: item.record, into: definition)
                    resolved[key] = byTitle(item.record, definition)
                    // Every app has the catalog: one found unchanged is not
                    // news, and would bury the few of the user's own.
                    if item.record.catalogKey == nil { summary.exercisesUnchanged += 1 }

                case .review(let local, let differences):
                    guard let definition = existing(local.id) else { continue }
                    adoptRest(of: item.record, into: definition)
                    adoptPhoto(of: item.record, into: definition)
                    var changed = false
                    for difference in differences where decisions.side(for: item.record.name, difference) == .file {
                        changed = true
                        switch difference {
                        case .category(_, let file):
                            definition.categoryName = ExerciseCategory.resolve(file)?.name ?? ""
                        case .muscles(_, let file):
                            definition.muscleGroupNames = muscles(file.primary)
                            definition.secondaryMuscleGroupNames = muscles(file.secondary)
                        case .sides(_, let file):
                            definition.sides = file
                        case .assistance(_, let file):
                            definition.offersAssistance = file
                        case .fieldOrder(_, let file):
                            // The file's order, matched by title; a field the
                            // file does not name keeps its place at the end.
                            let order = Dictionary(uniqueKeysWithValues: file.enumerated().map { ($1.exerciseKey, $0) })
                            for field in definition.fields {
                                field.orderIndex = order[field.label.exerciseKey] ?? file.count
                            }
                        }
                    }
                    resolved[key] = byTitle(item.record, definition)
                    if changed { summary.exercisesUpdated += 1 } else { summary.exercisesUnchanged += 1 }

                case .conflict(let local):
                    guard let definition = existing(local.id) else { continue }
                    switch decisions.resolution(for: item.record.name) ?? .skip {
                    case .skip:
                        // The file's values keep their own titles and keys:
                        // they belong to an exercise that was not brought in.
                        resolved[key] = Target(definition: definition, keyRewrite: [:], aligns: false)
                        if definition.isCatalog {
                            // The catalog's own exercise, only described
                            // differently: the user's rest for it still holds.
                            adoptRest(of: item.record, into: definition)
                            summary.exercisesMatchedToCatalog += 1
                        } else {
                            summary.exercisesSkipped += 1
                        }
                    case .rename(let name):
                        let renamed = insert(item.record, named: name)
                        adoptPhoto(of: item.record, into: renamed)
                        resolved[key] = Target(definition: renamed, keyRewrite: [:], aligns: true)
                        summary.exercisesRenamed += 1
                    case .merge(let mapping):
                        guard case .success(let result) = DefinitionMerge.merge(
                            source: item.record, into: BackupExporter.record(definition), mapping: mapping
                        ) else {
                            resolved[key] = Target(definition: definition, keyRewrite: [:], aligns: false)
                            summary.exercisesSkipped += 1
                            continue
                        }
                        ExerciseMerging.addCarriedFields(result, to: definition, in: context)
                        adoptRest(of: item.record, into: definition)
                        adoptPhoto(of: item.record, into: definition)
                        resolved[key] = Target(definition: definition, keyRewrite: result.keyRewrite, aligns: true)
                        summary.exercisesMerged += 1
                    }
                }
            }
        }

        if selection.workouts && selection.replaceWorkouts {
            for session in (try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.trained))) ?? [] {
                context.delete(session)
            }
        }

        /// The definition an entry hangs on when the file's exercise section
        /// did not settle it: one already here under that name, or else one
        /// made from the entry's first set, so no entry is left without one.
        func target(for entry: EntryRecord) -> Target {
            let key = entry.identity
            if let known = resolved[key] { return known }
            if let index = ExerciseNaming.match(
                identity: key, name: entry.exercise,
                among: definitions.map { (identity: $0.identity, name: $0.name) }
            ) {
                // Nothing said how the file's fields relate to this one's, so
                // the values keep their own titles.
                let found = Target(definition: definitions[index], keyRewrite: [:], aligns: false)
                resolved[key] = found
                return found
            }
            // Whether it tracked sets is not in the file — it belongs to the
            // definition the file did not bring. Several sets say it did; a
            // single set of weight and reps almost certainly did too.
            let first = entry.sets.first
            let firstTypes = (first?.values ?? []).map { FieldType(rawValue: $0.type)?.fieldType.rawValue ?? $0.type }
            let weightTraining = firstTypes.contains(FieldType.weight.rawValue) && firstTypes.contains(FieldType.reps.rawValue)
            let assisted = Assistance(rawValue: entry.assistance)?.isAssisted ?? false
            let tracksSets = entry.sets.count > 1 || weightTraining
            let record = ExerciseRecord(
                name: entry.exercise,
                category: tracksSets ? ExerciseCategory.strength.name : "",
                muscleGroupNames: [],
                secondaryMuscleGroupNames: [],
                tracksSets: tracksSets,
                // Sides are not in the file either; that the entry logged some
                // is the only evidence there is that the exercise offers them.
                sides: (entry.sets.contains { $0.side != SetSide.both.rawValue } || weightTraining
                    ? ExerciseSides.either : .both).rawValue,
                // Help logged in place of the weight says there is a weight
                // field, and that the exercise offers help.
                offersAssistance: assisted,
                fields: (first?.values ?? []).map { value in
                    guard value.type == FieldType.assistance.rawValue else {
                        return FieldRecord(key: value.key, label: value.label, type: value.type)
                    }
                    return FieldRecord(key: value.key, label: FieldType.weight.displayName, type: FieldType.weight.rawValue)
                }
            )
            let made = Target(definition: insert(record, named: entry.exercise), keyRewrite: [:], aligns: true)
            summary.exercisesAdded += 1
            resolved[key] = made
            return made
        }

        /// Writes a workout's or a template's entries, in the file's order.
        // Gyms and machines are found by name, and made where there is none:
        // the file's lists first, then whatever a workout names.
        var gyms = (try? context.fetch(FetchDescriptor<Gym>())) ?? []
        var machines = (try? context.fetch(FetchDescriptor<Machine>())) ?? []
        func gym(named name: String) -> Gym? {
            guard !name.exerciseKey.isEmpty else { return nil }
            if let found = gyms.first(where: { $0.name.exerciseKey == name.exerciseKey }) { return found }
            let gym = GymChoices.addGym(named: name.trimmingCharacters(in: .whitespacesAndNewlines), in: context)
            gyms.append(gym)
            summary.gymsAdded += 1
            return gym
        }
        func machine(named name: String) -> Machine? {
            guard !name.exerciseKey.isEmpty else { return nil }
            if let found = machines.first(where: { $0.name.exerciseKey == name.exerciseKey }) { return found }
            let machine = GymChoices.addMachine(named: name.trimmingCharacters(in: .whitespacesAndNewlines), at: nil, in: context)
            machines.append(machine)
            summary.machinesAdded += 1
            return machine
        }
        for record in plan.machines {
            guard let machine = machine(named: record.name) else { continue }
            // Like an exercise's: one here stays, one the device lacks comes
            // from the file.
            guard let name = record.photo, machine.photo == nil else { continue }
            guard let data = photos[name].flatMap(PhotoFile.arriving) else {
                summary.photosMissing += 1
                continue
            }
            machine.setPhoto(data, framing: record.photoFraming?.framing ?? .centered, in: context)
            summary.photosAdded += 1
        }
        for record in plan.gyms {
            guard let gym = gym(named: record.name) else { continue }
            for name in record.machines {
                if let machine = machine(named: name), !gym.machines.contains(where: { $0.id == machine.id }) {
                    gym.machines.append(machine)
                }
            }
        }

        func fill(_ session: WorkoutSession, with records: [EntryRecord]) {
            // The file's group numbers mean nothing outside this workout;
            // each one gets a fresh id here, shared by every entry that
            // names it.
            var supersetIDs: [Int: UUID] = [:]

            for (index, record) in records.enumerated() {
                let target = target(for: record)
                let entry = ExerciseEntry(
                    name: target.definition.name,
                    notes: record.notes,
                    instructions: record.instructions,
                    orderIndex: index,
                    definitionID: target.definition.id,
                    supersetID: record.supersetGroup.map { group in
                        if let known = supersetIDs[group] { return known }
                        let id = UUID()
                        supersetIDs[group] = id
                        return id
                    },
                    effortScale: EffortScale(rawValue: record.effortScale) ?? .off,
                    catalogKey: target.definition.catalogKey,
                    session: session
                )
                entry.machine = record.machine.flatMap(machine(named:))
                entry.unilateralMode = UnilateralMode(rawValue: record.mode) ?? .bilateral
                entry.startSideRawValue = record.startSide
                entry.assistance = Assistance(rawValue: record.assistance) ?? .unassisted
                // A rating is kept only as the entry's scale reads it; one the
                // scale cannot hold has no meaning to carry over.
                let scale = entry.effortScale
                context.insert(entry)

                // Sets are numbered per side, the way the editor numbers them:
                // a left/right log counts left 1, 2, 3 and right 1, 2, 3.
                var numbers: [String: Int] = [:]
                for set in record.sets {
                    numbers[set.side, default: 0] += 1
                    let stored = SetEntry(
                        setNumber: numbers[set.side] ?? 1, sideRawValue: set.side,
                        effortValue: scale.effort(storedAs: set.effort)?.storedValue,
                        supersetPosition: record.supersetGroup == nil ? nil : set.supersetPosition,
                        sideOrder: set.sideOrder,
                        isDone: set.done, exercise: entry
                    )
                    entry.sets.append(stored)
                    context.insert(stored)
                    for (order, value) in set.values.enumerated() {
                        let storedValue = FieldValue(
                            fieldKey: value.key, label: value.label, typeRawValue: value.type, orderIndex: order,
                            textValue: value.text, numberValue: value.number, set: stored
                        )
                        stored.values.append(storedValue)
                        context.insert(storedValue)
                    }
                }
                if target.aligns {
                    ExerciseMerging.attach(entry, to: target.definition, keyRewrite: target.keyRewrite, in: context)
                }
                session.exercises.append(entry)
            }
        }

        if selection.workouts {
            for item in plan.workouts {
                guard !item.isKnown || selection.replaceWorkouts else {
                    summary.workoutsSkipped += 1
                    continue
                }
                let session = WorkoutSession(name: item.record.name, date: item.record.date, notes: item.record.notes)
                session.id = item.record.id
                session.durationSeconds = item.record.durationSeconds
                context.insert(session)
                session.gym = item.record.gym.flatMap(gym(named:))
                fill(session, with: item.record.exercises)
                summary.workoutsAdded += 1
            }
        }

        if selection.templates {
            // The file's templates stand first, in the file's order, like a
            // template made here: what was just brought in is what is wanted
            // next. The ones already here move back behind them.
            let existing = (try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: WorkoutSession.templates))) ?? []
            let arriving = plan.templates.filter { !$0.isKnown }.count
            if arriving > 0 {
                for template in existing {
                    template.templateOrder += arriving
                }
            }
            var order = 0
            for item in plan.templates {
                guard !item.isKnown else {
                    summary.templatesSkipped += 1
                    continue
                }
                let template = WorkoutSession(name: item.record.name, notes: item.record.notes)
                template.id = item.record.id
                template.isTemplate = true
                template.isArchived = item.record.archived
                template.plannedFor = item.record.plannedFor
                template.templateOrder = order
                order += 1
                context.insert(template)
                template.gym = item.record.gym.flatMap(gym(named:))
                fill(template, with: item.record.exercises)
                summary.templatesAdded += 1
            }
        }
        return summary
    }
}
