import CoreGraphics
import XCTest
@testable import ReTyper

final class SyntheticInputGateTests: XCTestCase {
    private var now: TimeInterval = 100
    private var frontmost: pid_t? = 42
    private var gate: SyntheticInputGate!

    override func setUp() {
        super.setUp()
        now = 100
        frontmost = 42
        gate = SyntheticInputGate(clock: { [unowned self] in self.now },
                                  frontmostPID: { [unowned self] in self.frontmost })
        gate.resetTap(isEnabled: true)
    }

    private func prepare(_ text: String = "text", targetPID: pid_t = 42,
                         activationPID: pid_t = 42) throws -> PreparedTextInput {
        try XCTUnwrap(gate.prepare(text, targetPID: targetPID, activationPID: activationPID,
                                  generation: gate.activityGeneration, deadline: 101))
    }

    private func submit(targetPID: pid_t = 42, activationPID: pid_t = 42) throws -> PreparedTextInput {
        let input = try prepare(targetPID: targetPID, activationPID: activationPID)
        XCTAssertNotNil(gate.takeSignals(for: input))
        return input
    }

    private func assertDrop(_ decision: SyntheticInputGate.Decision,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case .drop = decision else {
            return XCTFail("Expected a dropped event", file: file, line: line)
        }
    }

