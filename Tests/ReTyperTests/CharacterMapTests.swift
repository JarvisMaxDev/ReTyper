import XCTest
@testable import ReTyper

final class CharacterMapTests: XCTestCase {
    
    // MARK: - Mapping Completeness
    
    func testRussianMappingCompleteness() {
        // Every value in englishToRussian should have a reverse entry
        for (en, ru) in CharacterMap.englishToRussian {
            XCTAssertEqual(CharacterMap.russianToEnglish[ru], en,
                           "Missing reverse mapping for Russian: \(ru) should map back to \(en)")
        }
    }
    
    func testRussianPCMappingCompleteness() {
        for (en, ru) in CharacterMap.englishToRussianPC {
            XCTAssertEqual(CharacterMap.russianPCToEnglish[ru], en,
                           "Missing reverse mapping for Russian PC: \(ru) should map back to \(en)")
        }
    }
    
    func testUkrainianMappingCompleteness() {
        for (en, ua) in CharacterMap.englishToUkrainian {
            XCTAssertEqual(CharacterMap.ukrainianToEnglish[ua], en,
                           "Missing reverse mapping for Ukrainian: \(ua) should map back to \(en)")
        }
    }
    
    func testUkrainianPCMappingCompleteness() {
        for (en, ua) in CharacterMap.englishToUkrainianPC {
            XCTAssertEqual(CharacterMap.ukrainianPCToEnglish[ua], en,
                           "Missing reverse mapping for Ukrainian PC: \(ua) should map back to \(en)")
        }
    }
    
    func testBelarusianMappingCompleteness() {
        // Note: Belarusian maps both ] and } to ' (apostrophe),
        // so the reverse map has a collision — only one direction survives.
        // We skip colliding entries in this test.
        let collidingValues: Set<Character> = ["'"]
        for (en, by) in CharacterMap.englishToBelarusian {
            if collidingValues.contains(by) { continue }
            XCTAssertEqual(CharacterMap.belarusianToEnglish[by], en,
                           "Missing reverse mapping for Belarusian: \(by) should map back to \(en)")
        }
    }
    
    // MARK: - PC Layout Differences
    
    func testRussianPCMappingDiffersFromApple() {
        // Russian PC uses distinct maps from Apple Russian
        let pcMap = CharacterMap.englishToRussianPC
        let appleMap = CharacterMap.englishToRussian
        
        // PC has number row Shift symbols that Apple doesn't
        XCTAssertEqual(pcMap["@"], "\"", "Shift+2 in Russian PC should be \" (quotes)")
        XCTAssertEqual(pcMap["#"], "№", "Shift+3 in Russian PC should be № (number sign)")
        XCTAssertEqual(pcMap["$"], ";", "Shift+4 in Russian PC should be ; (semicolon)")
        XCTAssertEqual(pcMap["^"], ":", "Shift+6 in Russian PC should be : (colon)")
        XCTAssertEqual(pcMap["&"], "?", "Shift+7 in Russian PC should be ? (question mark)")
        
        // These should not be present in Apple map
        XCTAssertNil(appleMap["@"], "Apple Russian should not map @ to anything")
        XCTAssertNil(appleMap["#"], "Apple Russian should not map # to anything")
    }
    
    // MARK: - Ukrainian Specific Characters
    
    func testUkrainianSpecificChars() {
        XCTAssertEqual(CharacterMap.englishToUkrainian["`"], "ґ")
        XCTAssertEqual(CharacterMap.englishToUkrainian["'"], "є")
        XCTAssertEqual(CharacterMap.englishToUkrainian["s"], "і")
        XCTAssertEqual(CharacterMap.englishToUkrainian["]"], "ї")
        
        // Uppercase
        XCTAssertEqual(CharacterMap.englishToUkrainian["~"], "Ґ")
        XCTAssertEqual(CharacterMap.englishToUkrainian["\""], "Є")
        XCTAssertEqual(CharacterMap.englishToUkrainian["S"], "І")
        XCTAssertEqual(CharacterMap.englishToUkrainian["}"], "Ї")
    }
    
    // MARK: - Layout Detection
    
    func testIsLatinLayout() {
        XCTAssertTrue(CharacterMap.isLatinLayout("com.apple.keylayout.US"))
        XCTAssertTrue(CharacterMap.isLatinLayout("com.apple.keylayout.ABC"))
        XCTAssertTrue(CharacterMap.isLatinLayout("com.apple.keylayout.PolishPro"))
        XCTAssertTrue(CharacterMap.isLatinLayout("com.apple.keylayout.British"))
    }
    
    func testIsCyrillicLayout() {
        XCTAssertNotNil(CharacterMap.cyrillicLayout(for: "com.apple.keylayout.Russian"))
        XCTAssertNotNil(CharacterMap.cyrillicLayout(for: "com.apple.keylayout.RussianWin"))
        XCTAssertNotNil(CharacterMap.cyrillicLayout(for: "com.apple.keylayout.Ukrainian"))
        XCTAssertNotNil(CharacterMap.cyrillicLayout(for: "com.apple.keylayout.Ukrainian-PC"))
        XCTAssertNotNil(CharacterMap.cyrillicLayout(for: "com.apple.keylayout.Belarusian"))
    }
    
    func testCyrillicIsNotLatin() {
        XCTAssertFalse(CharacterMap.isLatinLayout("com.apple.keylayout.Russian"))
        XCTAssertFalse(CharacterMap.isLatinLayout("com.apple.keylayout.Ukrainian"))
    }
    
    // MARK: - Display Names
    
    func testDisplayName() {
        XCTAssertEqual(CharacterMap.displayName(for: "com.apple.keylayout.US"), "EN")
        XCTAssertEqual(CharacterMap.displayName(for: "com.apple.keylayout.Russian"), "RU")
        XCTAssertEqual(CharacterMap.displayName(for: "com.apple.keylayout.RussianWin"), "RU")
        XCTAssertEqual(CharacterMap.displayName(for: "com.apple.keylayout.Ukrainian"), "UA")
        XCTAssertEqual(CharacterMap.displayName(for: "com.apple.keylayout.Ukrainian-PC"), "UA")
        XCTAssertEqual(CharacterMap.displayName(for: "com.apple.keylayout.Belarusian"), "BY")
        XCTAssertEqual(CharacterMap.displayName(for: "com.apple.keylayout.PolishPro"), "PL")
    }
    
    // MARK: - CyrillicLayout Enum Maps
    
    func testCyrillicEnumUsesCorrectMaps() {
        let russianApple = CharacterMap.CyrillicLayout.russian
        let russianPC = CharacterMap.CyrillicLayout.russianPC
        
        // They should use different maps for PC
        XCTAssertNil(russianApple.fromEnglishMap["@"], "Apple Russian should not map @")
        XCTAssertEqual(russianPC.fromEnglishMap["@"], "\"", "Russian PC should map @ to \"")
    }
    
    // MARK: - Punctuation Mapping
    
    func testRussianPunctuationMapping() {
        // Period in Russian (".") comes from "/" key in English
        XCTAssertEqual(CharacterMap.englishToRussian["/"], ".")
        XCTAssertEqual(CharacterMap.russianToEnglish[Character(".")], "/")
        
        // Comma in Russian (",") comes from "?" (Shift+/) in English
        XCTAssertEqual(CharacterMap.englishToRussian["?"], ",")
        XCTAssertEqual(CharacterMap.russianToEnglish[Character(",")], "?")
    }
}
