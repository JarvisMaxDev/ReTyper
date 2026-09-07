import Cocoa

/// Detects the hotkey and routes prepared input, never retaining a typed-text buffer.
final class KeyboardMonitor: ReplacementInputProviding {
    static var shared: KeyboardMonitor?
    var onHotkeyTriggered: ((pid_t?, UInt64, TimeInterval) -> Void)?

    private let gate = SyntheticInputGate(
        clock: { ProcessInfo.processInfo.systemUptime },
        frontmostPID: {
            if Thread.isMainThread { return NSWorkspace.shared.frontmostApplication?.processIdentifier }
            return DispatchQueue.main.sync { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        }
    )
    private let tapLock = NSLock()
    private var sessionTap: CFMachPort?
    private var annotatedTap: CFMachPort?
    private var sessionSource: CFRunLoopSource?
    private var annotatedSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?

    // Both taps, lifecycle changes and hotkey state use the main run loop.
    private var stages = KeyboardEventStages()
    private let settings = SettingsManager.shared

    var activityGeneration: UInt64 { gate.activityGeneration }

    var isRunning: Bool {
        let enabled = tapsEnabled
        return enabled.session && enabled.annotated
    }

    private var tapsEnabled: (session: Bool, annotated: Bool) {
        tapLock.lock()
        let session = sessionTap
        let annotated = annotatedTap
        tapLock.unlock()
        return (session.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
                annotated.map { CGEvent.tapIsEnabled(tap: $0) } ?? false)
    }

    init() {
        KeyboardMonitor.shared = self
    }

    deinit {
        if sessionTap != nil || annotatedTap != nil {
            precondition(Thread.isMainThread)
            stop()
        }
    }

    // MARK: - Start / Stop

    func start() {
        precondition(Thread.isMainThread)
        guard !isRunning else { return }
        stop()

        let types: [CGEventType] = [
            .null, .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        let eventMask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let session = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(stage: .session, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.shared.log("Failed to create CGEventTap. Check Accessibility and Input Monitoring permissions.")
            return
        }

        guard let annotated = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.flagsChanged.rawValue,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(stage: .annotated, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            CFMachPortInvalidate(session)
            Logger.shared.log("Failed to create annotated hotkey CGEventTap.")
            return
        }

        guard let sessionSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, session, 0),
              let annotatedSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, annotated, 0) else {
            CFMachPortInvalidate(session)
            CFMachPortInvalidate(annotated)
            return
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.gate.recordActivity()
            if Thread.isMainThread {
                self?.resetHotkey()
            } else {
                DispatchQueue.main.async { [weak self] in self?.resetHotkey() }
            }
        }
        tapLock.lock()
        sessionTap = session
        annotatedTap = annotated
        tapLock.unlock()
        self.sessionSource = sessionSource
        self.annotatedSource = annotatedSource
        CFRunLoopAddSource(CFRunLoopGetMain(), sessionSource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), annotatedSource, .commonModes)
        CGEvent.tapEnable(tap: session, enable: true)
        CGEvent.tapEnable(tap: annotated, enable: true)
        gate.resetTap(isEnabled: isRunning)
    }

    func stop() {
        precondition(Thread.isMainThread)
        gate.resetTap(isEnabled: false)
        releasePendingKeys()
        resetHotkey()
        tapLock.lock()
        let taps = [sessionTap, annotatedTap].compactMap { $0 }
        sessionTap = nil
        annotatedTap = nil
        tapLock.unlock()
        for tap in taps {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        for source in [sessionSource, annotatedSource].compactMap({ $0 }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        sessionSource = nil
        annotatedSource = nil
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
    }

    /// Kept for AppDelegate wiring; text comes only from the coordinator's AX snapshot.
    func clearBuffer() {}

    // MARK: - Prepared Input

    func prepare(_ text: String, targetPID: pid_t, activationPID: pid_t, generation: UInt64,
                 deadline: TimeInterval) -> PreparedTextInput? {
        guard isRunning else { return nil }
        return gate.prepare(text, targetPID: targetPID, activationPID: activationPID,
                            generation: generation, deadline: deadline)
    }

    func send(_ input: PreparedTextInput) {
        guard isRunning else {
            gate.cancel(input)
            return
        }
        guard let signals = gate.takeSignals(for: input) else { return }
        // Only inert null events enter the global stream. A missing/disabled tap
        // cannot accidentally deliver Unicode input to the current application.
        signals.down.post(tap: .cgSessionEventTap)
        signals.up.post(tap: .cgSessionEventTap)
    }

    func delivery(of input: PreparedTextInput) -> InputDelivery {
        if !isRunning { return gate.cancel(input) }
        return gate.delivery(of: input)
    }

    @discardableResult
    func cancel(_ input: PreparedTextInput) -> InputDelivery {
        gate.cancel(input)
    }

    func finish(_ input: PreparedTextInput) {
        guard gate.finish(input) else { return }
        // A queued null release may have been lost while the tap was disabled.
        // Main-queue ordering ensures the down's postToPid call has completed.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if case let .route(up, pid) = self.gate.handle(type: .null, token: input.id + 1) {
                up.postToPid(pid)
            }
        }
    }

    // MARK: - Event Handling

    private func handleEvent(stage: KeyboardEventStages.Stage, type: CGEventType,
                             event: CGEvent) -> Unmanaged<CGEvent>? {
        precondition(Thread.isMainThread)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            gate.resetTap(isEnabled: false)
            releasePendingKeys()
            resetHotkey()
            tapLock.lock()
            let tap = stage == .session ? sessionTap : annotatedTap
            tapLock.unlock()
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                gate.resetTap(isEnabled: isRunning)
            }
            return Unmanaged.passUnretained(event)
        }

        let enabled = tapsEnabled
        let decision = stages.handle(stage: stage, type: type, event: event, gate: gate,
                                     sessionEnabled: enabled.session, annotatedEnabled: enabled.annotated,
                                     modifier: settings.hotkeyModifier, doubleTapMode: settings.doubleTapMode,
                                     now: ProcessInfo.processInfo.systemUptime)
        if !enabled.session || !enabled.annotated { releasePendingKeys() }
        switch decision {
        case .drop:
            return nil
        case let .route(payload, pid):
            // Process targeting does not prove field identity or application ACK.
            payload.postToPid(pid)
            return nil
        case let .hotkey(pid, generation, triggeredAt):
            onHotkeyTriggered?(pid, generation, triggeredAt)
            return Unmanaged.passUnretained(event)
        case .passThrough:
            return Unmanaged.passUnretained(event)
        }
    }

    private func releasePendingKeys() {
        for (up, pid) in gate.takePendingKeyUps() {
            up.postToPid(pid)
        }
    }

    private func resetHotkey() {
        stages.disarm()
    }

    static func checkedPID(_ value: Int64) -> pid_t? {
        guard value > 0 else { return nil }
        return pid_t(exactly: value)
    }
}

