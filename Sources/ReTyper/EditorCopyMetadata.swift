import Foundation
import CoreFoundation

/// VS Code's model-derived copy metadata, carried in Chromium's bounded Pickle dictionary.
struct EditorCopyMetadata {
    let id: UUID
    let isFromEmptySelection: Bool

    static func decode(_ data: Data) -> EditorCopyMetadata? {
        guard data.count >= 8, data.count <= 262_144 else { return nil }
        let bytes = Array(data)
        var offset = 0
        func uint32() -> Int? {
            guard offset <= bytes.count - 4 else { return nil }
            defer { offset += 4 }
            return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
                | (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24)
        }
        func string16() -> String? {
            guard let count = uint32(), count <= 65_536,
                  count <= (bytes.count - offset) / 2 else { return nil }
            let end = offset + count * 2
            guard let value = String(data: Data(bytes[offset..<end]), encoding: .utf16LittleEndian) else { return nil }
            offset = (end + 3) & ~3
            return offset <= bytes.count ? value : nil
        }
        guard uint32() == bytes.count - 4, let count = uint32(), count <= 64 else { return nil }
        var value: String?
        for _ in 0..<count {
            guard let key = string16(), let entry = string16() else { return nil }
            if key == "vscode-editor-data" {
                guard value == nil else { return nil }
                value = entry
            }
        }
        guard offset == bytes.count, let json = value?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let version = object["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let flag = object["isFromEmptySelection"] as? NSNumber,
              CFGetTypeID(flag) == CFBooleanGetTypeID(),
              object["multicursorText"] is NSNull,
              let rawID = object["id"] as? String, let id = UUID(uuidString: rawID) else { return nil }
        return EditorCopyMetadata(id: id, isFromEmptySelection: flag.boolValue)
    }
}
