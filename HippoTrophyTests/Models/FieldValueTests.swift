import Testing
@testable import HippoTrophy

/// Typed input on its way into `numberValue`, and what a field keeps when its
/// type changes underneath it.
struct FieldValueTests {
    @Test func acceptsEitherDecimalSeparator() {
        #expect(FieldType.number(fromInput: "1.5") == 1.5)
        #expect(FieldType.number(fromInput: "1,5") == 1.5)
        #expect(FieldType.number(fromInput: "12 kg") == 12)
    }

    /// A negative number is no value any field holds, and storing it positive
    /// would be a different number than the one typed.
    @Test func aMinusIsNotDroppedToMakeANumber() {
        #expect(FieldType.number(fromInput: "-5") == nil)
    }

    /// These used to be stored as 1215 and 12, without a word.
    @Test func digitsThatStandApartAreNotJoined() {
        #expect(FieldType.number(fromInput: "12-15") == nil)
        #expect(FieldType.number(fromInput: "1a2") == nil)
        #expect(FieldType.number(fromInput: "1 000") == nil)
    }

    @Test func aMarkBehindANumberIsLeftOut() {
        #expect(FieldType.number(fromInput: "60 kg") == 60)
        #expect(FieldType.number(fromInput: "11,25\"") == 11.25)
        #expect(FieldType.number(fromInput: " 12. ") == 12)
    }

    /// Documented, not desired: only Western digits are read, so these are
    /// refused rather than converted.
    @Test func losesDigitsThatAreNotWestern() {
        #expect(FieldType.number(fromInput: "٣") == nil)
    }

    @Test func nothingReadableIsNilRatherThanZero() {
        #expect(FieldType.number(fromInput: "") == nil)
        #expect(FieldType.number(fromInput: "abc") == nil)
        #expect(FieldType.number(fromInput: "1.2.3") == nil)
    }

    /// "1.5" used to be 15 reps, the separator dropped like any stray mark.
    @Test func aCountHasNoFraction() {
        #expect(FieldType.wholeNumber(fromInput: "12") == 12)
        #expect(FieldType.wholeNumber(fromInput: "10 reps") == 10)
        #expect(FieldType.wholeNumber(fromInput: "1.5") == nil)
        #expect(FieldType.wholeNumber(fromInput: "12-15") == nil)
    }

    @Test func repsInputIsReadAsACount() {
        let reps = value(.reps, number: 8)
        reps.applyInput("10", unit: .kilograms)
        #expect(reps.numberValue == 10)
        reps.applyInput("12-15", unit: .kilograms)
        #expect(reps.numberValue == nil)
    }

    // MARK: - What a field shows

    @Test func aFieldKeepsWhatItCanRead() {
        #expect(FieldType.weight.acceptedInput("82,5", replacing: "82,") == "82,5")
        #expect(FieldType.weight.acceptedInput("82,", replacing: "82") == "82,")
        #expect(FieldType.reps.acceptedInput("12", replacing: "1") == "12")
        #expect(FieldType.number.acceptedInput("", replacing: "12") == "")
    }

    /// Dropped at once, the mark would let the next digits join the number.
    @Test func aFieldKeepsAMarkBehindANumberWhileTyping() {
        #expect(FieldType.weight.acceptedInput("60 kg", replacing: "") == "60 kg")
        #expect(FieldType.weight.acceptedInput("11,25\"", replacing: "11,25") == "11,25\"")
        #expect(FieldType.number.acceptedInput("1.2.", replacing: "1.2") == "1.2.")
        #expect(FieldType.reps.acceptedInput("1.", replacing: "1") == "1.")
    }

    @Test func aFieldDropsTheMarkWhenItIsLeft() {
        #expect(FieldType.weight.settledInput("60 kg") == "60")
        #expect(FieldType.weight.settledInput("12-") == "12")
        #expect(FieldType.number.settledInput("1.2.") == "1.2")
        #expect(FieldType.reps.settledInput("1.") == "1")
        #expect(FieldType.weight.settledInput("82,5") == "82,5")
        #expect(FieldType.weight.settledInput("") == "")
        #expect(FieldType.text.settledInput("12-") == "12-")
    }

    /// Key by key, as with a hardware keyboard: the digits after the mark are
    /// refused, where they used to join the number and store 1215.
    @Test func typingTwelveDashFifteenStopsAtTheDash() {
        let weight = value(.weight, number: nil)
        #expect(typing("12-15", into: weight) == "12-")
        #expect(weight.numberValue == 12)

        let reps = value(.reps, number: nil)
        #expect(typing("1.5", into: reps) == "1.")
        #expect(reps.numberValue == 1)

        let number = value(.number, number: nil)
        #expect(typing("1.2.3", into: number) == "1.2.")
        #expect(number.numberValue == 1.2)
    }

