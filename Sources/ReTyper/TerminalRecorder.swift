import Cocoa
import Carbon

struct TerminalContext {
    let pid: pid_t
    let launched: Date
    let window: AXUIElement
    let field: AXUIElement

    static func capture(pid: pid_t) -> TerminalContext? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              TerminalReplacement.supportedBundleIDs.contains(app.bundleIdentifier ?? ""),
              let launched = app.launchDate, let field = FocusedText.focusedElement() else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(field, &owner) == .success, owner == pid,
              FocusedText.attribute(field, kAXRoleAttribute) as? String == kAXTextAreaRole,
              FocusedText.attribute(field, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole
        else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let raw = FocusedText.attribute(application, kAXFocusedWindowAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return TerminalContext(pid: pid, launched: launched, window: raw as! AXUIElement, field: field)
    }
    func isCurrent() -> Bool {
        guard let other = Self.capture(pid: pid) else { return false }
        return launched == other.launched && CFEqual(window, other.window) && CFEqual(field, other.field)
    }
}

/// Only the foreground supported terminal is recorded. AX reads are outside the event tap;
/// an epoch (not the per-character generation) rejects stale asynchronous focus captures.
final class TerminalRecorder {
    private(set) var fragment = TypedFragment()
    private(set) var context: TerminalContext?
    private var pid: pid_t?
    private var epoch = 0
    private var binding = false
    private var observer: AXObserver?
    private var secureTimer: Timer?
    private var layouts: [String: KeyLayout?] = [:]
    private let focusQueue = DispatchQueue(label: "com.retyper.app.terminal-focus")

    func setTarget(_ app: NSRunningApplication?) {
        stop()
        guard let app, TerminalReplacement.supportedBundleIDs.contains(app.bundleIdentifier ?? "") else { return }
        let targetPID = app.processIdentifier
        var created: AXObserver?
        let error = AXObserverCreate(targetPID, { observer, _, notification, pointer in
            guard let pointer else { return }
            let recorder = Unmanaged<TerminalRecorder>.fromOpaque(pointer).takeUnretainedValue()
            guard let current = recorder.observer, CFEqual(current, observer) else { return }
            recorder.reset(reason: notification as String)
        }, &created)
        guard error == .success, let created else { return }
        let application = AXUIElementCreateApplication(targetPID)
        AXUIElementSetMessagingTimeout(application, 0.15)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let windowResult = AXObserverAddNotification(created, application, kAXFocusedWindowChangedNotification as CFString, pointer)
        let focusResult = AXObserverAddNotification(created, application, kAXFocusedUIElementChangedNotification as CFString, pointer)
        guard windowResult == .success, focusResult == .success else {
            Logger.shared.log("Terminal context notifications unavailable: \(windowResult.rawValue)/\(focusResult.rawValue)")
            return
        }
        pid = targetPID; observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        secureTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            if IsSecureEventInputEnabled() { self?.suspend() }
        }
        secureTimer?.tolerance = 0.01
    }
    func stop() {
        secureTimer?.invalidate(); secureTimer = nil
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; pid = nil; reset(reason: "target stopped")
    }
    func reset(reason: String = "input boundary") {
        if !fragment.text.isEmpty { Logger.shared.log("Terminal fragment reset: \(reason)") }
        epoch &+= 1; binding = false; context = nil; fragment.reset()
    }
    func suspend() {
        epoch &+= 1; binding = false; context = nil; fragment.suspend()
    }
    private func layout() -> KeyLayout? {
        let id = LayoutManager.shared.currentLayoutID()
        let keyboardType = UInt32(LMGetKbdType())
        let key = "\(id)|\(keyboardType)"
        if let cached = layouts[key] { return cached }
        if layouts.count >= 32 { layouts.removeAll(keepingCapacity: true) }
        let result = KeyLayout.system(id: id, keyboardType: keyboardType)
        layouts.updateValue(result, forKey: key)
        return result
    }
    static func unicode(_ event: CGEvent) -> String {
        var count = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &count, unicodeString: nil)
        guard count <= 8 else { return "\u{FFFD}\u{FFFD}" }
        var units = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &count, unicodeString: &units)
        guard count <= units.count else { return "\u{FFFD}\u{FFFD}" }
        return String(utf16CodeUnits: units, count: count)
    }
    func record(_ event: CGEvent) {
        guard let pid else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, !IsSecureEventInputEnabled() else { reset(reason: "target or secure input changed"); return }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        var action = TerminalKey.classify(code: code, flags: event.flags, layout: layout())
        if case .character(let expected) = action {
            let unicode = Self.unicode(event)
            if TerminalInputGate.isReplay(event) {
                // The terminal may translate a held raw event using the newly selected layout.
                // Replay the original event, but do not guess the resulting text for another edit.
                action = .suspend
            } else if !unicode.isEmpty, unicode != String(expected) {
                Logger.shared.log("Terminal recording suspended: event Unicode differs from layout")
                action = .suspend
            }
        }
        switch action {
        case .reset: reset(reason: "reset key")
        case .suspend: suspend()
        case .backspace:
            fragment.deleteBackward()
            if fragment.text.isEmpty, !fragment.isSuspended { reset() }
        case .character(let character):
            fragment.append(character)
            if fragment.isSuspended { context = nil; return }
            guard context == nil, !binding else { return }
            binding = true
            let token = epoch
            focusQueue.async { [weak self] in
                let captured = TerminalContext.capture(pid: pid)
                DispatchQueue.main.async {
                    guard let self, self.pid == pid, self.epoch == token else { return }
                    self.binding = false; self.context = captured
                    if captured == nil { self.suspend() }
                }
            }
        }
    }
    func apply(_ edit: TerminalEdit, ifGeneration generation: Int) {
        guard fragment.generation == generation else { reset(reason: "apply generation mismatch"); return }
        if !fragment.replaceTail(count: edit.deleteCount, with: edit.insert) { reset(reason: "apply length mismatch") }
    }
}
