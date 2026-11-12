import Foundation

/// How the fields of one exercise fold into another when the two are merged.
///
/// Every source field ends up somewhere: mapped onto a target field of the
/// same type, or carried over as a new field on the target. Nothing is
/// dropped — a logged value with nowhere to go would be data lost by a
/// dialog, and that is the one thing a merge must never do. What the user
/// decides is *which* target field a source field means, because behind
/// every field is a title they wrote themselves.
struct FieldMapping: Equatable {
    enum Destination: Hashable {
        /// The values logged under the source field belong to this target key.
        case field(targetKey: String)
        /// The source field becomes a field of the target, key kept.
        case newField
    }

    /// By source field key.
    var destinations: [String: Destination]

    init(destinations: [String: Destination] = [:]) {
        self.destinations = destinations
    }

    /// A mapping that pairs every source field with a target field of the
    /// same title and type, and carries the rest over — the answer a user
    /// would give in most cases, offered as the starting point.
    static func suggested(from source: ExerciseRecord, into target: ExerciseRecord) -> FieldMapping {
        var destinations: [String: Destination] = [:]
        var taken = Set<String>()
        for field in source.fields {
            let match = target.fields.first {
                !taken.contains($0.key) && $0.label.exerciseKey == field.label.exerciseKey && $0.type == field.type
            }
            if let match {
                taken.insert(match.key)
                destinations[field.key] = .field(targetKey: match.key)
            } else {
                destinations[field.key] = .newField
            }
        }
        return FieldMapping(destinations: destinations)
    }
}

enum DefinitionMerge {
    struct Result: Equatable {
        /// The target with the carried-over fields appended.
        var merged: ExerciseRecord
        /// Source field key → key on the merged exercise, for rewriting values.
        var keyRewrite: [String: String]
    }

    enum Problem: Equatable, LocalizedError {
        case unmappedField(String)
        case typeMismatch(source: String, target: String)
        case targetTakenTwice(String)
        case tooManyFields(Int)

        var errorDescription: String? {
            switch self {
            case .unmappedField(let label):
                return "\"\(label)\" has nowhere to go yet."
            case .typeMismatch(let source, let target):
                return "\"\(source)\" and \"\(target)\" are different kinds of value."
            case .targetTakenTwice(let label):
                return "Two fields point at \"\(label)\"."
            case .tooManyFields(let count):
                return "The merged exercise would have \(CountFormat.text(count, "field", "fields")); \(ExerciseDefinition.maxFields) is the most an exercise can hold."
            }
        }
    }

    /// The fields of `source` that no field of `target` could take, one
    /// target field per source field and only of the same kind. Into a
    /// catalog exercise, which keeps its fields, any of these makes the merge
    /// impossible however the rest is mapped.
    static func fieldsWithoutCounterpart(source: ExerciseRecord, target: ExerciseRecord) -> [String] {
        var free = Dictionary(grouping: target.fields, by: \.type).mapValues(\.count)
        var result: [String] = []
        for field in source.fields {
            if let count = free[field.type], count > 0 {
                free[field.type] = count - 1
            } else {
                result.append(field.label)
            }
        }
        return result
    }

    /// Checks a mapping and, if it holds up, says what the merged exercise
    /// looks like and how logged keys move.
    static func merge(source: ExerciseRecord, into target: ExerciseRecord, mapping: FieldMapping) -> Swift.Result<Result, Problem> {
        var merged = target
        var rewrite: [String: String] = [:]
        var usedTargets = Set<String>()
        var takenKeys = Set(target.fields.map(\.key))

        for field in source.fields {
            guard let destination = mapping.destinations[field.key] else {
                return .failure(.unmappedField(field.label))
            }
            switch destination {
            case .field(let targetKey):
                guard let targetField = target.fields.first(where: { $0.key == targetKey }) else {
                    return .failure(.unmappedField(field.label))
                }
                guard targetField.type == field.type else {
                    return .failure(.typeMismatch(source: field.label, target: targetField.label))
                }
                guard usedTargets.insert(targetKey).inserted else {
                    return .failure(.targetTakenTwice(targetField.label))
                }
                rewrite[field.key] = targetKey
            case .newField:
                // A key the target already uses for something else cannot be
                // kept, so the field moves to the next free one.
                var key = field.key
                var number = takenKeys.count + 1
                while takenKeys.contains(key) {
                    key = "f\(number)"
                    number += 1
                }
                takenKeys.insert(key)
                merged.fields.append(FieldRecord(key: key, label: field.label, type: field.type))
                rewrite[field.key] = key
            }
        }

        guard merged.fields.count <= ExerciseDefinition.maxFields else {
            return .failure(.tooManyFields(merged.fields.count))
        }
        return .success(Result(merged: merged, keyRewrite: rewrite))
    }
}
