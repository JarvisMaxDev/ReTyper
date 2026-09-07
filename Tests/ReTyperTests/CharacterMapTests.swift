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
        for (en, by) in CharacterMap.englishToBelarusian {
            let expected: Character = by == "'" ? "]" : en
            XCTAssertEqual(CharacterMap.belarusianToEnglish[by], expected,
                           "Belarusian reverse mapping must prefer the unshifted bracket for the apostrophe")
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
        XCTAssertTrue(CharacterMap.isLatinLayout("com.apple.keylayout.French"))
        XCTAssertTrue(CharacterMap.isLatinLayout("com.apple.keylayout.Dvorak"))
    }

    func testUnknownLayoutIsNotClassifiedAsLatinByPrefixOrSubstring() {
        for id in ["com.apple.keylayout.Arabic", "com.apple.keylayout.Unknown", "com.apple.keylayout.US-extra",
                   "org.example.PolishPro", "US", ""] {
            XCTAssertFalse(CharacterMap.isLatinLayout(id), id)
        }
    }
    
    func testIsCyrillicLayout() {
        for layout in CharacterMap.CyrillicLayout.allCases {
            XCTAssertEqual(CharacterMap.cyrillicLayout(for: layout.rawValue), layout)
        }
    }

    func testCyrillicLayoutRejectsPartialAndUnknownIdentifiers() {
        for id in ["", "Russian", "com.apple.keylayout.", "com.apple.keylayout.RussianWin-extra"] {
            XCTAssertNil(CharacterMap.cyrillicLayout(for: id), id)
        }
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