    @discardableResult
    private func assertRoute(_ decision: SyntheticInputGate.Decision, type: CGEventType, token: Int64,
                             targetPID: pid_t = 42,
                             file: StaticString = #filePath, line: UInt = #line) -> CGEvent? {
        guard case let .route(event, pid) = decision else {
            XCTFail("Expected process-targeted routing", file: file, line: line)
            return nil
        }
        XCTAssertEqual(pid, targetPID, file: file, line: line)
        XCTAssertEqual(event.type, type, file: file, line: line)
        XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), token, file: file, line: line)
        return event
    }

    private func unicode(_ event: CGEvent) -> [UniChar] {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        var units = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        XCTAssertEqual(length, units.count)
        return units
    }

    func testPayloadRoundTripsExactUTF16WithoutPosting() throws {
        for text in ["plain", "\u{043F}\u{0440}\u{0438}\u{0432}\u{0456}\u{0442}",
                     "e\u{0301}", "\u{00E9}", "\u{212B}", "a\u{0323}\u{0301}",
                     "\u{1F642}", "\u{1F1FA}\u{1F1E6}", "\u{1F469}\u{200D}\u{1F4BB}", "a\0b\r\n\t"] {
            let payload = try XCTUnwrap(SyntheticTextPayload.make(text))
            XCTAssertEqual(payload.down.type, .keyDown)
            XCTAssertEqual(payload.up.type, .keyUp)
            for event in [payload.down, payload.up] {
                XCTAssertEqual(unicode(event), Array(text.utf16))
                XCTAssertTrue(event.flags.isEmpty)
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 0)
            }
        }
    }

    func testPayloadRejectsEmptyAndOversizedUTF16BeforePreparingTicket() {
        for text in ["", String(repeating: "a", count: 4097), String(repeating: "\u{1F642}", count: 2049)] {
            XCTAssertNil(SyntheticTextPayload.make(text))
            XCTAssertNil(gate.prepare(text, targetPID: 42, activationPID: 42,
                                      generation: gate.activityGeneration, deadline: 101))
        }
        XCTAssertEqual(gate.pendingTicketCount, 0)
    }

    func testMaximumPayloadIsEitherExactOrSafelyRejectedByPlatform() {
        let text = String(repeating: "\u{1F642}", count: SyntheticTextPayload.maximumUTF16Length / 2)
        if let payload = SyntheticTextPayload.make(text) {
            XCTAssertEqual(unicode(payload.down), Array(text.utf16))
            XCTAssertEqual(unicode(payload.up), Array(text.utf16))
        } else {
            XCTAssertNil(gate.prepare(text, targetPID: 42, activationPID: 42,
                                      generation: gate.activityGeneration, deadline: 101))
            XCTAssertEqual(gate.pendingTicketCount, 0)
        }
    }

    func testSendConsumesOnlyInertSignalsAndDoesNotClaimDelivery() throws {
        let input = try prepare()
        let signals = try XCTUnwrap(gate.takeSignals(for: input))
        XCTAssertEqual(signals.down.type, .null)
        XCTAssertEqual(signals.up.type, .null)
        XCTAssertEqual(signals.down.getIntegerValueField(.eventSourceUserData), input.id)
        XCTAssertEqual(signals.up.getIntegerValueField(.eventSourceUserData), input.id + 1)
        XCTAssertTrue(unicode(signals.down).isEmpty)
        XCTAssertTrue(unicode(signals.up).isEmpty)
        XCTAssertEqual(gate.delivery(of: input), .queued)
        XCTAssertNil(gate.takeSignals(for: input))
    }

    func testOverlayRoutesToRecipientRegardlessOfInertSignalTargetMetadata() throws {
        for metadata: Int64 in [0, -1, 42, 84, 99] {
            let input = try prepare(targetPID: 84, activationPID: 42)
            let generation = gate.activityGeneration
            let signals = try XCTUnwrap(gate.takeSignals(for: input))
            XCTAssertEqual(gate.delivery(of: input), .queued)
            for (signal, type) in [(signals.down, CGEventType.keyDown), (signals.up, .keyUp)] {
                signal.setIntegerValueField(.eventTargetUnixProcessID, value: metadata)
                XCTAssertEqual(signal.type, .null)
                let token = signal.getIntegerValueField(.eventSourceUserData)
                assertRoute(gate.handle(type: signal.type, token: token),
                            type: type, token: token, targetPID: 84)
            }
            XCTAssertEqual(gate.delivery(of: input), .handedOff)
            XCTAssertEqual(gate.activityGeneration, generation)
            gate.finish(input)
        }
        XCTAssertEqual(gate.pendingTicketCount, 0)
    }

    func testOverlayActivationChangeCancelsAtSendGateAndReceiptChecks() throws {
        for checkpoint in 0..<3 {
            for pid: pid_t? in [84, 99, 0, -1, nil] {
                frontmost = 42
                let input = try prepare(targetPID: 84, activationPID: 42)
                if checkpoint != 0 { XCTAssertNotNil(gate.takeSignals(for: input)) }
                frontmost = pid
                switch checkpoint {
                case 0: XCTAssertNil(gate.takeSignals(for: input))
                case 1: assertDrop(gate.handle(type: .null, token: input.id))
                default: XCTAssertEqual(gate.delivery(of: input), .cancelled)
                }
                XCTAssertEqual(gate.delivery(of: input), .cancelled)
                frontmost = 42
                XCTAssertNil(gate.takeSignals(for: input))
                assertDrop(gate.handle(type: .null, token: input.id))
                assertDrop(gate.handle(type: .null, token: input.id + 1))
                XCTAssertEqual(gate.delivery(of: input), .cancelled)
                gate.finish(input)
            }
        }
        XCTAssertEqual(gate.pendingTicketCount, 0)
    }

    func testPrepareRechecksActivationWitnessAfterPayloadConstruction() {
        var lookups = 0
        let local = SyntheticInputGate(clock: { 100 }, frontmostPID: {
            lookups += 1
            return lookups == 1 ? 42 : 84
        })
        local.resetTap(isEnabled: true)
        XCTAssertNil(local.prepare("text", targetPID: 84, activationPID: 42,
                                   generation: local.activityGeneration, deadline: 101))
        XCTAssertEqual(lookups, 2)
        XCTAssertEqual(local.pendingTicketCount, 0)
    }

    func testCancellationBeforeSendAndBeforeGateDropsBothEvents() throws {
        for sendFirst in [false, true] {
            let input = try prepare()
            if sendFirst { XCTAssertNotNil(gate.takeSignals(for: input)) }
            XCTAssertEqual(gate.cancel(input), .cancelled)
            XCTAssertEqual(gate.cancel(input), .cancelled)
            XCTAssertNil(gate.takeSignals(for: input))
            assertDrop(gate.handle(type: .null, token: input.id))
            assertDrop(gate.handle(type: .null, token: input.id + 1))
            XCTAssertEqual(gate.delivery(of: input), .cancelled)
            gate.finish(input)
        }
        XCTAssertEqual(gate.pendingTicketCount, 0)
    }

    func testCancellationAfterGateCannotUndoHandoffOrLoseMatchingUp() throws {
        for targetPID: pid_t in [42, 84] {
            frontmost = 42
            now = 100
            gate.resetTap(isEnabled: true)
            let input = try submit(targetPID: targetPID)
            assertRoute(gate.handle(type: .null, token: input.id),
                        type: .keyDown, token: input.id, targetPID: targetPID)
            XCTAssertEqual(gate.cancel(input), .handedOff)
            frontmost = 99
            now = 999
            gate.recordActivity()
            gate.resetTap(isEnabled: false)
            XCTAssertEqual(gate.delivery(of: input), .handedOff)
            assertRoute(gate.handle(type: .null, token: input.id + 1),
                        type: .keyUp, token: input.id + 1, targetPID: targetPID)
            XCTAssertEqual(gate.cancel(input), .handedOff)
            gate.finish(input)
            XCTAssertEqual(gate.delivery(of: input), .handedOff)
            XCTAssertEqual(gate.pendingTicketCount, 0)
        }
    }

    func testExpiryAtDeadlineDropsQueuedDownAndUpPermanently() throws {
        let input = try submit()
        now = 101
        assertDrop(gate.handle(type: .null, token: input.id))
        XCTAssertEqual(gate.delivery(of: input), .cancelled)
        now = 100
        assertDrop(gate.handle(type: .null, token: input.id))
        assertDrop(gate.handle(type: .null, token: input.id + 1))
    }

    func testWrongOrMissingFrontmostPIDCancelsAtGate() throws {
        for pid: pid_t? in [99, nil] {
            frontmost = 42
            let input = try submit()
            frontmost = pid
            assertDrop(gate.handle(type: .null, token: input.id))
            frontmost = 42
            assertDrop(gate.handle(type: .null, token: input.id))
            assertDrop(gate.handle(type: .null, token: input.id + 1))
            XCTAssertEqual(gate.delivery(of: input), .cancelled)
            gate.finish(input)
        }
    }

    func testPrepareRejectsInvalidPIDGenerationDeadlineAndDisabledTap() {
        let generation = gate.activityGeneration
        for pid: pid_t in [0, -1, .min] {
            XCTAssertNil(gate.prepare("text", targetPID: pid, activationPID: 42,
                                      generation: generation, deadline: 101))
            frontmost = pid
            XCTAssertNil(gate.prepare("text", targetPID: 42, activationPID: pid,
                                      generation: generation, deadline: 101))
            frontmost = 42
        }
        XCTAssertNil(gate.prepare("text", targetPID: 99, activationPID: 99,
                                  generation: generation, deadline: 101))
        XCTAssertNil(gate.prepare("text", targetPID: 42, activationPID: 42,
                                  generation: generation + 1, deadline: 101))
        for deadline in [100, 99, TimeInterval.nan, .infinity, -.infinity] {
            XCTAssertNil(gate.prepare("text", targetPID: 42, activationPID: 42,
                                      generation: generation, deadline: deadline))
        }
        gate.resetTap(isEnabled: false)
        XCTAssertNil(gate.prepare("text", targetPID: 42, activationPID: 42,
                                  generation: gate.activityGeneration, deadline: 101))
        XCTAssertEqual(gate.pendingTicketCount, 0)
    }

    func testSignalsCannotBeTakenAfterExpiryActivityOrActivationChange() throws {
        for change in 0..<3 {
            now = 100
            frontmost = 42
            let input = try prepare()
            switch change {
            case 0: now = 101
            case 1: gate.recordActivity()
            default: frontmost = 99
            }
            XCTAssertNil(gate.takeSignals(for: input))
            XCTAssertEqual(gate.delivery(of: input), .cancelled)
            gate.finish(input)
        }
    }

    func testDeadlineIsCheckedAfterFrontmostLookupReturns() throws {
        var time: TimeInterval = 100
        var slowLookup = false
        let local = SyntheticInputGate(clock: { time }, frontmostPID: {
            if slowLookup { time = 102 }
            return 42
        })
        local.resetTap(isEnabled: true)
        let input = try XCTUnwrap(local.prepare("text", targetPID: 42, activationPID: 42,
                                               generation: local.activityGeneration, deadline: 101))
        XCTAssertNotNil(local.takeSignals(for: input))
        slowLookup = true
        assertDrop(local.handle(type: .null, token: input.id))
        XCTAssertEqual(local.delivery(of: input), .cancelled)
    }

    func testRealInputGenerationInvalidatesBeforeHotkeyConsumerRuns() throws {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        for type in types {
            let input = try submit()
            let previousGeneration = gate.activityGeneration
            guard case .passThrough = gate.handle(type: type, token: 0) else {
                return XCTFail("Real input must pass through")
            }
            XCTAssertEqual(gate.activityGeneration, previousGeneration + 1)
            XCTAssertEqual(gate.delivery(of: input), .cancelled)
            assertDrop(gate.handle(type: .null, token: input.id))
            assertDrop(gate.handle(type: .null, token: input.id + 1))
            gate.finish(input)
        }
    }

    func testFocusActivationInvalidatesEvenAfterReturningToSamePID() throws {
        let input = try submit()
        let generation = gate.activityGeneration
        gate.recordActivity()
        gate.recordActivity()
        XCTAssertEqual(gate.activityGeneration, generation + 2)
        assertDrop(gate.handle(type: .null, token: input.id))
        XCTAssertEqual(gate.delivery(of: input), .cancelled)
    }

    func testTapDisableAndReenableNeverResurrectsQueuedInput() throws {
        for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let input = try submit()
            let generation = gate.activityGeneration
            _ = gate.handle(type: type, token: 0)
            XCTAssertEqual(gate.activityGeneration, generation + 1)
            gate.resetTap(isEnabled: true)
            assertDrop(gate.handle(type: .null, token: input.id))
            assertDrop(gate.handle(type: .null, token: input.id + 1))
            XCTAssertEqual(gate.delivery(of: input), .cancelled)
            gate.finish(input)
        }
    }

    func testUnavailableBackgroundMonitorCallsDoNotChangeLifecycleGeneration() {
        let previousMonitor = KeyboardMonitor.shared
        let monitor = KeyboardMonitor()
        defer { KeyboardMonitor.shared = previousMonitor }
        let generation = monitor.activityGeneration
        let completed = expectation(description: "Unavailable background calls completed")
        DispatchQueue.global().async {
            XCTAssertFalse(monitor.isRunning)
            XCTAssertNil(monitor.prepare("text", targetPID: 42, activationPID: 42,
                                         generation: generation, deadline: 101))
            XCTAssertEqual(monitor.activityGeneration, generation)
            let unknown = PreparedTextInput(id: 1)
            monitor.send(unknown)
            XCTAssertEqual(monitor.activityGeneration, generation)
            XCTAssertEqual(monitor.delivery(of: unknown), .handedOff)
            XCTAssertEqual(monitor.activityGeneration, generation)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
    }

    func testLateCallerCancellationAfterTapReenableOnlyAffectsItsOwnTicket() throws {
        let old = try submit()
        gate.resetTap(isEnabled: false)
        gate.resetTap(isEnabled: true)
        let fresh = try submit()
        let generation = gate.activityGeneration
        // A caller that observed the disabled tap may cancel only its own input.
        XCTAssertEqual(gate.cancel(old), .cancelled)
        XCTAssertEqual(gate.activityGeneration, generation)
        XCTAssertEqual(gate.delivery(of: fresh), .queued)
        assertRoute(gate.handle(type: .null, token: fresh.id), type: .keyDown, token: fresh.id)
        XCTAssertEqual(gate.cancel(fresh), .handedOff)
        XCTAssertNotNil(try prepare())
    }

    func testReorderedUpCancelsDownAndUnsubmittedSignalsNeverRoute() throws {
        let input = try prepare()
        assertDrop(gate.handle(type: .null, token: input.id))
        XCTAssertEqual(gate.delivery(of: input), .queued)
        XCTAssertNotNil(gate.takeSignals(for: input))
        assertDrop(gate.handle(type: .null, token: input.id + 1))
        assertDrop(gate.handle(type: .null, token: input.id))
        XCTAssertEqual(gate.delivery(of: input), .cancelled)
    }

    func testOwnEventsAndRoutingDuplicatesNeverCountAsActivityOrDeliverTwice() throws {
        let input = try submit()
        let generation = gate.activityGeneration
        for type in [CGEventType.keyDown, .keyUp, .flagsChanged, .scrollWheel] {
            assertDrop(gate.handle(type: type, token: input.id))
        }
        let down = assertRoute(gate.handle(type: .null, token: input.id), type: .keyDown, token: input.id)
        XCTAssertEqual(down.map(unicode), Array("text".utf16))
        assertDrop(gate.handle(type: .null, token: input.id))
        assertRoute(gate.handle(type: .null, token: input.id + 1), type: .keyUp, token: input.id + 1)
        assertDrop(gate.handle(type: .null, token: input.id + 1))
        XCTAssertEqual(gate.activityGeneration, generation)
        XCTAssertEqual(gate.delivery(of: input), .handedOff)
    }

    func testFinishRetainsOnlyPendingUpThenRetiresBothTokensPermanently() throws {
        let input = try submit()
        assertRoute(gate.handle(type: .null, token: input.id), type: .keyDown, token: input.id)
        gate.finish(input)
        gate.finish(input)
        XCTAssertEqual(gate.pendingTicketCount, 1)
        XCTAssertEqual(gate.cancel(input), .handedOff)
        frontmost = 99
        now = 999
        gate.resetTap(isEnabled: false)
        assertDrop(gate.handle(type: .null, token: input.id))
        assertRoute(gate.handle(type: .null, token: input.id + 1), type: .keyUp, token: input.id + 1)
        XCTAssertEqual(gate.pendingTicketCount, 0)
        assertDrop(gate.handle(type: .null, token: input.id))
        assertDrop(gate.handle(type: .null, token: input.id + 1))
        XCTAssertEqual(gate.cancel(input), .handedOff)
        XCTAssertEqual(gate.delivery(of: input), .handedOff)
    }

    func testFinishedQueuedAndUnknownStaleTokensAlwaysDropWithoutTombstones() throws {
        var retired: [Int64] = []
        for _ in 0..<100 {
            let input = try submit()
            retired.append(input.id)
            gate.finish(input)
        }
        XCTAssertEqual(gate.pendingTicketCount, 0)
        gate.resetTap(isEnabled: true)
        let fresh = try submit()
        let generation = gate.activityGeneration
        for token in retired + [fresh.id + 10_000] {
            XCTAssertTrue(SyntheticInputGate.ownsToken(token))
            assertDrop(gate.handle(type: .null, token: token))
            assertDrop(gate.handle(type: .null, token: token + 1))
        }
        XCTAssertEqual(gate.activityGeneration, generation)
        XCTAssertEqual(Set(retired + [fresh.id]).count, retired.count + 1)
        XCTAssertEqual(gate.delivery(of: fresh), .queued)
    }

    func testTokensAreNotReusedAcrossGateInstances() throws {
        let old = try prepare()
        let other = SyntheticInputGate(clock: { 100 }, frontmostPID: { 42 })
        other.resetTap(isEnabled: true)
        let fresh = try XCTUnwrap(other.prepare("text", targetPID: 42, activationPID: 42,
                                               generation: other.activityGeneration, deadline: 101))
        XCTAssertNotEqual(old.id, fresh.id)
        XCTAssertNotEqual(old.id + 1, fresh.id)
        assertDrop(other.handle(type: .null, token: old.id))
        assertDrop(other.handle(type: .null, token: old.id + 1))
    }

    func testLostUpsAreBoundedAndLateUpsFreeCapacity() throws {
        var inputs: [PreparedTextInput] = []
        for _ in 0..<SyntheticInputGate.maximumPendingTickets {
            let input = try submit()
            inputs.append(input)
            assertRoute(gate.handle(type: .null, token: input.id), type: .keyDown, token: input.id)
            gate.finish(input)
        }
        XCTAssertNil(gate.prepare("text", targetPID: 42, activationPID: 42,
                                  generation: gate.activityGeneration, deadline: 101))
        XCTAssertEqual(gate.pendingTicketCount, SyntheticInputGate.maximumPendingTickets)
        for input in inputs {
            assertRoute(gate.handle(type: .null, token: input.id + 1), type: .keyUp, token: input.id + 1)
        }
        XCTAssertEqual(gate.pendingTicketCount, 0)
        XCTAssertNotNil(try prepare())
    }

    func testResetReleasesOnlyHandedOffKeysOnceToCapturedPID() throws {
        for targetPID: pid_t in [42, 84] {
            frontmost = 42
            now = 100
            gate.resetTap(isEnabled: true)
            let handedOff = try submit(targetPID: targetPID)
            let queued = try submit(targetPID: targetPID)
            let cancelled = try submit(targetPID: targetPID)
            gate.cancel(cancelled)
            assertRoute(gate.handle(type: .null, token: handedOff.id),
                        type: .keyDown, token: handedOff.id, targetPID: targetPID)
            gate.finish(handedOff)
            gate.resetTap(isEnabled: false)
            frontmost = 99
            now = 999
            let releases = gate.takePendingKeyUps()
            XCTAssertEqual(releases.count, 1)
            let (up, pid) = try XCTUnwrap(releases.first)
            XCTAssertEqual(pid, targetPID)
            XCTAssertEqual(up.type, .keyUp)
            XCTAssertEqual(up.getIntegerValueField(.eventSourceUserData), handedOff.id + 1)
            XCTAssertTrue(gate.takePendingKeyUps().isEmpty)
            for input in [handedOff, queued, cancelled] {
                assertDrop(gate.handle(type: .null, token: input.id))
                assertDrop(gate.handle(type: .null, token: input.id + 1))
                gate.finish(input)
            }
            XCTAssertEqual(gate.delivery(of: handedOff), .handedOff)
            XCTAssertEqual(gate.pendingTicketCount, 0)
        }
    }

    func testConcurrentActivityGenerationDoesNotLoseUpdates() {
        let generation = gate.activityGeneration
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            _ = gate.handle(type: .flagsChanged, token: 0)
        }
        XCTAssertEqual(gate.activityGeneration, generation + 1000)
    }

    func testRecordActivityReturnsItsExactAtomicGeneration() {
        let generation = gate.activityGeneration
        let resultLock = NSLock()
        var returned: [UInt64] = []
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            let recorded = gate.recordActivity()
            resultLock.lock()
            returned.append(recorded)
            resultLock.unlock()
        }
        XCTAssertEqual(Set(returned), Set((generation + 1)...(generation + 1000)))
        XCTAssertEqual(gate.activityGeneration, generation + 1000)
    }

    func testCancelRacingGateNeverReportsCancellationForARoutedDown() throws {
        for _ in 0..<100 {
            let input = try submit()
            let resultLock = NSLock()
            var decision: SyntheticInputGate.Decision?
            var cancellation: InputDelivery?
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    let result = gate.handle(type: .null, token: input.id)
                    resultLock.lock()
                    decision = result
                    resultLock.unlock()
                } else {
                    let result = gate.cancel(input)
                    resultLock.lock()
                    cancellation = result
                    resultLock.unlock()
                }
            }
            let result = try XCTUnwrap(decision)
            if case .route = result {
                XCTAssertEqual(cancellation, .handedOff)
                XCTAssertEqual(gate.delivery(of: input), .handedOff)
                assertRoute(gate.handle(type: .null, token: input.id + 1), type: .keyUp, token: input.id + 1)
            } else {
                assertDrop(result)
                XCTAssertEqual(cancellation, .cancelled)
                XCTAssertEqual(gate.delivery(of: input), .cancelled)
                assertDrop(gate.handle(type: .null, token: input.id + 1))
            }
            gate.finish(input)
        }
        XCTAssertEqual(gate.pendingTicketCount, 0)
    }

    func testHandoffIsNotAnApplicationAcknowledgementAndUnknownReceiptsCannotProveCancellation() throws {
        let input = try submit()
        XCTAssertEqual(gate.delivery(of: input), .queued)
        // No application exists in this test. The gate can only authorize routing.
        assertRoute(gate.handle(type: .null, token: input.id), type: .keyDown, token: input.id)
        assertRoute(gate.handle(type: .null, token: input.id + 1), type: .keyUp, token: input.id + 1)
        XCTAssertEqual(gate.delivery(of: input), .handedOff)
        gate.finish(input)
        let unknown = PreparedTextInput(id: input.id + 10_000)
        XCTAssertEqual(gate.cancel(unknown), .handedOff)
        XCTAssertEqual(gate.delivery(of: unknown), .handedOff)
        assertDrop(gate.handle(type: .null, token: unknown.id))
    }
}

