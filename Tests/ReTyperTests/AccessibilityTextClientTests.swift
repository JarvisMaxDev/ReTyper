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
}
