import AppKit
import XCTest
@testable import ReTyper

/// Uses a private named pasteboard; the user's clipboard is never touched.
final class ClipboardSnapshotTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.retyper.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    func testRestorePutsBackEveryItemAndTypeAfterReTyperWrote() throws {
        let custom = NSPasteboard.PasteboardType("com.retyper.tests.custom")
        let first = NSPasteboardItem()
        first.setString("first", forType: .string)
        first.setData(Data([1, 2, 3]), forType: custom)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        let snapshot = ClipboardSnapshot(pasteboard)
        let written = ClipboardSnapshot.writeTemporary("\u{43F}\u{440}\u{438}", to: pasteboard)
        XCTAssertEqual(written, pasteboard.changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "\u{43F}\u{440}\u{438}")
        XCTAssertTrue(pasteboard.types?.contains(ClipboardSnapshot.transientType) == true)

        XCTAssertTrue(snapshot.restore(to: pasteboard, ifUnchangedSince: written))
        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].string(forType: .string), "first")
        XCTAssertEqual(items[0].data(forType: custom), Data([1, 2, 3]))
        XCTAssertEqual(items[1].string(forType: .string), "second")
    }

    func testNewerCopyIsNeverOverwrittenByRestore() {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let snapshot = ClipboardSnapshot(pasteboard)
        let written = ClipboardSnapshot.writeTemporary("temporary", to: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("copied meanwhile", forType: .string)
        XCTAssertFalse(snapshot.restore(to: pasteboard, ifUnchangedSince: written))
        XCTAssertEqual(pasteboard.string(forType: .string), "copied meanwhile")
    }

    func testEmptyClipboardIsRestoredEmpty() {
        pasteboard.clearContents()
        let snapshot = ClipboardSnapshot(pasteboard)
        let written = ClipboardSnapshot.writeTemporary("temporary", to: pasteboard)
        XCTAssertTrue(snapshot.restore(to: pasteboard, ifUnchangedSince: written))
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
    }
}
