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
