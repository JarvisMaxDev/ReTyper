import XCTest
@testable import ReTyper

final class TextFragmentResolverTests: XCTestCase {

    private let compoundCharacters = [
        "e\u{0301}",
        "\u{1F642}",
        "\u{1F1FA}\u{1F1E6}",
        "\u{1F469}\u{200D}\u{1F4BB}",
        "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
        "\u{1F44D}\u{1F3FD}",
        "\u{2708}\u{FE0F}"
    ]

    private let canonicallyEquivalentTextPairs = [
        ("e\u{0301}", "\u{00E9}"),
        ("\u{212B}", "\u{00C5}"),
        ("a\u{0323}\u{0301}", "a\u{0301}\u{0323}")
    ]

    private func snapshot(_ value: String, caret: Int, selectionLength: Int = 0, selectedText: String? = nil) -> TextSnapshot {
        TextSnapshot(value: value, caretLocation: caret, selectionLength: selectionLength, selectedText: selectedText)
    }

    // MARK: - fragmentBeforeCaret

    func testEmptyValueYieldsNoFragment() {
        XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snapshot("", caret: 0)))
    }

    func testCaretAtStartYieldsNoFragment() {
        XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snapshot("ghbdtn", caret: 0)))
    }

    func testCaretRightAfterSeparatorYieldsNoFragment() {
        XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snapshot("ghbdtn ", caret: 7)))
    }

    func testLastWordIsTakenWhenCaretIsAtEnd() {
        let fragment = TextFragmentResolver.fragmentBeforeCaret(snapshot("ghbdtn", caret: 6))
        XCTAssertEqual(fragment?.text, "ghbdtn")
        XCTAssertEqual(fragment?.range, 0..<6)
        XCTAssertEqual(fragment?.origin, .caretBoundary)
    }

    func testCaretInTheMiddleLimitsFragmentToTextBeforeCaret() {
        let fragment = TextFragmentResolver.fragmentBeforeCaret(snapshot("ghbdtn tests", caret: 6))
        XCTAssertEqual(fragment?.text, "ghbdtn")
        XCTAssertEqual(fragment?.range, 0..<6)
    }

    func testOnlyLastWordIsTakenFromMultiWordLine() {
        let fragment = TextFragmentResolver.fragmentBeforeCaret(snapshot("echo ghbdtn", caret: 11))
        XCTAssertEqual(fragment?.text, "ghbdtn")
        XCTAssertEqual(fragment?.range, 5..<11)
    }

    func testFragmentStopsAtLineBreak() {
        let value = "first line\nghbdtn"
        let fragment = TextFragmentResolver.fragmentBeforeCaret(snapshot(value, caret: value.utf16.count))
        XCTAssertEqual(fragment?.text, "ghbdtn")
    }

    func testTabIsTreatedAsSeparator() {
        let fragment = TextFragmentResolver.fragmentBeforeCaret(snapshot("a\tghbdtn", caret: 8))
        XCTAssertEqual(fragment?.text, "ghbdtn")
    }

    func testSurrogatePairIsNotSplit() {
        let value = "ghbdtn🙂"
        let fragment = TextFragmentResolver.fragmentBeforeCaret(snapshot(value, caret: value.utf16.count))
        XCTAssertEqual(fragment?.text, "ghbdtn🙂")
        XCTAssertFalse(fragment?.text.unicodeScalars.contains { $0 == "\u{FFFD}" } ?? true)
    }

    func testCaretInsideSurrogatePairIsRejected() {
        let value = "ab🙂"
        let fragment = TextFragmentResolver.fragmentBeforeCaret(snapshot(value, caret: 3))
        XCTAssertNil(fragment)
    }

    func testDiacriticsArePreserved() {
        let value = "café"
        let fragment = TextFragmentResolver.fragmentBeforeCaret(snapshot(value, caret: value.utf16.count))
        XCTAssertEqual(fragment?.text, "café")
    }

    func testSelectionPresentMeansNoCaretFragment() {
        XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snapshot("ghbdtn", caret: 0, selectionLength: 6)))
        XCTAssertNil(TextFragmentResolver.fragmentFromLineStart(snapshot("ghbdtn", caret: 0, selectionLength: 6)))
    }

    func testCaretModesRejectInvalidCoordinates() {
        for (caret, length) in [
            (-1, 0), (Int.min, 0), (4, 0), (Int.max, 0),
            (1, -1), (1, Int.min), (1, Int.max), (Int.max, 1)
        ] {
            let snap = snapshot("abc", caret: caret, selectionLength: length)
            XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snap), "caret=\(caret), length=\(length)")
            XCTAssertNil(TextFragmentResolver.fragmentFromLineStart(snap), "caret=\(caret), length=\(length)")
        }
    }

    func testCaretModesRequireEmptyReportedSelection() {
        for selectedText: String? in [nil, ""] {
            let snap = snapshot("word tail", caret: 4, selectedText: selectedText)
            XCTAssertEqual(TextFragmentResolver.fragmentBeforeCaret(snap)?.text, "word")
            XCTAssertEqual(TextFragmentResolver.fragmentFromLineStart(snap)?.text, "word")
        }
        for selectedText in ["word", "tail", " "] {
            let snap = snapshot("word tail", caret: 4, selectedText: selectedText)
            XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snap))
            XCTAssertNil(TextFragmentResolver.fragmentFromLineStart(snap))
        }
    }

    func testCaretModesPreserveWholeGraphemesAndUTF16Ranges() throws {
        for character in compoundCharacters {
            let prefix = "prefix "
            let caret = prefix.utf16.count + character.utf16.count
            let snap = snapshot(prefix + character + " suffix", caret: caret)
            let word = try XCTUnwrap(TextFragmentResolver.fragmentBeforeCaret(snap))
            XCTAssertEqual(Array(word.text.utf16), Array(character.utf16))
            XCTAssertEqual(word.range, prefix.utf16.count..<caret)
            XCTAssertEqual(word.origin, .caretBoundary)

            let line = try XCTUnwrap(TextFragmentResolver.fragmentFromLineStart(snap))
            XCTAssertEqual(Array(line.text.utf16), Array((prefix + character).utf16))
            XCTAssertEqual(line.range, 0..<caret)
            XCTAssertEqual(line.origin, .caretBoundary)
        }
    }

    func testCaretModesRejectEveryInteriorGraphemeOffset() {
        for character in compoundCharacters + ["\r\n"] {
            for offset in 1..<character.utf16.count {
                let snap = snapshot("ab" + character + " suffix", caret: 2 + offset)
                let message = "character=\(character.debugDescription), offset=\(offset)"
                XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snap), message)
                XCTAssertNil(TextFragmentResolver.fragmentFromLineStart(snap), message)
            }
        }
    }

    func testWordModeRetainsExistingSeparators() {
        for separator in [" ", "\t", "\n", "\r", "\r\n"] {
            let prefix = "first" + separator
            let snap = snapshot(prefix + "word tail", caret: prefix.utf16.count + 4)
            let fragment = TextFragmentResolver.fragmentBeforeCaret(snap)
            XCTAssertEqual(fragment?.text, "word")
            XCTAssertEqual(fragment?.range, prefix.utf16.count..<(prefix.utf16.count + 4))
            XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snapshot(prefix, caret: prefix.utf16.count)))
        }

        let value = "one\u{00A0}two\u{2003}three,.-"
        XCTAssertEqual(TextFragmentResolver.fragmentBeforeCaret(snapshot(value, caret: value.utf16.count))?.text, value)
    }

    func testWordModeRejectsStartInsideSeparatorGraphemeInsteadOfExpandingIt() {
        let value = " \u{0301}word"
        let snap = snapshot(value, caret: value.utf16.count)
        XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snap))
        XCTAssertEqual(TextFragmentResolver.fragmentFromLineStart(snap)?.text, value)
    }

    // MARK: - fragmentFromSelection

    func testZeroLengthSelectionYieldsNoFragment() {
        XCTAssertNil(TextFragmentResolver.fragmentFromSelection(snapshot("ghbdtn", caret: 3)))
    }

    func testSelectionFragmentAcceptsMatchingReportedSelectedText() {
        let fragment = TextFragmentResolver.fragmentFromSelection(
            snapshot("echo ghbdtn", caret: 5, selectionLength: 6, selectedText: "ghbdtn")
        )
        XCTAssertEqual(fragment?.text, "ghbdtn")
        XCTAssertEqual(fragment?.range, 5..<11)
        XCTAssertEqual(fragment?.origin, .userSelection)
    }

    func testSelectionFragmentFallsBackToValueWhenSelectedTextMissing() {
        let fragment = TextFragmentResolver.fragmentFromSelection(
            snapshot("echo ghbdtn", caret: 5, selectionLength: 6, selectedText: nil)
        )
        XCTAssertEqual(fragment?.text, "ghbdtn")
    }

    func testSelectionBeyondValueIsRejected() {
        let fragment = TextFragmentResolver.fragmentFromSelection(
            snapshot("abc", caret: 1, selectionLength: 99, selectedText: nil)
        )
        XCTAssertNil(fragment)
    }

    func testSelectionRejectsNegativeAndOutOfBoundsRanges() {
        for (caret, length) in [
            (-1, 2), (Int.min, 1), (0, -1), (1, Int.min),
            (0, 4), (2, 2), (3, 1), (4, 1), (Int.max, 0)
        ] {
            let snap = snapshot("abc", caret: caret, selectionLength: length)
            XCTAssertNil(TextFragmentResolver.fragmentFromSelection(snap), "caret=\(caret), length=\(length)")
        }
        XCTAssertNil(TextFragmentResolver.fragmentFromSelection(snapshot("", caret: 0, selectionLength: 1)))
    }

    func testSelectionRejectsOverflowingRanges() {
        for (caret, length) in [(1, Int.max), (Int.max, 1), (Int.max, Int.max)] {
            let snap = snapshot("abc", caret: caret, selectionLength: length)
            XCTAssertNil(TextFragmentResolver.fragmentFromSelection(snap), "caret=\(caret), length=\(length)")
        }
    }

    func testSelectionRejectsStaleSelectedText() {
        for selectedText in ["abd", "", "abcd", "tail"] {
            let snap = snapshot("abc tail", caret: 0, selectionLength: 3, selectedText: selectedText)
            XCTAssertNil(TextFragmentResolver.fragmentFromSelection(snap))
        }
    }

    func testSelectionRequiresIdenticalUTF16NotCanonicalEquivalence() {
        for (first, second) in canonicallyEquivalentTextPairs {
            XCTAssertEqual(first, second)
            XCTAssertNotEqual(Array(first.utf16), Array(second.utf16))
            for (actual, reported) in [(first, second), (second, first)] {
                let snap = snapshot(actual, caret: 0, selectionLength: actual.utf16.count, selectedText: reported)
                XCTAssertNil(TextFragmentResolver.fragmentFromSelection(snap))
            }
        }
    }

    func testSelectionPreservesWholeGraphemes() throws {
        for character in compoundCharacters + ["\r\n", " \t"] {
            for selectedText: String? in [nil, character] {
                let snap = snapshot("x" + character + "y", caret: 1,
                                    selectionLength: character.utf16.count, selectedText: selectedText)
                let fragment = try XCTUnwrap(TextFragmentResolver.fragmentFromSelection(snap))
                XCTAssertEqual(Array(fragment.text.utf16), Array(character.utf16))
                XCTAssertEqual(fragment.range, 1..<(1 + character.utf16.count))
                XCTAssertEqual(fragment.origin, .userSelection)
            }
        }
    }

    func testSelectionRejectsEveryInteriorGraphemeEndpoint() {
        for character in compoundCharacters + ["\r\n"] {
            for offset in 1..<character.utf16.count {
                for (caret, length) in [(1, offset), (1 + offset, character.utf16.count - offset)] {
                    for selectedText: String? in [nil, character] {
                        let snap = snapshot("x" + character + "y", caret: caret,
                                            selectionLength: length, selectedText: selectedText)
                        XCTAssertNil(TextFragmentResolver.fragmentFromSelection(snap),
                                     "character=\(character.debugDescription), caret=\(caret), length=\(length)")
                    }
                }
            }
        }
    }

    // MARK: - fragmentFromLineStart

    func testLineStartFragmentIncludesSpaces() {
        let value = "hello ghbdtn"
        let fragment = TextFragmentResolver.fragmentFromLineStart(snapshot(value, caret: value.utf16.count))
        XCTAssertEqual(fragment?.text, "hello ghbdtn")
    }

    func testLineStartFragmentStopsAtPreviousLine() {
        let value = "first\nhello ghbdtn"
        let fragment = TextFragmentResolver.fragmentFromLineStart(snapshot(value, caret: value.utf16.count))
        XCTAssertEqual(fragment?.text, "hello ghbdtn")
    }

    func testLineStartModeRetainsSpacesAndTabsAndStopsAtEachLineBreak() {
        for lineBreak in ["\n", "\r", "\r\n"] {
            let prefix = "previous" + lineBreak
            let line = "hello\tworld "
            let caret = prefix.utf16.count + line.utf16.count
            let snap = snapshot(prefix + line + "\nsuffix", caret: caret)
            let fragment = TextFragmentResolver.fragmentFromLineStart(snap)
            XCTAssertEqual(fragment?.text, line)
            XCTAssertEqual(fragment?.range, prefix.utf16.count..<caret)
            XCTAssertNil(TextFragmentResolver.fragmentBeforeCaret(snap))
            XCTAssertNil(TextFragmentResolver.fragmentFromLineStart(snapshot(prefix, caret: prefix.utf16.count)))
        }
    }

    func testLineStartModeStopsAtCaretInMiddleOfLine() {
        let snap = snapshot("first\nhello world suffix", caret: 14)
        let fragment = TextFragmentResolver.fragmentFromLineStart(snap)
        XCTAssertEqual(fragment?.text, "hello wo")
        XCTAssertEqual(fragment?.range, 6..<14)
        XCTAssertEqual(TextFragmentResolver.fragmentBeforeCaret(snap)?.text, "wo")
    }

    // MARK: - expectedValue

    func testExpectedValueSplicesReplacementInPlace() {
        let snap = snapshot("echo ghbdtn tail", caret: 11)
        let fragment = ReplacementFragment(text: "ghbdtn", range: 5..<11, origin: .caretBoundary)
        let expected = TextFragmentResolver.expectedValue(after: fragment, replacedWith: "привет", in: snap)
        XCTAssertEqual(expected, "echo привет tail")
    }

    func testExpectedValueAfterDeletionRemovesFragment() {
        let snap = snapshot("echo ghbdtn tail", caret: 11)
        let fragment = ReplacementFragment(text: "ghbdtn", range: 5..<11, origin: .caretBoundary)
        let expected = TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap)
        XCTAssertEqual(expected, "echo  tail")
    }

    func testExpectedValueKeepsMultilineTail() {
        let snap = snapshot("ghbdtn\nsecond", caret: 6)
        let fragment = ReplacementFragment(text: "ghbdtn", range: 0..<6, origin: .caretBoundary)
        let expected = TextFragmentResolver.expectedValue(after: fragment, replacedWith: "привет", in: snap)
        XCTAssertEqual(expected, "привет\nsecond")
    }

    func testExpectedValuesRejectInvalidFragmentRanges() {
        let snap = snapshot("abc", caret: 3)
        for range in [
            -2 ..< -1, -1..<1, 0..<0, 1..<1, 3..<3, 0..<4, 4..<5,
            0..<Int.max, Int.min..<Int.max
        ] {
            let fragment = ReplacementFragment(text: range.isEmpty ? "" : "abc", range: range, origin: .caretBoundary)
            XCTAssertNil(TextFragmentResolver.expectedValue(after: fragment, replacedWith: "x", in: snap), "\(range)")
            XCTAssertNil(TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap), "\(range)")
        }

        let emptyFragment = ReplacementFragment(text: "", range: 0..<0, origin: .caretBoundary)
        XCTAssertNil(TextFragmentResolver.expectedValue(after: emptyFragment, replacedWith: "x", in: snapshot("", caret: 0)))
        XCTAssertNil(TextFragmentResolver.expectedValueAfterDeletion(of: emptyFragment, in: snapshot("", caret: 0)))
    }

    func testExpectedValuesRejectStaleFragmentText() {
        let snap = snapshot("abc tail", caret: 3)
        for text in ["abd", "", "abcd", "tail"] {
            let fragment = ReplacementFragment(text: text, range: 0..<3, origin: .caretBoundary)
            XCTAssertNil(TextFragmentResolver.expectedValue(after: fragment, replacedWith: "x", in: snap))
            XCTAssertNil(TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap))
        }
    }

    func testExpectedValuesRequireIdenticalUTF16NotCanonicalEquivalence() {
        for (first, second) in canonicallyEquivalentTextPairs {
            for (actual, reported) in [(first, second), (second, first)] {
                let snap = snapshot(actual, caret: actual.utf16.count)
                let fragment = ReplacementFragment(text: reported, range: 0..<actual.utf16.count, origin: .caretBoundary)
                XCTAssertNil(TextFragmentResolver.expectedValue(after: fragment, replacedWith: "x", in: snap))
                XCTAssertNil(TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap))
            }
        }
    }

    func testExpectedValuesRejectInvalidSnapshotCoordinates() {
        let fragment = ReplacementFragment(text: "abc", range: 0..<3, origin: .caretBoundary)
        for (caret, length) in [
            (-1, 0), (Int.min, 0), (4, 0), (Int.max, 0), (-1, 2),
            (1, -1), (1, Int.min), (0, 4), (2, 2), (3, 1),
            (1, Int.max), (Int.max, 1), (Int.max, Int.max)
        ] {
            let snap = snapshot("abc", caret: caret, selectionLength: length)
            let message = "caret=\(caret), length=\(length)"
            XCTAssertNil(TextFragmentResolver.expectedValue(after: fragment, replacedWith: "x", in: snap), message)
            XCTAssertNil(TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap), message)
        }
    }

    func testExpectedValuesRejectInconsistentSelectedText() {
        let fragment = ReplacementFragment(text: "abc", range: 0..<3, origin: .caretBoundary)
        for snap in [
            snapshot("abc", caret: 3, selectedText: "abc"),
            snapshot("abc", caret: 0, selectionLength: 3, selectedText: "abd"),
            snapshot("abc", caret: 0, selectionLength: 3, selectedText: "")
        ] {
            XCTAssertNil(TextFragmentResolver.expectedValue(after: fragment, replacedWith: "x", in: snap))
            XCTAssertNil(TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap))
        }

        for (actual, reported) in canonicallyEquivalentTextPairs {
            let snap = snapshot(actual, caret: 0, selectionLength: actual.utf16.count, selectedText: reported)
            let matchingFragment = ReplacementFragment(text: actual, range: 0..<actual.utf16.count, origin: .userSelection)
            XCTAssertNil(TextFragmentResolver.expectedValue(after: matchingFragment, replacedWith: "x", in: snap))
            XCTAssertNil(TextFragmentResolver.expectedValueAfterDeletion(of: matchingFragment, in: snap))
        }
    }

    func testExpectedValuesRejectSnapshotEndpointsInsideGraphemes() {
        let fragment = ReplacementFragment(text: "x", range: 0..<1, origin: .caretBoundary)
        for character in compoundCharacters + ["\r\n"] {
            for offset in 1..<character.utf16.count {
                for (caret, length) in [(1 + offset, 0), (1, offset), (1 + offset, character.utf16.count - offset)] {
                    let snap = snapshot("x" + character + "y", caret: caret, selectionLength: length)
                    let message = "character=\(character.debugDescription), caret=\(caret), length=\(length)"
                    XCTAssertNil(TextFragmentResolver.expectedValue(after: fragment, replacedWith: "z", in: snap), message)
                    XCTAssertNil(TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap), message)
                }
            }
        }
    }

    func testExpectedValuesRejectFragmentEndpointsInsideGraphemes() {
        for character in compoundCharacters + ["\r\n"] {
            let value = "x" + character + "y"
            let snap = snapshot(value, caret: value.utf16.count)
            for offset in 1..<character.utf16.count {
                for range in [1..<(1 + offset), (1 + offset)..<(1 + character.utf16.count)] {
                    let text = String(decoding: Array(value.utf16)[range], as: UTF16.self)
                    let fragment = ReplacementFragment(text: text, range: range, origin: .userSelection)
                    let message = "character=\(character.debugDescription), range=\(range)"
                    XCTAssertNil(TextFragmentResolver.expectedValue(after: fragment, replacedWith: "z", in: snap), message)
                    XCTAssertNil(TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap), message)
                }
            }
        }
    }

    func testExpectedValuesPreserveExactUnicodeAndUnchangedSuffix() throws {
        let prefix = "e\u{0301}\u{212B} "
        let suffix = " e\u{0301}\u{212B}\r\n\u{1F1FA}\u{1F1E6}\u{1F469}\u{200D}\u{1F4BB} tail"
        for character in compoundCharacters {
            let range = prefix.utf16.count..<(prefix.utf16.count + character.utf16.count)
            let value = prefix + character + suffix
            for snap in [
                snapshot(value, caret: range.upperBound),
                snapshot(value, caret: range.upperBound, selectedText: ""),
                snapshot(value, caret: range.lowerBound, selectionLength: character.utf16.count),
                snapshot(value, caret: range.lowerBound, selectionLength: character.utf16.count, selectedText: character)
            ] {
                let fragment = ReplacementFragment(text: character, range: range, origin: .userSelection)
                for replacement in ["", "x", "longer replacement", "e\u{0301}", "\u{0301}", "\u{1F469}\u{200D}\u{1F4BB}"] {
                    let result = try XCTUnwrap(TextFragmentResolver.expectedValue(after: fragment, replacedWith: replacement, in: snap))
                    XCTAssertEqual(Array(result.utf16), Array((prefix + replacement + suffix).utf16))
                }
                let deleted = try XCTUnwrap(TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap))
                XCTAssertEqual(Array(deleted.utf16), Array((prefix + suffix).utf16))
            }
        }
    }

    func testExpectedValuesReplaceOnlyAddressedOccurrence() {
        let snap = snapshot("abc abc abc", caret: 7)
        let fragment = ReplacementFragment(text: "abc", range: 4..<7, origin: .systemSelection)
        XCTAssertEqual(TextFragmentResolver.expectedValue(after: fragment, replacedWith: "x", in: snap), "abc x abc")
        XCTAssertEqual(TextFragmentResolver.expectedValueAfterDeletion(of: fragment, in: snap), "abc  abc")
    }
}
