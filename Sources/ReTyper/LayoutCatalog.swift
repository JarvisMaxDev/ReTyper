import Foundation

/// Layouts offered in «Active Keyboards» and their short names for the menu bar.
/// Holds no character data: conversion reads every layout from macOS (see KeyLayout).
struct LayoutCatalog {

    /// Cyrillic layouts offered for selection.
    enum CyrillicLayout: String, CaseIterable {
        case russian = "com.apple.keylayout.Russian"
        case russianPC = "com.apple.keylayout.RussianWin"
        case ukrainian = "com.apple.keylayout.Ukrainian"
        case ukrainianPC = "com.apple.keylayout.Ukrainian-PC"
        case belarusian = "com.apple.keylayout.Byelorussian"

        var displayName: String {
            switch self {
            case .russian, .russianPC: return "RU"
            case .ukrainian, .ukrainianPC: return "UA"
            case .belarusian: return "BY"
            }
        }
    }

    /// Latin layouts offered for selection.
    static let latinLayoutIDs: [String] = [
        "ABC", "US", "British", "USInternational", "Australian",
        "Canadian", "USExtended", "Colemak", "Dvorak",
        "Polish", "PolishPro", "German", "French", "Spanish",
        "Italian", "Portuguese", "Dutch", "Swedish", "Norwegian",
        "Danish", "Finnish", "Czech", "Slovak", "Hungarian",
        "Romanian", "Croatian", "Slovenian", "Turkish",
    ].map { "com.apple.keylayout.\($0)" }

    /// Determine if a layout ID is Cyrillic and which one
    static func cyrillicLayout(for layoutID: String) -> CyrillicLayout? {
        return CyrillicLayout(rawValue: layoutID)
    }

    static func isLatinLayout(_ layoutID: String) -> Bool {
        latinLayoutIDs.contains(layoutID)
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
