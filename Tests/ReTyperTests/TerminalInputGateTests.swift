import XCTest
import CoreGraphics
@testable import ReTyper

final class TerminalInputGateTests: XCTestCase {
    private func event(_ code: UInt16, down: Bool = true) -> CGEvent {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    }
    func testReturnIsHeldAndReplayedInOrderOnlyAfterRelease() {
        var delivered: [CGEvent] = []
        let gate = TerminalInputGate(deliver: { delivered.append($0) }, schedule: { _, _ in })
        XCTAssertFalse(gate.deferEvent(event(36)))
        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())
        XCTAssertTrue(gate.deferEvent(event(36)))
        XCTAssertTrue(gate.deferEvent(event(36, down: false)))
        XCTAssertTrue(delivered.isEmpty)
        gate.release()
        XCTAssertEqual(delivered.map(\.type), [.keyDown, .keyUp])
        XCTAssertTrue(delivered.allSatisfy(TerminalInputGate.isReplay))
        XCTAssertTrue(delivered.allSatisfy { !KeyboardMonitor.isSynthetic($0) })
        XCTAssertTrue(gate.busy)
        delivered.forEach { gate.acknowledgeReplay($0) }
        XCTAssertFalse(gate.busy)
    }

    func testNewPhysicalInputCannotOvertakeAlreadyReplayedInput() {
        var delivered: [CGEvent] = []
        let gate = TerminalInputGate(deliver: { delivered.append($0) }, schedule: { _, _ in })
        XCTAssertTrue(gate.begin())
        XCTAssertTrue(gate.deferEvent(event(0)))
        gate.release()
        XCTAssertTrue(gate.deferEvent(event(36)))
        XCTAssertEqual(delivered.count, 1)
        gate.acknowledgeReplay(delivered[0])
        XCTAssertEqual(delivered.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [0, 36])
        XCTAssertFalse(gate.deferEvent(delivered[1]))
        gate.acknowledgeReplay(delivered[1])
        XCTAssertFalse(gate.busy)
    }

    func testWatchdogAndLateAcknowledgementCannotFinishANewerGate() {
        var scheduled: [() -> Void] = []
        var delivered: [CGEvent] = []
        let gate = TerminalInputGate(deliver: { delivered.append($0) }, schedule: { _, f in scheduled.append(f) })
        _ = gate.begin(); _ = gate.deferEvent(event(0)); gate.release()
        let old = delivered[0]
        scheduled[0]()
        XCTAssertFalse(gate.busy)
        _ = gate.begin(); _ = gate.deferEvent(event(36)); gate.release()
        scheduled[0](); gate.acknowledgeReplay(old)
        XCTAssertTrue(gate.busy)
        gate.acknowledgeReplay(delivered[1])
        XCTAssertFalse(gate.busy)
    }

    func testLargeBurstIsFlushedWithoutDroppingEvents() {
        var delivered: [CGEvent] = []
        let gate = TerminalInputGate(deliver: { delivered.append($0) }, schedule: { _, _ in })
        _ = gate.begin()
        for _ in 0..<512 { XCTAssertTrue(gate.deferEvent(event(0))) }
        XCTAssertEqual(delivered.count, 512)
        delivered.forEach { gate.acknowledgeReplay($0) }
        XCTAssertFalse(gate.busy)
    }

    func testSyntheticReplacementBatchHasNoSubmitKeys() throws {
        let edit = TerminalEdit(deleteCount: 3, insert: "тест", targetLayoutID: "ru")
        let events = try XCTUnwrap(KeyboardMonitor.terminalEvents(edit))
        XCTAssertEqual(events.count, (3 + 4) * 2)
        XCTAssertTrue(events.allSatisfy(KeyboardMonitor.isSynthetic))
        XCTAssertFalse(events.contains { $0.getIntegerValueField(.keyboardEventKeycode) == 36 })
    }

    func testCompletionIsConsumedAndCannotAffectALaterEditorOperation() {
        let gate = TerminalInputGate(deliver: { _ in }, schedule: { _, _ in })
        var completed = 0
        _ = gate.begin(); gate.onDrained = { completed += 1 }
        gate.release(); gate.release()
        XCTAssertEqual(completed, 1)
    }

    func testOlderReplayWaveWatchdogCannotReleaseNewerWave() {
        var delivered: [CGEvent] = []
        var scheduled: [() -> Void] = []
        let gate = TerminalInputGate(deliver: { delivered.append($0) }, schedule: { _, work in scheduled.append(work) })
        _ = gate.begin(); _ = gate.deferEvent(event(0)); gate.release()
        _ = gate.deferEvent(event(36))
        gate.acknowledgeReplay(delivered[0])
        XCTAssertEqual(delivered.count, 2)
        scheduled[0]()
        XCTAssertTrue(gate.busy)
        gate.acknowledgeReplay(delivered[1])
        XCTAssertFalse(gate.busy)
    }

    func testReplayPreservesPayloadWithoutModifyingOriginalEvent() {
        var delivered: [CGEvent] = []
        let gate = TerminalInputGate(deliver: { delivered.append($0) }, schedule: { _, _ in })
        let original = event(0)
        let units = Array("ж".utf16)
        original.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        original.flags = .maskShift
        _ = gate.begin(); _ = gate.deferEvent(original); gate.release()
        XCTAssertEqual(TerminalRecorder.unicode(delivered[0]), "ж")
        XCTAssertEqual(delivered[0].flags, .maskShift)
        XCTAssertFalse(TerminalInputGate.isReplay(original))
    }
}
