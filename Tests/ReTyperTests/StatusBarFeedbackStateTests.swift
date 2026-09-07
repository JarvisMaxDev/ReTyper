import XCTest
@testable import ReTyper

final class StatusBarFeedbackStateTests: XCTestCase {
    func testIdleDoesNotShowWarning() {
        let state = StatusBarFeedbackState()
        XCTAssertFalse(state.isRecoveryAvailable)
        XCTAssertFalse(state.showsWarning(at: 0))
        XCTAssertFalse(state.showsWarning(at: 100))
    }

    func testFailureWarningLastsFullDurationAcrossRepeatedReads() {
        var state = StatusBarFeedbackState()
        state.flashFailure(at: 10)

        XCTAssertEqual(StatusBarFeedbackState.failureFlashDuration, 1.5)
        for uptime in [10.0, 10.5, 11.0, 11.499] {
            state.isRecoveryAvailable = false
            XCTAssertTrue(state.showsWarning(at: uptime))
        }
        XCTAssertFalse(state.showsWarning(at: 11.5))
        XCTAssertFalse(state.showsWarning(at: 20))
    }

    func testOlderFlashDeadlineDoesNotEndNewerFlash() {
        var state = StatusBarFeedbackState()
        state.flashFailure(at: 10)
        state.flashFailure(at: 11)

        XCTAssertTrue(state.showsWarning(at: 11.5))
        XCTAssertTrue(state.showsWarning(at: 12.499))
        XCTAssertFalse(state.showsWarning(at: 12.5))
    }

    func testRecoveryWarningPersistsUntilCleared() {
        var state = StatusBarFeedbackState()
        state.isRecoveryAvailable = true

        XCTAssertTrue(state.showsWarning(at: 0))
        XCTAssertTrue(state.showsWarning(at: 100_000))

        state.isRecoveryAvailable = false
        XCTAssertFalse(state.showsWarning(at: 100_000))
    }

    func testRecoveryWarningOutlastsFailureFlash() {
        var state = StatusBarFeedbackState()
        state.flashFailure(at: 10)
        state.isRecoveryAvailable = true

        XCTAssertTrue(state.showsWarning(at: 11.5))
        XCTAssertTrue(state.showsWarning(at: 100))

        state.flashFailure(at: 100)
        XCTAssertTrue(state.showsWarning(at: 101.5))

        state.isRecoveryAvailable = false
        XCTAssertFalse(state.showsWarning(at: 101.5))
    }

    func testClearingRecoveryDoesNotEndActiveFlash() {
        var state = StatusBarFeedbackState()
        state.isRecoveryAvailable = true
        state.flashFailure(at: 10)
        state.isRecoveryAvailable = false

        XCTAssertTrue(state.showsWarning(at: 11.499))
        XCTAssertFalse(state.showsWarning(at: 11.5))
    }

    func testFailureExplanationRemainsAfterTriangleDisappears() {
        var state = StatusBarFeedbackState()
        state.recordOutcome(.aborted(.unsupportedField))
        state.flashFailure(at: 10)
        let explanation = state.outcomeMessage

        XCTAssertNotNil(explanation)
        XCTAssertFalse(state.showsWarning(at: 100))
        XCTAssertEqual(state.outcomeMessage, explanation)
        XCTAssertFalse(state.isRecoveryAvailable)
        XCTAssertTrue(explanation?.contains("No text was sent") == true)
        XCTAssertFalse(explanation?.contains("Copy Original Text") == true)
    }

    func testNormalLayoutRefreshDoesNotClearFailureExplanation() {
        var state = StatusBarFeedbackState()
        state.recordOutcome(.aborted(.inputCancelled))
        let explanation = state.outcomeMessage
        state.isRecoveryAvailable = false
        XCTAssertEqual(state.outcomeMessage, explanation)
    }

    func testIgnoredBusyOutcomePreservesLastExplanation() {
        var state = StatusBarFeedbackState()
        state.recordOutcome(.aborted(.noTextAccess))
        let explanation = state.outcomeMessage
        state.recordOutcome(.aborted(.busy))
        XCTAssertEqual(state.outcomeMessage, explanation)
    }

    func testSuccessClearsStaleFailureExplanation() {
        for outcome in [ReplacementOutcome.replaced, .layoutOnly] {
            var state = StatusBarFeedbackState()
            state.recordOutcome(.aborted(.unsupportedField))
            state.flashFailure(at: 10)
            state.recordOutcome(outcome)
            XCTAssertNil(state.outcomeMessage)
            XCTAssertFalse(state.showsWarning(at: 10.5))
        }
    }

    func testRecoveryMessagePersistsUntilExplicitClear() {
        var state = StatusBarFeedbackState()
        state.isRecoveryAvailable = true
        state.recordOutcome(.needsRecovery)
        XCTAssertTrue(state.outcomeMessage?.contains("Copy Original Text") == true)
        XCTAssertTrue(state.showsWarning(at: 100_000))
        state.isRecoveryAvailable = false
        XCTAssertNil(state.outcomeMessage)
    }

    func testRestoredFailureDoesNotRequestManualRecovery() {
        var state = StatusBarFeedbackState()
        state.recordOutcome(.restoredAfterFailure)
        XCTAssertTrue(state.outcomeMessage?.contains("original text was restored") == true)
        XCTAssertFalse(state.isRecoveryAvailable)
    }
}
