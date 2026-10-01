import Cocoa
import Carbon

// Only generated vared prompts receive test input; their contents are never executed.
@main enum TerminalDriver {
    static let pl = "com.apple.keylayout.PolishPro"
    static let ru = "com.apple.keylayout.RussianWin"
    static let domain = "com.retyper.app" as CFString
    static let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.retyper.app/retyper.log")
    struct Scenario {
        let id: String
        var layout = pl
        var preset = ""
        let text: String
        var before: [UInt16] = []
        var control = false
        var command = false
        var mouse = false
        var leaveAndReturn = false
        var secure = false
        var lastWord = false
        var hotkeys = 1
        var enterDelay: Double? = nil
        var racingKey: UInt16? = nil
        let expected: String
        var target = ru
        var replaced = true
    }
    static var scenarios: [Scenario] { [
        .init(id: "T1", text: "ghbdtn", expected: "привет"),
        .init(id: "T2", layout: ru, text: "сгкд -Ш", expected: "curl -I", target: pl),
        .init(id: "T3", text: "ghbdtn", hotkeys: 2, expected: "ghbdtn", target: pl),
        .init(id: "T4", preset: "ls ", text: "ghbdtn", expected: "ls привет"),
        .init(id: "T5", text: "git commit -m ghbdtn", lastWord: true, expected: "git commit -m привет"),
        .init(id: "T6", text: "ghbdtn vbh", expected: "привет мир"),
        .init(id: "T7", text: "ghbdtnx", before: [51], expected: "привет"),
        .init(id: "T8", text: "ghbdtn", before: [123], expected: "ghbdtn", replaced: false),
        .init(id: "T9", text: "ghbdtn", before: [0], control: true, expected: "ghbdtn", replaced: false),
        .init(id: "T10", preset: "ls", text: "", expected: "ls", replaced: false),
        .init(id: "T11", text: String(repeating: "a", count: 260), expected: String(repeating: "a", count: 260), replaced: false),
        .init(id: "T13", text: String(repeating: "a", count: 100), expected: String(repeating: "ф", count: 100)),
        .init(id: "TMax", text: String(repeating: "a", count: 256), expected: String(repeating: "ф", count: 256)),
        .init(id: "Typing0", text: String(repeating: "a", count: 100), racingKey: 7, expected: String(repeating: "ф", count: 100) + "ч"),
        .init(id: "Enter0", text: String(repeating: "a", count: 100), enterDelay: 0, expected: String(repeating: "ф", count: 100)),
        .init(id: "Enter10", text: String(repeating: "a", count: 100), enterDelay: 0.01, expected: String(repeating: "ф", count: 100)),
        .init(id: "Enter30", text: String(repeating: "a", count: 100), enterDelay: 0.03, expected: String(repeating: "ф", count: 100)),
        .init(id: "Enter80", text: String(repeating: "a", count: 100), enterDelay: 0.08, expected: String(repeating: "ф", count: 100)),
        .init(id: "Tab", text: "ghbdtn", before: [48], expected: "ghbdtn", replaced: false),
        .init(id: "Paste", text: "ghbdtn", before: [9], command: true, expected: "ghbdtnterminal sentinel", replaced: false),
        .init(id: "Mouse", text: "ghbdtn", mouse: true, expected: "ghbdtn", replaced: false),
        .init(id: "AppReturn", text: "ghbdtn", leaveAndReturn: true, expected: "ghbdtn", replaced: false),
        .init(id: "Secure", text: "ghbdtn", secure: true, expected: "ghbdtn", replaced: false),
    ] }
    struct Failure: Error { let message: String }
    static func pump(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
    static func layout() -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue() as String
    }
    static func select(_ id: String) throws {
        let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
        guard let source = sources.first, TISSelectInputSource(source) == noErr else { throw Failure(message: "Layout unavailable: \(id)") }
        pump(0.08)
    }
    static func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }
    static func window(_ name: String) -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.apple.Terminal",
              let window = attr(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
              let title = attr(window as! AXUIElement, kAXTitleAttribute) as? String, title.contains(name) else { return nil }
        return (window as! AXUIElement)
    }
    static func terminalWindows() throws -> [AXUIElement] {
        guard let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first else { return [] }
        let app = AXUIElementCreateApplication(terminal.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let deadline = Date(timeIntervalSinceNow: 2)
        var error = AXError.failure
        repeat {
            var raw: CFTypeRef?
            error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
            if error == .success, let windows = raw as? [AXUIElement] { return windows }
            // Terminal can briefly stop answering AX while closing its last test window.
            // Wait for an actual window list; never treat an AX error as successful cleanup.
            pump(0.05)
        } while Date() < deadline
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty {
            return []
        }
        throw Failure(message: "Cannot verify test-window cleanup (AX \(error.rawValue))")
    }
    static func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 8 else { return [] }
        let children = attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return children + children.flatMap { descendants($0, depth: depth + 1) }
    }
    /// Close only our uniquely named fixture. A close request is not evidence of closure:
    /// Terminal may leave a confirmation sheet while login-shell cleanup still runs.
    static func closeOwnedWindow(named name: String) throws {
        let matches = try terminalWindows().filter {
            (attr($0, kAXTitleAttribute) as? String ?? "").contains(name + ".command")
        }
        guard !matches.isEmpty else { return }
        guard matches.count == 1, let owned = matches.first else {
            throw Failure(message: "Ambiguous test-window identity; cleanup stopped")
        }
        var requested = false
        var confirmedSheets: [AXUIElement] = []
        let deadline = Date(timeIntervalSinceNow: 5)
        while Date() < deadline {
            guard try terminalWindows().contains(where: { CFEqual($0, owned) }) else { return }
            let sheets = descendants(owned).filter { attr($0, kAXRoleAttribute) as? String == kAXSheetRole }
            if sheets.isEmpty, !requested {
                guard let raw = attr(owned, kAXCloseButtonAttribute),
                      AXUIElementPerformAction(raw as! AXUIElement, kAXPressAction as CFString) == .success else {
                    throw Failure(message: "Cannot close own test window: \(name)")
                }
                requested = true
            }
            for sheet in sheets where !confirmedSheets.contains(where: { CFEqual($0, sheet) }) {
                let terminate = descendants(sheet).filter {
                    attr($0, kAXRoleAttribute) as? String == kAXButtonRole
                        && ["Прервать", "Terminate", "Закрыть", "Close"].contains(attr($0, kAXTitleAttribute) as? String ?? "")
                }
                // A sheet can appear before its buttons, or change from Terminate to Close
                // when the shell finishes saving its session. Keep the same bounded wait.
                if terminate.count == 1,
                   AXUIElementPerformAction(terminate[0], kAXPressAction as CFString) == .success {
                    confirmedSheets.append(sheet)
                }
            }
            pump(0.1)
        }
        throw Failure(message: "Test window did not close; no further windows will be opened: \(name)")
    }
    static func post(_ code: UInt16, flags: CGEventFlags = [], unicode: String? = nil, name: String) throws {
        guard window(name) != nil else { throw Failure(message: "Test window lost focus; stopped") }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            // CGEvent's constructor supplies US Unicode even for a selected Russian layout.
            // Match the layout-derived key's payload, as a translated hardware event would.
            if let unicode {
                let units = Array(unicode.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            event.post(tap: .cghidEventTap)
            usleep(1_000)
        }
    }
    @discardableResult static func hotkey(name: String) throws -> Date {
        guard window(name) != nil else { throw Failure(message: "Test window lost focus") }
        for index in 0..<2 {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 58, keyDown: down)!
                event.type = .flagsChanged; event.flags = down ? .maskAlternate : []
                event.post(tap: .cghidEventTap)
                if down { usleep(40_000) }
            }
            if index == 0 { usleep(40_000) }
        }
        return Date()
    }
    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func visiblePrompt(name: String) -> String {
        guard window(name) != nil, let app = NSWorkspace.shared.frontmostApplication,
              let raw = attr(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute),
              let text = attr(raw as! AXUIElement, kAXValueAttribute) as? String,
              text.contains("RETYPER-TEST> ") else { return "<unavailable>" }
        // Only retain our vared prompt, never the login shell's startup output.
        return text.components(separatedBy: "RETYPER-TEST> ").last.map { String($0.prefix(600)) } ?? "<missing>"
    }
    static func run() throws -> Bool {
        let args = CommandLine.arguments
        func arg(_ key: String) -> String? { guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }; return args[i + 1] }
        let out = URL(fileURLWithPath: arg("--out") ?? "Tools/ReTyperStand/out/terminal-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard AXIsProcessTrusted(), !NSRunningApplication.runningApplications(withBundleIdentifier: domain as String).isEmpty else { throw Failure(message: "Accessibility and running ReTyper required") }
        let originalLayout = layout()
        let originalWord = CFPreferencesCopyAppValue("switchOnlyLastWord" as CFString, domain)
        let originalMouse = CGEvent(source: nil)?.location
        var ownsSecureInput = false
        var openedNames: Set<String> = []
        let clipboard = NSPasteboard.general
        let originalClipboard = (clipboard.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        defer {
            if ownsSecureInput { DisableSecureEventInput() }
            // Also clean up if focus is lost, readiness times out, or a scenario throws.
            for name in openedNames {
                do { try closeOwnedWindow(named: name) }
                catch { fputs("Terminal stand cleanup failed: \(error)\n", stderr) }
            }
            if let originalMouse { CGWarpMouseCursorPosition(originalMouse) }
            CFPreferencesSetAppValue("switchOnlyLastWord" as CFString, originalWord, domain); CFPreferencesAppSynchronize(domain)
            try? select(originalLayout)
            clipboard.clearContents()
            clipboard.writeObjects(originalClipboard.map { entries in let item = NSPasteboardItem(); for (type, data) in entries { item.setData(data, forType: type) }; return item })
        }
        var results: [[String: Any]] = []
        for repeatIndex in 1...max(1, Int(arg("--repeat") ?? "1") ?? 1) {
            for scenario in scenarios where arg("--case") == nil || arg("--case") == scenario.id {
                let name = "retyper-terminal-\(scenario.id)-\(repeatIndex)-\(UUID().uuidString.prefix(6))"
                let lineURL = out.appendingPathComponent(name + ".txt")
                let readyURL = out.appendingPathComponent(name + ".ready")
                let command = out.appendingPathComponent(name + ".command")
                try ("#!/bin/zsh -f\nexport LC_CTYPE=en_US.UTF-8\nbindkey -e\nfunction zle-line-init { print ready > \(quote(readyURL.path)); }\nzle -N zle-line-init\nline=\(quote(scenario.preset)); vared -p 'RETYPER-TEST> ' -c line; print -rn -- \"$line\" > \(quote(lineURL.path + ".tmp")); /bin/mv \(quote(lineURL.path + ".tmp")) \(quote(lineURL.path)); exit\n").write(to: command, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)
                CFPreferencesSetAppValue("switchOnlyLastWord" as CFString, scenario.lastWord as CFBoolean, domain); CFPreferencesAppSynchronize(domain)
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = ["-a", "Terminal", command.path]
                openedNames.insert(name)
                try process.run(); process.waitUntilExit()
                let readyDeadline = Date(timeIntervalSinceNow: 8)
                while (!FileManager.default.fileExists(atPath: readyURL.path) || window(name) == nil), Date() < readyDeadline { pump(0.05) }
                guard FileManager.default.fileExists(atPath: readyURL.path) else { throw Failure(message: "vared not ready") }
                pump(0.1)
                guard window(name) != nil else { throw Failure(message: "Test prompt not focused: \(name)") }
                try select(scenario.layout)
                let sentinel = NSPasteboardItem(); sentinel.setString("terminal sentinel", forType: .string)
                sentinel.setData(Data("{\\rtf1 terminal sentinel}".utf8), forType: .rtf)
                clipboard.clearContents(); clipboard.writeObjects([sentinel]); let clipboardCount = clipboard.changeCount
                let map = KeyLayout.system(id: scenario.layout, keyboardType: UInt32(LMGetKbdType()))!
                for character in scenario.text {
                    let stroke = character == " " ? KeyStroke(keyCode: 49, shift: false) : map.keys.keys.sorted().first { map.keys[$0] == character }!
                    try post(stroke.keyCode, flags: stroke.shift ? .maskShift : [], unicode: String(character), name: name)
                    pump(0.004)
                }
                for code in scenario.before { try post(code, flags: scenario.control ? .maskControl : scenario.command ? .maskCommand : [], name: name) }
                if scenario.mouse {
                    guard window(name) != nil, let app = NSWorkspace.shared.frontmostApplication,
                          let raw = attr(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute),
                          let position = attr(raw as! AXUIElement, kAXPositionAttribute) else { throw Failure(message: "No test field position") }
                    var point = CGPoint.zero
                    guard AXValueGetValue(position as! AXValue, .cgPoint, &point) else { throw Failure(message: "No point") }
                    point.x += 30; point.y += 30
                    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                        pump(0.03)
                    }
                }
                if scenario.leaveAndReturn {
                    let terminal = NSWorkspace.shared.frontmostApplication!
                    guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { throw Failure(message: "No Finder for focus test") }
                    other.activate(options: .activateIgnoringOtherApps); pump(0.2)
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == other.processIdentifier else { throw Failure(message: "Focus did not leave Terminal") }
                    terminal.activate(options: .activateIgnoringOtherApps); pump(0.2)
                }
                pump(0.2)
                let beforeVisible = visiblePrompt(name: name)
                if scenario.secure {
                    guard !IsSecureEventInputEnabled(), EnableSecureEventInput() == noErr else { throw Failure(message: "Cannot own secure-input test") }
                    ownsSecureInput = true; pump(0.1)
                }
                let offset = (try Data(contentsOf: logURL)).count
                var start = Date()
                for index in 0..<scenario.hotkeys {
                    start = try hotkey(name: name)
                    if index + 1 < scenario.hotkeys { pump(0.4) }
                }
                if let delay = scenario.enterDelay { usleep(useconds_t(delay * 1_000_000)); try post(36, name: name) }
                if let code = scenario.racingKey { try post(code, name: name) }
                var log = ""
                let deadline = Date(timeIntervalSinceNow: 3)
                while Date() < deadline {
                    log = String(decoding: (try Data(contentsOf: logURL)).dropFirst(offset), as: UTF8.self)
                    if log.contains("Replacement outcome:") { break }
                    pump(0.01)
                }
                let elapsed = Date().timeIntervalSince(start)
                if ownsSecureInput { DisableSecureEventInput(); ownsSecureInput = false }
                pump(0.15)
                let finalLayout = layout()
                let afterVisible = visiblePrompt(name: name)
                if scenario.enterDelay == nil { try post(36, name: name) }
                let lineDeadline = Date(timeIntervalSinceNow: 3)
                while !FileManager.default.fileExists(atPath: lineURL.path), Date() < lineDeadline { pump(0.03) }
                let actual = try? String(contentsOf: lineURL, encoding: .utf8)
                let outcome = scenario.replaced ? "replaced(" : "layoutOnly("
                // An immediate Return may cancel preflight, but must never submit a partial edit.
                let cancelled = scenario.enterDelay != nil && actual == scenario.text && log.contains("layoutOnly(")
                // The user key can arrive on either side of the layout switch. Both complete
                // results are valid; missing, reordered or partially converted text is not.
                let racingText = scenario.racingKey != nil && actual == String(scenario.expected.dropLast()) + "x"
                let secureOK = scenario.secure && actual == scenario.expected && !log.contains("replaced(")
                let passed = ((((actual == scenario.expected || racingText) && log.contains(outcome)) || cancelled)
                    && finalLayout == scenario.target || secureOK) && clipboard.changeCount == clipboardCount
                results.append(["case": scenario.id, "repeat": repeatIndex, "passed": passed,
                                "actual": actual ?? "<no submitted line>", "layout": finalLayout,
                                "seconds": elapsed, "log": log, "cancelledBeforeEdit": cancelled])
                results[results.count - 1]["beforeVisible"] = beforeVisible
                results[results.count - 1]["afterVisible"] = afterVisible
                print("\(passed ? "PASS" : "FAIL") \(scenario.id) #\(repeatIndex): \(elapsed)s \(actual.map { String(reflecting: $0) } ?? "missing line") \(log)")
                try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("report.json"))
                try closeOwnedWindow(named: name)
                openedNames.remove(name)
                if !passed { return false }
            }
        }
        return !results.isEmpty
    }
    static func main() {
        do { exit(try run() ? 0 : 1) }
        catch { fputs("Terminal stand: \(error)\n", stderr); exit(2) }
    }
}
