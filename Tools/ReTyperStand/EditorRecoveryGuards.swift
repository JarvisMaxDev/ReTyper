import Cocoa
import Carbon

// Negative live scenarios against the real running ReTyper. Only supplied owned fixtures are used.
// Usage: guards CODE_PID FIXTURE OUT TEXTEDIT_PID TEXTEDIT_FIXTURE
let pid = pid_t(CommandLine.arguments[1])!, otherPID = pid_t(CommandLine.arguments[4])!
let app = NSRunningApplication(processIdentifier: pid)!, other = NSRunningApplication(processIdentifier: otherPID)!
let fixture = URL(fileURLWithPath: CommandLine.arguments[2]), out = URL(fileURLWithPath: CommandLine.arguments[3])
let otherFile = URL(fileURLWithPath: CommandLine.arguments[5])
let windowOnly = CommandLine.arguments.contains("--window-only")
let windowTarget = fixture.deletingLastPathComponent().appendingPathComponent("window-target.txt")
let previous = NSWorkspace.shared.frontmostApplication
let pb = NSPasteboard.general
let saved = (pb.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
let originalLayout = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let domain = "com.retyper.app" as CFString, wordKey = "switchOnlyLastWord" as CFString
let originalWord = CFPreferencesCopyAppValue(wordKey, domain)
let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.retyper.app/retyper.log")
struct Abort: Error { let reason: String }
func pump(_ t: Double) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
func attr(_ e: AXUIElement, _ n: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil }
func check() throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          let w = attr(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute),
          (attr(w as! AXUIElement, kAXTitleAttribute) as? String ?? "").contains(fixture.lastPathComponent)
    else { throw Abort(reason: "Target changed") }
}
func key(_ code: UInt16, _ flags: CGEventFlags = [], settle: Double = 0.05) throws {
    try check()
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        e.flags = flags; e.post(tap: .cghidEventTap); usleep(3000)
    }
    if settle > 0 { pump(settle) }
}
func write(_ text: String) { pb.clearContents(); pb.setString(text, forType: .string) }
func raiseWindow(named name: String) throws {
    guard let windows = attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement],
          let window = windows.first(where: { (attr($0, kAXTitleAttribute) as? String ?? "").contains(name) })
    else { throw Abort(reason: "Owned window missing") }
    _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { throw Abort(reason: "Cannot raise owned window") }
    pump(0.08)
}
func saveWindowTarget() throws -> Bool {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          let w = attr(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute),
          (attr(w as! AXUIElement, kAXTitleAttribute) as? String ?? "").contains(windowTarget.lastPathComponent)
    else { throw Abort(reason: "Window injection did not switch recipient") }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: 1, keyDown: down)!
        e.flags = .maskCommand; e.post(tap: .cghidEventTap); usleep(3000)
    }
    pump(0.2)
    return try String(contentsOf: windowTarget, encoding: .utf8) == "untouched-target\n"
}
func textLog() -> String { (try? String(contentsOf: log, encoding: .utf8)) ?? "" }
func focused() -> AXUIElement? {
    guard let v = attr(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}
func context() -> [String: Any] {
    guard let f = focused() else { return [:] }
    return ["role": attr(f, kAXRoleAttribute) as? String ?? "nil", "classes": attr(f, "AXDOMClassList") as? [String] ?? []]
}
func otherText() -> String? {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == otherPID,
          let w = attr(AXUIElementCreateApplication(otherPID), kAXFocusedWindowAttribute),
          (attr(w as! AXUIElement, kAXTitleAttribute) as? String ?? "").contains(otherFile.lastPathComponent),
          let f = focused() else { return nil }
    return attr(f, kAXValueAttribute) as? String
}
func hotkey(inject: (() throws -> Void)? = nil) throws -> (String, Bool) {
    let offset = textLog().utf8.count, before = pb.changeCount
    var injected = false
    try check()
    for i in 0..<4 {
        let down = i % 2 == 0
        let e = CGEvent(keyboardEventSource: nil, virtualKey: 58, keyDown: down)!
        e.type = .flagsChanged; e.flags = down ? .maskAlternate : []; e.post(tap: .cghidEventTap)
        if i < 3 { pump(0.05) }
    }
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        if !injected, let inject, pb.changeCount != before { try inject(); injected = true }
        let suffix = String(decoding: textLog().utf8.dropFirst(offset), as: UTF8.self)
        if let line = suffix.split(separator: "\n").first(where: { $0.contains("Replacement outcome:") }) {
            pump(0.7); return (String(line), injected)
        }
        pump(0.001)
    }
    return ("no event delivered", injected)
}
let sentinel = "retyper-guard-sentinel"
let base = String(repeating: "a", count: 150) + " ghbdtn"
func setup() throws {
    app.activate(); pump(0.4)
    if windowOnly { try raiseWindow(named: fixture.lastPathComponent) }
    try check()
    // Cmd+1 returns to the editor without modifying its document.
    try key(18, .maskCommand)
    CFPreferencesSetAppValue(wordKey, true as CFBoolean, domain); CFPreferencesAppSynchronize(domain)
    let source = (TISCreateInputSourceList([kTISPropertyInputSourceID as String: "com.apple.keylayout.PolishPro"] as CFDictionary, true)!.takeRetainedValue() as! [TISInputSource])[0]
    TISSelectInputSource(source); pump(0.05)
    try key(0, .maskCommand); write(base); try key(9, .maskCommand); try key(1, .maskCommand)
    write(sentinel)
}
var results: [[String: Any]] = []
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
defer {
    pb.clearContents(); let items = saved.map { pairs -> NSPasteboardItem in let i = NSPasteboardItem(); for (t,d) in pairs { i.setData(d, forType:t) }; return i }
    if !items.isEmpty { pb.writeObjects(items) }
    CFPreferencesSetAppValue(wordKey, originalWord, domain); CFPreferencesAppSynchronize(domain)
    TISSelectInputSource(originalLayout); previous?.activate()
}
do {
    for panel in (windowOnly ? [] : ["find", "terminal"]) {
        try setup()
        if panel == "find" { try key(3, .maskCommand) } else { try key(50, .maskControl); pump(1) }
        let observed = context(), count = pb.changeCount
        let (outcome, _) = try hotkey()
        let noCopy = pb.changeCount == count && pb.string(forType: .string) == sentinel
        let pass = outcome.contains("editor field not supported") && noCopy
        print(panel, pass ? "PASS" : "FAIL", observed, outcome)
        results.append(["scenario": panel, "pass": pass, "context": observed, "clipboardUnchanged": noCopy, "outcome": outcome])
        if panel == "find" { try key(53) } else { try key(50, .maskControl) }
        if !pass { throw Abort(reason: "Unsupported field accepted") }
    }
    for name in (windowOnly ? ["window-change", "foreign-editor-copy"] : ["typing", "field-change", "app-change", "round-trip", "foreign-copy"]) {
        try setup()
        let beforeOther = try String(contentsOf: otherFile, encoding: .utf8)
        let (outcome, injected) = try hotkey {
            switch name {
            case "typing": try key(7, settle: 0)
            case "field-change": try key(3, .maskCommand, settle: 0)
            case "app-change": other.activate(); pump(0.08)
            case "round-trip": other.activate(); pump(0.08); app.activate(); pump(0.08)
            case "window-change": try raiseWindow(named: windowTarget.lastPathComponent)
            case "foreign-editor-copy":
                try raiseWindow(named: windowTarget.lastPathComponent)
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: down)!
                    event.flags = .maskCommand; event.post(tap: .cghidEventTap); usleep(3000)
                }
                pump(0.08)
            default: write("foreign-copy-sentinel")
            }
        }
        let expectedClipboard = name == "foreign-editor-copy" ? "untouched-target\n" : name == "foreign-copy" ? "foreign-copy-sentinel" : sentinel
        let clipboardOK = pb.string(forType: .string) == expectedClipboard
        let otherOK = (name == "window-change" || name == "foreign-editor-copy") ? try saveWindowTarget() : name != "app-change" || otherText() == beforeOther
        let cancelled = outcome.contains("layoutOnly") && !outcome.contains("nothing to convert")
        let pass = injected && cancelled && clipboardOK && otherOK
        print(name, pass ? "PASS" : "FAIL", "injected", injected, "clipboard", clipboardOK, "other", otherOK, outcome)
        results.append(["scenario": name, "pass": pass, "injected": injected, "clipboard": clipboardOK, "otherField": otherOK, "outcome": outcome])
        app.activate(); pump(0.3)
        if name == "field-change" { try key(53) }
        // Finish all independent cases even if a cancellation exposed a clipboard issue.
    }
    if !windowOnly {
    try setup()
    let count = pb.changeCount
    guard !IsSecureEventInputEnabled(), EnableSecureEventInput() == noErr else { throw Abort(reason: "Cannot own secure-input test") }
    let result: (String, Bool)
    do { defer { DisableSecureEventInput() }; result = try hotkey() }
    let secureOK = pb.changeCount == count && (result.0 == "no event delivered" || result.0.contains("layoutOnly"))
    print("secure-input", secureOK ? "PASS" : "FAIL", result.0)
    results.append(["scenario": "secure-input", "pass": secureOK, "outcome": result.0])
    }
} catch { print("ABORT", error); results.append(["scenario": "harness", "pass": false, "error": String(describing: error)]) }
try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("report.json"))
