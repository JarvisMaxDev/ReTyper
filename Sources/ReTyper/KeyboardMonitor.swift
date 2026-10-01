import Cocoa

/// Detects the hotkey and only defers input during a bounded terminal replacement.
/// Only key presses and modifier changes matter; mouse movement and key releases cannot
/// cancel the gesture.
final class KeyboardMonitor {

    /// Shared instance for permission status checks
    static var shared: KeyboardMonitor?

    /// Marks ReTyper's own key presses so the monitor ignores them.
    static let syntheticEventMarker: Int64 = 0x5254_5950_4552_0001

    /// Called on the main thread when the hotkey is triggered.
    var onHotkeyTriggered: (() -> Void)?

    /// Real key presses seen so far; a running replacement compares it to notice typing.
    private(set) var userKeyDownCount = 0
    /// Invalidates an in-flight replacement, independently of modifier gesture recognition.
    private(set) var contextRevision = 0
    /// A later user Copy/Cut owns the clipboard even if it came from another editor window.
    private(set) var clipboardShortcutCount = 0

    func invalidateContext() { contextRevision &+= 1 }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var terminalTap: CFMachPort?
    private var terminalRunLoopSource: CFRunLoopSource?
    private var terminalInterceptionEnabled = false
    private var detector = ModifierHotkeyDetector()
    private let settings = SettingsManager.shared
    let terminalRecorder = TerminalRecorder()
    lazy var terminalInputGate = TerminalInputGate(deliver: { event in
        // Replay the original payload intact, including IME/Unicode input we cannot track.
        event.post(tap: .cghidEventTap)
    }, schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) })

    /// Whether the CGEventTap is installed and enabled
    var isRunning: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    init() {
        KeyboardMonitor.shared = self
    }

    // MARK: - Start / Stop

    func start() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }
        let eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        let eventMask = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                if let refcon {
                    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    if !monitor.terminalInterceptionEnabled || type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        monitor.handle(type: type, event: event)
                        if TerminalInputGate.isReplay(event) { monitor.terminalInputGate.acknowledgeReplay(event) }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.shared.log("⚠️ Failed to create CGEventTap! Grant Accessibility + Input Monitoring permissions.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // The terminal tap must see the hotkey before subsequent input can pass it.
        // Editors retain the passive tap; their clipboard work never blocks an active callback.
        terminalTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: eventMask, callback: { _, type, event, refcon in
                if let refcon {
                    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if monitor.terminalInputGate.busy {
                            monitor.terminalRecorder.reset(reason: "active tap disabled during replacement")
                            monitor.terminalInputGate.release()
                        }
                        if monitor.terminalInterceptionEnabled, let tap = monitor.terminalTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                    } else if !KeyboardMonitor.isSynthetic(event), monitor.terminalInputGate.deferEvent(event) {
                        return nil
                    } else if monitor.terminalInterceptionEnabled {
                        monitor.handle(type: type, event: event)
                        if TerminalInputGate.isReplay(event) { monitor.terminalInputGate.acknowledgeReplay(event) }
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let terminalTap {
            CGEvent.tapEnable(tap: terminalTap, enable: false)
            let terminalSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, terminalTap, 0)
            terminalRunLoopSource = terminalSource
            CFRunLoopAddSource(CFRunLoopGetMain(), terminalSource, .commonModes)
        }

        Logger.shared.log("✅ KeyboardMonitor started (CGEventTap created successfully)")
    }

    func stop() {
        terminalInterceptionEnabled = false
        terminalRecorder.stop()
        terminalInputGate.release()
        if let terminalTap { CFMachPortInvalidate(terminalTap) }
        if let terminalRunLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), terminalRunLoopSource, .commonModes) }
        terminalTap = nil; terminalRunLoopSource = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event Handling

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                Logger.shared.log("🔄 CGEventTap re-enabled (was disabled by system)")
            }
            detector.disarm()
            invalidateContext()
            terminalRecorder.reset(reason: "passive tap disabled")
            return
        }
        guard !Self.isSynthetic(event) else { return }

        switch type {
        case .keyDown:
            userKeyDownCount += 1
            invalidateContext()
            if Self.isClipboardShortcut(keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags) {
                clipboardShortcutCount &+= 1
            }
            // A modifier pressed around another key is a shortcut, not the hotkey.
            detector.disarm()
            terminalRecorder.record(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // A click cancels a pending replacement, not the modifier hotkey itself.
            invalidateContext()
            terminalRecorder.reset(reason: "mouse down")
        case .leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel:
            terminalRecorder.reset(reason: "mouse up or scroll")
        case .flagsChanged:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == 63 || keyCode == 179 { terminalRecorder.reset() }
            if keyCode == 57 { terminalRecorder.reset() }
            if detector.handle(keyCode: keyCode, flags: event.flags, modifier: settings.hotkeyModifier,
                               doubleTapMode: settings.doubleTapMode, now: ProcessInfo.processInfo.systemUptime) {
                if !terminalInputGate.busy {
                    onHotkeyTriggered?()
                }
            }
        default:
            break
        }
    }

    static func isSynthetic(_ event: CGEvent) -> Bool {
        if TerminalInputGate.isReplay(event) { return false }
        return event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker
            || event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid())
    }

    func beginTerminalInputHold() -> Bool {
        guard terminalInterceptionEnabled, let terminalTap, CGEvent.tapIsEnabled(tap: terminalTap) else { return false }
        return terminalInputGate.begin()
    }
    func finishTerminalReplay() {
        detector.disarm()
    }

    func setTerminalTarget(_ app: NSRunningApplication?) {
        terminalRecorder.setTarget(app)
        terminalInterceptionEnabled = terminalTap != nil && TerminalReplacement.supportedBundleIDs.contains(app?.bundleIdentifier ?? "")
        if let terminalTap { CGEvent.tapEnable(tap: terminalTap, enable: terminalInterceptionEnabled) }
        if !terminalInterceptionEnabled { terminalInputGate.release() }
    }

    /// Build the whole transaction before acquiring the input gate: no partial construction.
    static func terminalEvents(_ edit: TerminalEdit) -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        var events: [CGEvent] = []
        func append(code: CGKeyCode, text: String? = nil) -> Bool {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return false }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
                if let text {
                    let units = Array(text.utf16)
                    event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                }
                events.append(event)
            }
            return true
        }
        for _ in 0..<edit.deleteCount { if !append(code: 51) { return nil } }
        for character in edit.insert { if !append(code: 0, text: String(character)) { return nil } }
        return events
    }

    static func isClipboardShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand) && (keyCode == 8 || keyCode == 7)
    }

    // MARK: - Synthetic Key Presses

    /// Posts one key press to the focused application, like the user pressing it.
    static func press(keyCode: CGKeyCode, flags: CGEventFlags = [], holdMicroseconds: useconds_t = 5_000) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cghidEventTap)
            if keyDown { usleep(holdMicroseconds) }
        }
    }
}

