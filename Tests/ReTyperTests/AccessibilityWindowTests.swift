import ApplicationServices
import XCTest
@testable import ReTyper

final class AccessibilityWindowTests: XCTestCase {
    private static let pid: pid_t = 900_001
    private static let otherPID: pid_t = 900_002

    func testDirectWindowIsPreferredIncludingNonactivatingTargets() throws {
        for activationPID in [Self.pid, Self.otherPID] {
            let fixture = WindowFixture()
            fixture.activePID = activationPID
            fixture.attributes[kAXWindowAttribute] = (.success, fixture.window)
            let client = fixture.client()

            let result = try client.resolveWindow(fixture.field, applicationPID: Self.pid,
                                                  activationPID: activationPID, deadline: 1)
            XCTAssertEqual(result.source, .field)
            XCTAssertTrue(CFEqual(result.element, fixture.window))
            XCTAssertEqual(fixture.reads, [kAXWindowAttribute])
            XCTAssertTrue(try client.isFocused(fixture.target(source: result.source,
                                                              activationPID: activationPID), deadline: 1))
            XCTAssertFalse(fixture.reads.contains(kAXFocusedWindowAttribute))
        }
    }

    func testAbsentFieldWindowUsesAndRevalidatesApplicationSource() throws {
        for error: AXError in [.noValue, .attributeUnsupported, .success] {
            let fixture = WindowFixture()
            fixture.attributes[kAXWindowAttribute] = (error, nil)
            let client = fixture.client()

            let result = try client.resolveWindow(fixture.field, applicationPID: Self.pid,
                                                  activationPID: Self.pid, deadline: 1)
            XCTAssertEqual(result.source, .application)
            XCTAssertTrue(CFEqual(result.element, fixture.window))
            XCTAssertEqual(fixture.reads, [kAXWindowAttribute, kAXFocusedAttribute,
                                           kAXFocusedWindowAttribute, kAXRoleAttribute])
            fixture.reads.removeAll()
            XCTAssertTrue(try client.isFocused(fixture.target(source: result.source), deadline: 1))
            XCTAssertEqual(fixture.reads, [kAXFocusedUIElementAttribute, kAXFocusedAttribute,
                                           kAXFocusedWindowAttribute, kAXRoleAttribute])
        }
    }

    func testFallbackRequiresStrictTrueBooleanFieldFocus() {
        let cases: [(String, AXError, CFTypeRef?)] = [
            ("false", .success, kCFBooleanFalse),
            ("no value", .noValue, nil),
            ("unsupported", .attributeUnsupported, nil),
            ("nil", .success, nil),
            ("number one", .success, NSNumber(value: 1)),
            ("string", .success, "true" as CFString),
        ]
        for (label, error, value) in cases {
            let fixture = WindowFixture()
            fixture.attributes[kAXFocusedAttribute] = (error, value)
            XCTAssertThrowsError(try fixture.client().resolveWindow(fixture.field, applicationPID: Self.pid,
                                                                    activationPID: Self.pid, deadline: 1), label) {
                XCTAssertEqual($0 as? TextAccessError, .focusChanged, label)
            }
            XCTAssertEqual(fixture.reads, [kAXWindowAttribute, kAXFocusedAttribute], label)
        }
    }

    func testFallbackRequiresMatchingPositiveApplicationActivationAndFrontmostPIDs() {
        let cases: [(pid_t, pid_t, pid_t?)] = [
            (0, 0, 0), (-1, -1, -1), (Self.pid, 0, 0),
            (Self.pid, Self.otherPID, Self.otherPID),
            (Self.pid, Self.pid, Self.otherPID), (Self.pid, Self.pid, nil),
        ]
        for (applicationPID, activationPID, activePID) in cases {
            let fixture = WindowFixture()
            fixture.activePID = activePID
            XCTAssertThrowsError(try fixture.client().resolveWindow(fixture.field, applicationPID: applicationPID,
                                                                    activationPID: activationPID, deadline: 1)) {
                XCTAssertEqual($0 as? TextAccessError, .focusChanged)
            }
            XCTAssertEqual(fixture.reads, [kAXWindowAttribute])
        }
    }

