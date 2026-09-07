import XCTest
@testable import ReTyper

final class TextConverterTests: XCTestCase {
    
    // MARK: - Script Detection
    
    func testDetectCyrillicScript() {
        XCTAssertEqual(TextConverter.detectScript("привет"), .cyrillic)
        XCTAssertEqual(TextConverter.detectScript("мир"), .cyrillic)
        XCTAssertEqual(TextConverter.detectScript("ПРИВЕТ"), .cyrillic)
    }
    
    func testDetectLatinScript() {
        XCTAssertEqual(TextConverter.detectScript("hello"), .latin)
        XCTAssertEqual(TextConverter.detectScript("world"), .latin)
        XCTAssertEqual(TextConverter.detectScript("HELLO"), .latin)
    }
    
    func testDetectMixedScript() {
        // Predominantly Cyrillic
        XCTAssertEqual(TextConverter.detectScript("привет w"), .cyrillic)
        // Predominantly Latin
        XCTAssertEqual(TextConverter.detectScript("hello м"), .latin)
    }
    
    func testDetectUnknownScript() {
        // Pure numbers/symbols — no letters
        XCTAssertEqual(TextConverter.detectScript("12345"), .unknown)
        XCTAssertEqual(TextConverter.detectScript("!@#$%"), .unknown)
        XCTAssertEqual(TextConverter.detectScript(""), .unknown)
    }
    
    // MARK: - Conversion (Latin → Russian)
    
    func testConvertLatinToRussian() {
        let layouts = [
            "com.apple.keylayout.US",
            "com.apple.keylayout.Russian",
        ]
        
        let result = TextConverter.autoConvert("ghbdtn", availableLayoutIDs: layouts)
        XCTAssertEqual(result.converted, "привет")
        XCTAssertEqual(result.targetLayoutID, "com.apple.keylayout.Russian")
    }
    
    func testConvertLatinToRussianUppercase() {
        let layouts = [
            "com.apple.keylayout.US",
            "com.apple.keylayout.Russian",
        ]
        
        let result = TextConverter.autoConvert("GHBDTN", availableLayoutIDs: layouts)
        XCTAssertEqual(result.converted, "ПРИВЕТ")
    }
    
    // MARK: - Conversion (Russian → Latin)
    
    func testConvertRussianToLatin() {
        let layouts = [
            "com.apple.keylayout.US",
            "com.apple.keylayout.Russian",
        ]
        
        let result = TextConverter.autoConvert("руддщ", availableLayoutIDs: layouts)
        XCTAssertEqual(result.converted, "hello")
        XCTAssertEqual(result.targetLayoutID, "com.apple.keylayout.US")
    }

    func testIncompatibleLatinTargetsPreserveTheOriginal() {
        let source = "\u{440}\u{443}\u{434}\u{434}\u{449}"
        for target in ["Arabic", "German", "French", "Dvorak", "Colemak", "British", "US-extra"] {
            let result = TextConverter.autoConvert(source, availableLayoutIDs: [
                "com.apple.keylayout.Russian", "com.apple.keylayout." + target
            ])
            XCTAssertEqual(Array(result.converted.utf16), Array(source.utf16), target)
            XCTAssertNil(result.targetLayoutID, target)
        }
    }

    func testSupportedLatinTargetsPreserveCallerOrderAndSkipIncompatibleTargets() {
        let targets = ["com.apple.keylayout.US", "com.apple.keylayout.ABC", "com.apple.keylayout.PolishPro"]
        for first in targets {
            let layouts = ["com.apple.keylayout.Russian", "com.apple.keylayout.Dvorak", first]
                + targets.filter { $0 != first }
            let result = TextConverter.autoConvert("\u{440}\u{443}\u{434}\u{434}\u{449}", availableLayoutIDs: layouts)
            XCTAssertEqual(result.converted, "hello")
            XCTAssertEqual(result.targetLayoutID, first)
        }
    }
    
    // MARK: - Conversion with Punctuation
    
    func testConvertWithPunctuation() {
        let layouts = [
            "com.apple.keylayout.US",
            "com.apple.keylayout.Russian",
        ]
        
        // "ghbdtn/" typed in English layout should become "привет." in Russian
        let result = TextConverter.autoConvert("ghbdtn/", availableLayoutIDs: layouts)
        XCTAssertEqual(result.converted, "привет.")
    }
    
