import Cocoa

/// Application delegate. Wires together all components and handles the app lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusBarController: StatusBarController!
    private var keyboardMonitor: KeyboardMonitor!
    private let layoutManager = LayoutManager()
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
        
        // Wire up layout switching
        keyboardMonitor.onHotkeyTriggered = { [weak self] bufferedText in
            self?.handleHotkey(bufferedText: bufferedText)
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
    
    // MARK: - Hotkey Handler
    
    private func handleHotkey(bufferedText: String) {
        let log = Logger.shared
        let availableLayouts = layoutManager.relevantLayoutIDs()
        
        log.log("🔑 Hotkey triggered!")
        
        // Run on background thread to avoid blocking main run loop
        // CGEvent.post works from any thread
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            let monitor = self.keyboardMonitor!
            
            // Save clipboard on main thread
            var savedItems: [[NSPasteboard.PasteboardType: Data]] = []
            var savedChangeCount: Int = 0
            DispatchQueue.main.sync {
                let pasteboard = NSPasteboard.general
                savedChangeCount = pasteboard.changeCount
                savedItems = self.saveClipboard()
            }
            
            // === Step 1: Try Cmd+C for existing selection ===
            monitor.isSendingEvents = true
            monitor.simulateKeyPress(keyCode: 8, flags: .maskCommand)  // Cmd+C
            monitor.isSendingEvents = false
            Thread.sleep(forTimeInterval: 0.15)  // 150ms
            
            var textToConvert: String?
            var wasAlreadySelected = false
            
            DispatchQueue.main.sync {
                let pasteboard = NSPasteboard.general
                if pasteboard.changeCount != savedChangeCount {
                    textToConvert = pasteboard.string(forType: .string)
                    wasAlreadySelected = true
                    log.log("   📋 Got selected text (\(textToConvert?.count ?? 0) chars): \"\(textToConvert ?? "nil")\"")
                }
            }
            
            // === Step 2: If no selection, select text automatically ===
            if textToConvert == nil || textToConvert?.isEmpty == true {
                monitor.isSendingEvents = true
                
                if self.settings.switchOnlyLastWord {
                    log.log("   🔤 Selecting last word (Opt+Shift+Left)")
                    monitor.simulateKeyPress(keyCode: 123, flags: [.maskShift, .maskAlternate])
                } else {
                    log.log("   📝 Selecting to start of line (Cmd+Shift+Left)")
                    monitor.simulateKeyPress(keyCode: 123, flags: [.maskShift, .maskCommand])
                }
                
                Thread.sleep(forTimeInterval: 0.1)  // 100ms
                
                // Copy the selection
                monitor.simulateKeyPress(keyCode: 8, flags: .maskCommand)  // Cmd+C
                monitor.isSendingEvents = false
                Thread.sleep(forTimeInterval: 0.15)  // 150ms
                
                DispatchQueue.main.sync {
                    textToConvert = NSPasteboard.general.string(forType: .string)
                    log.log("   📋 Auto-selected text (\(textToConvert?.count ?? 0) chars): \"\(textToConvert ?? "nil")\"")
                }
            }
            
            // === If still empty, just switch layout ===
            guard let text = textToConvert, !text.isEmpty else {
                DispatchQueue.main.sync {
                    self.restoreClipboard(savedItems)
                    _ = self.layoutManager.switchToNextLayout()
                    self.statusBarController.updateTitle()
                    self.playSwitchSound()
                }
                log.log("   → No text found, switched layout")
                return
            }
            
            // === Step 3: Convert ===
            let result = TextConverter.autoConvert(text, availableLayoutIDs: availableLayouts)
            log.log("   → Conversion: \"\(text)\" → \"\(result.converted)\", target: \(result.targetLayoutID ?? "nil")")
            
            guard let targetLayoutID = result.targetLayoutID, result.converted != text else {
                if !wasAlreadySelected {
                    monitor.isSendingEvents = true
                    monitor.simulateKeyPress(keyCode: 124, flags: [])  // Right arrow to deselect
                    monitor.isSendingEvents = false
                }
                DispatchQueue.main.sync {
                    self.restoreClipboard(savedItems)
                    _ = self.layoutManager.switchToNextLayout()
                    self.statusBarController.updateTitle()
                    self.playSwitchSound()
                }
                log.log("   → No conversion possible, just switched layout")
                return
            }
            
            // === Step 4: Delete selected text ===
            monitor.isSendingEvents = true
            monitor.simulateKeyPress(keyCode: 51, flags: [])  // Delete/Backspace
            monitor.isSendingEvents = false
            Thread.sleep(forTimeInterval: 0.05)
            
            // === Step 5: Set clipboard and paste ===
            DispatchQueue.main.sync {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(result.converted, forType: .string)
            }
            Thread.sleep(forTimeInterval: 0.05)
            
            monitor.isSendingEvents = true
            monitor.simulateKeyPress(keyCode: 9, flags: .maskCommand)  // Cmd+V
            monitor.isSendingEvents = false
            Thread.sleep(forTimeInterval: 0.1)
            
            // === Step 6: Switch layout and update UI ===
            DispatchQueue.main.sync {
                self.layoutManager.switchTo(layoutID: targetLayoutID)
                monitor.clearBuffer()
                self.statusBarController.updateTitle()
                self.playSwitchSound()
            }
            
            log.log("   ✅ Done! Pasted \(result.converted.count) chars, switched to: \(targetLayoutID)")
            
            // === Step 7: Restore clipboard ===
            Thread.sleep(forTimeInterval: 0.5)
            DispatchQueue.main.sync {
                self.restoreClipboard(savedItems)
                log.log("   📋 Clipboard restored")
            }
        }
    }
    
    /// Save all clipboard items
    private func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]] {
        let pasteboard = NSPasteboard.general
        return pasteboard.pasteboardItems?.map { item in
            var typeData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    typeData[type] = data
                }
            }
            return typeData
        } ?? []
    }
    
    /// Restore clipboard items
    private func restoreClipboard(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for typeData in items {
            let newItem = NSPasteboardItem()
            for (type, data) in typeData {
                newItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([newItem])
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
}
