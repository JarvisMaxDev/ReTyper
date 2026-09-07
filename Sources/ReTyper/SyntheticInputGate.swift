import CoreGraphics
import Foundation

/// Local construction only: neither creating nor validating a payload posts input.
struct SyntheticTextPayload {
    static let maximumUTF16Length = 4096

    let down: CGEvent
    let up: CGEvent

    static func make(_ text: String) -> SyntheticTextPayload? {
        let units = Array(text.utf16.prefix(maximumUTF16Length + 1))
        guard !units.isEmpty, units.count <= maximumUTF16Length,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return nil }

        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            var length = 0
            event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
            guard length == units.count else { return nil }
            var readback = [UniChar](repeating: 0, count: units.count)
            event.keyboardGetUnicodeString(maxStringLength: readback.count,
                                           actualStringLength: &length, unicodeString: &readback)
            guard length == units.count, readback == units else { return nil }
        }
        return SyntheticTextPayload(down: down, up: up)
    }
}

/// A bounded, synchronous state machine. No taps, posting, AX, timers or logging.
final class SyntheticInputGate {
    enum Decision {
        case passThrough
        case drop
        case route(CGEvent, pid_t)
    }

    struct Signals {
        let down: CGEvent
        let up: CGEvent
    }

    private struct Ticket {
        let targetPID: pid_t
        let activationPID: pid_t
        let generation: UInt64
        let deadline: TimeInterval
        var down: CGEvent?
        var up: CGEvent?
        var signals: Signals?
        var submitted = false
        var delivery = InputDelivery.queued
        var finished = false
    }

    // The namespace recognizes retired tokens without retaining tombstones.
    // Allocation is process-wide, never reset on tap/monitor replacement, and
    // fails closed rather than wrapping. Each operation consumes two tokens.
    private static let tokenPrefix: Int64 = 0x5254_0000_0000_0000
    private static let tokenMask: Int64 = 0x7FFF_0000_0000_0000
    private static let tokenLock = NSLock()
    private static var nextToken: Int64 = 2
    static let maximumPendingTickets = 32

    private let lock = NSLock()
    private let clock: () -> TimeInterval
    // Workspace activation is a witness, not the keyboard recipient.
    private let frontmostPID: () -> pid_t?
    private var generation: UInt64 = 0
    private var enabled = false
    private var tickets: [Int64: Ticket] = [:]

    init(clock: @escaping () -> TimeInterval, frontmostPID: @escaping () -> pid_t?) {
        self.clock = clock
        self.frontmostPID = frontmostPID
    }