    /// What `ValueCell` does with each keystroke.
    private func typing(_ keys: String, into field: FieldValue) -> String {
        var shown = ""
        for key in keys {
            let accepted = field.type.acceptedInput(shown + String(key), replacing: shown)
            if accepted != shown {
                shown = accepted
                field.applyInput(shown, unit: .kilograms)
            }
        }
        return shown
    }

    /// Pasted over a field, these leave what was in it: the field shows what is
    /// stored, not something that looks saved and is not.
    @Test func aFieldRefusesWhatItCannotRead() {
        #expect(FieldType.weight.acceptedInput("12-15", replacing: "60") == "60")
        #expect(FieldType.weight.acceptedInput("-5", replacing: "60") == "60")
        #expect(FieldType.number.acceptedInput("abc", replacing: "") == "")
        #expect(FieldType.reps.acceptedInput("1.5", replacing: "8") == "8")
    }

    @Test func aTextFieldTakesAnything() {
        #expect(FieldType.text.acceptedInput("12-15", replacing: "") == "12-15")
    }

    /// What a field shows has to pass, or it could not be edited at all.
    @Test func whatAFieldShowsIsAccepted() {
        let kilograms = value(.weight, number: 82.5).editText(unit: .kilograms)
        #expect(FieldType.weight.acceptedInput(kilograms, replacing: "") == kilograms)
        let pounds = value(.weight, number: 1360).editText(unit: .pounds)
        #expect(FieldType.weight.acceptedInput(pounds, replacing: "") == pounds)
    }

    @Test func writesAWholeNumberWithoutAFraction() {
        #expect(FieldType.canonicalText(for: 142) == "142")
        #expect(FieldType.canonicalText(for: 1.5) == "1.5")
        #expect(FieldType.canonicalText(for: 0) == "0")
    }

    // MARK: - Weights in the editor

    /// The editor shows the weight the row shows, quarter step included.
    @Test func theEditorShowsAQuarterStep() {
        let weight = value(.weight, number: 11.25)
        let shown = weight.editText(unit: .kilograms)
        #expect(FieldType.number(fromInput: shown) == 11.25)
    }

    /// With one fraction digit, 11.2 typed over a stored 11.25 fell inside the
    /// tolerance and was dropped as "the same weight".
    @Test func typingADifferentWeightNearAQuarterStepIsAnEdit() {
        let weight = value(.weight, number: 11.25)
        weight.applyInput("11.2", unit: .kilograms)
        #expect(weight.numberValue == 11.2)
    }

    /// Showing a kilogram weight in pounds and leaving the field as it is must
    /// not rewrite the set.
    @Test func aWeightShownInPoundsIsNotWrittenBack() {
        let weight = value(.weight, number: 60)
        weight.applyInput(weight.editText(unit: .pounds), unit: .pounds)
        #expect(weight.numberValue == 60)
    }

    // MARK: - Type changes

    private func value(
        _ type: FieldType,
        text: String? = nil,
        number: Double? = nil
    ) -> FieldValue {
        FieldValue(
            fieldKey: "field",
            label: "Field",
            typeRawValue: type.rawValue,
            orderIndex: 0,
            textValue: text,
            numberValue: number
        )
    }

    @Test func aDurationInTextBecomesSeconds() {
        let converted = value(.text, text: "8:30").converting(to: .time)
        #expect(converted.numberValue == 510)
        #expect(converted.textValue == nil)
        #expect(converted.lost == false)
    }

    @Test func textThatIsNoDurationIsLost() {
        let converted = value(.text, text: "warm").converting(to: .time)
        #expect(converted.numberValue == nil)
        #expect(converted.lost == true)
    }

    @Test func aNumberBecomesTheTextTheBackupSpells() {
        let converted = value(.number, number: 142).converting(to: .text)
        #expect(converted.textValue == "142")
        #expect(converted.numberValue == nil)
        #expect(converted.lost == false)
    }

    @Test func aDurationBecomesItsReadableSpelling() {
        let converted = value(.time, number: 510).converting(to: .text)
        #expect(converted.textValue == "8:30")
        #expect(converted.lost == false)
    }

    @Test func aNumberBecomesWholeSecondsWhenItTurnsIntoADuration() {
        #expect(value(.number, number: 1.6).converting(to: .time).numberValue == 2)
        #expect(value(.number, number: 100_000).converting(to: .time).numberValue == 86399)
    }

    /// An empty field means nothing was logged. No conversion can turn that into
    /// a zero, and nothing is reported as lost.
    @Test func anEmptyFieldSurvivesEveryTypeChange() {
        for target in [FieldType.text, .number, .time] {
            let converted = value(.text).converting(to: target)
            #expect(converted.textValue == nil)
            #expect(converted.numberValue == nil)
            #expect(converted.lost == false)
        }
    }
}
