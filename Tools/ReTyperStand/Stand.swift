import Cocoa
import ScreenCaptureKit

// ReTyper test stand: one plain text field that the driver fills and reads back.
// It reports its own content and captures only its own window. Test strings only.

let commandNotification = Notification.Name("com.retyper.stand.command")

final class StandDelegate: NSObject, NSApplicationDelegate {
    private let outputDirectory: URL
    private var window: NSWindow!
    private var textView: NSTextView!

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 180),
                          styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ReTyper Stand"

        let scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as? NSTextView
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 32, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 16)
        // Nothing may alter what ReTyper pastes.
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        window.contentView = scrollView

        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handle(_:)), name: commandNotification,
            object: nil, suspensionBehavior: .deliverImmediately)
        writeState(id: "ready", capture: "none")
    }

    /// NSTextView gets ⌘C/⌘V/⌘A only through Edit menu items; ReTyper relies on them.
    private func installMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ReTyper Stand", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func handle(_ notification: Notification) {
        guard let info = notification.userInfo as? [String: String],
              let action = info["action"], let id = info["id"] else { return }
        switch action {
        case "set":
            textView.string = info["text"] ?? ""
            let length = (textView.string as NSString).length
            let location = Int(info["selectionLocation"] ?? "") ?? length
            let selected = Int(info["selectionLength"] ?? "") ?? 0
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: location, length: selected))
            writeState(id: id, capture: "none")
        case "state":
            writeState(id: id, capture: "none")
        case "snapshot":
            Task { @MainActor in
                let method = await self.captureWindow(to: self.outputDirectory.appendingPathComponent("\(id).png"))
                self.writeState(id: id, capture: method)
            }
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    /// Real pixels of this window through ScreenCaptureKit; a view render only as a labelled fallback.
    @MainActor
    private func captureWindow(to url: URL) async -> String {
        if #available(macOS 14.4, *) {
            do {
                let content = try await SCShareableContent.currentProcess
                if let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                    let filter = SCContentFilter(desktopIndependentWindow: target)
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
                    configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                           configuration: configuration)
                    if save(NSBitmapImageRep(cgImage: image), to: url) { return "screencapturekit" }
                }
            } catch {
                // Fall through to the labelled render.
            }
        }
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return "failed" }
        view.cacheDisplay(in: view.bounds, to: rep)
        return save(rep, to: url) ? "view-render" : "failed"
    }

    private func save(_ rep: NSBitmapImageRep, to url: URL) -> Bool {
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    private func writeState(id: String, capture: String) {
        let selection = textView.selectedRange()
        let state: [String: Any] = [
            "id": id,
            "text": textView.string,
            "selectionLocation": selection.location,
            "selectionLength": selection.length,
            "isActive": NSApp.isActive,
            "isKeyWindow": window.isKeyWindow,
            "firstResponderIsText": window.firstResponder === textView,
            "capture": capture,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else { return }
        let url = outputDirectory.appendingPathComponent("\(id).json")
        let temporary = url.appendingPathExtension("tmp")
        // Write then rename, so the driver never reads half a file.
        try? data.write(to: temporary)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.moveItem(at: temporary, to: url)
    }
}

let arguments = CommandLine.arguments
guard let index = arguments.firstIndex(of: "--out"), index + 1 < arguments.count else {
    FileHandle.standardError.write("usage: ReTyperStand --out <directory>\n".data(using: .utf8)!)
    exit(2)
}
let output = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = StandDelegate(outputDirectory: output)
app.delegate = delegate
app.run()
