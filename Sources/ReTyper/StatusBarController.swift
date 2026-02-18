import Cocoa

/// Manages the status bar item (menu bar text label) and popover.
final class StatusBarController {
    
    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private let layoutManager = LayoutManager()
    private let popoverVC: PopoverViewController
    
    var onQuit: (() -> Void)?
    
    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popoverVC = PopoverViewController()
        
        popover.contentViewController = popoverVC
        popover.behavior = .transient  // Close when clicking outside
        popover.animates = true
        
        popoverVC.onQuit = { [weak self] in
            self?.onQuit?()
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
    
    /// Update the status bar title to reflect the current layout
    func updateTitle() {
        guard let button = statusItem.button else { return }
        
        let displayName = layoutManager.currentLayoutDisplayName()
        
        // Create attributed string with bordered appearance
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
        ]
        
        button.attributedTitle = NSAttributedString(string: displayName, attributes: attrs)
    }
    
    // MARK: - Popover
    
    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            guard let button = statusItem.button else { return }
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
