import ApplicationServices
import XCTest
@testable import ReTyper

final class TextAccessCapabilityTests: XCTestCase {
    private func target(_ recipient: pid_t, _ activated: pid_t) -> TextAccessCapability {
        TextAccessCapability(applicationPID: recipient, activationPID: activated,
                             element: AXUIElementCreateApplication(recipient), window: AXUIElementCreateApplication(recipient),
                             windowSource: .field, elementRole: "AXTextField", canSetValue: true, canSetSelection: true)
    }

    func testNormalReceiverKeepsExistingActivationRule() {
        XCTAssertTrue(target(123, 123).acceptsActivation(123, fieldFocused: nil))
        XCTAssertFalse(target(123, 123).acceptsActivation(456, fieldFocused: true))
        XCTAssertFalse(target(123, 123).acceptsActivation(nil, fieldFocused: true))
    }

    func testNonactivatingReceiverRequiresAffirmativeFieldFocus() {
        XCTAssertTrue(target(456, 123).acceptsActivation(123, fieldFocused: true))
        XCTAssertFalse(target(456, 123).acceptsActivation(123, fieldFocused: false))
        XCTAssertFalse(target(456, 123).acceptsActivation(123, fieldFocused: nil))
    }

    func testOverlayDoesNotReplaceWitnessWithRecipientDuringValidation() {
        XCTAssertFalse(target(456, 123).acceptsActivation(456, fieldFocused: true))
        XCTAssertFalse(target(456, 123).acceptsActivation(789, fieldFocused: true))
    }

    func testMissingEnabledDoesNotBypassTextAreaWriteRequirements() {
        for canSetValue in [false, true] {
            for canSetSelection in [false, true] {
                let capability = TextAccessCapability(
                    applicationPID: 123, activationPID: 123,
                    element: AXUIElementCreateApplication(123), window: AXUIElementCreateApplication(123),
                    windowSource: .field, elementRole: "AXTextArea", canSetValue: canSetValue, canSetSelection: canSetSelection
                )
                let eligible = AccessibilityTextClient.acceptsEnabled(nil, role: capability.elementRole)
                    && capability.supportsReplacement
                XCTAssertEqual(eligible, canSetValue && canSetSelection)
            }
        }
    }
}
