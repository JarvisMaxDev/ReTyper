import Cocoa

/// Detects the hotkey with a listen-only CGEventTap: it never delays or changes user input.
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
    private var detector = ModifierHotkeyDetector()
    private let settings = SettingsManager.shared

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
        let eventTypes: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let eventMask = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
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

        Logger.shared.log("✅ KeyboardMonitor started (CGEventTap created successfully)")
    }

    func stop() {
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
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // A click cancels a pending replacement, not the modifier hotkey itself.
            invalidateContext()
        case .flagsChanged:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            if detector.handle(keyCode: keyCode, flags: event.flags, modifier: settings.hotkeyModifier,
                               doubleTapMode: settings.doubleTapMode, now: ProcessInfo.processInfo.systemUptime) {
                onHotkeyTriggered?()
            }
        default:
            break
        }
    }

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker
            || event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid())
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
