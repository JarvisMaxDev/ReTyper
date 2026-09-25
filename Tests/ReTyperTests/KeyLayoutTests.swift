import XCTest
@testable import ReTyper

final class KeyLayoutTests: XCTestCase {

    // MARK: - Keyboard kind

    func testKeyboardKindFromKeyboardType() {
        for type: UInt32 in [40, 58, 61] { XCTAssertEqual(KeyboardKind(keyboardType: type), .ansi, "\(type)") }
        for type: UInt32 in [41, 59, 62] { XCTAssertEqual(KeyboardKind(keyboardType: type), .iso, "\(type)") }
        for type: UInt32 in [42, 60, 63] { XCTAssertEqual(KeyboardKind(keyboardType: type), .jis, "\(type)") }
        XCTAssertEqual(KeyboardKind(keyboardType: 0), .ansi)
    }

    func testKeyCodesExistOnlyOnTheirKeyboards() {
        let ansi = Set(0...50).subtracting([10, 36, 48, 49]).map(UInt16.init)
        XCTAssertEqual(KeyboardKind.ansi.keyCodes.count, 47)
        XCTAssertEqual(Set(KeyboardKind.ansi.keyCodes), Set(ansi))
        XCTAssertEqual(Set(KeyboardKind.iso.keyCodes), Set(ansi).union([10]))
        XCTAssertEqual(Set(KeyboardKind.jis.keyCodes), Set(ansi).union([93, 94]))
    }

    // MARK: - Key order and mapping

    func testUnshiftedKeysComeFirstThenKeyCodeOrder() {
        let keys = [KeyStroke(keyCode: 5, shift: true), KeyStroke(keyCode: 9, shift: false),
                    KeyStroke(keyCode: 1, shift: true), KeyStroke(keyCode: 2, shift: false)]
        XCTAssertEqual(keys.sorted(), [KeyStroke(keyCode: 2, shift: false), KeyStroke(keyCode: 9, shift: false),
                                       KeyStroke(keyCode: 1, shift: true), KeyStroke(keyCode: 5, shift: true)])
    }

    func testCollisionPrefersUnshiftedKeyThenLowerKeyCode() {
        // Three keys of the source print "'"; each maps to a different target character.
        let source = KeyLayout(id: "source", keys: [
            KeyStroke(keyCode: 30, shift: true): "'",
            KeyStroke(keyCode: 39, shift: false): "'",
            KeyStroke(keyCode: 30, shift: false): "'",
        ])
        let target = KeyLayout(id: "target", keys: [
            KeyStroke(keyCode: 30, shift: true): "}",
            KeyStroke(keyCode: 39, shift: false): "э",
            KeyStroke(keyCode: 30, shift: false): "]",
        ])
        XCTAssertEqual(source.mapping(to: target)["'"], "]")

        let shiftedOnly = KeyLayout(id: "shifted", keys: [
            KeyStroke(keyCode: 12, shift: true): "x",
            KeyStroke(keyCode: 3, shift: true): "x",
        ])
        let other = KeyLayout(id: "other", keys: [
            KeyStroke(keyCode: 12, shift: true): "A",
            KeyStroke(keyCode: 3, shift: true): "B",
        ])
        XCTAssertEqual(shiftedOnly.mapping(to: other)["x"], "B")
    }

    func testMappingSkipsKeysMissingInTarget() {
        let source = KeyLayout(id: "s", keys: [KeyStroke(keyCode: 0, shift: false): "a",
                                               KeyStroke(keyCode: 10, shift: false): "§"])
        let target = KeyLayout(id: "t", keys: [KeyStroke(keyCode: 0, shift: false): "ф"])
        XCTAssertEqual(source.mapping(to: target), ["a": "ф"])
    }

    // MARK: - Scripts

    func testLetterScript() {
        for c: Character in ["a", "Z", "ü", "ł"] { XCTAssertEqual(Script.of(c), .latin, "\(c)") }
        for c: Character in ["ж", "ї", "ў"] { XCTAssertEqual(Script.of(c), .cyrillic, "\(c)") }
        for c: Character in ["×", "÷", "^", "1", "👍"] { XCTAssertNil(Script.of(c), "\(c)") }
    }