    func testFallbackRejectsInvalidWindowRole() {
        for role: CFTypeRef in ["AXTextArea" as CFString, NSNumber(value: 1)] {
            let fixture = WindowFixture()
            fixture.attributes[kAXRoleAttribute] = (.success, role)
            XCTAssertThrowsError(try fixture.client().resolveWindow(fixture.field, applicationPID: Self.pid,
                                                                    activationPID: Self.pid, deadline: 1)) {
                XCTAssertEqual($0 as? TextAccessError, .invalidValue)
            }
            XCTAssertEqual(fixture.reads.last, kAXRoleAttribute)
        }
    }

    func testFallbackRejectsForeignFieldAndWindowOwners() {
        for foreignField in [true, false] {
            let fixture = WindowFixture()
            let foreign = AXUIElementCreateApplication(Self.otherPID)
            let field = foreignField ? foreign : fixture.field
            if !foreignField { fixture.attributes[kAXFocusedWindowAttribute] = (.success, foreign) }

            XCTAssertThrowsError(try fixture.client().resolveWindow(field, applicationPID: Self.pid,
                                                                    activationPID: Self.pid, deadline: 1)) {
                XCTAssertEqual($0 as? TextAccessError, .focusChanged)
            }
            XCTAssertEqual(fixture.reads.last, kAXRoleAttribute)
        }
    }

    func testMalformedDirectWindowAndReadErrorsNeverQueryFocusedWindow() {
        let cases: [(AXError, CFTypeRef?, TextAccessError)] = [
            (.success, "not an element" as CFString, .invalidValue),
            (.success, NSNumber(value: 1), .invalidValue),
            (.cannotComplete, nil, .system(AXError.cannotComplete.rawValue)),
        ]
        for (error, value, expected) in cases {
            let fixture = WindowFixture()
            fixture.attributes[kAXWindowAttribute] = (error, value)
            XCTAssertThrowsError(try fixture.client().resolveWindow(fixture.field, applicationPID: Self.pid,
                                                                    activationPID: Self.pid, deadline: 1)) {
                XCTAssertEqual($0 as? TextAccessError, expected)
            }
            XCTAssertEqual(fixture.reads, [kAXWindowAttribute])
        }
    }

    func testFieldSourceLossCannotBeRescuedByApplicationWindow() throws {
        for error: AXError in [.noValue, .attributeUnsupported, .success] {
            let fixture = WindowFixture()
            fixture.attributes[kAXWindowAttribute] = (.success, fixture.window)
            let client = fixture.client()
            let target = fixture.target(source: .field)
            XCTAssertTrue(try client.isFocused(target, deadline: 1))

            fixture.attributes[kAXWindowAttribute] = (error, nil)
            fixture.reads.removeAll()
            XCTAssertThrowsError(try client.isFocused(target, deadline: 1)) {
                XCTAssertEqual($0 as? TextAccessError, .unavailable)
            }
            XCTAssertEqual(fixture.reads, [kAXFocusedUIElementAttribute, kAXWindowAttribute])
        }
    }

    func testApplicationSourceLossCannotBeRescuedByNewDirectWindow() throws {
        for error: AXError in [.noValue, .attributeUnsupported, .success] {
            let fixture = WindowFixture()
            let client = fixture.client()
            let target = fixture.target(source: .application)
            XCTAssertTrue(try client.isFocused(target, deadline: 1))

            fixture.attributes[kAXWindowAttribute] = (.success, fixture.window)
            fixture.attributes[kAXFocusedWindowAttribute] = (error, nil)
            fixture.reads.removeAll()
            XCTAssertThrowsError(try client.isFocused(target, deadline: 1)) {
                XCTAssertEqual($0 as? TextAccessError, .unavailable)
            }
            XCTAssertEqual(fixture.reads, [kAXFocusedUIElementAttribute, kAXFocusedAttribute,
                                           kAXFocusedWindowAttribute])
        }
    }

    func testIsFocusedRejectsChangedFieldBeforeResolvingWindow() throws {
        for source: TextWindowSource in [.field, .application] {
            let fixture = WindowFixture()
            fixture.attributes[kAXWindowAttribute] = (.success, fixture.window)
            fixture.attributes[kAXFocusedUIElementAttribute] = (.success, AXUIElementCreateApplication(Self.otherPID))
            XCTAssertFalse(try fixture.client().isFocused(fixture.target(source: source), deadline: 1))
            XCTAssertEqual(fixture.reads, [kAXFocusedUIElementAttribute])
        }
    }

