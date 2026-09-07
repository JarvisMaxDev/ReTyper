import Foundation

/// Only observed states authorize another write. A timeout after handing off an
/// event is an unknown outcome, never an invitation to paste the original again.
final class TextReplacementCoordinator {
    private let accessibility: TextAccessProviding
    private let input: ReplacementInputProviding
    private let now: () -> TimeInterval
    private let pause: (TimeInterval) -> Void
    private let convert: (String, [String]) -> (converted: String, targetLayoutID: String?)
    private let confirmationTimeout: TimeInterval = 0.3
    private let lock = NSLock()
    private var busy = false
    private var originalForRecovery: String?

    init(accessibility: TextAccessProviding, input: ReplacementInputProviding,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         pause: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
         convert: @escaping (String, [String]) -> (converted: String, targetLayoutID: String?) = TextConverter.autoConvert) {
        self.accessibility = accessibility
        self.input = input
        self.now = now
        self.pause = pause
        self.convert = convert
    }

    var recoveryOriginalText: String? {
        lock.lock()
        defer { lock.unlock() }
        return originalForRecovery
    }

    /// Explicit user acknowledgement after manual inspection/recovery. No typing.
    @discardableResult
    func clearRecovery() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !busy else { return false }
        originalForRecovery = nil
        return true
    }

    func performReplacement(_ options: ReplacementOptions) -> ReplacementResult {
        lock.lock()
        let blocked: AbortReason? = busy ? .busy : (originalForRecovery == nil ? nil : .recoveryPending)
        if blocked == nil { busy = true }
        lock.unlock()
        if let blocked { return ReplacementResult(outcome: .aborted(blocked)) }
        defer {
            lock.lock()
            busy = false
            lock.unlock()
        }

        let startedAt = now()
        guard options.applicationPID > 0, options.activationPID > 0,
              options.triggeredAt.isFinite, startedAt >= options.triggeredAt,
              startedAt - options.triggeredAt < confirmationTimeout,
              input.activityGeneration == options.inputGeneration else { return aborted(.contextChanged) }
        let captureDeadline = options.triggeredAt + confirmationTimeout
        let target: TextAccessCapability
        let before: TextSnapshot
        do {
            target = try accessibility.captureCapability(applicationPID: options.applicationPID,
                                                        activationPID: options.activationPID, deadline: captureDeadline)
            guard target.applicationPID == options.applicationPID, target.activationPID == options.activationPID else {
                return aborted(.contextChanged)
            }
            guard target.supportsReplacement else { return aborted(.unsupportedField) }
            guard now() < captureDeadline else { return aborted(.noTextAccess) }
            before = try accessibility.snapshot(target, deadline: captureDeadline)
            guard now() < captureDeadline else { return aborted(.noTextAccess) }
        } catch TextAccessError.focusChanged {
            return aborted(.contextChanged)
        } catch {
            return aborted(.noTextAccess)
        }
        guard TextFragmentResolver.isValid(before) else { return aborted(.invalidSnapshot) }

        let fragment: ReplacementFragment?
        if before.hasSelection {
            fragment = TextFragmentResolver.fragmentFromSelection(before)
        } else {
            fragment = options.onlyLastWord
                ? TextFragmentResolver.fragmentBeforeCaret(before)
                : TextFragmentResolver.fragmentFromLineStart(before)
        }
        guard let fragment else { return ReplacementResult(outcome: .layoutOnly) }
        let conversion = convert(fragment.text, options.availableLayoutIDs)
        guard let layout = conversion.targetLayoutID,
              !conversion.converted.utf16.elementsEqual(fragment.text.utf16) else {
            return ReplacementResult(outcome: .layoutOnly)
        }
        guard let expected = TextFragmentResolver.expectedValue(after: fragment, replacedWith: conversion.converted, in: before) else {
            return aborted(.invalidSnapshot)
        }

        let selectionDeadline = now() + confirmationTimeout
        guard let event = input.prepare(conversion.converted, targetPID: target.applicationPID,
                                        activationPID: target.activationPID, generation: options.inputGeneration,
                                        deadline: selectionDeadline) else {
            return aborted(.inputUnavailable)
        }
        var selectionRequested = false
        defer {
            if input.cancel(event) == .cancelled, selectionRequested {
                restoreSelectionOnly(before, fragment: fragment, target: target, options: options)
            }
            input.finish(event)
        }
        do {
            let fresh = try current(target, options: options, deadline: selectionDeadline)
            guard fresh.matches(value: before.value, range: selectionRange(before)) else {
                input.cancel(event)
                return aborted(.contextChanged)
            }
            if selectionRange(fresh) != fragment.range {
                selectionRequested = true
                try accessibility.selectRange(fragment.range, in: target, deadline: selectionDeadline)
            }
            guard try observe(target, options: options, deadline: selectionDeadline,
                              matching: { $0.matches(value: before.value, range: fragment.range) }) != nil else {
                input.cancel(event)
                return aborted(.selectionNotEstablished)
            }
            // Revalidate both content and selection, including user-created selections.
            let selected = try current(target, options: options, deadline: selectionDeadline)
            guard selected.matches(value: before.value, range: fragment.range) else {
                input.cancel(event)
                return aborted(.contextChanged)
            }
        } catch {
            input.cancel(event)
            return aborted(error as? TextAccessError == .focusChanged ? .contextChanged : .selectionNotEstablished)
        }

        input.send(event)
        let caret = fragment.range.lowerBound + conversion.converted.utf16.count
        var observationError: TextAccessError?
        do {
            if try observe(target, options: options, deadline: now() + confirmationTimeout, matching: {
                self.input.delivery(of: event) == .handedOff && $0.matches(value: expected, range: caret..<caret)
            }) != nil {
                return ReplacementResult(outcome: .replaced, targetLayoutID: layout)
            }
        } catch {
            // Whether an event crossed the gate is independent of AX availability.
            observationError = error as? TextAccessError
        }

        let delivery = input.cancel(event)
        if delivery == .cancelled {
            return aborted(observationError == .focusChanged ? .contextChanged : .inputCancelled)
        }

        // An entire observed replacement proves this single payload affected the field.
        // A wrong caret/remaining selection is the only automatic rollback case. Partial,
        // absent, or conflicting results remain unknown and never cause another input.
        if delivery == .handedOff,
           let recovered = attemptConfirmedRestoration(before, fragment: fragment, converted: conversion.converted,
                                                       expected: expected, target: target, options: options) {
            return ReplacementResult(outcome: recovered, targetLayoutID: recovered == .replaced ? layout : nil)
        }
        lock.lock()
        originalForRecovery = fragment.text
        lock.unlock()
        return ReplacementResult(outcome: .needsRecovery)
    }

    private func attemptConfirmedRestoration(_ before: TextSnapshot, fragment: ReplacementFragment,
                                            converted: String, expected: String, target: TextAccessCapability,
                                            options: ReplacementOptions) -> ReplacementOutcome? {
        let deadline = now() + confirmationTimeout
        do {
            let actual = try current(target, options: options, deadline: deadline)
            guard actual.value.utf16.elementsEqual(expected.utf16) else { return nil }
            let expectedCaret = fragment.range.lowerBound + converted.utf16.count
            if actual.matches(value: expected, range: expectedCaret..<expectedCaret) { return .replaced }
            let range = fragment.range.lowerBound..<(fragment.range.lowerBound + converted.utf16.count)
            let replaced = ReplacementFragment(text: converted, range: range, origin: .systemSelection)
            guard let restoredValue = TextFragmentResolver.expectedValue(after: replaced, replacedWith: fragment.text, in: actual),
                  restoredValue.utf16.elementsEqual(before.value.utf16),
                  let restoreEvent = input.prepare(fragment.text, targetPID: target.applicationPID,
                                                   activationPID: target.activationPID, generation: options.inputGeneration,
                                                   deadline: deadline) else { return nil }
            defer { input.finish(restoreEvent) }
            do {
                try accessibility.selectRange(range, in: target, deadline: deadline)
                guard try observe(target, options: options, deadline: deadline,
                                  matching: { $0.matches(value: expected, range: range) }) != nil else {
                    input.cancel(restoreEvent)
                    return nil
                }
                let fresh = try current(target, options: options, deadline: deadline)
                guard fresh.matches(value: expected, range: range) else {
                    input.cancel(restoreEvent)
                    return nil
                }
                input.send(restoreEvent)
                let restoredCaret = fragment.range.upperBound
                let verified = try observe(target, options: options, deadline: now() + confirmationTimeout, matching: {
                    self.input.delivery(of: restoreEvent) == .handedOff
                        && $0.matches(value: before.value, range: restoredCaret..<restoredCaret)
                }) != nil
                if !verified { input.cancel(restoreEvent) }
                return verified ? .restoredAfterFailure : nil
            } catch {
                input.cancel(restoreEvent)
                return nil
            }
        } catch { return nil }
    }

    private func restoreSelectionOnly(_ before: TextSnapshot, fragment: ReplacementFragment,
                                      target: TextAccessCapability, options: ReplacementOptions) {
        let deadline = now() + confirmationTimeout
        do {
            let actual = try current(target, options: options, deadline: deadline)
            guard actual.matches(value: before.value, range: fragment.range) else { return }
            try accessibility.selectRange(selectionRange(before), in: target, deadline: deadline)
        } catch {
            // No text was sent and no attempt is made to alter a different context.
        }
    }

    private func current(_ target: TextAccessCapability, options: ReplacementOptions,
                         deadline: TimeInterval) throws -> TextSnapshot {
        guard now() < deadline else { throw TextAccessError.timeout }
        guard input.activityGeneration == options.inputGeneration,
              try accessibility.isFocused(target, deadline: deadline) else { throw TextAccessError.focusChanged }
        let state = try accessibility.snapshot(target, deadline: deadline)
        guard now() < deadline else { throw TextAccessError.timeout }
        guard input.activityGeneration == options.inputGeneration,
              try accessibility.isFocused(target, deadline: deadline) else { throw TextAccessError.focusChanged }
        guard now() < deadline else { throw TextAccessError.timeout }
        guard input.activityGeneration == options.inputGeneration else { throw TextAccessError.focusChanged }
        guard TextFragmentResolver.isValid(state) else { throw TextAccessError.invalidValue }
        return state
    }

    private func observe(_ target: TextAccessCapability, options: ReplacementOptions, deadline: TimeInterval,
                         matching: (TextSnapshot) -> Bool) throws -> TextSnapshot? {
        while now() < deadline {
            do {
                let state = try current(target, options: options, deadline: deadline)
                let matches = matching(state)
                guard now() < deadline else { throw TextAccessError.timeout }
                guard input.activityGeneration == options.inputGeneration else { throw TextAccessError.focusChanged }
                if matches { return state }
            } catch TextAccessError.inconsistentSnapshot {
                // A provider updated between reads. Retry within the original deadline.
            }
            let remaining = deadline - now()
            if remaining > 0 { pause(min(0.01, remaining)) }
        }
        return nil
    }

    private func selectionRange(_ snapshot: TextSnapshot) -> Range<Int> {
        snapshot.caretLocation..<(snapshot.caretLocation + snapshot.selectionLength)
    }

    private func aborted(_ reason: AbortReason) -> ReplacementResult {
        ReplacementResult(outcome: .aborted(reason))
    }
}