    func testLayoutScriptIsTheMajorityOfUnshiftedLetters() {
        let cyrillic = KeyLayout(id: "c", keys: [
            KeyStroke(keyCode: 0, shift: false): "ф", KeyStroke(keyCode: 1, shift: false): "ы",
            KeyStroke(keyCode: 2, shift: false): "d",
            // Shifted letters do not vote.
            KeyStroke(keyCode: 0, shift: true): "A", KeyStroke(keyCode: 1, shift: true): "B",
            KeyStroke(keyCode: 2, shift: true): "C",
        ])
        XCTAssertEqual(cyrillic.script, .cyrillic)
        let latin = KeyLayout(id: "l", keys: [KeyStroke(keyCode: 0, shift: false): "a",
                                              KeyStroke(keyCode: 1, shift: false): "ü"])
        XCTAssertEqual(latin.script, .latin)
        let tie = KeyLayout(id: "t", keys: [KeyStroke(keyCode: 0, shift: false): "a",
                                            KeyStroke(keyCode: 1, shift: false): "ф"])
        XCTAssertEqual(tie.script, .other)
        let symbols = KeyLayout(id: "n", keys: [KeyStroke(keyCode: 18, shift: false): "1"])
        XCTAssertEqual(symbols.script, .other)
    }

    // MARK: - System layouts

    /// A missing reference layout is a failure, never a skip (constitution, principle II).
    static func systemLayout(_ name: String, _ keyboardType: UInt32,
                             file: StaticString = #filePath, line: UInt = #line) throws -> KeyLayout {
        try XCTUnwrap(KeyLayout.system(id: "com.apple.keylayout.\(name)", keyboardType: keyboardType),
                      "reference layout missing: \(name)", file: file, line: line)
    }

    func testRussianPCOnISO() throws {
        let layout = try Self.systemLayout("RussianWin", 41)
        XCTAssertEqual(layout.keys[KeyStroke(keyCode: 22, shift: true)], ":")
        XCTAssertEqual(layout.keys[KeyStroke(keyCode: 10, shift: false)], "ё")
        XCTAssertEqual(layout.script, .cyrillic)
    }

    func testANSIHasNoSectionKey() throws {
        let russian = try Self.systemLayout("RussianWin", 40)
        let polish = try Self.systemLayout("PolishPro", 40)
        XCTAssertNil(russian.keys[KeyStroke(keyCode: 10, shift: false)])
        // Without the absent § key, ё reverses to the key that prints it on ANSI.
        XCTAssertEqual(russian.mapping(to: polish)["ё"], "`")
    }

    func testDeadKeysPrintTheirOwnSymbol() throws {
        let german = try Self.systemLayout("German", 41)
        XCTAssertEqual(german.keys[KeyStroke(keyCode: 24, shift: false)], "´")
        XCTAssertEqual(german.keys[KeyStroke(keyCode: 10, shift: false)], "^")
    }

    func testSourcesWithoutKeyDataAreNotLayouts() {
        XCTAssertNil(KeyLayout.system(id: "com.apple.keylayout.DoesNotExist", keyboardType: 41))
        // Pinyin is installed with macOS but has no key layout data.
        XCTAssertNil(KeyLayout.system(id: "com.apple.inputmethod.SCIM.ITABC", keyboardType: 41))
    }

    /// SC-006: the average printed by `measure` is recorded from a release build; the bound
    /// here only catches gross regressions, since CI machines vary.
    func testPairBuildTime() throws {
        func build() throws {
            let latin = try Self.systemLayout("PolishPro", 41)
            let cyrillic = try Self.systemLayout("RussianWin", 41)
            _ = latin.mapping(to: cyrillic)
            _ = cyrillic.mapping(to: latin)
        }
        try build() // warm-up: first Text Input Sources call initialises the framework
        let start = ProcessInfo.processInfo.systemUptime
        try build()
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.05)
        measure { try? build() }
    }
}
