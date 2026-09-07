import ApplicationServices
import XCTest
@testable import ReTyper

final class LayoutSwitchPolicyTests: XCTestCase {
    func testEarlyAndCoordinatorRefusalsAdvanceWithStableWitness() {
        let reasons: [AbortReason] = [.noTextAccess, .unsupportedField, .invalidSnapshot,
                                     .selectionNotEstablished, .inputUnavailable, .inputCancelled]
        for reason in reasons {
            let result = ReplacementResult(outcome: .aborted(reason))
            XCTAssertEqual(result.layoutSwitchAction(activationPID: 42, currentActivationPID: 42,
                                                     inputGeneration: 7, currentInputGeneration: 7), .next)
        }
    }

    func testLayoutOnlyAndConfirmedReplacementUseDifferentActions() {
        let layoutOnly = ReplacementResult(outcome: .layoutOnly)
        let replaced = ReplacementResult(outcome: .replaced, targetLayoutID: "target-layout")
        XCTAssertEqual(layoutOnly.layoutSwitchAction(activationPID: 42, currentActivationPID: 42,
                                                     inputGeneration: 7, currentInputGeneration: 7), .next)
        XCTAssertEqual(replaced.layoutSwitchAction(activationPID: 42, currentActivationPID: 42,
                                                   inputGeneration: 7, currentInputGeneration: 7), .select("target-layout"))
        XCTAssertNil(ReplacementResult(outcome: .replaced).layoutSwitchAction(
            activationPID: 42, currentActivationPID: 42, inputGeneration: 7, currentInputGeneration: 7))
    }

    func testProtectedOutcomesNeverSwitchEvenWithATargetLayout() {
        let outcomes: [ReplacementOutcome] = [.aborted(.busy), .aborted(.contextChanged),
                                               .aborted(.recoveryPending), .needsRecovery, .restoredAfterFailure]
        for outcome in outcomes {
            let result = ReplacementResult(outcome: outcome, targetLayoutID: "target-layout")
            XCTAssertNil(result.layoutSwitchAction(activationPID: 42, currentActivationPID: 42,
                                                   inputGeneration: 7, currentInputGeneration: 7))
        }
    }

    func testMissingInvalidOrChangedContextNeverSwitches() {
        let contexts: [(pid_t?, pid_t?, UInt64, UInt64)] = [
            (nil, nil, 7, 7), (nil, 42, 7, 7), (42, nil, 7, 7),
            (0, 0, 7, 7), (-1, -1, 7, 7), (42, 43, 7, 7), (42, 42, 7, 8)
        ]
        for outcome in [ReplacementOutcome.aborted(.noTextAccess), .layoutOnly, .replaced] {
            let result = ReplacementResult(outcome: outcome, targetLayoutID: "target-layout")
            for (activation, current, generation, currentGeneration) in contexts {
                XCTAssertNil(result.layoutSwitchAction(activationPID: activation, currentActivationPID: current,
                                                       inputGeneration: generation, currentInputGeneration: currentGeneration))
            }
        }
    }
}
