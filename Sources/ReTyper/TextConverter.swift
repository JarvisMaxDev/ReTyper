import Foundation

/// How the direction of a conversion was decided. Logged instead of the text.
enum DirectionSource: String {
    case letters
    case layoutOnlySymbols = "layout-only symbols"
    case currentLayout = "current layout"
    case undetermined
}

struct ConversionResult {
    let converted: String
    /// Nil when the direction could not be decided; the text is then unchanged.
    let targetLayoutID: String?
    let source: DirectionSource
}

/// Converts text typed with the wrong layout, key by key, using the selected system layouts.
/// Pure: no Text Input Sources calls and no logging, so it runs on any queue.
enum TextConverter {
    static func convert(_ text: String, layouts: [KeyLayout], currentLayoutID: String) -> ConversionResult {
        let unchanged = ConversionResult(converted: text, targetLayoutID: nil, source: .undetermined)
        guard let latin = layouts.first(where: { $0.script == .latin }),
              let cyrillic = layouts.first(where: { $0.script == .cyrillic }) else { return unchanged }

        var latinLetters = 0
        var cyrillicLetters = 0
        for character in text {
            switch Script.of(character) {
            case .latin: latinLetters += 1
            case .cyrillic: cyrillicLetters += 1
            default: break
            }
        }

        let fromLatin: Bool
        let source: DirectionSource
        if latinLetters + cyrillicLetters > 0 {
            guard latinLetters != cyrillicLetters else { return unchanged }
            fromLatin = latinLetters > cyrillicLetters
            source = .letters
        } else {
            // No letters: characters only one layout of the pair can type show where they came from.
            let latinOnly = latin.characters.subtracting(cyrillic.characters)
            let cyrillicOnly = cyrillic.characters.subtracting(latin.characters)
            let hasLatinOnly = text.contains { latinOnly.contains($0) }
            let hasCyrillicOnly = text.contains { cyrillicOnly.contains($0) }
            if hasLatinOnly != hasCyrillicOnly {
                fromLatin = hasLatinOnly
                source = .layoutOnlySymbols
            } else if hasLatinOnly {
                return unchanged
            } else if currentLayoutID == latin.id || currentLayoutID == cyrillic.id {
                // Only shared symbols: they were typed with the layout that is active now.
                fromLatin = currentLayoutID == latin.id
                source = .currentLayout
            } else {
                return unchanged
            }
        }

        let (from, to) = fromLatin ? (latin, cyrillic) : (cyrillic, latin)
        let mapping = from.mapping(to: to)
        let converted = String(text.map { mapping[$0] ?? $0 })
        return ConversionResult(converted: converted, targetLayoutID: to.id, source: source)
    }
}
