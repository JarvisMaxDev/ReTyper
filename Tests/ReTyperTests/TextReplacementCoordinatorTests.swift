import ApplicationServices
import XCTest
@testable import ReTyper

final class TextReplacementCoordinatorTests: XCTestCase {
    private final class Clock {
        var time: TimeInterval = 1
        func pause(_ interval: TimeInterval) { time += interval }
    }

    private final class Access: TextAccessProviding {
        var target = TextAccessCapability(applicationPID: 123, activationPID: 123, element: AXUIElementCreateApplication(123),
                                          window: AXUIElementCreateApplication(124), elementRole: "AXTextArea",
                                          canSetValue: true, canSetSelection: true)
        var state = TextSnapshot(value: "ghbdtn tail", caretLocation: 6, selectionLength: 0, selectedText: "")
        var focused = true
        var reads = 0
        var selections: [Range<Int>] = []
        var onRead: (() throws -> Void)?
        var onSelect: (() throws -> Void)?
        var onFocus: (() -> Void)?
        var captureError: TextAccessError?
        var onCapture: (() -> Void)?
        var requestedApplicationPID: pid_t?
        var requestedActivationPID: pid_t?

        func captureCapability(applicationPID: pid_t, activationPID: pid_t, deadline: TimeInterval) throws -> TextAccessCapability {
            requestedApplicationPID = applicationPID
            requestedActivationPID = activationPID
            onCapture?()
            if let captureError { throw captureError }
            return target
        }
        func isFocused(_ target: TextAccessCapability, deadline: TimeInterval) throws -> Bool {
            onFocus?()
            return focused
        }
        func snapshot(_ target: TextAccessCapability, deadline: TimeInterval) throws -> TextSnapshot {
            reads += 1
            try onRead?()
            return state
        }
        func selectRange(_ range: Range<Int>, in target: TextAccessCapability, deadline: TimeInterval) throws {
            selections.append(range)
            try onSelect?()
            state = TextSnapshot(value: state.value, caretLocation: range.lowerBound, selectionLength: range.count, selectedText: nil)
        }
    }

    private final class Input: ReplacementInputProviding {
        var activityGeneration: UInt64 = 10
        var prepared: [String] = []
        var sent: [String] = []
        var states: [Int64: InputDelivery] = [:]
        var onSend: ((String) -> Void)?
        var onPrepare: (() -> Void)?
        var canPrepare = true
        var delayDelivery = false
        var cancelled: [Int64] = []
        var finished: [Int64] = []
        var targetPIDs: [pid_t] = []
        var activationPIDs: [pid_t] = []
        func prepare(_ text: String, targetPID: pid_t, activationPID: pid_t, generation: UInt64, deadline: TimeInterval) -> PreparedTextInput? {
            onPrepare?()
            guard canPrepare else { return nil }
            targetPIDs.append(targetPID)
            activationPIDs.append(activationPID)
            prepared.append(text)
            let id = Int64(prepared.count)
            states[id] = .queued
            return PreparedTextInput(id: id)
        }
        func send(_ input: PreparedTextInput) {
            let text = prepared[Int(input.id) - 1]
            sent.append(text)
            if !delayDelivery { states[input.id] = .handedOff; onSend?(text) }
        }
        func delivery(of input: PreparedTextInput) -> InputDelivery { states[input.id] ?? .handedOff }
        func cancel(_ input: PreparedTextInput) -> InputDelivery {
            cancelled.append(input.id)
            if states[input.id] == .queued { states[input.id] = .cancelled }
            return delivery(of: input)
        }
        func finish(_ input: PreparedTextInput) { finished.append(input.id) }
    }

    private let options = ReplacementOptions(applicationPID: 123, activationPID: 123, inputGeneration: 10, triggeredAt: 1, onlyLastWord: true, availableLayoutIDs: [])

