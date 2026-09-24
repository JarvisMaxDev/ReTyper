import Cocoa
import Carbon.HIToolbox

/// Real side effects of one replacement: key presses, the general pasteboard and read-only
/// Accessibility queries. Create one per hotkey; call it from a background queue.
final class SystemReplacementHost: ReplacementHost {
    private let pid: pid_t
    private let startKeyDownCount: Int
    private var snapshot: ClipboardSnapshot?
    /// The pasteboard state ReTyper caused last; restore only if nobody changed it since.
    private var expectedChangeCount: Int?
    private var didPaste = false

    init(pid: pid_t, keyDownCount: Int) {
        self.pid = pid
        startKeyDownCount = keyDownCount
    }

    func selection() -> TextSelection? {
        if let selection = FocusedText.selection() { return selection }
        // Electron apps expose text fields only after a request; give the tree a moment.
        guard FocusedText.requestAccessibility(pid: pid) else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        while ProcessInfo.processInfo.systemUptime < deadline {
            usleep(20_000)
            if let selection = FocusedText.selection() { return selection }
        }
        return nil
    }

    func settledSelectionLength(expected: Int?) -> Int? {
        guard var length = FocusedText.selection()?.length else {
            usleep(100_000) // 0.9.0 timing for fields that do not report a selection
            return nil
        }
        let isSettled: (Int) -> Bool = { length in expected.map { length == $0 } ?? (length > 0) }
        let deadline = ProcessInfo.processInfo.systemUptime + (expected == nil ? 0.4 : 0.5)
        while !isSettled(length), ProcessInfo.processInfo.systemUptime < deadline {
            usleep(10_000)
            guard let next = FocusedText.selection()?.length else { return nil }
            length = next
        }
        return length
    }

    func isSecureField() -> Bool {
        FocusedText.isSecure()
    }

    func press(_ key: EditingKey) {
        switch key {
        case .selectToLineStart:
            KeyboardMonitor.press(keyCode: CGKeyCode(kVK_LeftArrow), flags: [.maskCommand, .maskShift])
        case .shrinkSelectionFromStart(let count):
            for _ in 0..<count {
                KeyboardMonitor.press(keyCode: CGKeyCode(kVK_RightArrow), flags: .maskShift, holdMicroseconds: 1_000)
            }
        case .collapseToEnd:
            KeyboardMonitor.press(keyCode: CGKeyCode(kVK_RightArrow))
        }
    }

    func copySelection() -> String? {
        let before = onMain { () -> Int in
            let pasteboard = NSPasteboard.general
            if snapshot == nil { snapshot = ClipboardSnapshot(pasteboard) }
            return pasteboard.changeCount
        }
        KeyboardMonitor.press(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        // Up to 300 ms for the copy, then up to 50 ms more for its text to be written.
        var changedAt: Int?
        for attempt in 0..<35 {
            usleep(10_000)
            let state = onMain { () -> (count: Int, text: String?) in
                let pasteboard = NSPasteboard.general
                return (pasteboard.changeCount, pasteboard.string(forType: .string))
            }
            if state.count != before {
                expectedChangeCount = state.count
                if let text = state.text { return text }
                let first = changedAt ?? attempt
                changedAt = first
                if attempt - first >= 5 { break }
            } else if attempt >= 29 {
                break
            }
        }
        Logger.shared.log(changedAt == nil ? "Copy did not change the pasteboard" : "Copy produced no text")
        return nil
    }

    func paste(_ text: String) {
        onMain { expectedChangeCount = ClipboardSnapshot.writeTemporary(text, to: NSPasteboard.general) }
        KeyboardMonitor.press(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        didPaste = true
    }

    func contextIsUnchanged() -> Bool {
        onMain {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                && KeyboardMonitor.shared?.userKeyDownCount == startKeyDownCount
        }
    }

    /// Puts the user's clipboard back unless something else was copied in the meantime.
    func restoreClipboard() {
        guard let snapshot, let expected = expectedChangeCount else { return }
        // Give the target application time to read the paste (0.9.0 waited 500 ms as well).
        let delay: TimeInterval = didPaste ? 0.5 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !snapshot.restore(to: .general, ifUnchangedSince: expected) {
                Logger.shared.log("Clipboard restore skipped: pasteboard changed by another copy")
            }
        }
    }

    private func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}

/// Complete copy of the user's pasteboard, taken before ReTyper's first Cmd+C.
struct ClipboardSnapshot {
    /// nspasteboard.org markers: clipboard managers do not record ReTyper's own writes.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")

    private let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    /// Restores the snapshot unless something was copied after `expectedChangeCount`.
    @discardableResult
    func restore(to pasteboard: NSPasteboard, ifUnchangedSince expectedChangeCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else { return false }
        restore(to: pasteboard)
        return true
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            // The original copy is already in any clipboard history.
            item.setData(Data(), forType: Self.transientType)
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }

    /// Writes ReTyper's temporary text and returns the resulting change count.
    static func writeTemporary(_ text: String, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        item.setData(Data(), forType: autoGeneratedType)
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }
}

/// Read-only Accessibility queries about the focused field; nil means the field does not tell.
enum FocusedText {
    /// Accessed only from the replacement queue.
    private static var requestedAccessibility: [pid_t: Date] = [:]

    static func selection() -> TextSelection? {
        guard let element = focusedElement(),
              let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let rangeValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(rangeValue) == .cfRange, AXValueGetValue(rangeValue, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { return nil }
        return TextSelection(location: range.location, length: range.length)
    }

    static func isSecure() -> Bool {
        guard let element = focusedElement() else { return false }
        return attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
    }

    /// Electron apps build their accessibility tree only on request. Returns true once per launch.
    static func requestAccessibility(pid: pid_t) -> Bool {
        guard let launchDate = NSRunningApplication(processIdentifier: pid)?.launchDate,
              requestedAccessibility[pid] != launchDate else { return false }
        requestedAccessibility[pid] = launchDate
        let error = AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid),
                                                 "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return error == .success
    }

    /// The focused element across all apps, including panels that do not activate their app.
    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        // Applies to this process: a hung application cannot stall a replacement for long.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        guard let value = attribute(systemWide, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        return element
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
