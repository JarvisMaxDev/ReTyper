import Foundation

/// Keyboard commands ReTyper sends to the focused field, like a user would.
enum EditingKey: Equatable {
    /// Cmd+Shift+Left: select from the caret to the start of the line.
    case selectToLineStart
    /// Shift+Right, repeated: shrink a leftward selection from its start.
    case shrinkSelectionFromStart(Int)
    /// Right: drop the selection, leaving the caret at its end, where it was.
    case collapseToEnd
}

/// A selection in UTF-16 units; length 0 is a plain caret.
struct TextSelection: Equatable {
    let location: Int
    let length: Int
}

/// Side effects of one replacement. The real host posts key presses and uses the pasteboard.
protocol ReplacementHost: AnyObject {
    /// The focused field's selection, or nil when the field does not tell.
    func selection() -> TextSelection?
    /// Waits briefly for a keyboard selection to settle; nil when the field does not tell.
    func settledSelectionLength(expected: Int?) -> Int?
    func isSecureField() -> Bool
    func press(_ key: EditingKey)
    /// Cmd+C. Returns nil when the pasteboard did not change, so older contents are never used.
    func copySelection() -> String?
    /// Cmd+V over the current selection.
    func paste(_ text: String)
    /// False once the user typed or another app became active.
    func contextIsUnchanged() -> Bool
}

enum ReplacementOutcome: Equatable {
    case replaced(targetLayoutID: String)
    /// Nothing was replaced; the reason is metadata for the log.
    case layoutOnly(reason: String)
}

/// The 0.9.0 replacement (select, copy, convert, paste) with the causes of its known bugs removed.
enum ReplacementFlow {
    static func run(host: ReplacementHost, onlyLastWord: Bool,
                    convert: (String) -> (converted: String, targetLayoutID: String?)) -> ReplacementOutcome {
        guard !host.isSecureField() else { return .layoutOnly(reason: "secure field") }

        let initialSelection = host.selection()
        if initialSelection == TextSelection(location: 0, length: 0) {
            return .layoutOnly(reason: "nothing before caret")
        }

        // Some editors copy the whole line when nothing is selected. That line used to be
        // mistaken for a user selection and duplicated, so a known caret is never copied.
        var text: String?
        if initialSelection?.length != 0 {
            if let copied = host.copySelection(), !copied.isEmpty {
                text = copied
            } else if initialSelection != nil {
                // A real selection that cannot be copied is left untouched.
                return .layoutOnly(reason: "selection not copyable")
            }
        }

        var ownSelection = false
        if text == nil {
            guard host.contextIsUnchanged() else { return .layoutOnly(reason: "context changed") }
            host.press(.selectToLineStart)
            let selected = host.settledSelectionLength(expected: nil)
            guard selected != 0 else { return .layoutOnly(reason: "nothing before caret") }
            guard let line = host.copySelection(), !line.isEmpty else {
                // The previous clipboard contents are never pasted instead.
                if selected != nil { host.press(.collapseToEnd) }
                return .layoutOnly(reason: "copy unavailable")
            }
            ownSelection = true
            text = line

            if onlyLastWord {
                let word = lastWord(in: line)
                guard !word.isEmpty else {
                    host.press(.collapseToEnd)
                    return .layoutOnly(reason: "no word")
                }
                let leading = line.count - word.count
                if leading > 0 {
                    host.press(.shrinkSelectionFromStart(leading))
                    if let length = host.settledSelectionLength(expected: word.utf16.count),
                       length != word.utf16.count {
                        host.press(.collapseToEnd)
                        return .layoutOnly(reason: "word selection mismatch")
                    }
                }
                text = word
            }
        }

        guard let source = text else { return .layoutOnly(reason: "no text") }
        let result = convert(source)
        guard let target = result.targetLayoutID, result.converted != source else {
            if ownSelection { host.press(.collapseToEnd) }
            return .layoutOnly(reason: "nothing to convert")
        }
        guard host.contextIsUnchanged() else { return .layoutOnly(reason: "context changed") }
        // Pasting replaces the selection. There is no separate delete step that could lose text.
        host.paste(result.converted)
        return .replaced(targetLayoutID: target)
    }

    /// The last whitespace-separated word with any whitespace after it. Letters on punctuation
    /// keys (ж, э, х, б, ю) stay inside the word, unlike with Option+Shift+Left.
    static func lastWord(in line: String) -> String {
        let characters = Array(line)
        var end = characters.count
        while end > 0, characters[end - 1].isWhitespace { end -= 1 }
        var start = end
        while start > 0, !characters[start - 1].isWhitespace { start -= 1 }
        guard start < end else { return "" }
        return String(characters[start...])
    }
}
