import Testing
@testable import HippoTrophy

/// Merging two exercises must never lose a logged value: every source field
/// lands on a target field of the same type or becomes a field of its own.
struct DefinitionMergeTests {
    private let rowing = ExerciseRecord(name: "Rowing", category: "Cardio", muscleGroupNames: [], tracksSets: false, sides: "both", fields: [
        FieldRecord(key: "f1", label: "Time", type: "time"),
        FieldRecord(key: "f2", label: "Heart Rate", type: "number")
    ])
    private let rudern = ExerciseRecord(name: "Rudermaschine", category: "Cardio", muscleGroupNames: [], tracksSets: false, sides: "both", fields: [
        FieldRecord(key: "f1", label: "Dauer", type: "time"),
        FieldRecord(key: "f2", label: "Heart Rate", type: "number"),
        FieldRecord(key: "f3", label: "Distance", type: "number")
    ])

    /// Rudermaschine has two number fields and Rowing one: one of them has
    /// nowhere to go on Rowing, whatever the mapping.
    @Test func aFieldWithoutACounterpartOfItsKindIsNamed() {
        #expect(DefinitionMerge.fieldsWithoutCounterpart(source: rudern, target: rowing) == ["Distance"])
        #expect(DefinitionMerge.fieldsWithoutCounterpart(source: rowing, target: rudern).isEmpty)
    }

    @Test func theSuggestionPairsMatchingTitlesAndCarriesTheRest() {
        let mapping = FieldMapping.suggested(from: rudern, into: rowing)
        #expect(mapping.destinations["f2"] == .field(targetKey: "f2"))
        #expect(mapping.destinations["f1"] == .newField)
        #expect(mapping.destinations["f3"] == .newField)
    }

    @Test func aMappedFieldRewritesItsKeyAndANewOneGetsAFreeKey() throws {
        var mapping = FieldMapping.suggested(from: rudern, into: rowing)
        mapping.destinations["f1"] = .field(targetKey: "f1")
        let result = try DefinitionMerge.merge(source: rudern, into: rowing, mapping: mapping).get()

        #expect(result.keyRewrite["f1"] == "f1")
        #expect(result.keyRewrite["f2"] == "f2")
        // "f3" is free on the target, so the carried field keeps its key.
        #expect(result.keyRewrite["f3"] == "f3")
        #expect(result.merged.fields.map(\.label) == ["Time", "Heart Rate", "Distance"])
        #expect(result.merged.name == "Rowing")
    }

    @Test func aCarriedFieldWhoseKeyIsTakenMovesToAFreeOne() throws {
        let source = ExerciseRecord(name: "A", category: "", muscleGroupNames: [], tracksSets: false, sides: "both", fields: [
            FieldRecord(key: "f1", label: "Calories", type: "number")
        ])
        let result = try DefinitionMerge.merge(source: source, into: rowing, mapping: FieldMapping(destinations: ["f1": .newField])).get()
        #expect(result.keyRewrite["f1"] == "f3")
        #expect(result.merged.fields.last?.key == "f3")
    }

    @Test func aTypeMismatchIsRefused() {
        let mapping = FieldMapping(destinations: ["f1": .field(targetKey: "f2"), "f2": .newField, "f3": .newField])
        let result = DefinitionMerge.merge(source: rudern, into: rowing, mapping: mapping)
        #expect(result == .failure(.typeMismatch(source: "Dauer", target: "Heart Rate")))
    }

    @Test func twoFieldsCannotLandOnOne() {
        let mapping = FieldMapping(destinations: ["f1": .newField, "f2": .field(targetKey: "f2"), "f3": .field(targetKey: "f2")])
        #expect(DefinitionMerge.merge(source: rudern, into: rowing, mapping: mapping) == .failure(.targetTakenTwice("Heart Rate")))
    }

    @Test func anUnmappedFieldIsRefusedRatherThanDropped() {
        let mapping = FieldMapping(destinations: ["f1": .newField])
        #expect(DefinitionMerge.merge(source: rudern, into: rowing, mapping: mapping) == .failure(.unmappedField("Heart Rate")))
    }

    @Test func theLimitOnFieldsHolds() {
        let big = ExerciseRecord(name: "B", category: "", muscleGroupNames: [], tracksSets: false, sides: "both", fields:
            (1...5).map { FieldRecord(key: "f\($0)", label: "F\($0)", type: "number") })
        let mapping = FieldMapping(destinations: Dictionary(uniqueKeysWithValues: big.fields.map { ($0.key, FieldMapping.Destination.newField) }))
        #expect(DefinitionMerge.merge(source: big, into: rowing, mapping: mapping) == .failure(.tooManyFields(7)))
    }
}
