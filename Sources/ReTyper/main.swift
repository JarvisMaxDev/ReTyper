import Cocoa

// Configure this app as an agent (no Dock icon, no main menu)
// This is set via Info.plist LSUIElement = true, but since we're using SPM,
// we handle it programmatically.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No Dock icon

let delegate = AppDelegate()
app.delegate = delegate

app.run()
