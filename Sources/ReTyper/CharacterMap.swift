import Foundation

/// Static character mapping tables for converting between Latin (QWERTY) and Cyrillic keyboard layouts.
/// Covers Russian, Ukrainian, and Belarusian Apple keyboard layouts.
struct CharacterMap {
    
    // MARK: - Russian (ЙЦУКЕН)
    
    /// QWERTY → Russian ЙЦУКЕН mapping (lowercase + uppercase + special chars)
    static let englishToRussian: [Character: Character] = [
        // Lowercase letters
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
        "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п",
        "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и",
        "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",
        "`": "ё",
        
        // Uppercase letters
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
        "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ъ",
        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П",
        "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж", "\"": "Э",
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И",
        "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ",",
        "~": "Ё",
    ]
    
    /// Russian ЙЦУКЕН → QWERTY mapping (reverse of above)
    static let russianToEnglish: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (en, ru) in englishToRussian {
            map[ru] = en
        }
        return map
    }()
    
    // MARK: - Ukrainian (ЙЦУКЕН-UA)
    
    /// QWERTY → Ukrainian mapping
    /// Ukrainian layout differs from Russian in several keys:
    /// - ґ, є, і, ї replace some Russian characters
    static let englishToUkrainian: [Character: Character] = [
        // Lowercase letters
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
        "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ї",
        "a": "ф", "s": "і", "d": "в", "f": "а", "g": "п",
        "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж", "'": "є",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и",
        "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",
        "`": "ґ",
        
        // Uppercase letters
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
        "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ї",
        "A": "Ф", "S": "І", "D": "В", "F": "А", "G": "П",
        "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж", "\"": "Є",
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И",
        "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ",",
        "~": "Ґ",
    ]
    
    static let ukrainianToEnglish: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (en, ua) in englishToUkrainian {
            map[ua] = en
        }
        return map
    }()
    
    // MARK: - Belarusian (ЙЦУКЕН-BY)
    
    /// QWERTY → Belarusian mapping
    /// Belarusian layout differs: ў replaces щ position, і replaces ы
    static let englishToBelarusian: [Character: Character] = [
        // Lowercase letters
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
        "y": "н", "u": "г", "i": "ш", "o": "ў", "p": "з",
        "[": "х", "]": "'",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п",
        "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "і",
        "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",
        "`": "ё",
        
        // Uppercase letters
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
        "Y": "Н", "U": "Г", "I": "Ш", "O": "Ў", "P": "З",
        "{": "Х", "}": "'",
        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П",
        "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж", "\"": "Э",
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "І",
        "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ",",
        "~": "Ё",
    ]
    
    static let belarusianToEnglish: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (en, by) in englishToBelarusian {
            map[by] = en
        }
        return map
    }()
    
    // MARK: - Layout Detection
    
    /// Known Cyrillic layout identifiers
    enum CyrillicLayout: String, CaseIterable {
        case russian = "com.apple.keylayout.Russian"
        case russianPC = "com.apple.keylayout.RussianWin"
        case ukrainian = "com.apple.keylayout.Ukrainian"
        case ukrainianPC = "com.apple.keylayout.Ukrainian-PC"
        case belarusian = "com.apple.keylayout.Belarusian"
        
        var displayName: String {
            switch self {
            case .russian, .russianPC: return "RU"
            case .ukrainian, .ukrainianPC: return "UA"
            case .belarusian: return "BY"
            }
        }
        
        var toEnglishMap: [Character: Character] {
            switch self {
            case .russian, .russianPC: return russianToEnglish
            case .ukrainian, .ukrainianPC: return ukrainianToEnglish
            case .belarusian: return belarusianToEnglish
            }
        }
        
        var fromEnglishMap: [Character: Character] {
            switch self {
            case .russian, .russianPC: return englishToRussian
            case .ukrainian, .ukrainianPC: return englishToUkrainian
            case .belarusian: return englishToBelarusian
            }
        }
    }
    
    /// Determine if a layout ID is Cyrillic and which one
    static func cyrillicLayout(for layoutID: String) -> CyrillicLayout? {
        return CyrillicLayout.allCases.first { layoutID.contains($0.rawValue) || $0.rawValue.contains(layoutID) }
    }
    
    /// Determine if a layout ID is a Latin-based layout (QWERTY/QWERTZ/AZERTY).
    /// Treats any non-Cyrillic keyboard layout as Latin for conversion purposes.
    static func isLatinLayout(_ layoutID: String) -> Bool {
        // If it's Cyrillic, it's not Latin
        if cyrillicLayout(for: layoutID) != nil { return false }
        
        // Known Latin layouts (explicit match)
        let latinPatterns = [
            "ABC", "US", "British", "USInternational", "Australian",
            "Canadian", "USExtended", "Colemak", "Dvorak",
            "Polish", "PolishPro", "German", "French", "Spanish",
            "Italian", "Portuguese", "Dutch", "Swedish", "Norwegian",
            "Danish", "Finnish", "Czech", "Slovak", "Hungarian",
            "Romanian", "Croatian", "Slovenian", "Turkish",
        ]
        let idLower = layoutID.lowercased()
        if latinPatterns.contains(where: { idLower.contains($0.lowercased()) }) {
            return true
        }
        
        // Fallback: if it starts with com.apple.keylayout and isn't Cyrillic, assume Latin
        if layoutID.hasPrefix("com.apple.keylayout.") {
            return true
        }
        
        return false
    }
    
    /// Legacy alias for compatibility
    static func isEnglishLayout(_ layoutID: String) -> Bool {
        return isLatinLayout(layoutID)
    }
    
    /// Get display abbreviation for a layout ID
    static func displayName(for layoutID: String) -> String {
        if let cyrillic = cyrillicLayout(for: layoutID) {
            return cyrillic.displayName
        }
        
        // Known Latin display names
        let knownNames: [String: String] = [
            "Polish": "PL", "PolishPro": "PL",
            "ABC": "EN", "US": "EN", "British": "EN",
            "USInternational": "EN", "Australian": "EN", "Canadian": "EN",
            "German": "DE", "French": "FR", "Spanish": "ES",
            "Italian": "IT", "Portuguese": "PT", "Dutch": "NL",
            "Swedish": "SV", "Norwegian": "NO", "Danish": "DA",
            "Finnish": "FI", "Czech": "CZ", "Slovak": "SK",
            "Hungarian": "HU", "Romanian": "RO", "Croatian": "HR",
            "Slovenian": "SI", "Turkish": "TR",
        ]
        
        for (pattern, name) in knownNames {
            if layoutID.contains(pattern) {
                return name
            }
        }
        
        // Fallback: use last component
        let components = layoutID.split(separator: ".")
        let last = components.last.map(String.init) ?? layoutID
        return String(last.prefix(2)).uppercased()
    }
}
