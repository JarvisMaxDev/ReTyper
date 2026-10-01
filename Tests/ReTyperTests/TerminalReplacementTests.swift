import XCTest
import Carbon
@testable import ReTyper

final class TypedFragmentTests: XCTestCase {
    func testTypingBackspaceAndReset() {
        var buffer = TypedFragment()
        for c in "ghbdtx" { buffer.append(c) }
        buffer.deleteBackward(); buffer.append("n")
        XCTAssertEqual(buffer.text, "ghbdtn")
        let generation = buffer.generation
        buffer.reset()
        XCTAssertTrue(buffer.text.isEmpty)
        XCTAssertGreaterThan(buffer.generation, generation)
        buffer.deleteBackward()
        XCTAssertTrue(buffer.text.isEmpty)
    }

    func testOverflowClearsTextAndDisablesRecordingUntilReset() {
        var buffer = TypedFragment()
        for _ in 0..<256 { buffer.append("a") }
        XCTAssertEqual(buffer.text.count, 256)
        buffer.append("b")
        XCTAssertTrue(buffer.isSuspended)
        XCTAssertEqual(buffer.text, "")
        buffer.append("c"); buffer.deleteBackward()
        XCTAssertEqual(buffer.text, "")
        buffer.reset(); buffer.append("d")
        XCTAssertEqual(buffer.text, "d")
    }

    func testUnsupportedCompositionCannotStartAFictitiousSuffix() {
        var buffer = TypedFragment()
        buffer.append("a"); buffer.suspend(); buffer.append("e")
        XCTAssertEqual(buffer.text, "")
        XCTAssertTrue(buffer.isSuspended)
        buffer.reset(); buffer.append("b")
        XCTAssertEqual(buffer.text, "b")
    }

    func testReplaceTailPreservesPrefixAndRejectsInvalidLength() {
        var buffer = TypedFragment()
        for c in "ls ghbdtn" { buffer.append(c) }
        XCTAssertTrue(buffer.replaceTail(count: 6, with: "привет"))
        XCTAssertEqual(buffer.text, "ls привет")
        XCTAssertFalse(buffer.replaceTail(count: 100, with: "x"))
        XCTAssertEqual(buffer.text, "ls привет")
    }

    func testEveryMutationInvalidatesAnEarlierSnapshot() {
        var buffer = TypedFragment()
        var snapshot = buffer.generation
        buffer.deleteBackward()
        XCTAssertGreaterThan(buffer.generation, snapshot)
        snapshot = buffer.generation
        buffer.append("я")
        XCTAssertGreaterThan(buffer.generation, snapshot)
        snapshot = buffer.generation
        XCTAssertTrue(buffer.replaceTail(count: 1, with: "z"))
        XCTAssertGreaterThan(buffer.generation, snapshot)
        buffer.suspend(); snapshot = buffer.generation
        buffer.append("a")
        XCTAssertGreaterThan(buffer.generation, snapshot)
        XCTAssertEqual(buffer.text, "")
    }
}

final class TerminalKeyTests: XCTestCase {
    func testSystemKeysAndResetActions() throws {
        let pl = try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout.PolishPro", keyboardType: 41))
        let ru = try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout.RussianWin", keyboardType: 41))
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: [], layout: pl), .character("g"))
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: .maskShift, layout: pl), .character("G"))
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: [], layout: ru), .character("п"))
        XCTAssertEqual(TerminalKey.classify(code: 22, flags: .maskShift, layout: ru), .character(":"))
        XCTAssertEqual(TerminalKey.classify(code: 49, flags: [], layout: pl), .character(" "))
        XCTAssertEqual(TerminalKey.classify(code: 51, flags: [], layout: pl), .backspace)
        for code: UInt16 in [36, 76, 48, 53, 117, 123, 124, 125, 126, 115, 119, 116, 121, 122, 83] {
            XCTAssertEqual(TerminalKey.classify(code: code, flags: [], layout: pl), .reset)
        }
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: .maskCommand, layout: pl), .reset)
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: .maskControl, layout: pl), .reset)
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: .maskAlternate, layout: pl), .suspend)
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: .maskAlphaShift, layout: pl), .suspend)
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: [], layout: nil), .suspend)
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: .maskSecondaryFn, layout: pl), .reset)
        XCTAssertEqual(TerminalKey.classify(code: 51, flags: .maskAlternate, layout: pl), .reset)
        XCTAssertEqual(TerminalKey.classify(code: 49, flags: .maskShift, layout: pl), .character(" "))
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: [.maskNonCoalesced, .maskNumericPad], layout: pl), .character("g"))
    }

    func testDeadKeysAreIdentifiedWithoutChangingConversionMappings() throws {
        let de = try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout.German", keyboardType: 41))
        let fr = try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout.French", keyboardType: 41))
        XCTAssertEqual(de.deadKeys, [KeyStroke(keyCode: 10, shift: false), KeyStroke(keyCode: 24, shift: false), KeyStroke(keyCode: 24, shift: true)])
        XCTAssertEqual(fr.deadKeys, [KeyStroke(keyCode: 33, shift: false), KeyStroke(keyCode: 33, shift: true), KeyStroke(keyCode: 42, shift: false)])
        XCTAssertEqual(TerminalKey.classify(code: 24, flags: [], layout: de), .suspend)
        XCTAssertNotNil(de.keys[KeyStroke(keyCode: 24, shift: false)])
        for id in ["PolishPro", "RussianWin", "Russian", "US", "ABC", "Ukrainian-PC"] {
            let layout = try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout." + id, keyboardType: 41))
            XCTAssertTrue(layout.deadKeys.isEmpty, id)
        }
        XCTAssertTrue(KeyLayout(id: "fake", keys: [:]).deadKeys.isEmpty)
    }

    func testCombiningCharactersCannotBeCountedAsSingleDeletions() {
        let layout = KeyLayout(id: "custom", keys: [KeyStroke(keyCode: 5, shift: false): "e\u{301}"])
        XCTAssertEqual(TerminalKey.classify(code: 5, flags: [], layout: layout), .suspend)
    }
}

