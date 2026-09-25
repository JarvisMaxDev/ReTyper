import Carbon
import XCTest
@testable import ReTyper

final class LayoutCatalogTests: XCTestCase {

    // MARK: - Layout Detection

    func testIsLatinLayout() {
        XCTAssertTrue(LayoutCatalog.isLatinLayout("com.apple.keylayout.US"))
        XCTAssertTrue(LayoutCatalog.isLatinLayout("com.apple.keylayout.ABC"))
        XCTAssertTrue(LayoutCatalog.isLatinLayout("com.apple.keylayout.PolishPro"))
        XCTAssertTrue(LayoutCatalog.isLatinLayout("com.apple.keylayout.British"))
        XCTAssertTrue(LayoutCatalog.isLatinLayout("com.apple.keylayout.French"))
        XCTAssertTrue(LayoutCatalog.isLatinLayout("com.apple.keylayout.Dvorak"))
    }

    func testUnknownLayoutIsNotClassifiedAsLatinByPrefixOrSubstring() {
        for id in ["com.apple.keylayout.Arabic", "com.apple.keylayout.Unknown", "com.apple.keylayout.US-extra",
                   "org.example.PolishPro", "US", ""] {
            XCTAssertFalse(LayoutCatalog.isLatinLayout(id), id)
        }
    }

    func testIsCyrillicLayout() {
        for layout in LayoutCatalog.CyrillicLayout.allCases {
            XCTAssertEqual(LayoutCatalog.cyrillicLayout(for: layout.rawValue), layout)
        }
    }

    func testCyrillicLayoutRejectsPartialAndUnknownIdentifiers() {
        for id in ["", "Russian", "com.apple.keylayout.", "com.apple.keylayout.RussianWin-extra"] {
            XCTAssertNil(LayoutCatalog.cyrillicLayout(for: id), id)
        }
    }

    func testCyrillicIsNotLatin() {
        XCTAssertFalse(LayoutCatalog.isLatinLayout("com.apple.keylayout.Russian"))
        XCTAssertFalse(LayoutCatalog.isLatinLayout("com.apple.keylayout.Ukrainian"))
    }

    /// macOS names the Belarusian layout "Byelorussian"; the old "Belarusian" ID never existed.
    func testBelarusianUsesTheSystemIdentifier() {
        XCTAssertEqual(LayoutCatalog.cyrillicLayout(for: "com.apple.keylayout.Byelorussian"), .belarusian)
        XCTAssertNil(LayoutCatalog.cyrillicLayout(for: "com.apple.keylayout.Belarusian"))
    }

    // MARK: - Display Names

    func testDisplayName() {
        XCTAssertEqual(LayoutCatalog.displayName(for: "com.apple.keylayout.US"), "EN")
        XCTAssertEqual(LayoutCatalog.displayName(for: "com.apple.keylayout.Russian"), "RU")
        XCTAssertEqual(LayoutCatalog.displayName(for: "com.apple.keylayout.RussianWin"), "RU")
        XCTAssertEqual(LayoutCatalog.displayName(for: "com.apple.keylayout.Ukrainian"), "UA")
        XCTAssertEqual(LayoutCatalog.displayName(for: "com.apple.keylayout.Ukrainian-PC"), "UA")
        XCTAssertEqual(LayoutCatalog.displayName(for: "com.apple.keylayout.Byelorussian"), "BY")
        XCTAssertEqual(LayoutCatalog.displayName(for: "com.apple.keylayout.PolishPro"), "PL")
    }

    // MARK: - Offered layouts load from the system (SC-002)

    func testEveryOfferedInstalledLayoutLoadsWithItsScript() throws {
        let required: Set<String> = Set(LayoutCatalog.CyrillicLayout.allCases.map(\.rawValue)).union(
            ["US", "ABC", "PolishPro", "German"].map { "com.apple.keylayout.\($0)" })
        let groups: [(ids: [String], script: Script)] = [
            (LayoutCatalog.CyrillicLayout.allCases.map(\.rawValue), .cyrillic),
            (LayoutCatalog.latinLayoutIDs, .latin),
        ]
        var checked = 0
        for group in groups {
            for id in group.ids {
                guard Self.isInstalled(id) else {
                    XCTAssertFalse(required.contains(id), "required layout is not installed: \(id)")
                    continue
                }
                let layout = try XCTUnwrap(KeyLayout.system(id: id, keyboardType: 41), "no key data: \(id)")
                XCTAssertEqual(layout.script, group.script, id)
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, required.count)
    }

    private static func isInstalled(_ id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        return !(sources ?? []).isEmpty
    }
}
