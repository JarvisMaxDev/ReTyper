import Cocoa
import Carbon

// Drives only an explicitly supplied test process/document. The application under test handles
// the real modifier hotkey; this driver never calls its replacement implementation directly.
// Usage: editor-recovery-driver PID /absolute/path/repro.txt /absolute/output [repeats]
guard CommandLine.arguments.count >= 4, let pid = pid_t(CommandLine.arguments[1]),
      let app = NSRunningApplication(processIdentifier: pid) else { fatalError("PID, fixture and output required") }
let fixture = URL(fileURLWithPath: CommandLine.arguments[2])
let out = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let repeats = CommandLine.arguments.count > 4 ? Int(CommandLine.arguments[4]) ?? 1 : 1
let performance = CommandLine.arguments.contains("--performance")
let traceClipboard = CommandLine.arguments.contains("--trace-clipboard")
let previous = NSWorkspace.shared.frontmostApplication
let launchDate = app.launchDate
let pasteboard = NSPasteboard.general
let saved = (pasteboard.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
let originalSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let domain = "com.retyper.app" as CFString
let wordKey = "switchOnlyLastWord" as CFString
let originalWord = CFPreferencesCopyAppValue(wordKey, domain)
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.retyper.app/retyper.log")
let latin = "com.apple.keylayout.PolishPro", cyrillic = "com.apple.keylayout.RussianWin"
struct Abort: Error { let reason: String }
func pump(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func check() throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          NSRunningApplication(processIdentifier: pid)?.launchDate == launchDate,
          let rawWindow = attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute),
          CFGetTypeID(rawWindow) == AXUIElementGetTypeID(),
          (attribute(rawWindow as! AXUIElement, kAXTitleAttribute) as? String ?? "").contains(fixture.lastPathComponent)
    else { throw Abort(reason: "Test recipient changed; no further input sent") }
}
func key(_ code: UInt16, _ flags: CGEventFlags = []) throws {
    try check()
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { throw Abort(reason: "No event") }
        event.flags = flags; event.post(tap: .cghidEventTap); usleep(5_000)
    }
    pump(0.05)
}
func write(_ text: String) {
    pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
}
func selectLayout(_ id: String) throws {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let source = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first,
          TISSelectInputSource(source) == noErr else { throw Abort(reason: "Missing layout") }
    pump(0.08)
}
func currentLayout() -> String {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    return Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue() as String
}
func logText() -> String { (try? String(contentsOf: logURL, encoding: .utf8)) ?? "" }
var gestureFinishedAt = 0.0
func hotkey() throws -> (String, Double) {
    try check()
    let offset = logText().utf8.count
    for _ in 0..<2 {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 58, keyDown: down)!
            event.type = .flagsChanged; event.flags = down ? .maskAlternate : []
            event.post(tap: .cghidEventTap)
            if !down { gestureFinishedAt = ProcessInfo.processInfo.systemUptime }
            pump(0.05)
        }
    }
    let start = ProcessInfo.processInfo.systemUptime
    while ProcessInfo.processInfo.systemUptime - start < 4 {
        let suffix = String(decoding: logText().utf8.dropFirst(offset), as: UTF8.self)
        if let line = suffix.split(separator: "\n").first(where: { $0.contains("Replacement outcome:") }) {
            let delay = ProcessInfo.processInfo.systemUptime - start
            if !performance { pump(0.65) }
            return (String(line), delay)
        }
        pump(0.01)
    }
    throw Abort(reason: "No hotkey outcome")
}
let sentinel = NSAttributedString(string: "retyper recovery sentinel", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
let rtf = sentinel.rtf(from: NSRange(location: 0, length: sentinel.length), documentAttributes: [:])!
func setSentinel() {
    pasteboard.clearContents(); let item = NSPasteboardItem()
    item.setString("retyper recovery sentinel", forType: .string); item.setData(rtf, forType: .rtf)
    pasteboard.writeObjects([item])
}
var scenarios: [(String, String, String, String, Bool, Bool)] = [
    ("partial-forward", "prefix ghbdtn suffix", "prefix привет suffix", "forward", false, false),
    ("partial-backward", "prefix ghbdtn suffix", "prefix привет suffix", "backward", false, false),
    ("partial-word-mode", "prefix ghbdtn suffix", "prefix привет suffix", "forward", true, false),
    ("whole-line", "ghbdtn", "привет", "end", false, false),
    ("line-start", "ghbdtn", "ghbdtn", "start", false, false),
    ("empty", "", "", "end", false, false),
    ("last-word", "hello ghbdtn", "hello привет", "end", true, false),
    ("symbols", "^)", ":)", "end", false, false),
    ("reverse", "привет", "ghbdtn", "end", false, true)
]
if CommandLine.arguments.contains("--reverse-first") { scenarios.swapAt(0, 1) }
if performance { scenarios = [("hundred-characters", String(repeating: "a", count: 100), String(repeating: "ф", count: 100), "end", false, false)] }
if let filter = CommandLine.arguments.first(where: { $0.hasPrefix("--scenario=") }) {
    scenarios = scenarios.filter { $0.0 == String(filter.dropFirst("--scenario=".count)) }
}
var results: [[String: Any]] = []
var failure: String?
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
func restoreEnvironment() {
    pasteboard.clearContents()
    let restored = saved.map { pairs -> NSPasteboardItem in let item = NSPasteboardItem(); for (t, d) in pairs { item.setData(d, forType: t) }; return item }
    if !restored.isEmpty { pasteboard.writeObjects(restored) }
    CFPreferencesSetAppValue(wordKey, originalWord, domain); CFPreferencesAppSynchronize(domain)
    TISSelectInputSource(originalSource); previous?.activate()
}
defer { restoreEnvironment() }
do {
    app.activate(); pump(0.7)
    if let windows = attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] {
        let matches = windows.filter { (attribute($0, kAXTitleAttribute) as? String ?? "").contains(fixture.lastPathComponent) }
        guard matches.count == 1 else { throw Abort(reason: "Test window is missing or ambiguous") }
        _ = AXUIElementSetAttributeValue(matches[0], kAXMainAttribute as CFString, kCFBooleanTrue)
        guard AXUIElementPerformAction(matches[0], kAXRaiseAction as CFString) == .success else { throw Abort(reason: "Cannot activate test window") }
        pump(0.15)
    }
    for iteration in 1...max(1, repeats) {
        for (name, input, expected, position, word, reverse) in scenarios {
            try check()
            CFPreferencesSetAppValue(wordKey, word as CFBoolean, domain); CFPreferencesAppSynchronize(domain)
            try selectLayout(reverse ? cyrillic : latin)
            try key(0, .maskCommand)
            if input.isEmpty { try key(51) } else { write(input); try key(9, .maskCommand) }
            if position == "start" { try key(123, .maskCommand) }
            if position == "forward" || position == "backward" {
                try key(123, .maskCommand)
                for _ in 0..<(position == "forward" ? 7 : 13) { try key(124) }
                for _ in 0..<6 { try key(position == "forward" ? 124 : 123, .maskShift) }
            }
            setSentinel()
            var clipboardTrace: [[String: Any]] = []
            var lastCount = pasteboard.changeCount
            let traceStart = ProcessInfo.processInfo.systemUptime
            let timer = traceClipboard ? Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { _ in
                let count = pasteboard.changeCount
                guard count != lastCount else { return }
                lastCount = count
                let value = pasteboard.string(forType: .string)
                let kind = value == "retyper recovery sentinel" ? "sentinel" : value == input ? "input" : value == expected ? "expected-document" : value == "ghbdtn" ? "selected-source" : value == "привет" ? "converted-selection" : "other"
                clipboardTrace.append(["seconds": ProcessInfo.processInfo.systemUptime - traceStart, "count": count,
                                       "types": pasteboard.types?.map(\.rawValue) ?? [], "contentKind": kind])
            } : nil
            defer { timer?.invalidate() }
            let (outcome, delay) = try hotkey()
            let layoutAtOutcome = currentLayout()
            // Saving after the outcome observes the actual document, not merely the queued paste.
            try key(1, .maskCommand)
            var actual = try String(contentsOf: fixture, encoding: .utf8)
            let deadline = Date().addingTimeInterval(1)
            while actual != expected, Date() < deadline {
                pump(0.01); actual = try String(contentsOf: fixture, encoding: .utf8)
            }
            let documentDelay = ProcessInfo.processInfo.systemUptime - gestureFinishedAt
            let expectedLayout = reverse ? latin : cyrillic
            while currentLayout() != expectedLayout, ProcessInfo.processInfo.systemUptime - gestureFinishedAt < 1 {
                pump(0.01)
            }
            let layoutOK = currentLayout() == expectedLayout
            if performance { pump(0.65) }
            let clipboardOK = pasteboard.string(forType: .string) == "retyper recovery sentinel"
                && pasteboard.data(forType: .rtf) == rtf
            let pass = actual == expected && clipboardOK && layoutOK && (!performance || documentDelay <= 1)
            results.append(["iteration": iteration, "scenario": name, "pass": pass, "actual": actual,
                            "expected": expected, "clipboard": clipboardOK, "layout": layoutOK,
                            "outcome": outcome, "outcomeObservedAfterGestureSeconds": delay,
                            "clipboardTrace": clipboardTrace,
                            "layoutAtOutcome": layoutAtOutcome, "layoutAfterDocumentSave": currentLayout(),
                            "savedDocumentObservedAfterGestureSeconds": documentDelay])
            print(iteration, name, pass ? "PASS" : "FAIL", "clipboard=\(clipboardOK)", "layout=\(layoutOK)")
            if !pass { throw Abort(reason: "Scenario mismatch: \(name)") }
        }
    }
} catch { failure = String(describing: error); print("ABORT", failure!) }
let report: [String: Any] = ["pid": pid, "fixture": fixture.path, "results": results,
                            "failure": failure as Any? ?? NSNull(), "passed": results.filter { $0["pass"] as? Bool == true }.count]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("report.json"))
print("TOTAL", results.count, "PASS", results.filter { $0["pass"] as? Bool == true }.count)
if failure != nil { restoreEnvironment(); exit(1) }
