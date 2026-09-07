import Cocoa

/// Application delegate. Wires together all components and handles the app lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusBarController: StatusBarController!
    private var keyboardMonitor: KeyboardMonitor!
    private var coordinator: TextReplacementCoordinator!
    private var replacementRunning = false
    private var waitingToTerminate = false
    private let layoutManager = LayoutManager.shared
    private let settings = SettingsManager.shared
    
    private var retryTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let log = Logger.shared
        log.log("🚀 ReTyper starting...")
        
        // Request Accessibility permission (auto-adds app to Accessibility list)
        requestAccessibility()
        
        // Initialize components
        statusBarController = StatusBarController()
        keyboardMonitor = KeyboardMonitor()
        coordinator = TextReplacementCoordinator(accessibility: AccessibilityTextClient(), input: keyboardMonitor)
        statusBarController.onCopyOriginal = { [weak self] in
            guard let self, let original = self.coordinator.recoveryOriginalText else { return }
            // Clipboard mutation is an explicit user action, never an automatic transport.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if !pasteboard.setString(original, forType: .string) {
                self.statusBarController.flashFailure()
            }
        }
        statusBarController.onClearRecovery = { [weak self] in
            guard let self, self.coordinator.clearRecovery() else { return }
            self.statusBarController.showRecovery(false)
        }
        
        // Wire up layout switching
        keyboardMonitor.onHotkeyTriggered = { [weak self] recipientPID, generation, triggeredAt in
            self?.handleHotkey(applicationPID: recipientPID, generation: generation, triggeredAt: triggeredAt)
        }
        
        // Wire up quit
        statusBarController.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        
        // Start monitoring keyboard (will trigger Input Monitoring prompt)
        keyboardMonitor.start()
        
        // If monitor didn't start, prompt for Input Monitoring and retry
        if !keyboardMonitor.isRunning {
            promptInputMonitoring()
            startRetryTimer()
        }
        
        // Start observing layout changes
        layoutManager.startObserving()
        
        let mode = settings.doubleTapMode ? "Double" : "Single"
        log.log("✅ ReTyper started")
        log.log("   Available layouts: \(layoutManager.relevantLayoutIDs())")
        log.log("   Current layout: \(layoutManager.currentLayoutDisplayName())")
        log.log("   Hotkey: \(mode) \(settings.hotkeyModifier.displaySymbol)")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor.stop()
        layoutManager.stopObserving()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if replacementRunning {
            waitingToTerminate = true
            return .terminateLater
        }
        return confirmRecoveryLoss() ? .terminateNow : .terminateCancel
    }

    private func confirmRecoveryLoss() -> Bool {
        guard coordinator?.recoveryOriginalText != nil else { return true }
        let alert = NSAlert()
        alert.messageText = "Original text is still available for recovery"
        alert.informativeText = "Quitting will discard the saved original text. Cancel to inspect the target and use Copy Original Text before quitting."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Without Recovery")
        return alert.runModal() == .alertSecondButtonReturn
    }
    
    // MARK: - Hotkey Handler
    
    /// The whole replacement scenario lives in the coordinator; this only dispatches it
    /// off the event tap thread and turns the outcome into user-visible feedback.
    private func handleHotkey(applicationPID: pid_t?, generation: UInt64, triggeredAt: TimeInterval) {
        // Reserve on the tap's main thread, not after dispatch: a queued second
        // hotkey must not become a new operation when the first one finishes.
        guard !replacementRunning else { return }
        let activationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let applicationPID, let activationPID else {
            let reason: AbortReason = coordinator.recoveryOriginalText == nil ? .noTextAccess : .recoveryPending
            let result = ReplacementResult(outcome: .aborted(reason))
            applyLayoutSwitch(result, activationPID: activationPID, generation: generation)
            signalOutcome(result.outcome)
            return
        }
        replacementRunning = true
        let options = ReplacementOptions(applicationPID: applicationPID, activationPID: activationPID,
                                         inputGeneration: generation,
                                         triggeredAt: triggeredAt,
                                         onlyLastWord: settings.switchOnlyLastWord,
                                         availableLayoutIDs: layoutManager.relevantLayoutIDs())
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let result = self.coordinator.performReplacement(options)
            Logger.shared.log("Replacement outcome: \(result.outcome)")
            DispatchQueue.main.async {
                self.replacementRunning = false
                guard result.outcome != .aborted(.busy) else { return }
                self.keyboardMonitor.clearBuffer()
                self.applyLayoutSwitch(result, activationPID: options.activationPID, generation: options.inputGeneration)
                self.statusBarController.showRecovery(self.coordinator.recoveryOriginalText != nil)
                self.statusBarController.updateTitle()
                self.signalOutcome(result.outcome)
                if self.waitingToTerminate {
                    self.waitingToTerminate = false
                    NSApplication.shared.reply(toApplicationShouldTerminate: self.confirmRecoveryLoss())
                }
            }
        }
    }
    
    private func applyLayoutSwitch(_ result: ReplacementResult, activationPID: pid_t?, generation: UInt64) {
        let action = result.layoutSwitchAction(
            activationPID: activationPID,
            currentActivationPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            inputGeneration: generation,
            currentInputGeneration: keyboardMonitor.activityGeneration
        )
        switch action {
        case .next?:
            _ = layoutManager.switchToNextLayout()
        case .select(let layout)?:
            layoutManager.switchTo(layoutID: layout)
        case nil:
            break
        }
    }

    /// Success and failure must be distinguishable without looking at the field.
    private func signalOutcome(_ outcome: ReplacementOutcome) {
        if outcome == .aborted(.busy) { return }
        statusBarController.recordOutcome(outcome)

        if outcome.isFailure {
            playAbortSound()
            statusBarController.flashFailure()
        } else {
            playSwitchSound()
        }
    }
    
    // MARK: - Permissions
    
    /// Request Accessibility permission — this auto-adds the app to the Accessibility list
    private func requestAccessibility() {
        let log = Logger.shared
        
        // Check with prompt: this BOTH checks AND adds the app to the Accessibility list
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        if trusted {
            log.log("✅ Accessibility permissions already granted")
        } else {
            log.log("⚠️ Accessibility permissions requested — user needs to enable in System Settings")
        }
    }
    
    /// Show a dialog directing the user to Input Monitoring settings
    private func promptInputMonitoring() {
        let log = Logger.shared
        log.log("⚠️ Input Monitoring not available — prompting user")
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Input Monitoring Required"
            alert.informativeText = "ReTyper needs Input Monitoring permission to detect keyboard input.\n\nPlease go to:\nSystem Settings → Privacy & Security → Input Monitoring\n\nand enable ReTyper."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
        }
    }
    
    /// Retry starting the keyboard monitor every 3 seconds until it succeeds
    private func startRetryTimer() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            if self.keyboardMonitor.isRunning {
                timer.invalidate()
                self.retryTimer = nil
                return
            }
            
            Logger.shared.log("🔄 Retrying keyboard monitor start...")
            self.keyboardMonitor.start()
            
            if self.keyboardMonitor.isRunning {
                Logger.shared.log("✅ Keyboard monitor started successfully!")
                timer.invalidate()
                self.retryTimer = nil
            }
        }
    }
    
    // MARK: - Sound
    
    private func playSwitchSound() {
        guard settings.playSwitchingSound else { return }
        NSSound(named: "Tink")?.play()
    }

    /// Deliberately different from the success sound (FR-009).
    private func playAbortSound() {
        guard settings.playSwitchingSound else { return }
        NSSound(named: "Funk")?.play()
    }
}
