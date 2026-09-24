import XCTest
@testable import ReTyper

final class ReplacementFlowTests: XCTestCase {
    private final class FakeHost: ReplacementHost {
        var initialSelection: TextSelection?
        var settled: [Int?] = []
        var copies: [String?] = []
        var secure = false
        var steady = true
        private(set) var actions: [String] = []

        func selection() -> TextSelection? { initialSelection }
        func settledSelectionLength(expected: Int?) -> Int? { settled.isEmpty ? nil : settled.removeFirst() }
        func isSecureField() -> Bool { secure }
        func press(_ key: EditingKey) { actions.append("\(key)") }
        func copySelection() -> String? {
            actions.append("copy")
            return copies.isEmpty ? nil : copies.removeFirst()
        }
        func paste(_ text: String) { actions.append("paste \(text)") }
        func contextIsUnchanged() -> Bool { steady }
    }

    private let table = ["ghbdtn": "\u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}",
                         ",s": "\u{431}\u{44B}", "ult ,s": "\u{433}\u{434}\u{435} \u{431}\u{44B}"]

    private func run(_ host: FakeHost, onlyLastWord: Bool = false) -> ReplacementOutcome {
        ReplacementFlow.run(host: host, onlyLastWord: onlyLastWord) { text in
            self.table[text].map { ($0, "ru") } ?? (text, nil)
        }
    }

    func testCaretIsNeverCopiedSoLineCopyingEditorsCannotDuplicateText() {
        // OpenChamber copied the whole line on Cmd+C without a selection: `ghbdtпривет`.
        let host = FakeHost()
        host.initialSelection = TextSelection(location: 6, length: 0)
        host.settled = [6]
        host.copies = ["ghbdtn"]
        XCTAssertEqual(run(host), .replaced(targetLayoutID: "ru"))
        XCTAssertEqual(host.actions, ["selectToLineStart", "copy", "paste \u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}"])
    }

    func testUserSelectionIsPastedOverWithoutSeparateDeletion() {
        let host = FakeHost()
        host.initialSelection = TextSelection(location: 0, length: 6)
        host.copies = ["ghbdtn"]
        XCTAssertEqual(run(host), .replaced(targetLayoutID: "ru"))
        XCTAssertEqual(host.actions, ["copy", "paste \u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}"])
    }

    func testFieldWithoutSelectionInfoKeepsThe090Order() {
        let selected = FakeHost()
        selected.copies = ["ghbdtn"]
        XCTAssertEqual(run(selected), .replaced(targetLayoutID: "ru"))
        XCTAssertEqual(selected.actions, ["copy", "paste \u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}"])

        let caret = FakeHost()
        caret.copies = [nil, "ghbdtn"]
        XCTAssertEqual(run(caret), .replaced(targetLayoutID: "ru"))
        XCTAssertEqual(caret.actions, ["copy", "selectToLineStart", "copy",
                                       "paste \u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}"])
    }

    func testUnchangedPasteboardIsNeverPastedAsText() {
        // Terminal used to convert whatever was already on the clipboard.
        let known = FakeHost()
        known.initialSelection = TextSelection(location: 4, length: 0)
        known.settled = [4]
        known.copies = [nil]
        XCTAssertEqual(run(known), .layoutOnly(reason: "copy unavailable"))
        XCTAssertEqual(known.actions, ["selectToLineStart", "copy", "collapseToEnd"])

        let unknown = FakeHost()
        unknown.copies = [nil, nil]
        XCTAssertEqual(run(unknown), .layoutOnly(reason: "copy unavailable"))
        XCTAssertEqual(unknown.actions, ["copy", "selectToLineStart", "copy"])
    }

