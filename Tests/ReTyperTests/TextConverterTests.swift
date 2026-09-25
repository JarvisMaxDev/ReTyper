import XCTest
@testable import ReTyper

final class TextConverterTests: XCTestCase {
    private let polish = "com.apple.keylayout.PolishPro"
    private let russianPC = "com.apple.keylayout.RussianWin"
    /// A layout outside every pair used here.
    private let unrelated = "com.apple.keylayout.ABC"

    private func layouts(_ names: String..., keyboardType: UInt32 = 41) throws -> [KeyLayout] {
        try names.map { try KeyLayoutTests.systemLayout($0, keyboardType) }
    }

    private func owner() throws -> [KeyLayout] { try layouts("PolishPro", "RussianWin") }

    private func convert(_ text: String, _ layouts: [KeyLayout], current: String? = nil) -> ConversionResult {
        TextConverter.convert(text, layouts: layouts, currentLayoutID: current ?? unrelated)
    }

    // MARK: - Letters decide (FR-003)

    func testLatinLettersBecomeCyrillic() throws {
        let result = convert("ghbdtn", try owner())
        XCTAssertEqual(result.converted, "привет")
        XCTAssertEqual(result.targetLayoutID, russianPC)
        XCTAssertEqual(result.source, .letters)
        XCTAssertEqual(convert("GHBDTN", try owner()).converted, "ПРИВЕТ")
    }

    func testCyrillicLettersBecomeLatin() throws {
        let result = convert("руддщ", try owner())
        XCTAssertEqual(result.converted, "hello")
        XCTAssertEqual(result.targetLayoutID, polish)
        XCTAssertEqual(result.source, .letters)
    }

    func testMajorityOfLettersDecides() throws {
        XCTAssertEqual(convert("привет w", try owner()).targetLayoutID, polish)
        XCTAssertEqual(convert("hello м", try owner()).targetLayoutID, russianPC)
    }

    func testLetterTieIsUndetermined() {
        let latin = KeyLayout(id: "latin", keys: [KeyStroke(keyCode: 0, shift: false): "a",
                                                  KeyStroke(keyCode: 11, shift: false): "b"])
        let cyrillic = KeyLayout(id: "cyrillic", keys: [KeyStroke(keyCode: 0, shift: false): "а",
                                                        KeyStroke(keyCode: 11, shift: false): "б"])
        let result = convert("ab аб", [latin, cyrillic])
        XCTAssertEqual(result.converted, "ab аб")
        XCTAssertNil(result.targetLayoutID)
        XCTAssertEqual(result.source, .undetermined)
    }

    func testLettersWinOverSymbolsOfTheOtherLayout() throws {
        // ^ has no key in Russian – PC, so it stays.
        XCTAssertEqual(convert("Привет ^)", try owner()).converted, "Ghbdtn ^)")
    }

    func testCharactersOutsideTheMainKeyBlockSurvive() throws {
        XCTAssertEqual(convert("Ghbdtn 👍—", try owner()).converted, "Привет 👍—")
    }

    func testNothingToDecide() throws {
        for text in ["", "12345"] {
            let result = convert(text, try owner())
            XCTAssertEqual(result.converted, text)
            XCTAssertNil(result.targetLayoutID, text)
        }
        let noLayouts = convert("hello", [])
        XCTAssertEqual(noLayouts.converted, "hello")
        XCTAssertNil(noLayouts.targetLayoutID)
        XCTAssertEqual(noLayouts.source, .undetermined)
    }

    // MARK: - Symbols of only one layout (FR-004, User Story 1)

    func testSymbolsTypedOnTheLatinLayout() throws {
        let smiley = convert("^)", try owner())
        XCTAssertEqual(smiley.converted, ":)")
        XCTAssertEqual(smiley.targetLayoutID, russianPC)
        XCTAssertEqual(smiley.source, .layoutOnlySymbols)
        XCTAssertEqual(convert("&", try owner()).converted, "?")
        XCTAssertEqual(convert("§", try owner()).converted, "ё")
    }

    func testSymbolsTypedOnTheCyrillicLayout() throws {
        let result = convert("№", try owner())
        XCTAssertEqual(result.converted, "#")
        XCTAssertEqual(result.targetLayoutID, polish)
        XCTAssertEqual(result.source, .layoutOnlySymbols)
    }

    func testSymbolsOfBothLayoutsAreUndetermined() throws {
        let result = convert("^№", try owner())
        XCTAssertEqual(result.converted, "^№")
        XCTAssertNil(result.targetLayoutID)
        XCTAssertEqual(result.source, .undetermined)
    }

