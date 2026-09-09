import ApplicationServices
import XCTest
@testable import ReTyper

final class AccessibilityTextClientTests: XCTestCase {
    func testAbsentOrOrdinarySubroleIsAccepted() {
        XCTAssertTrue(AccessibilityTextClient.acceptsSubrole(nil))
        XCTAssertTrue(AccessibilityTextClient.acceptsSubrole("AXSearchField" as CFString))
    }

    func testSecureSubroleIsRejected() {
        XCTAssertFalse(AccessibilityTextClient.acceptsSubrole(kAXSecureTextFieldSubrole as CFString))
    }

    func testInvalidSubroleTypesAreNotTreatedAsAbsent() {
        let values: [CFTypeRef] = [NSNumber(value: true), NSNumber(value: 42), NSArray(), NSDictionary()]
        for value in values {
            XCTAssertFalse(AccessibilityTextClient.acceptsSubrole(value))
        }
    }

    func testTextAreaMayOmitEnabledAttribute() {
        XCTAssertTrue(AccessibilityTextClient.acceptsEnabled(nil, role: "AXTextArea"))
    }

    func testOtherRolesStillRequireEnabledAttribute() {
        for role in ["AXTextField", "AXComboBox", "AXButton", ""] {
            XCTAssertFalse(AccessibilityTextClient.acceptsEnabled(nil, role: role), role)
        }
    }

    func testExplicitEnabledAndDisabledStatesAreRespected() {
        for role in ["AXTextArea", "AXTextField", "AXComboBox"] {
            XCTAssertTrue(AccessibilityTextClient.acceptsEnabled(kCFBooleanTrue, role: role), role)
            XCTAssertFalse(AccessibilityTextClient.acceptsEnabled(kCFBooleanFalse, role: role), role)
        }
    }

    func testPresentEnabledValueMustBeBoolean() {
        let values: [CFTypeRef] = [NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: 42),
                                   "true" as CFString, NSArray(), NSDictionary()]
        for value in values {
            XCTAssertFalse(AccessibilityTextClient.acceptsEnabled(value, role: "AXTextArea"))
        }
    }
}
