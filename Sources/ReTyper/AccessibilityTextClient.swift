import AppKit
import ApplicationServices

/// AX is an external, potentially stale data source. Errors never select a more
/// destructive editing strategy, and no text write is performed by this client.
final class AccessibilityTextClient: TextAccessProviding {
    private let now: () -> TimeInterval
    private let frontmost: () -> pid_t?
    private let copyAttribute: (AXUIElement, String) -> (AXError, CFTypeRef?)
    private var requestedAccessibility: [pid_t: Date] = [:]

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         frontmost: @escaping () -> pid_t? = {
             if Thread.isMainThread { return NSWorkspace.shared.frontmostApplication?.processIdentifier }
             return DispatchQueue.main.sync { NSWorkspace.shared.frontmostApplication?.processIdentifier }
         },
         copyAttribute: @escaping (AXUIElement, String) -> (AXError, CFTypeRef?) = { element, name in
             var value: CFTypeRef?
             let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
             return (error, value)
         }) {
        self.now = now
        self.frontmost = frontmost
        self.copyAttribute = copyAttribute
    }

    func captureCapability(applicationPID: pid_t, activationPID: pid_t, deadline: TimeInterval) throws -> TextAccessCapability {
        guard applicationPID > 0, activationPID > 0,
              frontmost() == activationPID else {
            throw TextAccessError.focusChanged
        }
        guard let application = NSRunningApplication(processIdentifier: applicationPID), !application.isTerminated else {
            throw TextAccessError.unavailable
        }
        let app = AXUIElementCreateApplication(applicationPID)
        // This is a request, not evidence that a provider's tree is already ready.
        if let launchDate = application.launchDate, requestedAccessibility[applicationPID] != launchDate {
            try configureTimeout(app, deadline: deadline)
            let error = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if error == .success { requestedAccessibility[applicationPID] = launchDate }
            // Unsupported is normal for native providers; transient failures are not cached.
        }

        let element = try elementValue(attribute(app, kAXFocusedUIElementAttribute, deadline: deadline))
        guard let role = try attribute(element, kAXRoleAttribute, deadline: deadline) as? String,
               ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) else {
            Logger.shared.log("AX capture rejected: unsupported role or role type")
            throw TextAccessError.unavailable
        }
        let subrole = try optionalAttribute(element, kAXSubroleAttribute, deadline: deadline)
        guard Self.acceptsSubrole(subrole),
              Self.acceptsEnabled(try optionalAttribute(element, kAXEnabledAttribute, deadline: deadline),
                                  role: role) else {
            Logger.shared.log("AX capture rejected: subrole or enabled state")
            throw TextAccessError.unavailable
        }

        let window = try resolveWindow(element, applicationPID: applicationPID, activationPID: activationPID,
                                       deadline: deadline)
        let target = TextAccessCapability(
            applicationPID: applicationPID, activationPID: activationPID, element: element,
            window: window.element, windowSource: window.source, elementRole: role,
            canSetValue: try isSettable(element, kAXValueAttribute, deadline: deadline),
            canSetSelection: try isSettable(element, kAXSelectedTextRangeAttribute, deadline: deadline)
        )
        guard try isFocused(target, deadline: deadline) else { throw TextAccessError.focusChanged }
        return target
    }

    static func acceptsSubrole(_ value: CFTypeRef?) -> Bool {
        guard let value else { return true }
        guard let subrole = value as? String else { return false }
        return subrole != kAXSecureTextFieldSubrole
    }

    static func acceptsEnabled(_ value: CFTypeRef?, role: String) -> Bool {
        // NSTextView may omit AXEnabled; writable value and selection remain mandatory.
        guard let value else { return role == "AXTextArea" }
        return isTrueBoolean(value)
    }

    private static func isTrueBoolean(_ value: CFTypeRef?) -> Bool {
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        let boolean = value as! CFBoolean
        return CFBooleanGetValue(boolean)
    }

    /// Choose once during capture. Revalidation must never rescue a lost source with another one.
    func resolveWindow(_ element: AXUIElement, applicationPID: pid_t, activationPID: pid_t,
                       source: TextWindowSource? = nil,
                       deadline: TimeInterval) throws -> (element: AXUIElement, source: TextWindowSource) {
        if source != .application {
            if let value = try optionalAttribute(element, kAXWindowAttribute, deadline: deadline) {
                return (try elementValue(value), .field)
            }
            guard source == nil else { throw TextAccessError.unavailable }
        }

        guard applicationPID > 0, applicationPID == activationPID, frontmost() == applicationPID,
              Self.isTrueBoolean(try optionalAttribute(element, kAXFocusedAttribute, deadline: deadline)) else {
            throw TextAccessError.focusChanged
        }
        let app = AXUIElementCreateApplication(applicationPID)
        let window = try elementValue(attribute(app, kAXFocusedWindowAttribute, deadline: deadline))
        guard try attribute(window, kAXRoleAttribute, deadline: deadline) as? String == kAXWindowRole else {
            throw TextAccessError.invalidValue
        }
        for reference in [element, window] {
            var owner: pid_t = 0
            let error = AXUIElementGetPid(reference, &owner)
            guard error == .success else { throw TextAccessError.system(error.rawValue) }
            guard owner == applicationPID else { throw TextAccessError.focusChanged }
        }
        try checkDeadline(deadline)
        guard frontmost() == applicationPID else { throw TextAccessError.focusChanged }
        try checkDeadline(deadline)
        return (window, .application)
    }

    func isFocused(_ target: TextAccessCapability, deadline: TimeInterval) throws -> Bool {
        try checkDeadline(deadline)
        guard frontmost() == target.activationPID else { return false }
        let app = AXUIElementCreateApplication(target.applicationPID)
        let focused = try elementValue(attribute(app, kAXFocusedUIElementAttribute, deadline: deadline))
        guard CFEqual(focused, target.element) else { return false }
        let window = try resolveWindow(focused, applicationPID: target.applicationPID,
                                       activationPID: target.activationPID, source: target.windowSource,
                                       deadline: deadline)
        let fieldFocused: Bool?
        if target.applicationPID != target.activationPID {
            fieldFocused = Self.isTrueBoolean(try optionalAttribute(focused, kAXFocusedAttribute, deadline: deadline))
        } else {
            fieldFocused = nil
        }
        let stillFocused = CFEqual(window.element, target.window)
            && target.acceptsActivation(frontmost(), fieldFocused: fieldFocused)
        try checkDeadline(deadline)
        return stillFocused
    }

    func snapshot(_ target: TextAccessCapability, deadline: TimeInterval) throws -> TextSnapshot {
        guard try isFocused(target, deadline: deadline) else { throw TextAccessError.focusChanged }
        let first = try readSnapshot(target.element, deadline: deadline)
        let second = try readSnapshot(target.element, deadline: deadline)
        guard first.matches(value: second.value, range: second.caretLocation..<(second.caretLocation + second.selectionLength)) else {
            Logger.shared.log("AX snapshot rejected: consecutive reads differ")
            throw TextAccessError.inconsistentSnapshot
        }
        guard try isFocused(target, deadline: deadline) else { throw TextAccessError.focusChanged }
        try checkDeadline(deadline)
        return second
    }

    func selectRange(_ range: Range<Int>, in target: TextAccessCapability, deadline: TimeInterval) throws {
        guard target.supportsReplacement, try isFocused(target, deadline: deadline) else {
            throw TextAccessError.focusChanged
        }
        let current = try snapshot(target, deadline: deadline)
        guard Self.validRange(range, in: current.value) else { throw TextAccessError.invalidValue }
        var selection = CFRange(location: range.lowerBound, length: range.count)
        guard let value = AXValueCreate(.cfRange, &selection) else { throw TextAccessError.invalidValue }
        try configureTimeout(target.element, deadline: deadline)
        let error = AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, value)
        guard error == .success else { throw TextAccessError.system(error.rawValue) }
        try checkDeadline(deadline)
        // The caller must confirm both the range AND the content before sending input.
    }

    private func readSnapshot(_ element: AXUIElement, deadline: TimeInterval) throws -> TextSnapshot {
        guard let text = try attribute(element, kAXValueAttribute, deadline: deadline) as? String else {
            Logger.shared.log("AX snapshot rejected: value type")
            throw TextAccessError.invalidValue
        }
        let rangeValue = try attribute(element, kAXSelectedTextRangeAttribute, deadline: deadline)
        guard CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            Logger.shared.log("AX snapshot rejected: selection range type")
            throw TextAccessError.invalidValue
        }
        let axValue = rangeValue as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else {
            Logger.shared.log("AX snapshot rejected: selection range encoding")
            throw TextAccessError.invalidValue
        }
        let count = text.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= count,
              range.length <= count - range.location,
               Self.validRange(range.location..<(range.location + range.length), in: text) else {
            Logger.shared.log("AX snapshot rejected: invalid selection bounds or grapheme boundary")
            throw TextAccessError.invalidValue
        }
        let selectedValue = try optionalAttribute(element, kAXSelectedTextAttribute, deadline: deadline)
        if let selectedValue, !(selectedValue is String) {
            Logger.shared.log("AX snapshot rejected: selected text type")
            throw TextAccessError.invalidValue
        }
        let selected = selectedValue as? String
        let start = String.Index(utf16Offset: range.location, in: text)
        let end = String.Index(utf16Offset: range.location + range.length, in: text)
        if let selected, !selected.utf16.elementsEqual(text[start..<end].utf16) {
            Logger.shared.log("AX snapshot rejected: selected text does not match range")
            throw TextAccessError.inconsistentSnapshot
        }
        return TextSnapshot(value: text, caretLocation: range.location, selectionLength: range.length, selectedText: selected)
    }

    private static func validRange(_ range: Range<Int>, in text: String) -> Bool {
        guard range.lowerBound >= 0, range.upperBound <= text.utf16.count else { return false }
        let lower = String.Index(utf16Offset: range.lowerBound, in: text)
        let upper = String.Index(utf16Offset: range.upperBound, in: text)
        return (lower == text.endIndex || text.indices.contains(lower))
            && (upper == text.endIndex || text.indices.contains(upper))
    }

    private func attribute(_ element: AXUIElement, _ name: String, deadline: TimeInterval) throws -> CFTypeRef {
        guard let value = try optionalAttribute(element, name, deadline: deadline) else {
            Logger.shared.log("AX required attribute absent: \(name)")
            throw TextAccessError.unavailable
        }
        return value
    }

    private func optionalAttribute(_ element: AXUIElement, _ name: String, deadline: TimeInterval) throws -> CFTypeRef? {
        try configureTimeout(element, deadline: deadline)
        let (error, value) = copyAttribute(element, name)
        try checkDeadline(deadline)
        switch error {
        case .success: return value
        case .noValue, .attributeUnsupported: return nil
        default:
            Logger.shared.log("AX read failed: attribute=\(name), code=\(error.rawValue)")
            throw TextAccessError.system(error.rawValue)
        }
    }

    private func isSettable(_ element: AXUIElement, _ name: String, deadline: TimeInterval) throws -> Bool {
        try configureTimeout(element, deadline: deadline)
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(element, name as CFString, &settable)
        try checkDeadline(deadline)
        switch error {
        case .success: return settable.boolValue
        case .attributeUnsupported: return false
        default:
            Logger.shared.log("AX write-capability query failed: attribute=\(name), code=\(error.rawValue)")
            throw TextAccessError.system(error.rawValue)
        }
    }

    private func elementValue(_ value: CFTypeRef) throws -> AXUIElement {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            Logger.shared.log("AX element rejected: reference type")
            throw TextAccessError.invalidValue
        }
        return value as! AXUIElement
    }

    private func configureTimeout(_ element: AXUIElement, deadline: TimeInterval) throws {
        try checkDeadline(deadline)
        let remaining = deadline - now()
        guard remaining > 0 else { throw TextAccessError.timeout }
        let error = AXUIElementSetMessagingTimeout(element, Float(min(remaining, 0.1)))
        guard error == .success else {
            Logger.shared.log("AX timeout configuration failed: code=\(error.rawValue)")
            throw TextAccessError.system(error.rawValue)
        }
    }

    private func checkDeadline(_ deadline: TimeInterval) throws {
        guard now() < deadline else {
            Logger.shared.log("AX operation rejected: deadline exceeded")
            throw TextAccessError.timeout
        }
    }

}
