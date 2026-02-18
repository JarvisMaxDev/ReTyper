import Foundation
import CoreGraphics

/// Manages user preferences, stored in UserDefaults.
final class SettingsManager {
    
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Keys
    
    private enum Key: String {
        case hotkeyModifier = "hotkeyModifier"
        case doubleTapMode = "doubleTapMode"
        case switchOnlyLastWord = "switchOnlyLastWord"
        case autoSwitchOnTab = "autoSwitchOnTab"
        case autoSwitchOnSpace = "autoSwitchOnSpace"
        case autoSwitchOnEnter = "autoSwitchOnEnter"
        case playSwitchingSound = "playSwitchingSound"
        case displayLayoutFlag = "displayLayoutFlag"
        case autostartAfterLogin = "autostartAfterLogin"
        case activeKeyboards = "activeKeyboards"
    }
    
    // MARK: - Hotkey Modifier
    
    /// Which modifier key double-tap triggers the switch
    enum HotkeyModifier: String, CaseIterable {
        case option = "option"      // ⌥
        case shift = "shift"        // ⇧
        case control = "control"    // ⌃
        case command = "command"    // ⌘
        
        var displaySymbol: String {
            switch self {
            case .option: return "⌥"
            case .shift: return "⇧"
            case .control: return "⌃"
            case .command: return "⌘"
            }
        }
        
        var displayName: String {
            switch self {
            case .option: return "Option"
            case .shift: return "Shift"
            case .control: return "Control"
            case .command: return "Command"
            }
        }
        
        /// The CGEventFlags bit for this modifier
        var cgEventFlag: CGEventFlags {
            switch self {
            case .option: return .maskAlternate
            case .shift: return .maskShift
            case .control: return .maskControl
            case .command: return .maskCommand
            }
        }
        
        /// The Carbon key code for this modifier
        var keyCode: UInt16 {
            switch self {
            case .option: return 58    // kVK_Option
            case .shift: return 56     // kVK_Shift
            case .control: return 59   // kVK_Control
            case .command: return 55   // kVK_Command
            }
        }
    }
    
    var hotkeyModifier: HotkeyModifier {
        get {
            guard let raw = defaults.string(forKey: Key.hotkeyModifier.rawValue),
                  let modifier = HotkeyModifier(rawValue: raw) else {
                return .option // Default: double tap ⌥
            }
            return modifier
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.hotkeyModifier.rawValue)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    
    /// Whether the hotkey requires a double-tap (true) or single tap (false)
    var doubleTapMode: Bool {
        get { defaults.bool(forKey: Key.doubleTapMode.rawValue, default: true) }
        set {
            defaults.set(newValue, forKey: Key.doubleTapMode.rawValue)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    
    // MARK: - Toggle Settings
    
    var switchOnlyLastWord: Bool {
        get { defaults.bool(forKey: Key.switchOnlyLastWord.rawValue, default: true) }
        set {
            defaults.set(newValue, forKey: Key.switchOnlyLastWord.rawValue)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    
    var autoSwitchOnTab: Bool {
        get { defaults.bool(forKey: Key.autoSwitchOnTab.rawValue, default: false) }
        set { defaults.set(newValue, forKey: Key.autoSwitchOnTab.rawValue) }
    }
    
    var autoSwitchOnSpace: Bool {
        get { defaults.bool(forKey: Key.autoSwitchOnSpace.rawValue, default: false) }
        set { defaults.set(newValue, forKey: Key.autoSwitchOnSpace.rawValue) }
    }
    
    var autoSwitchOnEnter: Bool {
        get { defaults.bool(forKey: Key.autoSwitchOnEnter.rawValue, default: false) }
        set { defaults.set(newValue, forKey: Key.autoSwitchOnEnter.rawValue) }
    }
    
    var playSwitchingSound: Bool {
        get { defaults.bool(forKey: Key.playSwitchingSound.rawValue, default: false) }
        set { defaults.set(newValue, forKey: Key.playSwitchingSound.rawValue) }
    }
    
    var displayLayoutFlag: Bool {
        get { defaults.bool(forKey: Key.displayLayoutFlag.rawValue, default: false) }
        set {
            defaults.set(newValue, forKey: Key.displayLayoutFlag.rawValue)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    
    var autostartAfterLogin: Bool {
        get { defaults.bool(forKey: Key.autostartAfterLogin.rawValue, default: false) }
        set {
            defaults.set(newValue, forKey: Key.autostartAfterLogin.rawValue)
            updateLoginItem(enabled: newValue)
        }
    }
    
    var activeKeyboards: [String] {
        get { defaults.stringArray(forKey: Key.activeKeyboards.rawValue) ?? [] }
        set { defaults.set(newValue, forKey: Key.activeKeyboards.rawValue) }
    }
    
    // MARK: - Login Item
    
    private func updateLoginItem(enabled: Bool) {
        // For macOS 13+, use SMAppService
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update login item: \(error)")
            }
        }
    }
    
    private init() {
        defaults.register(defaults: [
            Key.hotkeyModifier.rawValue: HotkeyModifier.option.rawValue,
            Key.doubleTapMode.rawValue: true,
            Key.switchOnlyLastWord.rawValue: true,
            Key.playSwitchingSound.rawValue: false,
            Key.displayLayoutFlag.rawValue: false,
            Key.autostartAfterLogin.rawValue: false,
        ])
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let settingsChanged = Notification.Name("SettingsManagerSettingsChanged")
}

// MARK: - UserDefaults Helper

extension UserDefaults {
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
}

// MARK: - SMAppService import
import ServiceManagement