    func testIsFocusedRejectsChangedWindow() throws {
        for source: TextWindowSource in [.field, .application] {
            let fixture = WindowFixture()
            // A different fake application handle also has a different owner PID.
            let changed = AXUIElementCreateApplication(Self.otherPID)
            fixture.attributes[kAXWindowAttribute] = (.success, changed)
            fixture.attributes[kAXFocusedWindowAttribute] = (.success, changed)
            let client = fixture.client()
            let target = fixture.target(source: source)
            if source == .field {
                XCTAssertFalse(try client.isFocused(target, deadline: 1))
            } else {
                XCTAssertThrowsError(try client.isFocused(target, deadline: 1)) {
                    XCTAssertEqual($0 as? TextAccessError, .focusChanged)
                }
                XCTAssertFalse(fixture.reads.contains(kAXWindowAttribute))
            }
        }
    }

    func testIsFocusedRejectsFallbackFocusLoss() throws {
        for focus: CFTypeRef? in [kCFBooleanFalse, nil] {
            let fixture = WindowFixture()
            let client = fixture.client()
            let target = fixture.target(source: .application)
            XCTAssertTrue(try client.isFocused(target, deadline: 1))

            fixture.attributes[kAXFocusedAttribute] = (.success, focus)
            fixture.attributes[kAXWindowAttribute] = (.success, fixture.window)
            fixture.reads.removeAll()
            XCTAssertThrowsError(try client.isFocused(target, deadline: 1)) {
                XCTAssertEqual($0 as? TextAccessError, .focusChanged)
            }
            XCTAssertEqual(fixture.reads, [kAXFocusedUIElementAttribute, kAXFocusedAttribute])
        }
    }

    func testIsFocusedRejectsChangedActivationWithoutAttributeReads() throws {
        for source: TextWindowSource in [.field, .application] {
            for activePID: pid_t? in [Self.otherPID, nil] {
                let fixture = WindowFixture()
                fixture.activePID = activePID
                XCTAssertFalse(try fixture.client().isFocused(fixture.target(source: source), deadline: 1))
                XCTAssertTrue(fixture.reads.isEmpty)
            }
        }
    }

    func testFallbackRechecksFrontmostAfterWindowReads() {
        let fixture = WindowFixture()
        let client = AccessibilityTextClient(now: { 0 }, frontmost: {
            fixture.reads.contains(kAXRoleAttribute) ? Self.otherPID : Self.pid
        }, copyAttribute: fixture.read)
        XCTAssertThrowsError(try client.resolveWindow(fixture.field, applicationPID: Self.pid,
                                                      activationPID: Self.pid, deadline: 1)) {
            XCTAssertEqual($0 as? TextAccessError, .focusChanged)
        }
        XCTAssertEqual(fixture.reads.last, kAXRoleAttribute)
    }

    func testExpiredDeadlinePreventsAllAttributeReads() {
        for source: TextWindowSource? in [nil, .field, .application] {
            let fixture = WindowFixture()
            let client = fixture.client(now: { 1 })
            XCTAssertThrowsError(try client.resolveWindow(fixture.field, applicationPID: Self.pid,
                                                          activationPID: Self.pid, source: source, deadline: 1)) {
                XCTAssertEqual($0 as? TextAccessError, .timeout)
            }
            if let source {
                XCTAssertThrowsError(try client.isFocused(fixture.target(source: source), deadline: 1)) {
                    XCTAssertEqual($0 as? TextAccessError, .timeout)
                }
            }
            XCTAssertTrue(fixture.reads.isEmpty)
        }
    }

