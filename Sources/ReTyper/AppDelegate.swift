import Cocoa
import Carbon

/// Application delegate. Wires together all components and handles the app lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusBarController: StatusBarController!
    private var keyboardMonitor: KeyboardMonitor!
    private let layoutManager = LayoutManager.shared
    private let settings = SettingsManager.shared
    private let replacementQueue = DispatchQueue(label: "com.retyper.app.replacement", qos: .userInteractive)
    private var isReplacing = false
    
    private var retryTimer: Timer?

    /// Terminals cannot select a command line with the keyboard, so they only switch the layout.
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
    ]
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let log = Logger.shared
        log.log("🚀 ReTyper starting...")
        
        // Request Accessibility permission (auto-adds app to Accessibility list)
        requestAccessibility()
        
        // Initialize components
        statusBarController = StatusBarController()
        keyboardMonitor = KeyboardMonitor()
        
        // Wire up layout switching
        keyboardMonitor.onHotkeyTriggered = { [weak self] in
            self?.handleHotkey()
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
        logPasteboardAccess()
    }

    /// macOS 15.4+ may ask the user before an app reads the clipboard. Read through KVC so the
    /// project still builds with older SDKs; only the setting is logged, never contents.
    private func logPasteboardAccess() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.responds(to: NSSelectorFromString("accessBehavior")),
              let behavior = pasteboard.value(forKey: "accessBehavior") as? Int else { return }
        let names = [0: "default (ask on first read)", 1: "ask", 2: "always allow", 3: "always deny"]
        Logger.shared.log("   Clipboard access: \(names[behavior] ?? "unknown \(behavior)")")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor.stop()
        layoutManager.stopObserving()
    }
    
    // MARK: - Hotkey Handler
    
    private func handleHotkey() {
        // A second hotkey during a replacement is ignored rather than queued.
        guard !isReplacing else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid(),
              !Self.terminalBundleIDs.contains(app.bundleIdentifier ?? "") else {
            finish(.layoutOnly(reason: "terminal or no target application"))
            return
        }

        isReplacing = true
        let host = SystemReplacementHost(pid: app.processIdentifier, keyDownCount: keyboardMonitor.userKeyDownCount)
        let onlyLastWord = settings.switchOnlyLastWord
        // Text Input Sources are read here, on the main thread; the queue only gets values.
        let keyboardType = UInt32(LMGetKbdType())
        let layouts = layoutManager.relevantLayoutIDs().compactMap {
            KeyLayout.system(id: $0, keyboardType: keyboardType)
        }
        let currentLayoutID = layoutManager.currentLayoutID()

        // Key presses and pasteboard polling must not block the main run loop.
        replacementQueue.async { [weak self] in
            let outcome = ReplacementFlow.run(host: host, onlyLastWord: onlyLastWord) { text in
                let result = TextConverter.convert(text, layouts: layouts, currentLayoutID: currentLayoutID)
                // Only metadata: the text itself never reaches the log.
                Logger.shared.log("Conversion: source=\(result.source.rawValue) len=\(text.count) "
                    + "target=\(result.targetLayoutID ?? "none")")
                return (result.converted, result.targetLayoutID)
            }
            host.restoreClipboard()
            DispatchQueue.main.async {
                self?.isReplacing = false
                self?.finish(outcome)
            }
        }
    }
    
    private func finish(_ outcome: ReplacementOutcome) {
        switch outcome {
        case .replaced(let targetLayoutID):
            layoutManager.switchTo(layoutID: targetLayoutID)
        case .layoutOnly:
            _ = layoutManager.switchToNextLayout()
        }
        Logger.shared.log("Replacement outcome: \(outcome)")
        statusBarController.updateTitle()
        playSwitchSound()
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
}
