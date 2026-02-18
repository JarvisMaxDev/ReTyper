import Foundation

/// Converts text typed in a wrong keyboard layout to the correct layout.
/// Detection is based on the text content (Cyrillic vs Latin), NOT on the current keyboard layout.
struct TextConverter {
    
    /// Detect whether text is predominantly Cyrillic or Latin
    enum DetectedScript {
        case cyrillic
        case latin
        case unknown
    }
    
    /// Analyze text to determine its script
    static func detectScript(_ text: String) -> DetectedScript {
        var cyrillicCount = 0
        var latinCount = 0
        
        for char in text {
            if char.unicodeScalars.allSatisfy({ (0x0400...0x04FF).contains($0.value) }) {
                cyrillicCount += 1
            } else if char.unicodeScalars.allSatisfy({
                (0x0041...0x005A).contains($0.value) || // A-Z
                (0x0061...0x007A).contains($0.value)    // a-z
            }) {
                latinCount += 1
            }
        }
        
        if cyrillicCount > 0 && latinCount == 0 { return .cyrillic }
        if latinCount > 0 && cyrillicCount == 0 { return .latin }
        if cyrillicCount > latinCount { return .cyrillic }
        if latinCount > cyrillicCount { return .latin }
        return .unknown
    }
    
    /// Auto-detect direction from the TEXT itself and convert.
    /// - If text is Latin → convert to Cyrillic, return target Cyrillic layout ID
    /// - If text is Cyrillic → convert to Latin, return target Latin layout ID
    static func autoConvert(_ text: String, availableLayoutIDs: [String]) -> (converted: String, targetLayoutID: String?) {
        let script = detectScript(text)
        let log = Logger.shared
        log.log("   📝 Detected script: \(script), text: \"\(text)\"")
        
        switch script {
        case .latin:
            // Text is Latin → convert to Cyrillic
            // Find the first available Cyrillic layout
            if let targetID = availableLayoutIDs.first(where: { CharacterMap.cyrillicLayout(for: $0) != nil }),
               let cyrLayout = CharacterMap.cyrillicLayout(for: targetID) {
                let converted = String(text.map { char in
                    cyrLayout.fromEnglishMap[char] ?? char
                })
                return (converted, targetID)
            }
            
        case .cyrillic:
            // Text is Cyrillic → convert to Latin
            // Try each Cyrillic layout's reverse map to see which one matches best
            for layoutID in availableLayoutIDs {
                if let cyrLayout = CharacterMap.cyrillicLayout(for: layoutID) {
                    let converted = String(text.map { char in
                        cyrLayout.toEnglishMap[char] ?? char
                    })
                    // Find the Latin target layout
                    if let latinID = availableLayoutIDs.first(where: { CharacterMap.isLatinLayout($0) }) {
                        return (converted, latinID)
                    }
                }
            }
            
        case .unknown:
            break
        }
        
        return (text, nil)
    }
}
