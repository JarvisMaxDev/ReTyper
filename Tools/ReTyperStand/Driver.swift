import Cocoa
import Carbon

// Drives ReTyperStand like a user: prepares the field, presses a double ⌥ and checks the result.
// Keys are posted only while the stand is the active app; otherwise the run stops.

let standBundleID = "com.retyper.stand"
let reTyperBundleID = "com.retyper.app"
let latinLayout = "com.apple.keylayout.PolishPro"
let cyrillicLayout = "com.apple.keylayout.RussianWin"
let lastWordKey = "switchOnlyLastWord" as CFString
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Caches/com.retyper.app/retyper.log")

struct Scenario {
    let number: Int
    let title: String
    /// Layout to select first; nil continues from the previous scenario.
    let layout: String?
    /// Field content to set first; nil keeps the field as the previous scenario left it.
    let text: String?
    var selection: NSRange? = nil
    var lastWord = false
    var richClipboard = false
    let expectedText: String
    let expectedLayout: String
    /// Fragment of ReTyper's "Replacement outcome:" line that must appear.
    var expectedOutcome = "replaced("
    /// Scenario that must pass first; otherwise this one is skipped.
    var dependsOn: Int? = nil
}

let scenarios: [Scenario] = CommandLine.arguments.contains("--copy-race") ? [
    Scenario(number: 1, title: "native copy followed by delayed renderer copy", layout: latinLayout,
             text: "ghbdtn", richClipboard: true, expectedText: "привет", expectedLayout: cyrillicLayout),
] : CommandLine.arguments.contains("--secure-input") ? [
    Scenario(number: 1, title: "ordinary field with unrelated global secure input", layout: latinLayout,
             text: "ghbdtn", richClipboard: true, expectedText: "привет", expectedLayout: cyrillicLayout),
] : CommandLine.arguments.contains("--secure-field") ? [
    Scenario(number: 1, title: "real NSSecureTextField is never copied or replaced", layout: latinLayout,
             text: "ghbdtn", richClipboard: true, expectedText: "ghbdtn", expectedLayout: cyrillicLayout,
             expectedOutcome: "layoutOnly(reason: \"secure field\")"),
] : [
    Scenario(number: 1, title: "^) on PL", layout: latinLayout, text: "^)",
             expectedText: ":)", expectedLayout: cyrillicLayout),
    Scenario(number: 2, title: "second press right after 1", layout: nil, text: nil,
             expectedText: "^)", expectedLayout: latinLayout, dependsOn: 1),
    Scenario(number: 3, title: ":) on RU", layout: cyrillicLayout, text: ":)",
             expectedText: "^)", expectedLayout: latinLayout),
    Scenario(number: 4, title: "Ghbdtn^) on PL", layout: latinLayout, text: "Ghbdtn^)",
             expectedText: "Привет:)", expectedLayout: cyrillicLayout),
    Scenario(number: 5, title: "& on PL", layout: latinLayout, text: "&",
             expectedText: "?", expectedLayout: cyrillicLayout),
    Scenario(number: 6, title: "))) unchanged, layout switches", layout: latinLayout, text: ")))",
             expectedText: ")))", expectedLayout: cyrillicLayout,
             expectedOutcome: "layoutOnly(reason: \"nothing to convert\")"),
    Scenario(number: 7, title: "§ on PL (ISO)", layout: latinLayout, text: "§",
             expectedText: "ё", expectedLayout: cyrillicLayout),
    Scenario(number: 8, title: "last word mode: ок ^)", layout: latinLayout, text: "ок ^)", lastWord: true,
             expectedText: "ок :)", expectedLayout: cyrillicLayout),
    Scenario(number: 9, title: "user selection ^) ^)", layout: latinLayout, text: "abc ^) ^)",
             selection: NSRange(location: 4, length: 5),
             expectedText: "abc :) :)", expectedLayout: cyrillicLayout),
    Scenario(number: 10, title: "empty field", layout: latinLayout, text: "",
             expectedText: "", expectedLayout: cyrillicLayout,
             expectedOutcome: "layoutOnly(reason: \"nothing before caret\")"),
    Scenario(number: 11, title: "RTF + text clipboard restored", layout: latinLayout, text: "^)",
             richClipboard: true, expectedText: ":)", expectedLayout: cyrillicLayout),
]