/// Pure hotkey state: a tap is one aggregate down/up cycle, not one per side.
struct ModifierHotkeyDetector {
    private var previousFlags: CGEventFlags = []
    private var targetModifier: SettingsManager.HotkeyModifier?
    private var modifierWasAlone = false
    private var lastReleaseTime: TimeInterval?
    private let doubleTapThreshold: TimeInterval = 0.4

    mutating func disarm() {
        // Preserve aggregate state so a partial release cannot rearm the gesture.
        modifierWasAlone = false
        lastReleaseTime = nil
    }

    mutating func handle(keyCode: UInt16, flags: CGEventFlags, modifier: SettingsManager.HotkeyModifier,
                         doubleTapMode: Bool, now: TimeInterval) -> Bool {
        let targetFlag = modifier.cgEventFlag
        let modifierFlags: CGEventFlags = [.maskAlternate, .maskShift, .maskControl, .maskCommand]
        let currentFlags = flags.intersection(modifierFlags)
        let wasDown = previousFlags.contains(targetFlag)
        let isDown = currentFlags.contains(targetFlag)
        previousFlags = currentFlags

        if targetModifier != modifier {
            targetModifier = modifier
            disarm()
        }

        guard isModifierKeyCode(keyCode, modifier: modifier) else {
            disarm()
            return false
        }
        if isDown {
            if currentFlags != targetFlag {
                disarm()
            } else if !wasDown {
                modifierWasAlone = true
            }
            return false
        }
        guard wasDown, modifierWasAlone, currentFlags.isEmpty else {
            disarm()
            return false
        }
        modifierWasAlone = false
        if !doubleTapMode {
            lastReleaseTime = nil
            return true
        }
        if let lastReleaseTime = lastReleaseTime,
           now >= lastReleaseTime, now - lastReleaseTime < doubleTapThreshold {
            self.lastReleaseTime = nil
            return true
        }
        lastReleaseTime = now
        return false
    }

    private func isModifierKeyCode(_ keyCode: UInt16, modifier: SettingsManager.HotkeyModifier) -> Bool {
        switch modifier {
        case .option: return keyCode == 58 || keyCode == 61
        case .shift: return keyCode == 56 || keyCode == 60
        case .control: return keyCode == 59 || keyCode == 62
        case .command: return keyCode == 55 || keyCode == 54
        }
    }
}
