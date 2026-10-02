import XCTest
@testable import ReTyper

final class ClipboardCopyStabilityTests: XCTestCase {
    func testOldClipboardNeverBecomesCopyResult() {
        var copy = ClipboardCopyStability(initialChangeCount: 10)
        XCTAssertFalse(copy.observe(changeCount: 10, hasText: true, now: 0))
        XCTAssertFalse(copy.observe(changeCount: 10, hasText: true, now: 1))
    }

    func testSecondWriteRestartsSettlingInsteadOfRacingPaste() {
        var copy = ClipboardCopyStability(initialChangeCount: 10)
        XCTAssertFalse(copy.observe(changeCount: 11, hasText: true, now: 0.010))
        XCTAssertFalse(copy.observe(changeCount: 11, hasText: true, now: 0.030))
        XCTAssertFalse(copy.observe(changeCount: 12, hasText: true, now: 0.035))
        XCTAssertFalse(copy.observe(changeCount: 12, hasText: true, now: 0.080))
        XCTAssertTrue(copy.observe(changeCount: 12, hasText: true, now: 0.100))
    }

    func testStableGenerationStillNeedsText() {
        var copy = ClipboardCopyStability(initialChangeCount: 10)
        XCTAssertFalse(copy.observe(changeCount: 11, hasText: false, now: 0))
        XCTAssertFalse(copy.observe(changeCount: 11, hasText: false, now: 0.1))
        XCTAssertTrue(copy.observe(changeCount: 11, hasText: true, now: 0.11))
    }

    func testContinuouslyChangingClipboardIsNeverAccepted() {
        var copy = ClipboardCopyStability(initialChangeCount: 10)
        for index in 1...35 {
            XCTAssertFalse(copy.observe(changeCount: 10 + index, hasText: true, now: Double(index) * 0.01))
        }
    }
}
