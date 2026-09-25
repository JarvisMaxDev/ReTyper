import Carbon

/// Writing system of a letter or of a whole keyboard layout.
enum Script {
    case latin
    case cyrillic
    case other

    /// The script of a letter; nil for anything that is not a Latin or Cyrillic letter.
    static func of(_ character: Character) -> Script? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x0400...0x04FF:
            return .cyrillic
        case 0x41...0x5A, 0x61...0x7A:
            return .latin
        case 0xD7, 0xF7: // × and ÷ sit inside the Latin-1 letter block
            return nil
        case 0xC0...0x024F:
            return .latin
        default:
            return nil
        }
    }
}

/// Physical keyboard type. It decides which keys exist: macOS describes keys a keyboard lacks.
enum KeyboardKind: Equatable {
    case ansi
    case iso
    case jis

    init(keyboardType: UInt32) {
        switch KBGetLayoutType(Int16(truncatingIfNeeded: keyboardType)) {
        case UInt32(kKeyboardISO): self = .iso
        case UInt32(kKeyboardJIS): self = .jis
        default: self = .ansi
        }
    }

    /// Printable keys of the main block: codes 0...50 without Return, Tab and Space,
    /// plus § (10) on ISO and ¥/_ (93, 94) on JIS.
    var keyCodes: [UInt16] {
        let main = (0...50).filter { ![10, 36, 48, 49].contains($0) }.map(UInt16.init)
        switch self {
        case .ansi: return main
        case .iso: return main + [10]
        case .jis: return main + [93, 94]
        }
    }
}

/// One physical key in one Shift state.
struct KeyStroke: Hashable, Comparable {
    let keyCode: UInt16
    let shift: Bool

    /// Unshifted keys first, then by key code. Decides which key wins a collision.
    static func < (lhs: KeyStroke, rhs: KeyStroke) -> Bool {
        if lhs.shift != rhs.shift { return !lhs.shift }
        return lhs.keyCode < rhs.keyCode
    }
}

/// What every key of one layout prints on one keyboard type. The only source of mappings.
struct KeyLayout {
    let id: String
    let keys: [KeyStroke: Character]

    /// Majority of the letters on unshifted keys.
    var script: Script {
        var latin = 0
        var cyrillic = 0
        for (key, character) in keys where !key.shift {
            switch Script.of(character) {
            case .latin: latin += 1
            case .cyrillic: cyrillic += 1
            default: break
            }
        }
        if latin > cyrillic { return .latin }
        if cyrillic > latin { return .cyrillic }
        return .other
    }

    var characters: Set<Character> { Set(keys.values) }

    /// Character of this layout → character of the same key in `target`. When several keys
    /// print the same character, the first key in `KeyStroke` order wins.
    func mapping(to target: KeyLayout) -> [Character: Character] {
        var result: [Character: Character] = [:]
        for key in keys.keys.sorted() {
            guard let source = keys[key], result[source] == nil, let mapped = target.keys[key] else { continue }
            result[source] = mapped
        }
        return result
    }
}

extension KeyLayout {
    /// Reads the layout from macOS. Nil when the input source is missing or has no key layout
    /// data (input methods). Main thread only, like every Text Input Sources call.
    static func system(id: String, keyboardType: UInt32) -> KeyLayout? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first,
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var keys: [KeyStroke: Character] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            for code in KeyboardKind(keyboardType: keyboardType).keyCodes {
                for shift in [false, true] {
                    if let character = printedCharacter(layout, code: code, shift: shift, keyboardType: keyboardType) {
                        keys[KeyStroke(keyCode: code, shift: shift)] = character
                    }
                }
            }
        }
        return KeyLayout(id: id, keys: keys)
    }

    /// The single printable character of a key; dead keys print their own symbol.
    private static func printedCharacter(_ layout: UnsafePointer<UCKeyboardLayout>, code: UInt16, shift: Bool,
                                         keyboardType: UInt32) -> Character? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        let modifiers = shift ? UInt32(shiftKey >> 8) : 0
        // The mask, not kUCKeyTranslateNoDeadKeysBit: that constant is the bit index (0).
        let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, keyboardType,
                                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                                    buffer.count, &length, &buffer)
        let text = String(utf16CodeUnits: buffer, count: length)
        guard status == noErr, text.count == 1, let character = text.first, !character.isWhitespace,
              character.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else { return nil }
        return character
    }
}
