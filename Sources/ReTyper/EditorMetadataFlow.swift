import Foundation

enum EditorCopy: Equatable {
    /// A fresh, model-confirmed, single selection. Never a whole-line copy from a caret.
    case selection(String)
    case empty
    case unavailable
}

protocol EditorMetadataHost: AnyObject {
    func isSecureField() -> Bool
    func contextIsUnchanged() -> Bool
    func press(_ key: EditingKey)
    func copyEditorSelection() -> EditorCopy
    func pasteEditorText(_ text: String) -> Bool
}

/// Bounded copy probes for a verified VS Code editor. All other fields use the existing flow.
enum EditorMetadataFlow {
    static func run(host: EditorMetadataHost, onlyLastWord: Bool,
                    convert: (String) -> (converted: String, targetLayoutID: String?)) -> ReplacementOutcome {
        func steady() -> Bool { host.contextIsUnchanged() && !host.isSecureField() }
        func copy() -> EditorCopy { steady() ? host.copyEditorSelection() : .unavailable }
        func collapse() { if steady() { host.press(.collapseToEnd) } }

        guard !host.isSecureField() else { return .layoutOnly(reason: "secure field") }
        guard steady() else { return .layoutOnly(reason: "context changed") }
        var result = copy()
        guard steady() else { return .layoutOnly(reason: "context changed") }
        var ownSelection = false
        if result == .empty {
            host.press(.selectToLineStart)
            result = copy()
            guard steady() else { return .layoutOnly(reason: "context changed") }
            ownSelection = true
        }
        let source: String
        switch result {
        case .empty: return .layoutOnly(reason: "editor: nothing selected")
        case .unavailable: return .layoutOnly(reason: "editor: copy unverified")
        case .selection(let text): source = text
        }
        guard !source.isEmpty else { return .layoutOnly(reason: "editor: empty copy") }
        var text = source
        if ownSelection, onlyLastWord {
            let word = ReplacementFlow.lastWord(in: source)
            guard !word.isEmpty else { collapse(); return .layoutOnly(reason: "editor: no word") }
            let leading = source.count - word.count
            if leading > 0 {
                guard steady() else { return .layoutOnly(reason: "context changed") }
                host.press(.shrinkSelectionFromStart(leading))
                let confirmed = copy()
                guard steady() else { return .layoutOnly(reason: "context changed") }
                guard case .selection(let actual) = confirmed else {
                    return .layoutOnly(reason: "editor: copy unverified")
                }
                guard actual == word else { collapse(); return .layoutOnly(reason: "editor: word selection mismatch") }
            }
            text = word
        }
        let converted = convert(text)
        guard let target = converted.targetLayoutID, converted.converted != text else {
            if ownSelection { collapse() }
            return .layoutOnly(reason: "nothing to convert")
        }
        guard steady() else { return .layoutOnly(reason: "context changed") }
        guard host.pasteEditorText(converted.converted) else { return .layoutOnly(reason: "editor: paste cancelled") }
        return .replaced(targetLayoutID: target)
    }
}