    private func coordinator(_ access: Access, _ input: Input, _ clock: Clock) -> TextReplacementCoordinator {
        TextReplacementCoordinator(accessibility: access, input: input, now: { clock.time }, pause: clock.pause,
                                   convert: { text, _ in (text == "ghbdtn" ? "\u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}" : "converted", "target-layout") })
    }

    private func apply(_ text: String, to access: Access, keepSelection: Bool = false) {
        let old = access.state
        let range = old.caretLocation..<(old.caretLocation + old.selectionLength)
        let value = (old.value as NSString).replacingCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: text)
        access.state = TextSnapshot(value: value, caretLocation: keepSelection ? range.lowerBound : range.lowerBound + text.utf16.count,
                                    selectionLength: keepSelection ? text.utf16.count : 0, selectedText: keepSelection ? text : "")
    }

    func testReplacesOnlyTargetWordAndVerifiesCaret() {
        let access = Access(), input = Input(), clock = Clock()
        input.onSend = { self.apply($0, to: access) }
        let result = coordinator(access, input, clock).performReplacement(options)
        XCTAssertEqual(result.outcome, .replaced)
        XCTAssertEqual(result.targetLayoutID, "target-layout")
        XCTAssertEqual(access.state.value, "\u{43F}\u{440}\u{438}\u{432}\u{435}\u{442} tail")
        XCTAssertEqual(access.state.caretLocation, 6)
        XCTAssertEqual(input.sent.count, 1)
    }

    func testLineModePreservedForEditableFields() {
        let access = Access(), input = Input(), clock = Clock()
        access.state = TextSnapshot(value: "old\nfirst second tail", caretLocation: 16, selectionLength: 0, selectedText: "")
        input.onSend = { self.apply($0, to: access) }
        let allLine = ReplacementOptions(applicationPID: 123, activationPID: 123, inputGeneration: 10, triggeredAt: 1, onlyLastWord: false, availableLayoutIDs: [])
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(allLine).outcome, .replaced)
        XCTAssertEqual(access.state.value, "old\nconverted tail")
    }

    func testEmptyEditableFieldReturnsLayoutOnlyWithoutPreparingInputInBothModes() {
        for onlyLastWord in [true, false] {
            let access = Access(), input = Input(), clock = Clock()
            let empty = TextSnapshot(value: "", caretLocation: 0, selectionLength: 0, selectedText: "")
            access.state = empty
            let options = ReplacementOptions(applicationPID: 123, activationPID: 123, inputGeneration: 10,
                                             triggeredAt: 1, onlyLastWord: onlyLastWord, availableLayoutIDs: [])
            let sut = TextReplacementCoordinator(accessibility: access, input: input,
                                                 now: { clock.time }, pause: clock.pause,
                                                 convert: { _, _ in
                XCTFail("An empty field must not invoke conversion")
                return ("", nil)
            })

            let result = sut.performReplacement(options)

            XCTAssertEqual(result.outcome, .layoutOnly, "onlyLastWord=\(onlyLastWord)")
            XCTAssertNil(result.targetLayoutID)
            XCTAssertFalse(result.outcome.isFailure)
            XCTAssertEqual(access.requestedApplicationPID, 123)
            XCTAssertEqual(access.requestedActivationPID, 123)
            XCTAssertEqual(access.reads, 1)
            XCTAssertEqual(access.state, empty)
            XCTAssertTrue(access.selections.isEmpty)
            XCTAssertTrue(input.prepared.isEmpty)
            XCTAssertTrue(input.sent.isEmpty)
            XCTAssertTrue(input.states.isEmpty)
            XCTAssertNil(sut.recoveryOriginalText)
        }
    }

    func testReadOnlyTerminalIsNotAuthorizedToDelete() {
        let access = Access(), input = Input(), clock = Clock()
        access.target = TextAccessCapability(applicationPID: 123, activationPID: 123, element: access.target.element, window: access.target.window,
                                              elementRole: "AXTextArea", canSetValue: false, canSetSelection: true)
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.unsupportedField))
        XCTAssertTrue(input.sent.isEmpty)
        XCTAssertTrue(access.selections.isEmpty)
    }

    func testCapabilityErrorDoesNotChooseDestructiveFallback() {
        let access = Access(), input = Input(), clock = Clock()
        access.captureError = .system(-25204)
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.noTextAccess))
        XCTAssertTrue(input.prepared.isEmpty)
    }

    func testPayloadIsPreparedBeforeChangingSelection() {
        let access = Access(), input = Input(), clock = Clock()
        input.canPrepare = false
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.inputUnavailable))
        XCTAssertTrue(access.selections.isEmpty)
    }

    func testChangedFocusBeforeWriteDoesNotSend() {
        let access = Access(), input = Input(), clock = Clock()
        input.onPrepare = { access.focused = false }
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.contextChanged))
        XCTAssertTrue(input.sent.isEmpty)
    }

    func testUserSelectionRevalidatedEvenIfItAlreadyExists() {
        let access = Access(), input = Input(), clock = Clock()
        access.state = TextSnapshot(value: "ghbdtn tail", caretLocation: 0, selectionLength: 6, selectedText: "ghbdtn")
        input.onPrepare = { access.state = TextSnapshot(value: "ghbdtn tail", caretLocation: 6, selectionLength: 0, selectedText: "") }
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.contextChanged))
        XCTAssertTrue(input.sent.isEmpty)
    }

    func testInterveningUserInputAbortsBeforeSend() {
        let access = Access(), input = Input(), clock = Clock()
        access.onSelect = { input.activityGeneration += 1 }
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.contextChanged))
        XCTAssertTrue(input.sent.isEmpty)
    }

    func testInconsistentSnapshotIsRejected() {
        let access = Access(), input = Input(), clock = Clock()
        access.state = TextSnapshot(value: "ghbdtn tail", caretLocation: 0, selectionLength: 6, selectedText: "OTHER!")
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.invalidSnapshot))
        XCTAssertTrue(input.sent.isEmpty)
    }

    func testQueuedTimeoutCanBeCancelledWithoutRecovery() {
        let access = Access(), input = Input(), clock = Clock()
        input.delayDelivery = true
        let sut = coordinator(access, input, clock)
        XCTAssertEqual(sut.performReplacement(options).outcome, .aborted(.inputCancelled))
        XCTAssertNil(sut.recoveryOriginalText)
        XCTAssertEqual(input.states[1], .cancelled)
        XCTAssertEqual(input.sent.count, 1)
        XCTAssertEqual(access.state.caretLocation, 6)
        XCTAssertEqual(access.state.selectionLength, 0)
    }

    func testUnobservedDeliveredEventNeverCausesSecondInput() {
        let access = Access(), input = Input(), clock = Clock()
        let sut = coordinator(access, input, clock)
        XCTAssertEqual(sut.performReplacement(options).outcome, .needsRecovery)
        XCTAssertEqual(sut.recoveryOriginalText, "ghbdtn")
        XCTAssertEqual(input.sent.count, 1)
        XCTAssertEqual(sut.performReplacement(options).outcome, .aborted(.recoveryPending))
        XCTAssertEqual(input.sent.count, 1)
    }

    func testPartialInsertionKeepsOriginalWithoutGuessingARollback() {
        let access = Access(), input = Input(), clock = Clock()
        input.onSend = { _ in self.apply("\u{43F}", to: access) }
        let sut = coordinator(access, input, clock)
        XCTAssertEqual(sut.performReplacement(options).outcome, .needsRecovery)
        XCTAssertEqual(input.sent.count, 1)
        XCTAssertEqual(sut.recoveryOriginalText, "ghbdtn")
    }

    func testFocusChangeAfterDeliveryNeverRestoresIntoAnotherField() {
        let access = Access(), input = Input(), clock = Clock()
        input.onSend = { _ in access.focused = false }
        let sut = coordinator(access, input, clock)
        XCTAssertEqual(sut.performReplacement(options).outcome, .needsRecovery)
        XCTAssertEqual(input.sent.count, 1)
        XCTAssertEqual(sut.recoveryOriginalText, "ghbdtn")
    }

    func testConfirmedWholeReplacementWithWrongCaretCanBeRestoredOnce() {
        let access = Access(), input = Input(), clock = Clock()
        input.onSend = { self.apply($0, to: access, keepSelection: input.sent.count == 1) }
        let sut = coordinator(access, input, clock)
        XCTAssertEqual(sut.performReplacement(options).outcome, .restoredAfterFailure)
        XCTAssertEqual(input.sent.count, 2)
        XCTAssertEqual(access.state.value, "ghbdtn tail")
        XCTAssertNil(sut.recoveryOriginalText)
    }

    func testUnconfirmedRestorationIsNeverRetried() {
        let access = Access(), input = Input(), clock = Clock()
        input.onSend = { if input.sent.count == 1 { self.apply($0, to: access, keepSelection: true) } }
        let sut = coordinator(access, input, clock)
        XCTAssertEqual(sut.performReplacement(options).outcome, .needsRecovery)
        XCTAssertEqual(input.sent.count, 2)
        XCTAssertEqual(sut.recoveryOriginalText, "ghbdtn")
    }

    func testUnexpectedRepeatedTextIsNotDiffedAndRetyped() {
        let access = Access(), input = Input(), clock = Clock()
        access.state = TextSnapshot(value: "abab", caretLocation: 3, selectionLength: 0, selectedText: "")
        input.onSend = { _ in access.state = TextSnapshot(value: "ab", caretLocation: 1, selectionLength: 0, selectedText: "") }
        let sut = coordinator(access, input, clock)
        XCTAssertEqual(sut.performReplacement(options).outcome, .needsRecovery)
        XCTAssertEqual(sut.recoveryOriginalText, "aba")
        XCTAssertEqual(access.state.value, "ab")
        XCTAssertEqual(input.sent.count, 1)
    }

    func testBusyOperationDoesNotReenter() {
        let access = Access(), input = Input(), clock = Clock()
        let sut = coordinator(access, input, clock)
        input.onPrepare = { XCTAssertEqual(sut.performReplacement(self.options).outcome, .aborted(.busy)) }
        input.onSend = { self.apply($0, to: access) }
        XCTAssertEqual(sut.performReplacement(options).outcome, .replaced)
        XCTAssertEqual(input.sent.count, 1)
    }

    func testExplicitRecoveryClearDoesNotTypeAnything() {
        let access = Access(), input = Input(), clock = Clock()
        let sut = coordinator(access, input, clock)
        XCTAssertEqual(sut.performReplacement(options).outcome, .needsRecovery)
        XCTAssertTrue(sut.clearRecovery())
        XCTAssertNil(sut.recoveryOriginalText)
        XCTAssertEqual(input.sent.count, 1)
    }

    func testDeadlineIncludesTimeSpentReading() {
        let access = Access(), input = Input(), clock = Clock()
        access.onRead = { clock.time += 1 }
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.noTextAccess))
        XCTAssertTrue(input.sent.isEmpty)
    }

    func testTransientReadErrorAfterSelectionRestoresOriginalCaretWithoutTyping() {
        let access = Access(), input = Input(), clock = Clock()
        access.onSelect = {
            access.onRead = { access.onRead = nil; throw TextAccessError.system(-25204) }
        }
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.selectionNotEstablished))
        XCTAssertTrue(input.sent.isEmpty)
        XCTAssertEqual(access.state.caretLocation, 6)
        XCTAssertEqual(access.state.selectionLength, 0)
        XCTAssertEqual(access.state.value, "ghbdtn tail")
    }

    func testLateObservedSuccessDoesNotRollBackSuccessfulReplacement() {
        let access = Access(), input = Input(), clock = Clock()
        input.onSend = {
            self.apply($0, to: access)
            access.onRead = { access.onRead = nil; throw TextAccessError.system(-25204) }
        }
        let result = coordinator(access, input, clock).performReplacement(options)
        XCTAssertEqual(result.outcome, .replaced)
        XCTAssertEqual(result.targetLayoutID, "target-layout")
        XCTAssertEqual(input.sent.count, 1)
    }

    func testActivityDuringFinalFocusReadCannotConfirmSuccess() {
        let access = Access(), input = Input(), clock = Clock()
        input.onSend = {
            self.apply($0, to: access)
            access.onRead = {
                access.onRead = nil
                access.onFocus = { access.onFocus = nil; input.activityGeneration += 1 }
            }
        }
        let sut = coordinator(access, input, clock)
        XCTAssertEqual(sut.performReplacement(options).outcome, .needsRecovery)
        XCTAssertEqual(sut.recoveryOriginalText, "ghbdtn")
        XCTAssertEqual(input.sent.count, 1)
    }

    func testDeadlineDuringFinalFocusReadIsNotAcceptedAsConfirmation() {
        let access = Access(), input = Input(), clock = Clock()
        input.onSend = {
            self.apply($0, to: access)
            access.onRead = { access.onFocus = { clock.time += 1 } }
        }
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .needsRecovery)
        XCTAssertEqual(input.sent.count, 1)
    }

    func testQueuedFocusChangeKeepsContextChangedReason() {
        let access = Access(), input = Input(), clock = Clock()
        input.delayDelivery = true
        access.onRead = { if !input.sent.isEmpty { access.focused = false } }
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.contextChanged))
        XCTAssertEqual(input.states[1], .cancelled)
        XCTAssertEqual(input.sent.count, 1)
    }

    func testNonactivatingPanelReceivesInputInsteadOfActivationWitness() {
        let access = Access(), input = Input(), clock = Clock()
        access.target = TextAccessCapability(applicationPID: 456, activationPID: 123,
                                             element: AXUIElementCreateApplication(456), window: AXUIElementCreateApplication(456),
                                             elementRole: "AXTextField", canSetValue: true, canSetSelection: true)
        let overlay = ReplacementOptions(applicationPID: 456, activationPID: 123, inputGeneration: 10,
                                         triggeredAt: 1, onlyLastWord: true, availableLayoutIDs: [])
        input.onSend = { self.apply($0, to: access) }
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(overlay).outcome, .replaced)
        XCTAssertEqual(access.requestedApplicationPID, 456)
        XCTAssertEqual(access.requestedActivationPID, 123)
        XCTAssertEqual(input.targetPIDs, [456])
        XCTAssertEqual(input.activationPIDs, [123])
    }

    func testMismatchingActivationWitnessCannotAuthorizeInput() {
        let access = Access(), input = Input(), clock = Clock()
        access.target = TextAccessCapability(applicationPID: 123, activationPID: 456,
                                             element: access.target.element, window: access.target.window,
                                             elementRole: "AXTextField", canSetValue: true, canSetSelection: true)
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.contextChanged))
        XCTAssertTrue(input.sent.isEmpty)
    }

    func testExpiredOrInvalidHotkeyEvidenceIsNotUsed() {
        for timestamp in [0.0, 1.1, .nan, .infinity] {
            let access = Access(), input = Input(), clock = Clock()
            let stale = ReplacementOptions(applicationPID: 123, activationPID: 123, inputGeneration: 10,
                                           triggeredAt: timestamp, onlyLastWord: true, availableLayoutIDs: [])
            XCTAssertEqual(coordinator(access, input, clock).performReplacement(stale).outcome, .aborted(.contextChanged))
            XCTAssertNil(access.requestedApplicationPID)
            XCTAssertTrue(input.sent.isEmpty)
        }
    }

    func testCaptureCannotExtendHotkeyEvidenceLifetime() {
        let access = Access(), input = Input(), clock = Clock()
        clock.time = 1.29
        access.onCapture = { clock.time += 0.05 }
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(options).outcome, .aborted(.noTextAccess))
        XCTAssertEqual(access.reads, 0)
        XCTAssertTrue(access.selections.isEmpty)
        XCTAssertTrue(input.prepared.isEmpty)
    }

    func testActivityAfterHotkeyDecisionAbortsBeforeCapabilityCapture() throws {
        let access = Access(), input = Input(), clock = Clock()
        let gate = SyntheticInputGate(clock: { clock.time }, frontmostPID: { 123 })
        gate.resetTap(isEnabled: true)
        var stages = KeyboardEventStages()
        var decision = KeyboardEventStages.Decision.passThrough
        for (timestamp, flags): (CGEventTimestamp, CGEventFlags) in [(1, .maskAlternate), (2, [])] {
            let event = try XCTUnwrap(CGEvent(source: nil))
            event.type = .flagsChanged
            event.timestamp = timestamp
            event.flags = flags
            event.setIntegerValueField(.keyboardEventKeycode, value: 58)
            event.setIntegerValueField(.eventTargetUnixProcessID, value: 123)
            for stage in [KeyboardEventStages.Stage.session, .annotated] {
                decision = stages.handle(stage: stage, type: .flagsChanged, event: event, gate: gate,
                                         sessionEnabled: true, annotatedEnabled: true,
                                         modifier: .option, doubleTapMode: false, now: clock.time)
            }
        }
        guard case let .hotkey(recipientPID, generation, triggeredAt) = decision else {
            return XCTFail("Expected a matched hotkey before the intervening activation")
        }
        input.activityGeneration = gate.recordActivity()
        clock.time += 0.01
        let captured = ReplacementOptions(applicationPID: try XCTUnwrap(recipientPID), activationPID: 123,
                                          inputGeneration: generation, triggeredAt: triggeredAt,
                                          onlyLastWord: true, availableLayoutIDs: [])
        XCTAssertEqual(input.activityGeneration, generation + 1)
        XCTAssertEqual(triggeredAt, 1)
        XCTAssertEqual(coordinator(access, input, clock).performReplacement(captured).outcome, .aborted(.contextChanged))
        XCTAssertNil(access.requestedApplicationPID)
        XCTAssertEqual(access.reads, 0)
        XCTAssertTrue(access.selections.isEmpty)
        XCTAssertTrue(input.prepared.isEmpty)
        XCTAssertTrue(input.sent.isEmpty)
        XCTAssertEqual(access.state.value, "ghbdtn tail")
    }

    func testT041SC002MatrixEvaluates100InitialOperations() {
        // Rows map to SC-002 in specs/001-fix-retype-text-replacement/quickstart.md.
        // Mock-only acceptance harness, not evidence of live application delivery.
        let rows = ["N1", "N2", "N3", "N4", "N5", "F1", "F2", "F3", "F4", "F5"]
        let converted = "\u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}"
        var initialOperations = 0
        var blockedRetries = 0

        for row in rows {
            var rowEvaluated = 0
            var rowBlockedRetries = 0
            for iteration in 1...10 {
                let label = "T041 SC-002 \(row) iteration \(iteration)"
                let access = Access(), input = Input(), clock = Clock()
                let sut = coordinator(access, input, clock)
                defer { input.onSend = nil; access.onRead = nil }
                var scenarioOptions = options
                var expectedOutcome: ReplacementOutcome = .replaced
                var expectedValue = converted + " tail"
                var expectedRange = 6..<6
                var expectedSent = [converted]
                var lateReadFailures = 0
                input.onSend = { self.apply($0, to: access) }

                switch row {
                case "N1":
                    break
                case "N2":
                    access.state = TextSnapshot(value: "old\nfirst second tail", caretLocation: 16,
                                                selectionLength: 0, selectedText: "")
                    scenarioOptions = ReplacementOptions(applicationPID: 123, activationPID: 123, inputGeneration: 10,
                                                         triggeredAt: 1, onlyLastWord: false, availableLayoutIDs: [])
                    expectedValue = "old\nconverted tail"
                    expectedRange = 13..<13
                    expectedSent = ["converted"]
                case "N3":
                    access.state = TextSnapshot(value: "prefix ghbdtn suffix", caretLocation: 7,
                                                selectionLength: 6, selectedText: "ghbdtn")
                    expectedValue = "prefix " + converted + " suffix"
                    expectedRange = 13..<13
                case "N4":
                    let prefix = "\u{1F1FA}\u{1F1E6} e\u{301}\r\n"
                    let fragment = "\u{1F469}\u{200D}\u{1F4BB}a\u{308}"
                    let suffix = " \u{1F44D}\u{1F3FD} o\u{308}\r\n"
                    access.state = TextSnapshot(value: prefix + fragment + suffix,
                                                caretLocation: prefix.utf16.count + fragment.utf16.count,
                                                selectionLength: 0, selectedText: "")
                    expectedValue = prefix + "converted" + suffix
                    let caret = prefix.utf16.count + "converted".utf16.count
                    expectedRange = caret..<caret
                    expectedSent = ["converted"]
                case "N5":
                    input.onSend = {
                        self.apply($0, to: access)
                        access.onRead = {
                            access.onRead = nil
                            lateReadFailures += 1
                            throw TextAccessError.system(-25204)
                        }
                    }
                case "F1":
                    input.delayDelivery = true
                    expectedOutcome = .aborted(.inputCancelled)
                    expectedValue = "ghbdtn tail"
                case "F2":
                    input.onSend = nil
                    expectedOutcome = .needsRecovery
                    expectedValue = "ghbdtn tail"
                    expectedRange = 0..<6
                case "F3":
                    input.onSend = { _ in self.apply("\u{43F}", to: access) }
                    expectedOutcome = .needsRecovery
                    expectedValue = "\u{43F} tail"
                    expectedRange = 1..<1
                case "F4":
                    input.onSend = { _ in access.focused = false }
                    expectedOutcome = .needsRecovery
                    expectedValue = "ghbdtn tail"
                    expectedRange = 0..<6
                case "F5":
                    input.onSend = {
                        if input.sent.count == 1 { self.apply($0, to: access, keepSelection: true) }
                    }
                    expectedOutcome = .needsRecovery
                    expectedRange = 0..<6
                    expectedSent = [converted, "ghbdtn"]
                default:
                    XCTFail("\(label): unmapped SC-002 row")
                    continue
                }

                let result = sut.performReplacement(scenarioOptions)
                initialOperations += 1
                let expectsRecovery = expectedOutcome == .needsRecovery
                XCTAssertEqual(result.outcome, expectedOutcome, "\(label): initial outcome")
                XCTAssertEqual(result.targetLayoutID, expectedOutcome == .replaced ? "target-layout" : nil,
                               "\(label): confirmed layout")
                XCTAssertEqual(Array(access.state.value.utf16), Array(expectedValue.utf16), "\(label): exact full UTF-16 value")
                XCTAssertEqual(access.state.caretLocation, expectedRange.lowerBound, "\(label): caret/selection start")
                XCTAssertEqual(access.state.selectionLength, expectedRange.count, "\(label): selection length")
                // The mock records submissions, including F1's queued input that never reaches handedOff.
                XCTAssertEqual(input.sent.count, expectedSent.count, "\(label): initial operation send count")
                XCTAssertEqual(input.sent, expectedSent, "\(label): exact payloads, no guessed rollback")
                XCTAssertEqual(input.states[1], row == "F1" ? .cancelled : .handedOff, "\(label): first delivery state")
                XCTAssertEqual(sut.recoveryOriginalText, expectsRecovery ? "ghbdtn" : nil, "\(label): exact recovery original")
                if row == "N5" {
                    XCTAssertEqual(lateReadFailures, 1, "\(label): transient read failure precedes late confirmation")
                }
                if row == "F1" {
                    XCTAssertGreaterThanOrEqual(clock.time, 1.3, "\(label): queued input reaches deadline")
                    XCTAssertTrue(input.cancelled.contains(1), "\(label): queued input cancellation requested")
                }
                if row == "F4" {
                    XCTAssertFalse(access.focused, "\(label): focus changed after handoff")
                }
                if row == "F5" {
                    XCTAssertEqual(input.states[2], .handedOff, "\(label): sole restore handed off but unconfirmed")
                    XCTAssertLessThanOrEqual(input.sent.count, 2, "\(label): at most one authorized restore")
                }

                if expectsRecovery {
                    let beforeRetry = access.state
                    let readsBeforeRetry = access.reads
                    let selectionsBeforeRetry = access.selections
                    let preparedBeforeRetry = input.prepared
                    // Fresh hotkey evidence makes this a separate retry, not one of the 100 initial operations.
                    let retryOptions = ReplacementOptions(applicationPID: 123, activationPID: 123,
                                                          inputGeneration: input.activityGeneration, triggeredAt: clock.time,
                                                          onlyLastWord: true, availableLayoutIDs: [])
                    let retry = sut.performReplacement(retryOptions)
                    blockedRetries += 1
                    rowBlockedRetries += 1
                    XCTAssertEqual(retry.outcome, .aborted(.recoveryPending), "\(label): deliberate blocked retry outcome")
                    XCTAssertNil(retry.targetLayoutID, "\(label): blocked retry cannot confirm a layout")
                    XCTAssertEqual(input.sent.count, expectedSent.count, "\(label): blocked retry adds no sends or restore attempts")
                    XCTAssertEqual(input.sent, expectedSent, "\(label): blocked retry leaves payloads unchanged")
                    XCTAssertEqual(input.prepared, preparedBeforeRetry, "\(label): blocked retry prepares no input")
                    XCTAssertEqual(access.reads, readsBeforeRetry, "\(label): blocked retry reads no field")
                    XCTAssertEqual(access.selections, selectionsBeforeRetry, "\(label): blocked retry selects no field")
                    XCTAssertEqual(Array(access.state.value.utf16), Array(beforeRetry.value.utf16), "\(label): blocked retry preserves full value")
                    XCTAssertEqual(access.state.caretLocation, beforeRetry.caretLocation, "\(label): blocked retry preserves caret")
                    XCTAssertEqual(access.state.selectionLength, beforeRetry.selectionLength, "\(label): blocked retry preserves range")
                    XCTAssertEqual(sut.recoveryOriginalText, "ghbdtn", "\(label): blocked retry retains exact original")
                }
                rowEvaluated += 1
            }
            XCTAssertEqual(rowEvaluated, 10, "T041 SC-002 \(row): initial operation evaluations")
            XCTAssertEqual(rowBlockedRetries, ["F2", "F3", "F4", "F5"].contains(row) ? 10 : 0,
                           "T041 SC-002 \(row): retries excluded from initial operations")
            print("T041 SC-002 \(row): evaluated=\(rowEvaluated)/10 initial operations; blocked retries=\(rowBlockedRetries) (excluded). Counts only; XCTest assertions determine status.")
        }
        XCTAssertEqual(initialOperations, 100, "T041 SC-002: exactly 100 initial operations")
        XCTAssertEqual(blockedRetries, 40, "T041 SC-002: 40 deliberate blocked retries, excluded from the 100 initial operations")
        print("T041 SC-002 totals: initial operations=\(initialOperations)/100; blocked retries=\(blockedRetries)/40 (excluded). Counts only; XCTest assertions determine status.")
    }
}
