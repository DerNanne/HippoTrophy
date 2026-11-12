import Foundation

/// Durations are stored as whole seconds, so they can be summed, compared and
/// sorted without parsing. Everything that turns those seconds into something
/// readable — and reads typed text back into them — lives here.
enum DurationFormat {
    static let maxSeconds = 24 * 3600 - 1

    /// `510` → `"8:30"`, `5025` → `"1:23:45"`.
    static func text(forSeconds total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func components(fromSeconds total: Int) -> (hours: Int, minutes: Int, seconds: Int) {
        let clamped = min(max(total, 0), maxSeconds)
        return (clamped / 3600, (clamped % 3600) / 60, clamped % 60)
    }

    static func clampedSeconds(hours: Int, minutes: Int, seconds: Int) -> Int {
        min(hours * 3600 + minutes * 60 + seconds, maxSeconds)
    }

    /// Reads the spelling a backup writes: `"30:30"` → 1830, `"1:23:45"` → 5025.
    ///
    /// The colon is the whole point. Without one a value is just a number, and a
    /// number cannot say whether it counts seconds or minutes — `"830"` is 830
    /// seconds under one reading and 8:30 under the other, with nothing to
    /// choose between them. A colon settles it, so anything without one is not
    /// a duration this will read.
    static func seconds(fromColonText text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(":") else { return nil }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }
        var total = 0
        for part in parts {
            // An empty piece ("8:") counts as zero; a non-numeric one does not.
            let piece = part.isEmpty ? 0 : Int(part)
            guard let piece, piece >= 0 else { return nil }
            total = total * 60 + piece
        }
        return min(total, maxSeconds)
    }

    /// Reads a duration someone typed into a text field, for turning that field
    /// into a duration field.
    ///
    /// `"8:30"` → 510, `"1:23:45"` → 5025. A bare number is read the way a
    /// stopwatch reads it, right to left: `"830"` → 8:30, `"45"` → 0:45 — lenient
    /// on purpose, because the text was never meant to be parsed. Returns nil
    /// for anything that is not a duration at all.
    static func seconds(fromFreeText text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") { return seconds(fromColonText: trimmed) }

        guard trimmed.allSatisfy(\.isWholeNumber) else { return nil }
        var digits = trimmed
        var total = 0
        var unit = 1
        while !digits.isEmpty && unit <= 3600 {
            let take = digits.suffix(2)
            digits = String(digits.dropLast(take.count))
            total += (Int(take) ?? 0) * unit
            unit *= 60
        }
        // Digits left over would be more than 24 hours anyway.
        guard digits.isEmpty else { return maxSeconds }
        return min(total, maxSeconds)
    }
}