// MARK: - Helpers

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write("stand-driver: \(message)\n".data(using: .utf8)!)
    exit(code)
}

/// Waits while letting the run loop deliver workspace updates.
func pump(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
}

func currentLayout() -> String {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "unknown" }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

func enabledSource(_ id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first
}

func selectLayout(_ id: String) -> Bool {
    guard let source = enabledSource(id) else { return false }
    return TISSelectInputSource(source) == noErr
}

typealias PasteboardContents = [[(type: NSPasteboard.PasteboardType, data: Data)]]

func readPasteboard() -> PasteboardContents {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
        item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
    }
}

func writePasteboard(_ contents: PasteboardContents) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let items = contents.map { entries -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for entry in entries { item.setData(entry.data, forType: entry.type) }
        return item
    }
    if !items.isEmpty { pasteboard.writeObjects(items) }
}

func richClipboardContents() -> PasteboardContents {
    let text = NSAttributedString(string: "stand bold sample",
                                  attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
    let rtf = text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:])!
    return [[(.rtf, rtf), (.string, "stand bold sample".data(using: .utf8)!)]]
}

func sentinelContents(_ number: Int) -> PasteboardContents {
    [[(.string, "retyper-stand-clipboard-\(number)".data(using: .utf8)!)]]
}

func sameContents(_ lhs: PasteboardContents, _ rhs: PasteboardContents) -> Bool {
    // ReTyper adds a transient marker to what it restores; compare only the original types.
    guard lhs.count == rhs.count else { return false }
    for (left, right) in zip(lhs, rhs) {
        for entry in left where !right.contains(where: { $0.type == entry.type && $0.data == entry.data }) {
            return false
        }
    }
    return true
}

func logSize() -> UInt64 {
    ((try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size] as? UInt64) ?? 0
}

func logLines(since offset: UInt64) -> [String] {
    guard let handle = try? FileHandle(forReadingFrom: logURL) else { return [] }
    defer { try? handle.close() }
    try? handle.seek(toOffset: offset)
    let data = handle.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
}

// MARK: - Stand

let arguments = CommandLine.arguments
func argument(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
guard let standPath = argument("--stand"), let outPath = argument("--out") else {
    fail("usage: stand-driver --stand <ReTyperStand.app> --out <directory>", code: 2)
}
let outDirectory = URL(fileURLWithPath: outPath, isDirectory: true)
try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)

var commandCounter = 0

/// Sends a command and waits for the stand to answer with its state file.
func stand(_ action: String, id: String? = nil, _ extra: [String: String] = [:],
           timeout: TimeInterval = 5) -> [String: Any]? {
    commandCounter += 1
    let id = id ?? "state-\(commandCounter)"
    let url = outDirectory.appendingPathComponent("\(id).json")
    try? FileManager.default.removeItem(at: url)
    var info = extra
    info["action"] = action
    info["id"] = id
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.retyper.stand.command"), object: nil, userInfo: info, deliverImmediately: true)
    let deadline = Date(timeIntervalSinceNow: timeout)
    while Date() < deadline {
        if let data = try? Data(contentsOf: url),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if action == "state" { try? FileManager.default.removeItem(at: url) }
            return state
        }
        pump(0.05)
    }
    return nil
}

func standIsReady(_ state: [String: Any]?) -> Bool {
    guard let state else { return false }
    return state["isActive"] as? Bool == true && state["isKeyWindow"] as? Bool == true
        && state["firstResponderIsText"] as? Bool == true
        && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == standBundleID
}

func postOptionTap() {
    let down = CGEvent(keyboardEventSource: nil, virtualKey: 58, keyDown: true)!
    down.type = .flagsChanged
    down.flags = .maskAlternate
    down.post(tap: .cghidEventTap)
    usleep(40_000)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: 58, keyDown: false)!
    up.type = .flagsChanged
    up.flags = []
    up.post(tap: .cghidEventTap)
}