    // MARK: - Conversion with PC Layout
    
    func testConvertLatinToRussianPC() {
        let layouts = [
            "com.apple.keylayout.US",
            "com.apple.keylayout.RussianWin",
        ]
        
        let result = TextConverter.autoConvert("ghbdtn", availableLayoutIDs: layouts)
        XCTAssertEqual(result.converted, "привет")
        XCTAssertEqual(result.targetLayoutID, "com.apple.keylayout.RussianWin")
    }

    func testPCIdentifiersUseTheirOwnPunctuationInBothDirections() {
        let pairs: [(CharacterMap.CyrillicLayout, CharacterMap.CyrillicLayout)] = [
            (.russianPC, .russian), (.ukrainianPC, .ukrainian)
        ]
        for (pc, apple) in pairs {
            let layouts = ["com.apple.keylayout.US", pc.rawValue]
            let differences = pc.fromEnglishMap.filter { apple.fromEnglishMap[$0.key] != $0.value }
            XCTAssertFalse(differences.isEmpty)
            for (latin, cyrillic) in differences {
                let source = "a" + String(latin)
                let expected = "\u{444}" + String(cyrillic)
                let forward = TextConverter.autoConvert(source, availableLayoutIDs: layouts)
                XCTAssertEqual(forward.converted, expected, "\(pc.rawValue): \(latin)")
                XCTAssertEqual(forward.targetLayoutID, pc.rawValue)
                let reverse = TextConverter.autoConvert(expected, availableLayoutIDs: layouts)
                XCTAssertEqual(reverse.converted, source, "\(pc.rawValue): \(cyrillic)")
                XCTAssertEqual(reverse.targetLayoutID, "com.apple.keylayout.US")
            }
        }
    }
    
    // MARK: - Ukrainian
    
    func testConvertLatinToUkrainian() {
        let layouts = [
            "com.apple.keylayout.US",
            "com.apple.keylayout.Ukrainian",
        ]
        
        // "s" in QWERTY → "і" in Ukrainian
        let result = TextConverter.autoConvert("ghbdsn", availableLayoutIDs: layouts)
        XCTAssertTrue(result.converted.contains("і"),
                      "Ukrainian conversion should contain 'і', got: \(result.converted)")
    }
    
    // MARK: - Unknown/No Conversion

    func testBelarusianApostropheAlwaysReversesToTheUnshiftedBracket() {
        let layouts = ["com.apple.keylayout.US", "com.apple.keylayout.Belarusian"]
        let source = "\u{430}'"
        let result = TextConverter.autoConvert(source, availableLayoutIDs: layouts)
        XCTAssertEqual(result.converted, "f]")
        XCTAssertEqual(result.targetLayoutID, "com.apple.keylayout.US")
        for text in ["f]", "f}"] {
            let forward = TextConverter.autoConvert(text, availableLayoutIDs: layouts)
            XCTAssertEqual(forward.converted, source)
            XCTAssertEqual(forward.targetLayoutID, "com.apple.keylayout.Belarusian")
        }
    }
    
    func testConvertUnknownScriptReturnsOriginal() {
        let layouts = [
            "com.apple.keylayout.US",
            "com.apple.keylayout.Russian",
        ]
        
        let result = TextConverter.autoConvert("12345", availableLayoutIDs: layouts)
        XCTAssertEqual(result.converted, "12345")
        XCTAssertNil(result.targetLayoutID)
    }
    
    func testConvertEmptyStringReturnsOriginal() {
        let layouts = [
            "com.apple.keylayout.US",
            "com.apple.keylayout.Russian",
        ]
        
        let result = TextConverter.autoConvert("", availableLayoutIDs: layouts)
        XCTAssertEqual(result.converted, "")
        XCTAssertNil(result.targetLayoutID)
    }
    
    func testConvertWithNoAvailableLayouts() {
        let result = TextConverter.autoConvert("hello", availableLayoutIDs: [])
        XCTAssertEqual(result.converted, "hello")
        XCTAssertNil(result.targetLayoutID)
    }
}
