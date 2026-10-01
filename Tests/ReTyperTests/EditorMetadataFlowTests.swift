import XCTest
@testable import ReTyper

final class EditorMetadataFlowTests: XCTestCase {
    private final class Host: EditorMetadataHost {
        var copies: [EditorCopy] = []
        var actions: [String] = []
        var steady = true
        var secure = false
        var cancelAfterCopy = false
        var cancelAfterPress = false
        var secureAfterCopy = false
        var acceptPaste = true
        func isSecureField() -> Bool { secure }
        func contextIsUnchanged() -> Bool { steady }
        func press(_ key: EditingKey) {
            actions.append("\(key)")
            if cancelAfterPress { steady = false }
        }
        func copyEditorSelection() -> EditorCopy {
            actions.append("copy")
            if cancelAfterCopy { steady = false }
            if secureAfterCopy { secure = true }
            return copies.isEmpty ? .unavailable : copies.removeFirst()
        }
        func pasteEditorText(_ text: String) -> Bool { actions.append("paste \(text)"); return acceptPaste }
    }
    private func run(_ host: Host, word: Bool = false) -> ReplacementOutcome {
        EditorMetadataFlow.run(host: host, onlyLastWord: word) {
            $0 == "ghbdtn" ? ("привет", "ru") : ($0, nil)
        }
    }
    func testPartialUserSelectionIsNeverExpandedEvenInWordMode() {
        for word in [false, true] {
            let host = Host(); host.copies = [.selection("ghbdtn")]
            XCTAssertEqual(run(host, word: word), .replaced(targetLayoutID: "ru"))
            XCTAssertEqual(host.actions, ["copy", "paste привет"])
        }
    }
    func testLineCopyIsDiscardedAndOnlyFreshSelectionIsConverted() {
        let host = Host(); host.copies = [.empty, .selection("ghbdtn")]
        XCTAssertEqual(run(host), .replaced(targetLayoutID: "ru"))
        XCTAssertEqual(host.actions, ["copy", "selectToLineStart", "copy", "paste привет"])
    }
    func testStartOfLineNeverPastesAndNeverMovesCaretRight() {
        let host = Host(); host.copies = [.empty, .empty]
        XCTAssertEqual(run(host), .layoutOnly(reason: "editor: nothing selected"))
        XCTAssertEqual(host.actions, ["copy", "selectToLineStart", "copy"])
    }
    func testMissingMetadataNeverFallsBackToBlindCopyOrPaste() {
        let host = Host(); host.copies = [.unavailable]
        XCTAssertEqual(run(host), .layoutOnly(reason: "editor: copy unverified"))
        XCTAssertEqual(host.actions, ["copy"])
        let own = Host(); own.copies = [.empty, .unavailable]
        XCTAssertEqual(run(own), .layoutOnly(reason: "editor: copy unverified"))
        XCTAssertEqual(own.actions, ["copy", "selectToLineStart", "copy"])
    }
    func testContextChangeAndSecureInputPreventFurtherCommands() {
        let host = Host(); host.copies = [.selection("ghbdtn")]; host.cancelAfterCopy = true
        XCTAssertEqual(run(host), .layoutOnly(reason: "context changed"))
        XCTAssertEqual(host.actions, ["copy"])
        let secure = Host(); secure.secure = true
        XCTAssertEqual(run(secure), .layoutOnly(reason: "secure field"))
        XCTAssertTrue(secure.actions.isEmpty)
    }

    func testContextChangeAfterSelectingPreventsCopyAndCleanupInNewField() {
        let host = Host(); host.copies = [.empty, .selection("ghbdtn")]; host.cancelAfterPress = true
        XCTAssertEqual(run(host), .layoutOnly(reason: "context changed"))
        XCTAssertEqual(host.actions, ["copy", "selectToLineStart"])
    }

    func testSecureInputStartingDuringCopyPreventsPaste() {
        let host = Host(); host.copies = [.selection("ghbdtn")]; host.secureAfterCopy = true
        XCTAssertEqual(run(host), .layoutOnly(reason: "context changed"))
        XCTAssertEqual(host.actions, ["copy"])
    }
    func testLastWordIsRecopiedAndComparedBeforePasting() {
        let host = Host(); host.copies = [.empty, .selection("hello ghbdtn"), .selection("ghbdtn")]
        XCTAssertEqual(run(host, word: true), .replaced(targetLayoutID: "ru"))
        XCTAssertEqual(host.actions, ["copy", "selectToLineStart", "copy", "shrinkSelectionFromStart(6)", "copy", "paste привет"])
        let mismatch = Host(); mismatch.copies = [.empty, .selection("hello ghbdtn"), .selection("wrong")]
        XCTAssertEqual(run(mismatch, word: true), .layoutOnly(reason: "editor: word selection mismatch"))
        XCTAssertEqual(mismatch.actions.last, "collapseToEnd")
    }
    func testOnlyKnownOwnSelectionIsCollapsedWhenUnchanged() {
        let user = Host(); user.copies = [.selection("123")]
        _ = run(user); XCTAssertEqual(user.actions, ["copy"])
        let own = Host(); own.copies = [.empty, .selection("123")]
        _ = run(own); XCTAssertEqual(own.actions.last, "collapseToEnd")
    }
    func testHostRefusalIsNotReportedAsReplacement() {
        let host = Host(); host.copies = [.selection("ghbdtn")]; host.acceptPaste = false
        XCTAssertEqual(run(host), .layoutOnly(reason: "editor: paste cancelled"))
    }

    func testEditorGateDoesNotAdmitTerminalOrUnknownFields() {
        XCTAssertTrue(EditorFocusContext.supported(role: "AXTextArea", classes: ["native-edit-context"]))
        XCTAssertTrue(EditorFocusContext.supported(role: "AXTextArea", classes: ["inputarea", "monaco-mouse-cursor-text"]))
        XCTAssertFalse(EditorFocusContext.supported(role: "AXTextField", classes: ["xterm-helper-textarea"]))
        XCTAssertFalse(EditorFocusContext.supported(role: "AXTextArea", classes: ["xterm-helper-textarea"]))
        XCTAssertFalse(EditorFocusContext.supported(role: "AXTextArea", classes: nil))
        XCTAssertFalse(EditorFocusContext.supported(role: nil, classes: ["native-edit-context"]))
    }

    func testUserClipboardShortcutsAreDistinguishedFromPasteAndTyping() {
        XCTAssertTrue(KeyboardMonitor.isClipboardShortcut(keyCode: 8, flags: .maskCommand))
        XCTAssertTrue(KeyboardMonitor.isClipboardShortcut(keyCode: 7, flags: .maskCommand))
        XCTAssertTrue(KeyboardMonitor.isClipboardShortcut(keyCode: 8, flags: [.maskCommand, .maskShift]))
        XCTAssertFalse(KeyboardMonitor.isClipboardShortcut(keyCode: 8, flags: []))
        XCTAssertFalse(KeyboardMonitor.isClipboardShortcut(keyCode: 8, flags: .maskControl))
        XCTAssertFalse(KeyboardMonitor.isClipboardShortcut(keyCode: 9, flags: .maskCommand))
    }
}