/// Pure stage dispatch: retain only one modifier fingerprint, never an event or typed text.
struct KeyboardEventStages {
    enum Stage {
        case session
        case annotated
    }

    enum Decision {
        case passThrough
        case drop
        case route(CGEvent, pid_t)
        case hotkey(pid_t?, UInt64, TimeInterval)
    }

    private var modifierEvent: (timestamp: CGEventTimestamp, keyCode: Int64,
                               sourceUserData: Int64, generation: UInt64)?
    private var hotkey = ModifierHotkeyDetector()

    mutating func disarm() {
        modifierEvent = nil
        hotkey.disarm()
    }

    mutating func handle(stage: Stage, type: CGEventType, event: CGEvent, gate: SyntheticInputGate,
                         sessionEnabled: Bool, annotatedEnabled: Bool,
                         modifier: SettingsManager.HotkeyModifier, doubleTapMode: Bool,
                         now: TimeInterval) -> Decision {
        let ready = sessionEnabled && annotatedEnabled
        if !ready {
            // Readiness comes from both live handles, not just their disable notifications.
            gate.resetTap(isEnabled: false)
            disarm()
        }

        let token = event.getIntegerValueField(.eventSourceUserData)
        switch stage {
        case .session:
            if SyntheticInputGate.ownsToken(token) {
                switch gate.handle(type: type, token: token) {
                case .passThrough: return .passThrough
                case .drop: return .drop
                case let .route(payload, pid): return .route(payload, pid)
                }
            }
            if SyntheticInputGate.isUserActivity(type) {
                let generation = gate.recordActivity()
                if type == .flagsChanged, ready {
                    if modifierEvent != nil { hotkey.disarm() }
                    modifierEvent = (event.timestamp, event.getIntegerValueField(.keyboardEventKeycode),
                                     token, generation)
                } else {
                    disarm()
                }
            }
        case .annotated:
            // postToPid echoes must pass untouched and must not count as fresh user input.
            guard type == .flagsChanged, !SyntheticInputGate.ownsToken(token) else { return .passThrough }
            guard ready, let observed = modifierEvent,
                  observed.timestamp == event.timestamp,
                  observed.keyCode == event.getIntegerValueField(.keyboardEventKeycode),
                  observed.sourceUserData == token,
                  observed.generation < UInt64.max,
                  observed.generation == gate.activityGeneration else {
                disarm()
                return .passThrough
            }
            modifierEvent = nil
            if hotkey.handle(keyCode: UInt16(truncatingIfNeeded: observed.keyCode), flags: event.flags,
                             modifier: modifier, doubleTapMode: doubleTapMode, now: now) {
                return .hotkey(KeyboardMonitor.checkedPID(event.getIntegerValueField(.eventTargetUnixProcessID)),
                               observed.generation, now)
            }
        }
        return .passThrough
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