final class KeyboardEventStagesTests: XCTestCase {
    private var stages = KeyboardEventStages()
    private var gate: SyntheticInputGate!
    private var frontmost: pid_t? = 42

    override func setUp() {
        super.setUp()
        stages = KeyboardEventStages()
        frontmost = 42
        gate = SyntheticInputGate(clock: { 100 }, frontmostPID: { [unowned self] in self.frontmost })
        gate.resetTap(isEnabled: true)
    }

    private func event(_ type: CGEventType = .flagsChanged, timestamp: CGEventTimestamp = 1,
                       keyCode: Int64 = 58, token: Int64 = 7, flags: CGEventFlags = [],
                       targetPID: Int64 = 84) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.type = type
        event.timestamp = timestamp
        event.flags = flags
        event.setIntegerValueField(.keyboardEventKeycode, value: keyCode)
        event.setIntegerValueField(.eventSourceUserData, value: token)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
        return event
    }

    private func handle(_ stage: KeyboardEventStages.Stage, _ event: CGEvent,
                        sessionEnabled: Bool = true, annotatedEnabled: Bool = true) -> KeyboardEventStages.Decision {
        stages.handle(stage: stage, type: event.type, event: event, gate: gate,
                      sessionEnabled: sessionEnabled, annotatedEnabled: annotatedEnabled,
                      modifier: .option, doubleTapMode: false, now: 100)
    }

    private func assertPass(_ decision: KeyboardEventStages.Decision,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case .passThrough = decision else {
            return XCTFail("Expected an untouched event", file: file, line: line)
        }
    }

    private func assertDrop(_ decision: KeyboardEventStages.Decision,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case .drop = decision else {
            return XCTFail("Expected a dropped event", file: file, line: line)
        }
    }

    private func assertHotkey(_ decision: KeyboardEventStages.Decision, pid: pid_t?,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard case let .hotkey(target, generation, triggeredAt) = decision else {
            return XCTFail("Expected an annotated hotkey", file: file, line: line)
        }
        XCTAssertEqual(target, pid, file: file, line: line)
        XCTAssertEqual(generation, gate.activityGeneration, file: file, line: line)
        XCTAssertEqual(triggeredAt, 100, file: file, line: line)
    }

    private func armHotkey() throws {
        let down = try event(flags: .maskAlternate)
        assertPass(handle(.session, down))
        assertPass(handle(.annotated, down))
    }

    private func submit() throws -> (PreparedTextInput, SyntheticInputGate.Signals) {
        let input = try XCTUnwrap(gate.prepare("text", targetPID: 84, activationPID: 42,
                                               generation: gate.activityGeneration, deadline: 101))
        return (input, try XCTUnwrap(gate.takeSignals(for: input)))
    }

    func testSessionRecordsOnceAndOnlyAnnotatedStageResolvesFinalRecipient() throws {
        let generation = gate.activityGeneration
        let down = try event(flags: .maskAlternate, targetPID: 42)
        assertPass(handle(.session, down))
        XCTAssertEqual(gate.activityGeneration, generation + 1)
        down.setIntegerValueField(.eventTargetUnixProcessID, value: 84)
        assertPass(handle(.annotated, down))
        XCTAssertEqual(gate.activityGeneration, generation + 1)

        let up = try event(timestamp: 2, targetPID: 42)
        assertPass(handle(.session, up))
        XCTAssertEqual(gate.activityGeneration, generation + 2)
        up.setIntegerValueField(.eventTargetUnixProcessID, value: 84)
        assertHotkey(handle(.annotated, up), pid: 84)
        assertPass(handle(.annotated, up))
        XCTAssertEqual(gate.activityGeneration, generation + 2)
    }

    func testInvalidAnnotatedRecipientDoesNotFallBackToSessionTarget() throws {
        try armHotkey()
        let up = try event(timestamp: 2, targetPID: 42)
        assertPass(handle(.session, up))
        up.setIntegerValueField(.eventTargetUnixProcessID, value: 0)
        assertHotkey(handle(.annotated, up), pid: nil)
    }

    func testAnnotatedInputWithoutSessionEvidenceCannotTriggerOrAdvanceGeneration() throws {
        let generation = gate.activityGeneration
        assertPass(handle(.annotated, try event(flags: .maskAlternate)))
        assertPass(handle(.annotated, try event(timestamp: 2)))
        assertPass(handle(.annotated, try event(.keyDown, timestamp: 3)))
        assertPass(handle(.annotated, try event(.keyUp, timestamp: 4)))
        XCTAssertEqual(gate.activityGeneration, generation)
    }

    func testFingerprintRequiresExactTimestampKeyCodeAndSourceUserData() throws {
        for mismatch in 0..<3 {
            stages = KeyboardEventStages()
            try armHotkey()
            let up = try event(timestamp: 2)
            assertPass(handle(.session, up))
            let changed = try event(timestamp: 2, token: mismatch == 2 ? 8 : 7)
            switch mismatch {
            case 0:
                changed.timestamp = 3
                XCTAssertNotEqual(changed.timestamp, up.timestamp)
            case 1:
                changed.setIntegerValueField(.keyboardEventKeycode, value: 61)
                XCTAssertNotEqual(changed.getIntegerValueField(.keyboardEventKeycode),
                                  up.getIntegerValueField(.keyboardEventKeycode))
            default:
                XCTAssertEqual(changed.getIntegerValueField(.eventSourceUserData), 8)
                XCTAssertEqual(up.getIntegerValueField(.eventSourceUserData), 7)
                XCTAssertNotEqual(changed.getIntegerValueField(.eventSourceUserData),
                                  up.getIntegerValueField(.eventSourceUserData))
            }
            assertPass(handle(.annotated, changed))
            assertPass(handle(.annotated, up))
        }
    }

    func testStaleAnnotationCannotAdoptNewerSessionModifierGeneration() throws {
        try armHotkey()
        let oldUp = try event(timestamp: 2)
        assertPass(handle(.session, oldUp))
        let generation = gate.activityGeneration
        let newDown = try event(timestamp: 3, flags: .maskAlternate)
        assertPass(handle(.session, newDown))
        XCTAssertEqual(gate.activityGeneration, generation + 1)
        assertPass(handle(.annotated, oldUp))
        assertPass(handle(.annotated, newDown))
        let newUp = try event(timestamp: 4)
        assertPass(handle(.session, newUp))
        assertPass(handle(.annotated, newUp))
    }

    func testUnconsumedSessionModifierDisarmsBeforeReplacingFingerprint() throws {
        try armHotkey()
        assertPass(handle(.session, try event(timestamp: 2)))
        let newDown = try event(timestamp: 3, flags: .maskAlternate)
        assertPass(handle(.session, newDown))
        assertPass(handle(.annotated, newDown))
        let newUp = try event(timestamp: 4)
        assertPass(handle(.session, newUp))
        assertPass(handle(.annotated, newUp))
    }

    func testActivationBetweenStagesInvalidatesCapturedGeneration() throws {
        try armHotkey()
        let up = try event(timestamp: 2)
        assertPass(handle(.session, up))
        let generation = gate.activityGeneration
        XCTAssertEqual(gate.recordActivity(), generation + 1)
        assertPass(handle(.annotated, up))
        assertPass(handle(.annotated, up))
        XCTAssertEqual(gate.activityGeneration, generation + 1)
    }

    func testOtherSessionUserInputClearsFingerprintAndDisarmsHotkey() throws {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel
        ]
        for type in types {
            stages = KeyboardEventStages()
            try armHotkey()
            let up = try event(timestamp: 2)
            assertPass(handle(.session, up))
            let generation = gate.activityGeneration
            assertPass(handle(.session, try event(type, timestamp: 3)))
            XCTAssertEqual(gate.activityGeneration, generation + 1)
            assertPass(handle(.annotated, up))
        }
    }

    func testOwnedTransportRoutesOnlyAtSessionAndEchoPreservesPendingModifier() throws {
        try armHotkey()
        let modifierUp = try event(timestamp: 2)
        assertPass(handle(.session, modifierUp))
        let generation = gate.activityGeneration
        let (input, signals) = try submit()
        for (signal, type) in [(signals.down, CGEventType.keyDown), (signals.up, .keyUp)] {
            assertPass(handle(.annotated, signal))
            guard case let .route(payload, pid) = handle(.session, signal) else {
                return XCTFail("Session must route the owned null signal")
            }
            XCTAssertEqual(pid, 84)
            XCTAssertEqual(payload.type, type)
            assertPass(handle(.annotated, payload))
            assertDrop(handle(.session, payload))
        }
        assertPass(handle(.annotated, try event(token: input.id, flags: .maskAlternate)))
        XCTAssertEqual(gate.activityGeneration, generation)
        XCTAssertEqual(gate.delivery(of: input), .handedOff)
        assertHotkey(handle(.annotated, modifierUp), pid: 84)
        gate.finish(input)
        XCTAssertEqual(gate.pendingTicketCount, 0)
    }

    func testBothTapsMustBeEnabledBeforeQueuedDownCanRoute() throws {
        for (session, annotated) in [(true, true), (true, false), (false, true), (false, false)] {
            gate.resetTap(isEnabled: true)
            let (input, signals) = try submit()
            let generation = gate.activityGeneration
            let decision = handle(.session, signals.down, sessionEnabled: session, annotatedEnabled: annotated)
            if session && annotated {
                guard case let .route(_, pid) = decision else { return XCTFail("Both taps are ready") }
                XCTAssertEqual(pid, 84)
                XCTAssertEqual(gate.activityGeneration, generation)
                XCTAssertEqual(gate.takePendingKeyUps().count, 1)
            } else {
                assertDrop(decision)
                XCTAssertEqual(gate.activityGeneration, generation + 1)
                XCTAssertEqual(gate.delivery(of: input), .cancelled)
                XCTAssertTrue(gate.takePendingKeyUps().isEmpty)
                gate.resetTap(isEnabled: true)
                assertDrop(handle(.session, signals.down))
                assertDrop(handle(.session, signals.up))
                XCTAssertEqual(gate.delivery(of: input), .cancelled)
            }
            gate.finish(input)
        }
        XCTAssertEqual(gate.pendingTicketCount, 0)
    }

    func testReadinessLossStillPairsHandedOffUpToOriginalRecipient() throws {
        let (input, signals) = try submit()
        guard case let .route(down, downPID) = handle(.session, signals.down) else {
            return XCTFail("Expected a handed-off down")
        }
        XCTAssertEqual(downPID, 84)
        let generation = gate.activityGeneration
        frontmost = 99
        assertPass(handle(.annotated, down, annotatedEnabled: false))
        XCTAssertEqual(gate.activityGeneration, generation + 1)
        XCTAssertEqual(gate.cancel(input), .handedOff)
        gate.finish(input)
        guard case let .route(up, upPID) = handle(.session, signals.up, annotatedEnabled: false) else {
            return XCTFail("A handed-off down still needs its original recipient's up")
        }
        XCTAssertEqual(upPID, 84)
        XCTAssertEqual(up.type, .keyUp)
        assertPass(handle(.annotated, up, annotatedEnabled: false))
        XCTAssertTrue(gate.takePendingKeyUps().isEmpty)
        XCTAssertEqual(gate.pendingTicketCount, 0)
        XCTAssertEqual(gate.delivery(of: input), .handedOff)
    }

    func testReadinessLossAtEitherStageDisarmsFingerprintAcrossReenable() throws {
        for stage in [KeyboardEventStages.Stage.session, .annotated] {
            stages = KeyboardEventStages()
            gate.resetTap(isEnabled: true)
            try armHotkey()
            let up = try event(timestamp: 2)
            assertPass(handle(.session, up))
            assertPass(handle(stage, try event(.null), annotatedEnabled: false))
            gate.resetTap(isEnabled: true)
            assertPass(handle(.annotated, up))
        }
    }
}

