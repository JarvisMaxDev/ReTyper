import Cocoa

/// Main-thread-only queue. Replacement events are posted as one prebuilt batch on the main queue
/// outside the event-tap callback. Hardware events are held until that batch and layout switch finish.
final class TerminalInputGate {
    private static let replayPrefix: Int64 = 0x5254_5052_0000_0000
    static func isReplay(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) & ~Int64(UInt32.max) == replayPrefix
    }
    private var replayMarker: Int64 { Self.replayPrefix | Int64(UInt32(truncatingIfNeeded: ticket)) }
    private(set) var holding = false
    private(set) var replaying = 0
    private var queued: [CGEvent] = []
    private var ticket = 0
    private var wave = 0
    private(set) var deferredEventCount = 0
    private(set) var replacementStarted = false
    var onDrained: (() -> Void)?
    let deliver: (CGEvent) -> Void
    let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(deliver: @escaping (CGEvent) -> Void,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void) {
        self.deliver = deliver; self.schedule = schedule
    }
    var busy: Bool { holding || replaying > 0 }
    var generation: Int { ticket }
    func begin() -> Bool {
        guard !busy else { return false }
        ticket &+= 1; holding = true; deferredEventCount = 0; replacementStarted = false
        return true
    }
    func markReplacementStarted() { replacementStarted = true }
    func deferEvent(_ event: CGEvent) -> Bool {
        guard busy, !Self.isReplay(event),
              let copy = event.copy() else { return false }
        queued.append(copy)
        deferredEventCount += 1
        // By the time the main run loop can receive another tap callback, the synchronous
        // posting batch has finished. Flush early rather than lose input during a large burst.
        if queued.count >= 512 { release() }
        return true
    }
    func release() {
        holding = false
        let events = queued; queued.removeAll(keepingCapacity: true)
        replaying += events.count
        let current = ticket
        wave &+= 1
        let currentWave = wave
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: replayMarker)
            event.timestamp = CGEvent(source: nil)?.timestamp ?? event.timestamp
            deliver(event)
        }
        if replaying == 0 { notifyDrained() }
        // A secure-input transition or a disabled tap may hide a replay from our own observer.
        // Do not leave the application waiting indefinitely; input was already delivered.
        if !events.isEmpty {
            schedule(1) { [weak self] in
                guard let self, self.ticket == current, self.wave == currentWave, !self.holding else { return }
                self.replaying = 0
                if self.queued.isEmpty { self.notifyDrained() } else { self.release() }
            }
        }
    }
    func acknowledgeReplay(_ event: CGEvent) {
        guard event.getIntegerValueField(.eventSourceUserData) == replayMarker else { return }
        if replaying > 0 { replaying -= 1 }
        if !holding, replaying == 0 {
            if queued.isEmpty { notifyDrained() } else { release() }
        }
    }
    private func notifyDrained() {
        let completion = onDrained
        onDrained = nil
        completion?()
    }
}
