import Foundation

/// Pure logic that decides which fragment of the field is going to be replaced.
/// Deliberately free of system APIs so it can be covered by unit tests.
struct TextFragmentResolver {

    /// Word separators. Everything else is part of a word.
    static let separators: Set<UInt16> = [
        0x20,  // space
        0x09,  // tab
        0x0A,  // line feed
        0x0D   // carriage return
    ]

    // MARK: - Fragment selection

    static func isValid(_ snapshot: TextSnapshot) -> Bool {
        validatedSelectionRange(in: snapshot) != nil
    }

    /// Fragment described by an existing selection.
    static func fragmentFromSelection(_ snapshot: TextSnapshot) -> ReplacementFragment? {
        guard snapshot.selectionLength > 0,
              let range = validatedSelectionRange(in: snapshot) else { return nil }

        return ReplacementFragment(
            text: String(snapshot.value[range]),
            range: snapshot.caretLocation..<(snapshot.caretLocation + snapshot.selectionLength),
            origin: .userSelection
        )
    }

    /// Fragment from the last separator before the caret up to the caret: the last word.
    static func fragmentBeforeCaret(_ snapshot: TextSnapshot) -> ReplacementFragment? {
        boundedFragment(snapshot, stopAtSeparator: true)
    }

    /// Fragment from the start of the current line up to the caret.
    /// Only meaningful for fields where the whole line belongs to the user.
    static func fragmentFromLineStart(_ snapshot: TextSnapshot) -> ReplacementFragment? {
        boundedFragment(snapshot, stopAtSeparator: false)
    }

    // MARK: - Expected result

    /// Content the field must have after the fragment is replaced.
    /// Used to confirm the outcome by re-reading the field instead of assuming success.
    /// Invalid snapshots, ranges, or mismatching fragment text yield nil.
    static func expectedValue(
        after fragment: ReplacementFragment,
        replacedWith text: String,
        in snapshot: TextSnapshot
    ) -> String? {
        guard !fragment.range.isEmpty,
              validatedSelectionRange(in: snapshot) != nil,
              let range = validatedRange(fragment.range, in: snapshot.value),
              fragment.text.utf16.elementsEqual(snapshot.value[range].utf16) else { return nil }

        return String(snapshot.value[..<range.lowerBound]) + text + String(snapshot.value[range.upperBound...])
    }

    /// Content the field must have after the fragment is deleted but before anything is typed.
    static func expectedValueAfterDeletion(
        of fragment: ReplacementFragment,
        in snapshot: TextSnapshot
    ) -> String? {
        expectedValue(after: fragment, replacedWith: "", in: snapshot)
    }

    // MARK: - Internals

    private static func boundedFragment(_ snapshot: TextSnapshot, stopAtSeparator: Bool) -> ReplacementFragment? {
        guard snapshot.selectionLength == 0,
              validatedSelectionRange(in: snapshot) != nil,
              snapshot.caretLocation > 0 else { return nil }

        let units = Array(snapshot.value.utf16)
        let caret = snapshot.caretLocation

        var start = caret
        while start > 0 {
            let unit = units[start - 1]
            if unit == 0x0A || unit == 0x0D { break }
            if stopAtSeparator && separators.contains(unit) { break }
            start -= 1
        }

        guard start < caret,
              let range = validatedRange(start..<caret, in: snapshot.value) else { return nil }

        return ReplacementFragment(text: String(snapshot.value[range]), range: start..<caret, origin: .caretBoundary)
    }

    private static func validatedSelectionRange(in snapshot: TextSnapshot) -> Range<String.Index>? {
        let count = snapshot.value.utf16.count
        // Check the remaining length before adding untrusted offsets.
        guard snapshot.caretLocation >= 0,
              snapshot.selectionLength >= 0,
              snapshot.caretLocation <= count,
              snapshot.selectionLength <= count - snapshot.caretLocation,
              let range = validatedRange(
                  snapshot.caretLocation..<(snapshot.caretLocation + snapshot.selectionLength),
                  in: snapshot.value
              ) else { return nil }

        // String equality accepts canonical equivalence; snapshots require exact UTF-16 identity.
        if let selectedText = snapshot.selectedText,
           !selectedText.utf16.elementsEqual(snapshot.value[range].utf16) {
            return nil
        }
        return range
    }

    /// Accept only exact extended grapheme cluster boundaries, without clamping or snapping.
    private static func validatedRange(_ range: Range<Int>, in value: String) -> Range<String.Index>? {
        guard range.lowerBound >= 0, range.upperBound <= value.utf16.count else { return nil }

        let lower = String.Index(utf16Offset: range.lowerBound, in: value)
        let upper = String.Index(utf16Offset: range.upperBound, in: value)
        guard (lower == value.endIndex || value.indices.contains(lower)),
              (upper == value.endIndex || value.indices.contains(upper)) else { return nil }

        return lower..<upper
    }
}