final class KeyboardMonitorPIDTests: XCTestCase {
    func testCheckedPIDRejectsZeroNegativeAndOverflowMetadata() {
        for value: Int64 in [0, -1, Int64(pid_t.min), Int64(pid_t.min) - 1,
                             Int64(pid_t.max) + 1, Int64(UInt32.max) + 43, .min, .max] {
            XCTAssertNil(KeyboardMonitor.checkedPID(value))
        }
    }

    func testCheckedPIDAcceptsPositiveEventMetadataIncludingOverlayRecipient() throws {
        let finalModifierEvent = try XCTUnwrap(CGEvent(source: nil))
        finalModifierEvent.type = .flagsChanged
        for value: Int64 in [1, 42, 84, Int64(pid_t.max)] {
            finalModifierEvent.setIntegerValueField(.eventTargetUnixProcessID, value: value)
            XCTAssertEqual(KeyboardMonitor.checkedPID(
                finalModifierEvent.getIntegerValueField(.eventTargetUnixProcessID)
            ), pid_t(value))
        }
    }
}

final class ModifierHotkeyDetectorTests: XCTestCase {
    func testSingleTapWorksForEitherSideOfEveryModifier() {
        let modifiers: [(SettingsManager.HotkeyModifier, [UInt16])] = [
            (.shift, [56, 60]), (.option, [58, 61]), (.control, [59, 62]), (.command, [55, 54])
        ]
        for (modifier, codes) in modifiers {
            for keyCode in codes {
                var detector = ModifierHotkeyDetector()
                XCTAssertFalse(detector.handle(keyCode: keyCode, flags: modifier.cgEventFlag,
                                                modifier: modifier, doubleTapMode: false, now: 100))
                XCTAssertTrue(detector.handle(keyCode: keyCode, flags: [], modifier: modifier,
                                               doubleTapMode: false, now: 100.1))
                XCTAssertFalse(detector.handle(keyCode: keyCode, flags: [], modifier: modifier,
                                                doubleTapMode: false, now: 100.2))
            }
        }
    }