    func testLettersStillDecideNextToSymbols() throws {
        XCTAssertEqual(convert("ok ^)", try owner()).converted, "щл :)")
        XCTAssertEqual(convert("Ghbdtn^)", try owner()).converted, "Привет:)")
    }

    // MARK: - Current layout decides shared symbols (FR-005, User Story 2)

    func testSharedSymbolsFollowTheCurrentLayout() throws {
        let typedInRussian = convert(":)", try owner(), current: russianPC)
        XCTAssertEqual(typedInRussian.converted, "^)")
        XCTAssertEqual(typedInRussian.targetLayoutID, polish)
        XCTAssertEqual(typedInRussian.source, .currentLayout)

        let typedInPolish = convert(":)", try owner(), current: polish)
        XCTAssertEqual(typedInPolish.converted, "Ж)")
        XCTAssertEqual(typedInPolish.targetLayoutID, russianPC)
    }

    func testCurrentLayoutOutsideThePairIsUndetermined() throws {
        let result = convert(":)", try owner(), current: unrelated)
        XCTAssertEqual(result.converted, ":)")
        XCTAssertNil(result.targetLayoutID)
        XCTAssertEqual(result.source, .undetermined)
    }

    func testSymbolsIdenticalOnBothLayoutsStayTheSame() throws {
        // ReplacementFlow treats an unchanged result as layout-only (FR-007).
        XCTAssertEqual(convert(")))", try owner(), current: polish).converted, ")))")
    }

    /// FR-009: a second hotkey press right after the first restores every reversible character.
    func testSecondPressRestoresEveryReversibleCharacter() throws {
        let pair = try owner()
        let forward = pair[0].mapping(to: pair[1])
        let backward = pair[1].mapping(to: pair[0])
        let reversible = forward.filter { backward[$0.value] == $0.key }.keys
        XCTAssertGreaterThan(reversible.count, 80)
        for character in reversible {
            let first = convert(String(character), pair, current: polish)
            XCTAssertEqual(first.targetLayoutID, russianPC, "\(character)")
            let second = convert(first.converted, pair, current: russianPC)
            XCTAssertEqual(second.converted, String(character), "\(character) → \(first.converted)")
        }
    }

    // MARK: - Pair selection (FR-002a)

    func testFirstLatinAndFirstCyrillicInSelectedOrder() throws {
        let result = convert("ghbdtn", try layouts("RussianWin", "PolishPro", "Russian", "US"))
        XCTAssertEqual(result.converted, "привет")
        XCTAssertEqual(result.targetLayoutID, russianPC)
        XCTAssertEqual(convert("руддщ", try layouts("RussianWin", "PolishPro", "US")).targetLayoutID, polish)
    }

    func testAnyLatinLayoutIsATarget() throws {
        let result = convert("руддщ", try layouts("German", "RussianWin"))
        XCTAssertEqual(result.targetLayoutID, "com.apple.keylayout.German")
    }

    // MARK: - Real layouts, not the old tables (User Story 3, research R8)

    func testAppleRussianShiftDigits() throws {
        let result = convert("^&", try layouts("US", "Russian", keyboardType: 40),
                             current: "com.apple.keylayout.US")
        XCTAssertEqual(result.converted, ",.")
    }

    func testGermanKeyPositions() throws {
        let result = convert("н", try layouts("German", "RussianWin"), current: "com.apple.keylayout.German")
        XCTAssertEqual(result.converted, "z")
        XCTAssertEqual(result.targetLayoutID, "com.apple.keylayout.German")
    }

    func testBelarusianApostropheReversesToTheUnshiftedBracket() throws {
        // ' exists in both layouts, so the current Belarusian layout decides the direction.
        let result = convert("'", try layouts("US", "Byelorussian", keyboardType: 40),
                             current: "com.apple.keylayout.Byelorussian")
        XCTAssertEqual(result.converted, "]")
    }

    func testRussianPCYoOnANSIReversesToBacktick() throws {
        XCTAssertEqual(convert("ё", try layouts("PolishPro", "RussianWin", keyboardType: 40)).converted, "`")
    }

    func testUkrainianLegacyFollowsTheRealLayout() throws {
        XCTAssertEqual(convert("ghbdsn", try layouts("US", "Ukrainian", keyboardType: 40)).converted, "прівит")
    }

    func testDiacriticLettersAreLatin() throws {
        let german = convert("ü", try layouts("German", "RussianWin"))
        XCTAssertEqual(german.converted, "х")
        XCTAssertEqual(german.source, .letters)
        // ł and friends need Option, which is outside the main block: nothing to replace.
        let polishLetters = convert("łąś", try owner())
        XCTAssertEqual(polishLetters.converted, "łąś")
        XCTAssertEqual(polishLetters.source, .letters)
    }
}
