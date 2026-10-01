import Cocoa
import Carbon

/// A bounded suffix of directly typed, single-scalar characters. Never persisted or logged.
struct TypedFragment {
    static let maximumLength = 256
    private(set) var text = ""
    private(set) var isSuspended = false
    private(set) var generation = 0

    mutating func append(_ character: Character) {
        generation &+= 1
        guard !isSuspended else { return }
        guard text.count < Self.maximumLength else { suspend(); return }
        text.append(character)
    }
    mutating func deleteBackward() {
        generation &+= 1
        if !isSuspended, !text.isEmpty { text.removeLast() }
    }
    mutating func reset() {
        generation &+= 1
        text = ""; isSuspended = false
    }
    mutating func suspend() {
        generation &+= 1
        text = ""; isSuspended = true
    }
    @discardableResult mutating func replaceTail(count: Int, with replacement: String) -> Bool {
        guard !isSuspended, count >= 0, count <= text.count, replacement.count == count else { return false }
        text = String(text.dropLast(count)) + replacement
        generation &+= 1
        return true
    }
}

enum TerminalKey: Equatable {
    case character(Character), backspace, reset, suspend

    static func classify(code: UInt16, flags: CGEventFlags, layout: KeyLayout?) -> TerminalKey {
        if !flags.intersection([.maskCommand, .maskControl]).isEmpty { return .reset }
        // Boundaries reset even when the selected input source has no keyboard table.
        if [36, 76, 48, 53, 117, 123, 124, 125, 126, 115, 119, 116, 121, 122, 83].contains(code) { return .reset }
        if flags.contains(.maskSecondaryFn) { return .reset }
        if code == 51, flags.contains(.maskAlternate) { return .reset }
        if !flags.intersection([.maskAlternate, .maskAlphaShift]).isEmpty { return .suspend }
        guard let layout else { return .suspend }
        if code == 49 { return .character(" ") }
        if code == 51 { return .backspace }
        let stroke = KeyStroke(keyCode: code, shift: flags.contains(.maskShift))
        if layout.deadKeys.contains(stroke) { return .suspend }
        guard let character = layout.keys[stroke] else { return .reset }
        // A dead/composed sequence is not equivalent to one backward-delete operation.
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
              !CharacterSet.nonBaseCharacters.contains(scalar), scalar.value >= 0x20, scalar.value != 0x7F
        else { return .suspend }
        return .character(character)
    }
}

struct TerminalEdit {
    let deleteCount: Int
    let insert: String
    let targetLayoutID: String
}

enum TerminalReplacement {
    static let supportedBundleIDs: Set<String> = ["com.apple.Terminal"]

    static func edit(fragment: TypedFragment, onlyLastWord: Bool,
                     convert: (String) -> (converted: String, targetLayoutID: String?)) -> TerminalEdit? {
        guard !fragment.isSuspended, !fragment.text.isEmpty else { return nil }
        let text = onlyLastWord ? ReplacementFlow.lastWord(in: fragment.text) : fragment.text
        guard !text.isEmpty else { return nil }
        let result = convert(text)
        guard let target = result.targetLayoutID, result.converted != text,
              result.converted.count == text.count,
              result.converted.allSatisfy({ c in
                  c.unicodeScalars.count == 1 && c.unicodeScalars.allSatisfy {
                      $0.value >= 0x20 && $0.value != 0x7F && !CharacterSet.nonBaseCharacters.contains($0)
                  }
              }) else { return nil }
        return TerminalEdit(deleteCount: text.count, insert: result.converted, targetLayoutID: target)
    }
}