    func testTypingWithBothShiftSidesHeldCannotRearmBeforeBothAreReleased() {
        for (first, second): (UInt16, UInt16) in [(56, 60), (60, 56)] {
            var detector = ModifierHotkeyDetector()
            XCTAssertFalse(detector.handle(keyCode: first, flags: .maskShift, modifier: .shift,
                                            doubleTapMode: false, now: 100))
            XCTAssertFalse(detector.handle(keyCode: second, flags: .maskShift, modifier: .shift,
                                            doubleTapMode: false, now: 100.1))
            detector.disarm() // A letter was pressed while both sides were held.
            for time in [100.2, 100.3, 100.4] {
                // Release, press again, then release one side; the other stays down.
                XCTAssertFalse(detector.handle(keyCode: first, flags: .maskShift, modifier: .shift,
                                                doubleTapMode: false, now: time))
            }
            XCTAssertFalse(detector.handle(keyCode: second, flags: [], modifier: .shift,
                                            doubleTapMode: false, now: 100.5))
            XCTAssertFalse(detector.handle(keyCode: first, flags: .maskShift, modifier: .shift,
                                            doubleTapMode: false, now: 100.6))
            XCTAssertTrue(detector.handle(keyCode: first, flags: [], modifier: .shift,
                                           doubleTapMode: false, now: 100.7))
        }
    }

