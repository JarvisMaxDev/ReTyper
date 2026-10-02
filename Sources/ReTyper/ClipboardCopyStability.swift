import Foundation

/// Some applications complete one Copy in multiple native/renderer clipboard writes.
/// A changed generation alone is not a completed copy. Never retain text in this observer.
struct ClipboardCopyStability {
    private let initialChangeCount: Int
    private var lastChangeCount: Int?
    private var lastChangedAt: TimeInterval?
    private let quietInterval: TimeInterval = 0.06

    init(initialChangeCount: Int) { self.initialChangeCount = initialChangeCount }

    mutating func observe(changeCount: Int, hasText: Bool, now: TimeInterval) -> Bool {
        guard changeCount != initialChangeCount else { return false }
        if lastChangeCount != changeCount {
            lastChangeCount = changeCount
            lastChangedAt = now
        }
        guard hasText, let lastChangedAt else { return false }
        return now - lastChangedAt >= quietInterval
    }
}
