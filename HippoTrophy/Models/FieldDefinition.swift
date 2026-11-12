import Foundation
import SwiftData

/// One configured field of a definition. `key` is stable and independent of `label`,
/// so renaming a field keeps values that were already logged under it.
@Model
final class FieldDefinition {
    var id: UUID
    var key: String
    var label: String
    var typeRawValue: String
    var orderIndex: Int
    var definition: ExerciseDefinition?

    init(
        key: String,
        label: String,
        typeRawValue: String = FieldType.number.rawValue,
        orderIndex: Int,
        definition: ExerciseDefinition? = nil
    ) {
        self.id = UUID()
        self.key = key
        self.label = label
        self.typeRawValue = typeRawValue
        self.orderIndex = orderIndex
        self.definition = definition
    }

    var type: FieldType {
        get { FieldType(rawValue: typeRawValue) ?? .number }
        set { typeRawValue = newValue.rawValue }
    }
}