    func testDeadlineIncludesTimeSpentReadingAttributes() {
        for source: TextWindowSource in [.field, .application] {
            let windowReads = source == .field ? [kAXWindowAttribute]
                : [kAXWindowAttribute, kAXFocusedAttribute, kAXFocusedWindowAttribute, kAXRoleAttribute]
            for revalidate in [false, true] {
                let attributes = revalidate ? [kAXFocusedUIElementAttribute] + windowReads.filter {
                    source == .field || $0 != kAXWindowAttribute
                } : windowReads
                for expiringRead in attributes {
                    let fixture = WindowFixture()
                    if source == .field { fixture.attributes[kAXWindowAttribute] = (.success, fixture.window) }
                    let client = fixture.client(now: { fixture.reads.contains(expiringRead) ? 1 : 0 })
                    if revalidate {
                        XCTAssertThrowsError(try client.isFocused(fixture.target(source: source), deadline: 1)) {
                            XCTAssertEqual($0 as? TextAccessError, .timeout, expiringRead)
                        }
                    } else {
                        XCTAssertThrowsError(try client.resolveWindow(fixture.field, applicationPID: Self.pid,
                                                                      activationPID: Self.pid, deadline: 1)) {
                            XCTAssertEqual($0 as? TextAccessError, .timeout, expiringRead)
                        }
                    }
                    XCTAssertEqual(fixture.reads.last, expiringRead)
                }
            }
        }
    }

    func testIsFocusedChecksDeadlineAfterFinalActivationProbe() {
        for source: TextWindowSource in [.field, .application] {
            let fixture = WindowFixture()
            fixture.attributes[kAXWindowAttribute] = (.success, fixture.window)
            let finalRead = source == .field ? kAXWindowAttribute : kAXRoleAttribute
            var time: TimeInterval = 0
            let client = AccessibilityTextClient(now: { time }, frontmost: {
                if fixture.reads.contains(finalRead) { time = 1 }
                return Self.pid
            }, copyAttribute: fixture.read)
            XCTAssertThrowsError(try client.isFocused(fixture.target(source: source), deadline: 1)) {
                XCTAssertEqual($0 as? TextAccessError, .timeout)
            }
            XCTAssertEqual(fixture.reads.last, finalRead)
        }
    }

    func testResolveWindowChecksDeadlineAfterFinalActivationProbe() {
        let fixture = WindowFixture()
        var time: TimeInterval = 0
        let client = AccessibilityTextClient(now: { time }, frontmost: {
            if fixture.reads.contains(kAXRoleAttribute) { time = 1 }
            return Self.pid
        }, copyAttribute: fixture.read)
        XCTAssertThrowsError(try client.resolveWindow(fixture.field, applicationPID: Self.pid,
                                                      activationPID: Self.pid, deadline: 1)) {
            XCTAssertEqual($0 as? TextAccessError, .timeout)
        }
        XCTAssertEqual(fixture.reads.last, kAXRoleAttribute)
    }

    private final class WindowFixture {
        // Handles are never used for remote reads; ownership checks remain real and handle-local.
        let field = AXUIElementCreateApplication(AccessibilityWindowTests.pid)
        let window = AXUIElementCreateApplication(AccessibilityWindowTests.pid)
        var activePID: pid_t? = AccessibilityWindowTests.pid
        var attributes: [String: (AXError, CFTypeRef?)]
        var reads: [String] = []

        init() {
            attributes = [
                kAXWindowAttribute: (.noValue, nil),
                kAXFocusedAttribute: (.success, kCFBooleanTrue),
                kAXFocusedWindowAttribute: (.success, window),
                kAXRoleAttribute: (.success, kAXWindowRole as CFString),
                kAXFocusedUIElementAttribute: (.success, field),
            ]
        }

        func read(_ element: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
            reads.append(name)
            guard let response = attributes[name] else {
                XCTFail("Unexpected attribute read: \(name)")
                return (.failure, nil)
            }
            return response
        }

        func client(now: @escaping () -> TimeInterval = { 0 }) -> AccessibilityTextClient {
            AccessibilityTextClient(now: now, frontmost: { self.activePID }, copyAttribute: read)
        }

        func target(source: TextWindowSource, activationPID: pid_t = AccessibilityWindowTests.pid) -> TextAccessCapability {
            TextAccessCapability(applicationPID: AccessibilityWindowTests.pid, activationPID: activationPID,
                                 element: field, window: window, windowSource: source, elementRole: "AXTextArea",
                                 canSetValue: true, canSetSelection: true)
        }
    }
}
