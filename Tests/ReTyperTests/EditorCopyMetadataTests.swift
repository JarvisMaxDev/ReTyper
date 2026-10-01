import XCTest
@testable import ReTyper

final class EditorCopyMetadataTests: XCTestCase {
    private let valid = "{\"version\":1,\"id\":\"12345678-1234-1234-1234-123456789abc\",\"isFromEmptySelection\":false,\"multicursorText\":null}"

    private func pickle(_ pairs: [(String, String)]) -> Data {
        var data = Data(repeating: 0, count: 4)
        func uint(_ v: Int) { for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: v >> shift)) } }
        func string(_ s: String) {
            uint(s.utf16.count)
            for u in s.utf16 { data.append(UInt8(truncatingIfNeeded: u)); data.append(UInt8(u >> 8)) }
            while data.count % 4 != 0 { data.append(0) }
        }
        uint(pairs.count)
        for (k, v) in pairs { string(k); string(v) }
        let size = data.count - 4
        for i in 0..<4 { data[i] = UInt8(truncatingIfNeeded: size >> (i * 8)) }
        return data
    }

    func testSelectionAndLineCopyAreDifferent() throws {
        let selected = try XCTUnwrap(EditorCopyMetadata.decode(pickle([("other", "тест"), ("vscode-editor-data", valid)])))
        XCTAssertFalse(selected.isFromEmptySelection)
        let empty = try XCTUnwrap(EditorCopyMetadata.decode(pickle([("vscode-editor-data", valid.replacingOccurrences(of: "false", with: "true"))])))
        XCTAssertTrue(empty.isFromEmptySelection)
    }

    func testMalformedOrAmbiguousMetadataIsRejected() {
        for value in ["{}", "null", "not JSON", valid.replacingOccurrences(of: "false", with: "0"),
                      valid.replacingOccurrences(of: "false", with: "\"false\""),
                      valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
                      valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":true"),
                      valid.replacingOccurrences(of: "null", with: "[\"a\",\"b\"]"),
                      valid.replacingOccurrences(of: "12345678-1234-1234-1234-123456789abc", with: "invalid")] {
            XCTAssertNil(EditorCopyMetadata.decode(pickle([("vscode-editor-data", value)])), value)
        }
        XCTAssertNil(EditorCopyMetadata.decode(pickle([])))
        XCTAssertNil(EditorCopyMetadata.decode(pickle([("other", valid)])))
        XCTAssertNil(EditorCopyMetadata.decode(pickle([("vscode-editor-data", valid), ("vscode-editor-data", valid)])))
    }

    func testAllTruncationsAndWrongLengthsAreRejected() {
        let complete = pickle([("vscode-editor-data", valid)])
        for length in 0..<complete.count { XCTAssertNil(EditorCopyMetadata.decode(complete.prefix(length))) }
        var corrupt = complete; corrupt[4] = 255
        XCTAssertNil(EditorCopyMetadata.decode(corrupt))
        corrupt = complete; corrupt[8] = 255; corrupt[9] = 255; corrupt[10] = 255; corrupt[11] = 255
        XCTAssertNil(EditorCopyMetadata.decode(corrupt))
        corrupt = complete; corrupt.append(0)
        XCTAssertNil(EditorCopyMetadata.decode(corrupt))
        XCTAssertNil(EditorCopyMetadata.decode(Data(repeating: 0, count: 262_145)))
    }
}
