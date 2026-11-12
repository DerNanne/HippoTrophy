import Foundation

/// A named list of exercise names that can be merged into the catalogue.
///
/// Lists come from a file the user picks. What the app ships is the catalog
/// (`Catalog.json`), which is in the store from the start and needs no import;
/// everything imported here is the user's own.
struct ImportableExerciseList: Identifiable, Hashable, Codable {
    /// Fresh for every file read; nothing remembers a list across visits.
    var id: String
    var name: String
    var exercises: [ExerciseListEntry]
}

/// One exercise in a list: a name and the muscles it trains. What it becomes
/// on import is a plain sets-and-reps definition; fields and category are set
/// in the editor afterwards.
struct ExerciseListEntry: Codable, Hashable {
    var name: String
    var muscleGroupNames: [String]
}

/// The shape the app's own lists used to ship in, `{ "lists": [...] }` — still
/// read, since such a file may be lying around.
struct ExerciseListBundle: Codable {
    var lists: [ImportableExerciseList]
}

enum ExerciseListLoader {
    /// Trims, drops blanks and collapses case-insensitive duplicates inside a
    /// single list, keeping the first spelling and the original order. Muscle
    /// groups the app does not know are dropped here rather than at import, so
    /// nothing downstream has to know a list can carry nonsense.
    static func sanitised(_ exercises: [ExerciseListEntry]) -> [ExerciseListEntry] {
        var seen = Set<String>()
        var result: [ExerciseListEntry] = []
        for exercise in exercises {
            let trimmed = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.exerciseKey).inserted else { continue }
            result.append(
                ExerciseListEntry(
                    name: trimmed,
                    muscleGroupNames: MuscleGroup.read(exercise.muscleGroupNames).muscles
                )
            )
        }
        return result
    }
}

// MARK: - Reading a list the user picked

enum ExerciseListImportError: LocalizedError {
    case unreadableFormat
    case noExercises

    var errorDescription: String? {
        switch self {
        case .unreadableFormat:
            return "This file is not an exercise list. Expected JSON in the same shape the app ships."
        case .noExercises:
            return "This file does not contain any exercises."
        }
    }
}

extension ExerciseListLoader {
    /// Reads a file the user picked into one or more lists.
    ///
    /// Accepted, in order: the old bundled `{ "lists": [...] }` shape, a single list
    /// object, and a bare array of exercises. `fallbackName` (the file name)
    /// titles the shapes that carry none.
    static func lists(fromFileAt data: Data, fallbackName: String) throws -> [ImportableExerciseList] {
        let decoder = JSONDecoder()
        var decoded: [ImportableExerciseList]

        if let bundle = try? decoder.decode(ExerciseListBundle.self, from: data) {
            decoded = bundle.lists
        } else if let single = try? decoder.decode(ImportableExerciseList.self, from: data) {
            decoded = [single]
        } else if let exercises = try? decoder.decode([ExerciseListEntry].self, from: data) {
            decoded = [ImportableExerciseList(id: UUID().uuidString, name: fallbackName, exercises: exercises)]
        } else {
            throw ExerciseListImportError.unreadableFormat
        }

        // A file's ids are not trusted to be unique, so every list gets its own.
        decoded = decoded.map { list in
            let name = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return ImportableExerciseList(
                id: UUID().uuidString,
                name: name.isEmpty ? fallbackName : name,
                exercises: sanitised(list.exercises)
            )
        }
        .filter { !$0.exercises.isEmpty }

        guard !decoded.isEmpty else { throw ExerciseListImportError.noExercises }
        return decoded
    }
}
