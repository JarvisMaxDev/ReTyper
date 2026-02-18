import Cocoa
import Carbon

/// Monitors keyboard events globally using CGEventTap.
/// Maintains a buffer of recently typed characters and detects the double-tap hotkey.
final class KeyboardMonitor {
    
    /// Shared instance for permission status checks
    static var shared: KeyboardMonitor?
    
    /// Called when the hotkey is triggered. Provides the buffered text.
    var onHotkeyTriggered: ((String) -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    /// Buffer of recently typed characters (current word)
    private var buffer: [Character] = []
    
    /// For double-tap detection — track by modifier type, not exact keyCode
    private var lastModifierReleaseTime: TimeInterval = 0
    private var lastModifierType: SettingsManager.HotkeyModifier? = nil
    private var modifierWasAlone = true
    private let doubleTapThreshold: TimeInterval = 0.4
    
    /// Flag to suppress capturing our own simulated events
    var isSendingEvents = false
    
    private let settings = SettingsManager.shared
    
    /// Whether the CGEventTap is running
    var isRunning: Bool { eventTap != nil }
    
    init() {
        KeyboardMonitor.shared = self
    }
    
    // MARK: - Start / Stop
    
    func start() {
        // Event mask: keyDown + flagsChanged
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.shared.log("⚠️ Failed to create CGEventTap! Grant Accessibility + Input Monitoring permissions.")
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        Logger.shared.log("✅ KeyboardMonitor started (CGEventTap created successfully)")
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
    
    func clearBuffer() {
        buffer.removeAll()
    }
    
    var bufferContent: String {
        return String(buffer)
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        
        // If we're sending synthetic events, don't process them
        if isSendingEvents {
            return Unmanaged.passRetained(event)
        }
        
        // Re-enable if the system disabled our tap
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                Logger.shared.log("🔄 CGEventTap re-enabled (was disabled by system)")
            }
            return Unmanaged.passRetained(event)
        }
        
        if type == .flagsChanged {
            handleFlagsChanged(event: event)
            return Unmanaged.passRetained(event)
        }
        
        if type == .keyDown {
            handleKeyDown(event: event)
            // Any regular key press means the modifier wasn't pressed alone
            modifierWasAlone = false
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func handleKeyDown(event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        
        // Backspace — remove last char
        if keyCode == 51 {
            if !buffer.isEmpty {
                buffer.removeLast()
            }
            return
        }
        
        // Word-breaking keys: Space(49), Return(36), Tab(48), Escape(53)
        if keyCode == 49 || keyCode == 36 || keyCode == 48 || keyCode == 53 {
            clearBuffer()
            return
        }
        
        // Get unicode character from the event
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        
        if length > 0 {
            let s = String(utf16CodeUnits: chars, count: length)
            for c in s {
                buffer.append(c)
            }
        }
        
        if buffer.count > 200 {
            buffer = Array(buffer.suffix(200))
        }
    }
    
    private func handleFlagsChanged(event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let targetModifier = settings.hotkeyModifier
        let targetFlag = targetModifier.cgEventFlag
        
        guard isModifierKeyCode(keyCode, modifier: targetModifier) else { return }
        
        let isDown = flags.contains(targetFlag)
        
        if isDown {
            modifierWasAlone = true
        } else {
            // Modifier released
            guard modifierWasAlone else { return }
            
            if settings.doubleTapMode {
                // Double-tap mode: need two quick taps
                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = now - lastModifierReleaseTime
                
                if elapsed < doubleTapThreshold && lastModifierType == targetModifier {
                    Logger.shared.log("🎯 Double-tap \(targetModifier.displaySymbol) detected! Buffer: \"\(bufferContent)\"")
                    triggerHotkey()
                    lastModifierReleaseTime = 0
                    lastModifierType = nil
                } else {
                    lastModifierReleaseTime = now
                    lastModifierType = targetModifier
                }
            } else {
                // Single-tap mode: trigger on first solo release
                Logger.shared.log("🎯 Single-tap \(targetModifier.displaySymbol) detected! Buffer: \"\(bufferContent)\"")
                triggerHotkey()
            }
        }
    }
    
    /// Check if a keyCode is for the given modifier (left or right)
    private func isModifierKeyCode(_ keyCode: UInt16, modifier: SettingsManager.HotkeyModifier) -> Bool {
        switch modifier {
        case .option:  return keyCode == 58 || keyCode == 61  // kVK_Option / kVK_RightOption
        case .shift:   return keyCode == 56 || keyCode == 60  // kVK_Shift / kVK_RightShift
        case .control: return keyCode == 59 || keyCode == 62  // kVK_Control / kVK_RightControl
        case .command: return keyCode == 55 || keyCode == 54  // kVK_Command / kVK_RightCommand
        }
    }
    
    private func triggerHotkey() {
        let text = bufferContent
        
        guard !text.isEmpty else {
            onHotkeyTriggered?("")
            return
        }
        
        onHotkeyTriggered?(text)
    }
    
    // MARK: - Text Manipulation via CGEvent
    
    /// Delete `count` characters by simulating Backspace
    func deleteCharacters(count: Int) {
        isSendingEvents = true
        for _ in 0..<count {
            simulateKeyPress(keyCode: 51, flags: [])
            usleep(8000)  // 8ms delay for reliability
        }
        isSendingEvents = false
    }
    
    /// Type a string via clipboard (reliable for Unicode)
    func typeString(_ text: String) {
        let log = Logger.shared
        isSendingEvents = true
        
        let pasteboard = NSPasteboard.general
        
        // Save ALL current clipboard items
        let savedItems = pasteboard.pasteboardItems?.map { item -> (String, [NSPasteboard.PasteboardType: Data]) in
            var typeData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    typeData[type] = data
                }
            }
            return ("", typeData)
        } ?? []
        
        // Set new clipboard content
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        let changeCount = pasteboard.changeCount
        log.log("📋 Clipboard set: success=\(success), text=\"\(text)\", changeCount=\(changeCount)")
        
        // Wait for pasteboard to be ready
        usleep(50000)  // 50ms
        
        // Verify clipboard was set
        let verify = pasteboard.string(forType: .string)
        log.log("📋 Clipboard verify: \"\(verify ?? "nil")\"")
        
        // Simulate ⌘V
        simulateKeyPress(keyCode: 9, flags: .maskCommand)  // kVK_ANSI_V
        
        isSendingEvents = false
        
        // Restore previous clipboard after a longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            for (_, typeData) in savedItems {
                let newItem = NSPasteboardItem()
                for (type, data) in typeData {
                    newItem.setData(data, forType: type)
                }
                pasteboard.writeObjects([newItem])
            }
            log.log("📋 Clipboard restored")
        }
    }
    
    func simulateKeyPress(keyCode: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        
        usleep(5000)  // 5ms between down and up
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
    }
}