// MARK: - Preconditions

guard NSRunningApplication.runningApplications(withBundleIdentifier: reTyperBundleID).first != nil else {
    fail("ReTyper is not running", code: 3)
}
guard AXIsProcessTrusted() else { fail("this process may not post key events (Accessibility)", code: 3) }
guard enabledSource(latinLayout) != nil, enabledSource(cyrillicLayout) != nil else {
    fail("\(latinLayout) and \(cyrillicLayout) must both be enabled", code: 3)
}

let originalLayout = currentLayout()
let originalPasteboard = readPasteboard()
let originalLastWord = CFPreferencesCopyAppValue(lastWordKey, reTyperBundleID as CFString)
var ownsSecureInput = false

func restoreEverything() {
    if ownsSecureInput { DisableSecureEventInput(); ownsSecureInput = false }
    CFPreferencesSetAppValue(lastWordKey, originalLastWord, reTyperBundleID as CFString)
    CFPreferencesAppSynchronize(reTyperBundleID as CFString)
    writePasteboard(originalPasteboard)
    _ = selectLayout(originalLayout)
    _ = stand("quit", timeout: 1)
}

func setLastWord(_ enabled: Bool) {
    CFPreferencesSetAppValue(lastWordKey, enabled ? kCFBooleanTrue : kCFBooleanFalse, reTyperBundleID as CFString)
    CFPreferencesAppSynchronize(reTyperBundleID as CFString)
}

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
configuration.arguments = ["--out", outDirectory.path]
configuration.createsNewApplicationInstance = true
NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: standPath), configuration: configuration) { _, error in
    if let error { FileHandle.standardError.write("open failed: \(error)\n".data(using: .utf8)!) }
}
let readyURL = outDirectory.appendingPathComponent("ready.json")
var waited = 0.0
while !FileManager.default.fileExists(atPath: readyURL.path), waited < 10 { pump(0.1); waited += 0.1 }
guard FileManager.default.fileExists(atPath: readyURL.path) else {
    restoreEverything()
    fail("stand did not start", code: 3)
}
pump(0.5)

// MARK: - Run

var results: [[String: Any]] = []
var aborted: String?

