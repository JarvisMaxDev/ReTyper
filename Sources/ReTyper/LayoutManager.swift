import Cocoa
import Carbon

/// Manages keyboard input sources (layouts) using the TIS API.
final class LayoutManager {
    
    static let shared = LayoutManager()
    
    /// Notification posted when the layout changes
    static let layoutChangedNotification = Notification.Name("LayoutManagerLayoutChanged")
    
    /// Returns the current keyboard layout ID
    func currentLayoutID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return "unknown"
        }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }
    
    /// Returns the display name for the current layout
    func currentLayoutDisplayName() -> String {
        return CharacterMap.displayName(for: currentLayoutID())
    }
    
    /// Returns all available keyboard layout IDs
    func availableLayoutIDs() -> [String] {
        let conditions = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsEnabled: true,
            kTISPropertyInputSourceIsSelectCapable: true,
        ] as CFDictionary
        
        guard let sourceList = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        
        return sourceList.compactMap { source -> String? in
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                return nil
            }
            return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        }
    }
    
    /// Returns available layout IDs filtered to only keyboard layouts (EN, RU, UA, BY, etc.)
    /// Uses user-selected keyboards if saved, otherwise auto-detects.
    func relevantLayoutIDs() -> [String] {
        let settings = SettingsManager.shared
        let saved = settings.activeKeyboards
        
        // If user explicitly selected keyboards, use those
        if !saved.isEmpty {
            // Verify they're still installed
            let installed = availableLayoutIDs()
            let valid = saved.filter { installed.contains($0) }
            if !valid.isEmpty {
                return valid
            }
        }
        
        // Auto-detect: find first Latin and first Cyrillic
        return availableLayoutIDs().filter { id in
            CharacterMap.isEnglishLayout(id) || CharacterMap.cyrillicLayout(for: id) != nil
        }
    }
    
    /// Switch to a specific layout by its ID
    @discardableResult
    func switchTo(layoutID: String) -> Bool {
        let conditions = [
            kTISPropertyInputSourceID: layoutID,
        ] as CFDictionary
        
        guard let sourceList = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sourceList.first else {
            return false
        }
        
        let status = TISSelectInputSource(source)
        if status == noErr {
            NotificationCenter.default.post(name: LayoutManager.layoutChangedNotification, object: nil)
        }
        return status == noErr
    }
    
    /// Switch to the "other" layout. If currently EN → switch to last Cyrillic, and vice versa.
    func switchToNextLayout() -> String? {
        let current = currentLayoutID()
        let available = relevantLayoutIDs()
        
        if CharacterMap.isEnglishLayout(current) {
            // Switch to first available Cyrillic
            if let target = available.first(where: { CharacterMap.cyrillicLayout(for: $0) != nil }) {
                switchTo(layoutID: target)
                return target
            }
        } else {
            // Switch to English
            if let target = available.first(where: { CharacterMap.isEnglishLayout($0) }) {
                switchTo(layoutID: target)
                return target
            }
        }
        
        // Fallback: cycle through available
        if let idx = available.firstIndex(of: current) {
            let nextIdx = (idx + 1) % available.count
            let target = available[nextIdx]
            switchTo(layoutID: target)
            return target
        }
        
        return nil
    }
    
    /// Start observing system layout changes
    func startObserving() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }
    
    func stopObserving() {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    @objc private func inputSourceChanged(_ notification: Notification) {
        NotificationCenter.default.post(name: LayoutManager.layoutChangedNotification, object: nil)
    }
}