    var activityGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    var pendingTicketCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tickets.count
    }

    @discardableResult
    func recordActivity() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        // At exhaustion, refuse new work instead of ever reusing a generation.
        if generation < UInt64.max { generation += 1 }
        return generation
    }

    /// Availability is owned by the monitor's main-serialized lifecycle, not its callers.
    func resetTap(isEnabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        enabled = isEnabled
        if generation < UInt64.max { generation += 1 }
    }

    static func ownsToken(_ token: Int64) -> Bool {
        token & tokenMask == tokenPrefix
    }

    static func isUserActivity(_ type: CGEventType) -> Bool {
        switch type {
        case .keyDown, .keyUp, .flagsChanged,
             .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp, .mouseMoved,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel:
            return true
        default:
            return false
        }
    }

    func prepare(_ text: String, targetPID: pid_t, activationPID: pid_t, generation expectedGeneration: UInt64,
                 deadline: TimeInterval) -> PreparedTextInput? {
        guard targetPID > 0, activationPID > 0, deadline.isFinite, clock() < deadline,
              frontmostPID() == activationPID,
              let payload = SyntheticTextPayload.make(text),
              let downSignal = CGEvent(source: nil), let upSignal = CGEvent(source: nil) else { return nil }

        Self.tokenLock.lock()
        guard Self.nextToken < 0x0000_FFFF_FFFF_FFFE else {
            Self.tokenLock.unlock()
            return nil
        }
        let id = Self.tokenPrefix | Self.nextToken
        Self.nextToken += 2
        Self.tokenLock.unlock()

        downSignal.type = .null
        upSignal.type = .null
        payload.down.setIntegerValueField(.eventSourceUserData, value: id)
        payload.up.setIntegerValueField(.eventSourceUserData, value: id + 1)
        downSignal.setIntegerValueField(.eventSourceUserData, value: id)
        upSignal.setIntegerValueField(.eventSourceUserData, value: id + 1)
        let pid = frontmostPID()
        let now = clock()
        lock.lock()
        defer { lock.unlock() }
        guard enabled, generation < UInt64.max, generation == expectedGeneration,
              now < deadline, pid == activationPID, tickets.count < Self.maximumPendingTickets else { return nil }

        tickets[id] = Ticket(targetPID: targetPID, activationPID: activationPID,
                             generation: generation, deadline: deadline,
                             down: payload.down, up: payload.up, signals: Signals(down: downSignal, up: upSignal))
        return PreparedTextInput(id: id)
    }

    /// Consumes the inert signals exactly once; it is not a delivery acknowledgement.
    func takeSignals(for input: PreparedTextInput) -> Signals? {
        let pid = frontmostPID()
        let now = clock()
        lock.lock()
        defer { lock.unlock() }
        guard var ticket = tickets[input.id] else { return nil }
        invalidateQueued(&ticket, now: now, pid: pid)
        guard ticket.delivery == .queued, !ticket.submitted, !ticket.finished else {
            tickets[input.id] = ticket
            return nil
        }
        let signals = ticket.signals
        ticket.signals = nil
        ticket.submitted = true
        tickets[input.id] = ticket
        return signals
    }

    /// Transport filtering belongs to the session stage, not the process-routed echo.
    func handle(type: CGEventType, token: Int64) -> Decision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetTap(isEnabled: false)
            return .passThrough
        }
        guard Self.ownsToken(token) else {
            if Self.isUserActivity(type) { recordActivity() }
            return .passThrough
        }
        // Process-routed keyboard events must never be routed again if another
        // component reinserts a copy into the session stream.
        guard type == .null else { return .drop }

        // Null target metadata is not keyboard evidence; check the witness and epoch.
        let isDown = token & 1 == 0
        let pid = isDown ? frontmostPID() : nil
        let now = isDown ? clock() : 0
        let id = token & ~Int64(1)
        lock.lock()
        defer { lock.unlock() }
        guard var ticket = tickets[id], ticket.submitted else { return .drop }

        if isDown {
            invalidateQueued(&ticket, now: now, pid: pid)
            guard ticket.delivery == .queued, !ticket.finished, let down = ticket.down else {
                tickets[id] = ticket
                return .drop
            }
            // Linearization point: cancellation after this cannot prove non-delivery.
            ticket.delivery = .handedOff
            ticket.down = nil
            tickets[id] = ticket
            return .route(down, ticket.targetPID)
        }

        guard ticket.delivery == .handedOff, let up = ticket.up else {
            // An up arriving before its down must also make the late down ineligible.
            if ticket.delivery == .queued { ticket.delivery = .cancelled }
            ticket.down = nil
            ticket.up = nil
            tickets[id] = ticket
            return .drop
        }
        ticket.up = nil
        if ticket.finished {
            tickets.removeValue(forKey: id)
        } else {
            tickets[id] = ticket
        }
        // Always pair a handed-off down, even after activation, expiry, reset or cancel.
        return .route(up, ticket.targetPID)
    }

    func delivery(of input: PreparedTextInput) -> InputDelivery {
        let pid = frontmostPID()
        let now = clock()
        lock.lock()
        defer { lock.unlock() }
        // finish ends the receipt's lifetime. Without a receipt, never assert
        // non-delivery and invite destructive automatic recovery.
        guard var ticket = tickets[input.id] else { return .handedOff }
        invalidateQueued(&ticket, now: now, pid: pid)
        tickets[input.id] = ticket
        return ticket.delivery
    }

    @discardableResult
    func cancel(_ input: PreparedTextInput) -> InputDelivery {
        lock.lock()
        defer { lock.unlock() }
        guard var ticket = tickets[input.id] else { return .handedOff }
        if ticket.delivery == .queued {
            ticket.delivery = .cancelled
            ticket.down = nil
            ticket.up = nil
            ticket.signals = nil
        }
        tickets[input.id] = ticket
        return ticket.delivery
    }

    @discardableResult
    func finish(_ input: PreparedTextInput) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var ticket = tickets[input.id] else { return false }
        if ticket.delivery == .handedOff, ticket.up != nil {
            // Keep only the necessary release, not the payload/signal pair. The
            // global capacity bounds even releases whose signal never arrives.
            ticket.finished = true
            ticket.down = nil
            ticket.signals = nil
            tickets[input.id] = ticket
            return true
        } else {
            tickets.removeValue(forKey: input.id)
            return false
        }
    }

    /// Teardown/reset can lose inert signals. Only releases of already handed-off
    /// downs may bypass them; the monitor posts these on the tap's main run loop.
    func takePendingKeyUps() -> [(CGEvent, pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        var releases: [(CGEvent, pid_t)] = []
        for (id, var ticket) in tickets where ticket.delivery == .handedOff {
            guard let up = ticket.up else { continue }
            releases.append((up, ticket.targetPID))
            ticket.up = nil
            if ticket.finished {
                tickets.removeValue(forKey: id)
            } else {
                tickets[id] = ticket
            }
        }
        return releases
    }

    private func invalidateQueued(_ ticket: inout Ticket, now: TimeInterval, pid: pid_t?) {
        if ticket.delivery == .queued,
           !enabled || generation == UInt64.max || generation != ticket.generation
            || !(now < ticket.deadline) || pid != ticket.activationPID {
            ticket.delivery = .cancelled
            ticket.down = nil
            ticket.up = nil
            ticket.signals = nil
        }
    }
}