    func testOverlappingShiftSidesCountAsOnlyOneTap() {
        var detector = ModifierHotkeyDetector()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.05))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.15))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.2))
        XCTAssertTrue(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                       doubleTapMode: true, now: 100.25))
    }

    func testTypingDuringOverlappingShiftPressesClearsPendingDoubleTap() {
        var detector = ModifierHotkeyDetector()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.05))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.15))
        detector.disarm()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.2))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.25))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.3))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.35))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.4))
        XCTAssertTrue(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                       doubleTapMode: true, now: 100.45))
    }

    func testChangingTargetModifierClearsPendingDoubleTap() {
        var detector = ModifierHotkeyDetector()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.05))
        XCTAssertFalse(detector.handle(keyCode: 58, flags: .maskAlternate, modifier: .option,
                                        doubleTapMode: true, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 58, flags: [], modifier: .option,
                                        doubleTapMode: true, now: 100.15))
        XCTAssertFalse(detector.handle(keyCode: 61, flags: .maskAlternate, modifier: .option,
                                        doubleTapMode: true, now: 100.2))
        XCTAssertTrue(detector.handle(keyCode: 61, flags: [], modifier: .option,
                                       doubleTapMode: true, now: 100.25))
    }

    func testChangingTargetToAlreadyHeldModifierRequiresAFreshAggregateDown() {
        var detector = ModifierHotkeyDetector()
        // Both Option sides are already held while Shift is the configured target.
        XCTAssertFalse(detector.handle(keyCode: 58, flags: .maskAlternate, modifier: .shift,
                                        doubleTapMode: false, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 61, flags: .maskAlternate, modifier: .shift,
                                        doubleTapMode: false, now: 100.05))
        // Change the target, then release the two sides one at a time.
        XCTAssertFalse(detector.handle(keyCode: 58, flags: .maskAlternate, modifier: .option,
                                        doubleTapMode: false, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 61, flags: [], modifier: .option,
                                        doubleTapMode: false, now: 100.15))
        XCTAssertFalse(detector.handle(keyCode: 58, flags: .maskAlternate, modifier: .option,
                                        doubleTapMode: false, now: 100.2))
        XCTAssertTrue(detector.handle(keyCode: 58, flags: [], modifier: .option,
                                       doubleTapMode: false, now: 100.25))
    }

    func testAnotherModifierCannotRearmPartlyReleasedShift() {
        var detector = ModifierHotkeyDetector()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: false, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: false, now: 100.05))
        XCTAssertFalse(detector.handle(keyCode: 59, flags: [.maskShift, .maskControl], modifier: .shift,
                                        doubleTapMode: false, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 59, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: false, now: 100.15))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: false, now: 100.2))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: [], modifier: .shift,
                                        doubleTapMode: false, now: 100.25))
    }
}
