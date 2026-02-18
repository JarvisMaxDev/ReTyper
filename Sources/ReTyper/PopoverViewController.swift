import Cocoa
import Carbon

/// The popover view controller that displays all settings.
/// Mimics the LangSwitcher-style dark popover UI.
final class PopoverViewController: NSViewController {
    
    private let settings = SettingsManager.shared
    private let layoutManager = LayoutManager()
    
    var onQuit: (() -> Void)?
    
    // MARK: - Lifecycle
    
    override func loadView() {
        let width: CGFloat = 340
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        self.view.wantsLayer = true
        
        buildUI()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    // MARK: - UI Construction
    
    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        // === Section 1: General ===
        stack.addArrangedSubview(makeToggleRow(
            title: "Autostart After Login",
            isOn: settings.autostartAfterLogin,
            action: #selector(toggleAutostart(_:))
        ))
        stack.addArrangedSubview(makeToggleRow(
            title: "Play Switching Sound",
            isOn: settings.playSwitchingSound,
            action: #selector(toggleSound(_:))
        ))
        
        stack.addArrangedSubview(makeSeparator())
        
        // === Section 2: Switching ===
        stack.addArrangedSubview(makeHotkeyRow())
        stack.addArrangedSubview(makeToggleRow(
            title: "Switch Only Last Word",
            isOn: settings.switchOnlyLastWord,
            action: #selector(toggleLastWord(_:))
        ))
        stack.addArrangedSubview(makeActiveKeyboardsRow())
        
        stack.addArrangedSubview(makeSeparator())
        
        // === Permissions ===
        stack.addArrangedSubview(makePermissionStatusRow())
        
        stack.addArrangedSubview(makeSeparator())
        
        // === Footer ===
        stack.addArrangedSubview(makeQuitRow())
        stack.addArrangedSubview(makeVersionLabel())
        
        // Calculate height
        stack.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height
        self.preferredContentSize = NSSize(width: 340, height: height)
        view.frame = NSRect(x: 0, y: 0, width: 340, height: height)
    }
    
    // MARK: - Row Builders
    
    private func makePermissionStatusRow() -> NSView {
        let accessOpts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        let hasAccessibility = AXIsProcessTrustedWithOptions(accessOpts)
        let hasInputMonitoring = KeyboardMonitor.shared?.isRunning ?? false
        
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 1
        container.translatesAutoresizingMaskIntoConstraints = false
        
        container.addArrangedSubview(
            makePermissionItem(name: "Accessibility", granted: hasAccessibility)
        )
        container.addArrangedSubview(
            makePermissionItem(name: "Input Monitoring", granted: hasInputMonitoring)
        )
        
        return container
    }
    
