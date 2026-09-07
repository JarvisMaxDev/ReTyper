import AppKit
import XCTest
@testable import ReTyper

final class PopoverLayoutTests: XCTestCase {
    private func hostedController() -> (PopoverViewController, NSView) {
        _ = NSApplication.shared
        let controller = PopoverViewController()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 800))
        host.addSubview(controller.view)
        // A container owns the origin of its content view, just as NSPopover does.
        controller.view.setFrameOrigin(NSPoint(x: 13, y: 12))
        return (controller, host)
    }

    func testShowingFailureDoesNotResetContainerOwnedOrigin() {
        let (controller, host) = hostedController()
        withExtendedLifetime(host) {
            controller.showOutcomeMessage("The field's text could not be read reliably. No text was sent.")
            XCTAssertEqual(controller.view.frame.origin, NSPoint(x: 13, y: 12))
        }
    }

    func testRecoveryAndClearingDoNotResetContainerOwnedOrigin() {
        let (controller, host) = hostedController()
        withExtendedLifetime(host) {
            controller.showRecovery(true)
            controller.showOutcomeMessage("Inspect the field and use Copy Original Text if needed.")
            XCTAssertEqual(controller.view.frame.origin, NSPoint(x: 13, y: 12))
            controller.showRecovery(false)
            controller.showOutcomeMessage(nil)
            XCTAssertEqual(controller.view.frame.origin, NSPoint(x: 13, y: 12))
        }
    }

    func testRebuildingDoesNotAccumulateOrClipRows() {
        let (controller, host) = hostedController()
        let initialSize = controller.preferredContentSize
        withExtendedLifetime(host) {
            for _ in 0..<3 {
                controller.showRecovery(true)
                controller.showOutcomeMessage("Replacement could not be confirmed. Inspect the field and use Copy Original Text if needed. Automatic replacement is paused until you clear recovery.")
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertEqual(controller.view.subviews.count, 1)
                XCTAssertGreaterThan(controller.preferredContentSize.height, initialSize.height)
                assertLabelVisible("Autostart After Login", in: controller.view)
                assertLabelVisible("Quit", in: controller.view)
                controller.showRecovery(false)
                controller.showOutcomeMessage(nil)
                XCTAssertEqual(controller.preferredContentSize, initialSize)
                XCTAssertEqual(controller.view.frame.origin, NSPoint(x: 13, y: 12))
            }
        }
    }

    func testPopoverSizeTracksMessageAndRecoveryChanges() {
        _ = NSApplication.shared
        let controller = PopoverViewController()
        let popover = NSPopover()
        popover.animates = false
        _ = controller.view
        popover.contentViewController = controller
        controller.onContentSizeChanged = { [weak popover] size in popover?.contentSize = size }
        popover.contentSize = controller.preferredContentSize
        let originalSize = popover.contentSize

        controller.showOutcomeMessage("The field's text could not be read reliably. No text was sent.")
        XCTAssertEqual(popover.contentSize, controller.preferredContentSize)
        XCTAssertGreaterThan(popover.contentSize.height, originalSize.height)
        controller.showRecovery(true)
        XCTAssertEqual(popover.contentSize, controller.preferredContentSize)
        controller.showRecovery(false)
        controller.showOutcomeMessage(nil)
        XCTAssertEqual(popover.contentSize, originalSize)
    }

    func testMessageBeforeFirstPresentationUsesCorrectInitialSize() {
        _ = NSApplication.shared
        let controller = PopoverViewController()
        controller.showOutcomeMessage("The field's text could not be read reliably. No text was sent.")
        let popover = NSPopover()
        popover.animates = false
        popover.contentViewController = controller
        controller.onContentSizeChanged = { [weak popover] size in popover?.contentSize = size }
        _ = controller.view
        popover.contentSize = controller.preferredContentSize
        XCTAssertEqual(popover.contentSize, controller.preferredContentSize)
        XCTAssertGreaterThan(popover.contentSize.height, 350)
        controller.view.layoutSubtreeIfNeeded()
        assertLabelVisible("Autostart After Login", in: controller.view)
        assertLabelVisible("Quit", in: controller.view)
    }

    private func assertLabelVisible(_ title: String, in root: NSView, file: StaticString = #filePath, line: UInt = #line) {
        func find(_ view: NSView) -> NSTextField? {
            if let label = view as? NSTextField, label.stringValue == title { return label }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let label = find(root) else { return XCTFail("Missing label: \(title)", file: file, line: line) }
        let rect = label.convert(label.bounds, to: root)
        XCTAssertTrue(root.bounds.contains(rect), "Clipped label: \(title), \(rect), root=\(root.bounds)", file: file, line: line)
        // AppKit text-field frames include drawing insets; constraints align their alignment rect.
        let alignment = label.alignmentRect(forFrame: label.frame)
        let aligned = label.superview!.convert(alignment, to: root)
        XCTAssertEqual(aligned.minX, 16, accuracy: 0.5, file: file, line: line)
    }
}