    func testEmptyFieldOrCaretAtLineStartOnlySwitchesLayout() {
        let empty = FakeHost()
        empty.initialSelection = TextSelection(location: 0, length: 0)
        XCTAssertEqual(run(empty), .layoutOnly(reason: "nothing before caret"))
        XCTAssertEqual(empty.actions, [])

        let lineStart = FakeHost()
        lineStart.initialSelection = TextSelection(location: 10, length: 0)
        lineStart.settled = [0]
        XCTAssertEqual(run(lineStart), .layoutOnly(reason: "nothing before caret"))
        XCTAssertEqual(lineStart.actions, ["selectToLineStart"])
    }

    func testSelectionThatCannotBeCopiedIsLeftUntouched() {
        let host = FakeHost()
        host.initialSelection = TextSelection(location: 0, length: 5)
        host.copies = [nil]
        XCTAssertEqual(run(host), .layoutOnly(reason: "selection not copyable"))
        XCTAssertEqual(host.actions, ["copy"])
    }

    func testWordModeKeepsLettersTypedOnPunctuationKeys() {
        let host = FakeHost()
        host.initialSelection = TextSelection(location: 6, length: 0)
        host.settled = [6, 2]
        host.copies = ["ult ,s"]
        XCTAssertEqual(run(host, onlyLastWord: true), .replaced(targetLayoutID: "ru"))
        XCTAssertEqual(host.actions, ["selectToLineStart", "copy", "shrinkSelectionFromStart(4)", "paste \u{431}\u{44B}"])
    }

    func testWordSelectionMismatchCancelsWithoutPasting() {
        let host = FakeHost()
        host.initialSelection = TextSelection(location: 6, length: 0)
        host.settled = [6, 3]
        host.copies = ["ult ,s"]
        XCTAssertEqual(run(host, onlyLastWord: true), .layoutOnly(reason: "word selection mismatch"))
        XCTAssertEqual(host.actions, ["selectToLineStart", "copy", "shrinkSelectionFromStart(4)", "collapseToEnd"])
    }

    func testNothingToConvertDropsOnlyReTypersOwnSelection() {
        let own = FakeHost()
        own.initialSelection = TextSelection(location: 5, length: 0)
        own.settled = [5]
        own.copies = ["hello"]
        XCTAssertEqual(run(own), .layoutOnly(reason: "nothing to convert"))
        XCTAssertEqual(own.actions, ["selectToLineStart", "copy", "collapseToEnd"])

        let user = FakeHost()
        user.initialSelection = TextSelection(location: 0, length: 5)
        user.copies = ["hello"]
        XCTAssertEqual(run(user), .layoutOnly(reason: "nothing to convert"))
        XCTAssertEqual(user.actions, ["copy"])
    }

    func testSecureFieldIsNeverTouched() {
        let host = FakeHost()
        host.secure = true
        host.initialSelection = TextSelection(location: 0, length: 6)
        XCTAssertEqual(run(host), .layoutOnly(reason: "secure field"))
        XCTAssertEqual(host.actions, [])
    }

    func testTypingOrSwitchingAppsDuringReplacementPreventsPaste() {
        let host = FakeHost()
        host.initialSelection = TextSelection(location: 0, length: 6)
        host.copies = ["ghbdtn"]
        host.steady = false
        XCTAssertEqual(run(host), .layoutOnly(reason: "context changed"))
        XCTAssertEqual(host.actions, ["copy"])
    }

    func testLastWordUsesWhitespaceOnly() {
        XCTAssertEqual(ReplacementFlow.lastWord(in: "ghbdtn"), "ghbdtn")
        XCTAssertEqual(ReplacementFlow.lastWord(in: "hello ghbdtn"), "ghbdtn")
        XCTAssertEqual(ReplacementFlow.lastWord(in: "hello ghbdtn  "), "ghbdtn  ")
        XCTAssertEqual(ReplacementFlow.lastWord(in: "vj;yj"), "vj;yj")
        XCTAssertEqual(ReplacementFlow.lastWord(in: "a\tb"), "b")
        XCTAssertEqual(ReplacementFlow.lastWord(in: "   "), "")
        XCTAssertEqual(ReplacementFlow.lastWord(in: ""), "")
    }
}