final class TerminalReplacementTests: XCTestCase {
    func testOnlyVerifiedStandaloneTerminalIsEnabled() {
        XCTAssertEqual(TerminalReplacement.supportedBundleIDs, ["com.apple.Terminal"])
        XCTAssertTrue(TerminalReplacement.supportedBundleIDs.isSubset(of: AppDelegate.terminalBundleIDs))
        for id in ["com.microsoft.VSCode", "com.jetbrains.WebStorm", "com.jetbrains.intellij"] {
            XCTAssertFalse(TerminalReplacement.supportedBundleIDs.contains(id))
        }
    }
    func testFullFragmentLastWordAndReversal() throws {
        let pl = try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout.PolishPro", keyboardType: 41))
        let ru = try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout.RussianWin", keyboardType: 41))
        for (input, output, word, count) in [("ghbdtn", "привет", false, 6), ("сгкд -Ш", "curl -I", false, 7),
                                            ("ghbdtn vbh", "привет мир", false, 10), ("hello ghbdtn ", "привет ", true, 7),
                                            ("^)", ":)", false, 2)] {
            var buffer = TypedFragment(); for c in input { buffer.append(c) }
            let edit = try XCTUnwrap(TerminalReplacement.edit(fragment: buffer, onlyLastWord: word) {
                let result = TextConverter.convert($0, layouts: [pl, ru], currentLayoutID: pl.id)
                return (result.converted, result.targetLayoutID)
            })
            XCTAssertEqual(edit.deleteCount, count)
            XCTAssertEqual(edit.insert, output)
            XCTAssertTrue(buffer.replaceTail(count: count, with: output))
            let reversed = try XCTUnwrap(TerminalReplacement.edit(fragment: buffer, onlyLastWord: word) {
                let result = TextConverter.convert($0, layouts: [pl, ru], currentLayoutID: edit.targetLayoutID)
                return (result.converted, result.targetLayoutID)
            })
            XCTAssertEqual(reversed.insert, String(input.suffix(count)))
        }
    }

    func testNoEditForEmptySuspendedOrUnconvertibleFragment() {
        var buffer = TypedFragment()
        XCTAssertNil(TerminalReplacement.edit(fragment: buffer, onlyLastWord: false) { ($0, "ru") })
        buffer.append("a"); buffer.suspend()
        XCTAssertNil(TerminalReplacement.edit(fragment: buffer, onlyLastWord: false) { _ in ("ф", "ru") })
        buffer.reset(); buffer.append("a")
        XCTAssertNil(TerminalReplacement.edit(fragment: buffer, onlyLastWord: false) { ($0, nil) })
        XCTAssertNil(TerminalReplacement.edit(fragment: buffer, onlyLastWord: false) { _ in ("longer", "ru") })
        XCTAssertNil(TerminalReplacement.edit(fragment: buffer, onlyLastWord: false) { _ in ("e\u{301}", "ru") })
        XCTAssertNil(TerminalReplacement.edit(fragment: buffer, onlyLastWord: false) { _ in ("\n", "ru") })
    }

    func testOnlyWhitespaceAndAmbiguousScriptsDoNotTriggerDeletion() throws {
        let pl = try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout.PolishPro", keyboardType: 41))
        let ru = try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout.RussianWin", keyboardType: 41))
        for text in ["   ", "ab аб"] {
            var fragment = TypedFragment(); for c in text { fragment.append(c) }
            XCTAssertNil(TerminalReplacement.edit(fragment: fragment, onlyLastWord: text == "   ") {
                let result = TextConverter.convert($0, layouts: [pl, ru], currentLayoutID: pl.id)
                return (result.converted, result.targetLayoutID)
            })
        }
    }
}