    private func makePermissionItem(name: String, granted: Bool) -> NSView {
        let row = makeRowContainer()
        
        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Status indicator: green "OK" or red "Fix →"
        let statusLabel: NSTextField
        if granted {
            statusLabel = NSTextField(labelWithString: "OK")
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel = NSTextField(labelWithString: "Fix →")
            statusLabel.textColor = .systemRed
        }
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Small colored dot
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = granted ? NSColor.systemGreen.cgColor : NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        
        row.addSubview(label)
        row.addSubview(dot)
        row.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -6),
            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 36),
        ])
        
        // Always clickable — opens the correct System Settings pane
        if name == "Accessibility" {
            let click = NSClickGestureRecognizer(target: self, action: #selector(openAccessibilitySettings))
            row.addGestureRecognizer(click)
        } else {
            let click = NSClickGestureRecognizer(target: self, action: #selector(openInputMonitoringSettings))
            row.addGestureRecognizer(click)
        }
        
        return row
    }
    
    private func makeToggleRow(title: String, isOn: Bool, action: Selector) -> NSView {
        let row = makeRowContainer()
        
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        
        row.addSubview(label)
        row.addSubview(toggle)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 36),
        ])
        
        return row
    }
    
    private func makeHotkeyRow() -> NSView {
        let row = makeRowContainer()
        
        let label = NSTextField(labelWithString: "Manual Switching")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Tap mode: Single / Double
        let tapMode = NSSegmentedControl(labels: ["Double"], trackingMode: .selectAny, target: self, action: #selector(doubleTapToggled(_:)))
        tapMode.translatesAutoresizingMaskIntoConstraints = false
        tapMode.controlSize = .small
        tapMode.segmentStyle = .roundRect
        tapMode.setSelected(settings.doubleTapMode, forSegment: 0)
        tapMode.setWidth(55, forSegment: 0)
        
        // Modifier key selector
        let segmented = NSSegmentedControl(labels: ["⇧", "⌃", "⌥", "⌘"], trackingMode: .selectOne, target: self, action: #selector(hotkeyChanged(_:)))
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.controlSize = .small
        segmented.segmentStyle = .roundRect
        
        switch settings.hotkeyModifier {
        case .shift: segmented.selectedSegment = 0
        case .control: segmented.selectedSegment = 1
        case .option: segmented.selectedSegment = 2
        case .command: segmented.selectedSegment = 3
        }
        
        segmented.setWidth(30, forSegment: 0)
        segmented.setWidth(30, forSegment: 1)
        segmented.setWidth(30, forSegment: 2)
        segmented.setWidth(30, forSegment: 3)
        
        let controlStack = NSStackView(views: [tapMode, segmented])
        controlStack.orientation = .horizontal
        controlStack.spacing = 4
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        
        row.addSubview(label)
        row.addSubview(controlStack)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            controlStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            controlStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 36),
        ])
        
        return row
    }
    
    private func makeActiveKeyboardsRow() -> NSView {
        let row = makeRowContainer()
        
        let label = NSTextField(labelWithString: "Active Keyboards")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let badgeStack = NSStackView()
        badgeStack.orientation = .horizontal
        badgeStack.spacing = 4
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        
        let layouts = layoutManager.relevantLayoutIDs()
        for id in layouts {
            let name = CharacterMap.displayName(for: id)
            let badge = makeBadge(text: name)
            badgeStack.addArrangedSubview(badge)
        }
        
        let chevron = NSTextField(labelWithString: "›")
        chevron.font = .systemFont(ofSize: 16)
        chevron.textColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        
        row.addSubview(label)
        row.addSubview(badgeStack)
        row.addSubview(chevron)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            badgeStack.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            badgeStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 36),
        ])
        
        let click = NSClickGestureRecognizer(target: self, action: #selector(showKeyboardPicker(_:)))
        row.addGestureRecognizer(click)
        
        return row
    }
    
    @objc private func showKeyboardPicker(_ gesture: NSClickGestureRecognizer) {
        guard let sourceView = gesture.view else { return }
        
        let menu = NSMenu(title: "Active Keyboards")
        
        let allLayouts = layoutManager.availableLayoutIDs()
        let activeLayouts = layoutManager.relevantLayoutIDs()
        
        // Group layouts
        var latinLayouts: [String] = []
        var cyrillicLayouts: [String] = []
        
        for id in allLayouts {
            if CharacterMap.cyrillicLayout(for: id) != nil {
                cyrillicLayouts.append(id)
            } else if CharacterMap.isEnglishLayout(id) {
                latinLayouts.append(id)
            }
        }
        
        // Get currently selected ones
        let selectedLatin = activeLayouts.first(where: { CharacterMap.isEnglishLayout($0) })
        let selectedCyrillic = activeLayouts.first(where: { CharacterMap.cyrillicLayout(for: $0) != nil })
        
        // Latin header
        let latinHeader = NSMenuItem(title: "Latin", action: nil, keyEquivalent: "")
        latinHeader.isEnabled = false
        latinHeader.attributedTitle = NSAttributedString(
            string: "LATIN",
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(latinHeader)
        
        for id in latinLayouts {
            let name = CharacterMap.displayName(for: id)
            // Get full display name from TIS
            let fullName = layoutDisplayName(for: id) ?? name
            let item = NSMenuItem(title: fullName, action: #selector(selectKeyboard(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["id": id, "type": "latin"]
            item.state = (id == selectedLatin) ? .on : .off
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Cyrillic header
        let cyrillicHeader = NSMenuItem(title: "Cyrillic", action: nil, keyEquivalent: "")
        cyrillicHeader.isEnabled = false
        cyrillicHeader.attributedTitle = NSAttributedString(
            string: "CYRILLIC",
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(cyrillicHeader)
        
        for id in cyrillicLayouts {
            let name = CharacterMap.displayName(for: id)
            let fullName = layoutDisplayName(for: id) ?? name
            let item = NSMenuItem(title: fullName, action: #selector(selectKeyboard(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["id": id, "type": "cyrillic"]
            item.state = (id == selectedCyrillic) ? .on : .off
            menu.addItem(item)
        }
        
        // Show menu below the row
        let point = NSPoint(x: sourceView.bounds.midX, y: sourceView.bounds.minY)
        menu.popUp(positioning: nil, at: point, in: sourceView)
    }
    
    @objc private func selectKeyboard(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let selectedID = info["id"],
              let type = info["type"] else { return }
        
        var activeLayouts = layoutManager.relevantLayoutIDs()
        
        if type == "latin" {
            // Replace the Latin layout
            activeLayouts.removeAll { CharacterMap.isEnglishLayout($0) }
            activeLayouts.insert(selectedID, at: 0)
        } else {
            // Replace the Cyrillic layout
            activeLayouts.removeAll { CharacterMap.cyrillicLayout(for: $0) != nil }
            activeLayouts.append(selectedID)
        }
        
        settings.activeKeyboards = activeLayouts
        
        // Rebuild UI to reflect change
        rebuildUI()
    }
    
    private func layoutDisplayName(for layoutID: String) -> String? {
        let conditions = [
            kTISPropertyInputSourceID: layoutID,
        ] as CFDictionary
        
        guard let sourceList = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sourceList.first,
              let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
    }
    
    private func rebuildUI() {
        // Remove all subviews and rebuild
        for subview in view.subviews {
            subview.removeFromSuperview()
        }
        buildUI()
    }
    
    private func makeQuitRow() -> NSView {
        let row = makeRowContainer()
        
        let label = NSTextField(labelWithString: "Quit")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let closeSymbol = NSTextField(labelWithString: "✕")
        closeSymbol.font = .systemFont(ofSize: 14)
        closeSymbol.textColor = .secondaryLabelColor
        closeSymbol.translatesAutoresizingMaskIntoConstraints = false
        
        row.addSubview(label)
        row.addSubview(closeSymbol)
        
        let click = NSClickGestureRecognizer(target: self, action: #selector(quitClicked))
        row.addGestureRecognizer(click)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            closeSymbol.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            closeSymbol.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 36),
        ])
        
        return row
    }
    
    private func makeVersionLabel() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let label = NSTextField(labelWithString: "ReTyper v1.0.0")
        label.font = .systemFont(ofSize: 10)
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            container.widthAnchor.constraint(equalToConstant: 340),
        ])
        
        return container
    }
    
    // MARK: - Helper Builders
    
    private func makeRowContainer() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        
        // Add hover tracking
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: row,
            userInfo: nil
        )
        row.addTrackingArea(area)
        
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 340),
        ])
        
        return row
    }
    
    private func makeSeparator() -> NSView {
        let sep = NSView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        
        NSLayoutConstraint.activate([
            sep.heightAnchor.constraint(equalToConstant: 1),
            sep.widthAnchor.constraint(equalToConstant: 340),
        ])
        
        return sep
    }
    
    private func makePillButton(title: String, isOn: Bool, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .recessed
        btn.setButtonType(.toggle)
        btn.state = isOn ? .on : .off
        btn.controlSize = .small
        btn.font = .systemFont(ofSize: 11)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }
    
    private func makeBadge(text: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.darkGray.cgColor
        container.layer?.cornerRadius = 4
        
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            container.heightAnchor.constraint(equalToConstant: 22),
        ])
        
        return container
    }
    
    // MARK: - Actions
    
    @objc private func toggleAutostart(_ sender: NSSwitch) {
        settings.autostartAfterLogin = sender.state == .on
    }
    
    @objc private func toggleSound(_ sender: NSSwitch) {
        settings.playSwitchingSound = sender.state == .on
    }
    
    @objc private func toggleLastWord(_ sender: NSSwitch) {
        settings.switchOnlyLastWord = sender.state == .on
    }
    
    @objc private func doubleTapToggled(_ sender: NSSegmentedControl) {
        let isOn = sender.isSelected(forSegment: 0)
        settings.doubleTapMode = isOn
        let mode = isOn ? "Double" : "Single"
        print("🔧 Tap mode changed to: \(mode) \(settings.hotkeyModifier.displaySymbol)")
    }
    
    @objc private func hotkeyChanged(_ sender: NSSegmentedControl) {
        let modifiers: [SettingsManager.HotkeyModifier] = [.shift, .control, .option, .command]
        let idx = sender.selectedSegment
        if idx >= 0 && idx < modifiers.count {
            settings.hotkeyModifier = modifiers[idx]
            let mode = settings.doubleTapMode ? "Double" : "Single"
            print("🔧 Hotkey changed to: \(mode) \(modifiers[idx].displaySymbol)")
        }
    }
    
    @objc private func quitClicked() {
        onQuit?()
    }
    
    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    @objc private func openInputMonitoringSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}