for scenario in scenarios {
    if let dependency = scenario.dependsOn,
       results.first(where: { $0["scenario"] as? Int == dependency })?["status"] as? String != "PASS" {
        results.append(["scenario": scenario.number, "title": scenario.title, "status": "SKIP",
                        "problems": ["scenario \(dependency) did not pass"]])
        print("SKIP \(scenario.number). \(scenario.title) — scenario \(dependency) did not pass")
        continue
    }
    setLastWord(scenario.lastWord)
    if let layout = scenario.layout, !selectLayout(layout) { aborted = "cannot select \(layout)"; break }
    if let text = scenario.text {
        var extra = ["text": text]
        if arguments.contains("--copy-race") {
            extra["duplicateCopyMs"] = "35"
            extra["pasteReadMs"] = "45"
        }
        if arguments.contains("--secure-field") { extra["secureField"] = "true" }
        if let selection = scenario.selection {
            extra["selectionLocation"] = String(selection.location)
            extra["selectionLength"] = String(selection.length)
        }
        guard stand("set", extra) != nil else { aborted = "stand did not answer set"; break }
    }
    let clipboard = scenario.richClipboard ? richClipboardContents() : sentinelContents(scenario.number)
    writePasteboard(clipboard)
    pump(0.4)

    let prefix = String(format: "scenario-%02d", scenario.number)
    let before = stand("snapshot", id: "\(prefix)-before")
    guard standIsReady(before) else {
        aborted = "stand is not the active app before scenario \(scenario.number); no keys posted"
        break
    }
    let beforeText = before?["text"] as? String ?? ""
    // The caret input-source badge in screenshots lags behind programmatic switches;
    // the system value is the source of truth.
    let layoutBefore = currentLayout()
    let logOffset = logSize()

    // Last check right before the keys: never post into another app.
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == standBundleID else {
        aborted = "focus left the stand before scenario \(scenario.number); no keys posted"
        break
    }
    if arguments.contains("--secure-input") {
        guard !IsSecureEventInputEnabled(), EnableSecureEventInput() == noErr else {
            aborted = "cannot own secure-input fixture"; break
        }
        ownsSecureInput = true
        guard IsSecureEventInputEnabled() else { aborted = "secure-input fixture did not enable protection"; break }
    }
    postOptionTap()
    usleep(120_000)
    postOptionTap()

    // Wait for ReTyper to report the outcome, then for its clipboard restore (0.5 s after paste).
    var outcomeLines: [String] = []
    let deadline = Date(timeIntervalSinceNow: 4)
    while Date() < deadline {
        outcomeLines = logLines(since: logOffset)
        if outcomeLines.contains(where: { $0.contains("Replacement outcome:") }) { break }
        pump(0.1)
    }
    pump(1.2)
    if ownsSecureInput { DisableSecureEventInput(); ownsSecureInput = false }
    outcomeLines = logLines(since: logOffset)

    let after = stand("snapshot", id: "\(prefix)-after")
    let afterText = after?["text"] as? String
    let layoutAfter = currentLayout()
    let clipboardRestored = sameContents(clipboard, readPasteboard())
    let checkedStrings = [beforeText, scenario.expectedText].filter { $0.count >= 2 }
    let logHasText = outcomeLines.contains { line in checkedStrings.contains { line.contains($0) } }

    var problems: [String] = []
    if afterText != scenario.expectedText {
        problems.append("text \(String(reflecting: afterText ?? "<no answer>")) != \(String(reflecting: scenario.expectedText))")
    }
    if let expected = scenario.layout, layoutBefore != expected {
        problems.append("layout before \(layoutBefore) != \(expected)")
    }
    let secureHotkeySuppressed = arguments.contains("--secure-field") && !outcomeLines.contains { $0.contains("Replacement outcome:") }
    if layoutAfter != scenario.expectedLayout && !(secureHotkeySuppressed && layoutAfter == layoutBefore) {
        problems.append("layout \(layoutAfter) != \(scenario.expectedLayout)")
    }
    if !clipboardRestored { problems.append("clipboard not restored") }
    if let outcome = outcomeLines.last(where: { $0.contains("Replacement outcome:") }) {
        if !outcome.contains(scenario.expectedOutcome) {
            problems.append("outcome is not \(scenario.expectedOutcome): \(outcome)")
        }
    } else if !secureHotkeySuppressed {
        problems.append("no outcome in log")
    }
    if logHasText { problems.append("log contains scenario text") }

    let status = problems.isEmpty ? "PASS" : "FAIL"
    results.append([
        "scenario": scenario.number, "title": scenario.title, "status": status, "problems": problems,
        "before": beforeText, "after": afterText ?? NSNull(), "expected": scenario.expectedText,
        "layoutBefore": layoutBefore, "layoutAfter": layoutAfter, "clipboardRestored": clipboardRestored,
        "capture": after?["capture"] ?? "none", "log": outcomeLines,
    ])
    print("\(status) \(scenario.number). \(scenario.title): \(String(reflecting: beforeText)) → "
        + "\(String(reflecting: afterText ?? "?")), layout \(layoutBefore.split(separator: ".").last ?? "")"
        + " → \(layoutAfter.split(separator: ".").last ?? "")"
        + (problems.isEmpty ? "" : " — " + problems.joined(separator: "; ")))
}

restoreEverything()

let passed = results.filter { $0["status"] as? String == "PASS" }.count
let report: [String: Any] = [
    "date": ISO8601DateFormatter().string(from: Date()),
    "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
    "keyboardType": Int(LMGetKbdType()),
    "results": results, "passed": passed, "total": scenarios.count,
    "aborted": aborted ?? NSNull(),
]
if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
    try? data.write(to: outDirectory.appendingPathComponent("report.json"))
}
print("\(passed)/\(scenarios.count) passed" + (aborted.map { ", aborted: \($0)" } ?? "")
    + " — report: \(outDirectory.appendingPathComponent("report.json").path)")
exit(aborted != nil ? 3 : (passed == scenarios.count ? 0 : 1))
