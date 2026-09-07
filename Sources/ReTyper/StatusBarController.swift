import Cocoa

/// Manages the status bar item (menu bar text label) and popover.
final class StatusBarController {
    
    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private let layoutManager = LayoutManager.shared
    private let popoverVC: PopoverViewController
    
    private var feedbackState = StatusBarFeedbackState()

    var onQuit: (() -> Void)?
    var onCopyOriginal: (() -> Void)?
    var onClearRecovery: (() -> Void)?
    
    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popoverVC = PopoverViewController()
        
        popover.contentViewController = popoverVC
        popoverVC.onContentSizeChanged = { [weak self] size in
            self?.popover.contentSize = size
        }
        popover.behavior = .transient  // Close when clicking outside
        popover.animates = true
        
        popoverVC.onQuit = { [weak self] in
            self?.onQuit?()
        }
        popoverVC.onCopyOriginal = { [weak self] in
            self?.onCopyOriginal?()
        }
        popoverVC.onClearRecovery = { [weak self] in
            self?.onClearRecovery?()
        }
        
        setupButton()
        updateTitle()
        
        // Observe layout changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(layoutChanged),
            name: LayoutManager.layoutChangedNotification,
            object: nil
        )
        
        // Observe settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .settingsChanged,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupButton() {
        guard let button = statusItem.button else { return }
        
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        
        // Style: bold text in a rectangle
        button.font = .boldSystemFont(ofSize: 12)
    }
    
    /// Reflect the current layout without interrupting active warnings.
    func updateTitle() {
        guard let button = statusItem.button else { return }
        
        let showsWarning = feedbackState.showsWarning(at: ProcessInfo.processInfo.systemUptime)
        let displayName = showsWarning ? "⚠︎" : layoutManager.currentLayoutDisplayName()
        let description: String
        if feedbackState.isRecoveryAvailable {
            description = "ReTyper: Recovery required. Automatic text replacement is paused. Inspect the target and use Copy Original Text for manual recovery."
        } else if let message = feedbackState.outcomeMessage {
            description = "ReTyper: \(message)"
        } else if showsWarning {
            description = "ReTyper: Text replacement could not be completed."
        } else {
            description = "ReTyper: \(displayName)"
        }
        
        // Create attributed string with bordered appearance
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
        ]
        
        button.attributedTitle = NSAttributedString(string: displayName, attributes: attrs)
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    /// Synchronize recovery availability without accessing the retained text.
    func showRecovery(_ isAvailable: Bool) {
        feedbackState.isRecoveryAvailable = isAvailable
        popoverVC.showRecovery(isAvailable)
        popoverVC.showOutcomeMessage(feedbackState.outcomeMessage)
        updateTitle()
    }

    func recordOutcome(_ outcome: ReplacementOutcome) {
        feedbackState.recordOutcome(outcome)
        popoverVC.showOutcomeMessage(feedbackState.outcomeMessage)
        updateTitle()
    }

    /// Short visual signal that a replacement could not be completed.
    /// Paired with a distinct sound so the outcome is noticeable without watching the field.
    func flashFailure() {
        feedbackState.flashFailure(at: ProcessInfo.processInfo.systemUptime)
        updateTitle()

        DispatchQueue.main.asyncAfter(deadline: .now() + StatusBarFeedbackState.failureFlashDuration) { [weak self] in
            self?.updateTitle()
        }
    }
    
    // MARK: - Popover
    
    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            guard let button = statusItem.button else { return }
            // Load lazily so permission indicators reflect the started monitor.
            _ = popoverVC.view
            popover.contentSize = popoverVC.preferredContentSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            
            // Make the popover key window
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    // MARK: - Notifications
    
    @objc private func layoutChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateTitle()
        }
    }
    
    @objc private func settingsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateTitle()
        }
    }
}
