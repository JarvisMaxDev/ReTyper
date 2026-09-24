import CoreGraphics
import XCTest
@testable import ReTyper

final class ModifierHotkeyDetectorTests: XCTestCase {
    func testSingleTapWorksForEitherSideOfEveryModifier() {
        let modifiers: [(SettingsManager.HotkeyModifier, [UInt16])] = [
            (.shift, [56, 60]), (.option, [58, 61]), (.control, [59, 62]), (.command, [55, 54])
        ]
        for (modifier, codes) in modifiers {
            for keyCode in codes {
                var detector = ModifierHotkeyDetector()
                XCTAssertFalse(detector.handle(keyCode: keyCode, flags: modifier.cgEventFlag,
                                                modifier: modifier, doubleTapMode: false, now: 100))
                XCTAssertTrue(detector.handle(keyCode: keyCode, flags: [], modifier: modifier,
                                               doubleTapMode: false, now: 100.1))
                XCTAssertFalse(detector.handle(keyCode: keyCode, flags: [], modifier: modifier,
                                                doubleTapMode: false, now: 100.2))
            }
        }
    }

    func testTypingWithBothShiftSidesHeldCannotRearmBeforeBothAreReleased() {
        for (first, second): (UInt16, UInt16) in [(56, 60), (60, 56)] {
            var detector = ModifierHotkeyDetector()
            XCTAssertFalse(detector.handle(keyCode: first, flags: .maskShift, modifier: .shift,
                                            doubleTapMode: false, now: 100))
            XCTAssertFalse(detector.handle(keyCode: second, flags: .maskShift, modifier: .shift,
                                            doubleTapMode: false, now: 100.1))
            detector.disarm() // A letter was pressed while both sides were held.
            for time in [100.2, 100.3, 100.4] {
                // Release, press again, then release one side; the other stays down.
                XCTAssertFalse(detector.handle(keyCode: first, flags: .maskShift, modifier: .shift,
                                                doubleTapMode: false, now: time))
            }
            XCTAssertFalse(detector.handle(keyCode: second, flags: [], modifier: .shift,
                                            doubleTapMode: false, now: 100.5))
            XCTAssertFalse(detector.handle(keyCode: first, flags: .maskShift, modifier: .shift,
                                            doubleTapMode: false, now: 100.6))
            XCTAssertTrue(detector.handle(keyCode: first, flags: [], modifier: .shift,
                                           doubleTapMode: false, now: 100.7))
        }
    }

    func testOverlappingShiftSidesCountAsOnlyOneTap() {
        var detector = ModifierHotkeyDetector()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.05))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.15))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.2))
        XCTAssertTrue(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                       doubleTapMode: true, now: 100.25))
    }

    func testTypingDuringOverlappingShiftPressesClearsPendingDoubleTap() {
        var detector = ModifierHotkeyDetector()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.05))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.15))
        detector.disarm()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.2))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.25))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.3))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.35))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100.4))
        XCTAssertTrue(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                       doubleTapMode: true, now: 100.45))
    }

    func testChangingTargetModifierClearsPendingDoubleTap() {
        var detector = ModifierHotkeyDetector()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: true, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: [], modifier: .shift,
                                        doubleTapMode: true, now: 100.05))
        XCTAssertFalse(detector.handle(keyCode: 58, flags: .maskAlternate, modifier: .option,
                                        doubleTapMode: true, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 58, flags: [], modifier: .option,
                                        doubleTapMode: true, now: 100.15))
        XCTAssertFalse(detector.handle(keyCode: 61, flags: .maskAlternate, modifier: .option,
                                        doubleTapMode: true, now: 100.2))
        XCTAssertTrue(detector.handle(keyCode: 61, flags: [], modifier: .option,
                                       doubleTapMode: true, now: 100.25))
    }

    func testChangingTargetToAlreadyHeldModifierRequiresAFreshAggregateDown() {
        var detector = ModifierHotkeyDetector()
        // Both Option sides are already held while Shift is the configured target.
        XCTAssertFalse(detector.handle(keyCode: 58, flags: .maskAlternate, modifier: .shift,
                                        doubleTapMode: false, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 61, flags: .maskAlternate, modifier: .shift,
                                        doubleTapMode: false, now: 100.05))
        // Change the target, then release the two sides one at a time.
        XCTAssertFalse(detector.handle(keyCode: 58, flags: .maskAlternate, modifier: .option,
                                        doubleTapMode: false, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 61, flags: [], modifier: .option,
                                        doubleTapMode: false, now: 100.15))
        XCTAssertFalse(detector.handle(keyCode: 58, flags: .maskAlternate, modifier: .option,
                                        doubleTapMode: false, now: 100.2))
        XCTAssertTrue(detector.handle(keyCode: 58, flags: [], modifier: .option,
                                       doubleTapMode: false, now: 100.25))
    }

    func testAnotherModifierCannotRearmPartlyReleasedShift() {
        var detector = ModifierHotkeyDetector()
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: false, now: 100))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: false, now: 100.05))
        XCTAssertFalse(detector.handle(keyCode: 59, flags: [.maskShift, .maskControl], modifier: .shift,
                                        doubleTapMode: false, now: 100.1))
        XCTAssertFalse(detector.handle(keyCode: 59, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: false, now: 100.15))
        XCTAssertFalse(detector.handle(keyCode: 56, flags: .maskShift, modifier: .shift,
                                        doubleTapMode: false, now: 100.2))
        XCTAssertFalse(detector.handle(keyCode: 60, flags: [], modifier: .shift,
                                        doubleTapMode: false, now: 100.25))
    }

    func testDoubleTapFiresUnlessAnotherKeyIsPressedBetweenTaps() {
        let steps: [(CGEventFlags, TimeInterval)] = [(.maskAlternate, 100), ([], 100.08),
                                                     (.maskAlternate, 100.16), ([], 100.24)]
        var detector = ModifierHotkeyDetector()
        XCTAssertEqual(steps.map { detector.handle(keyCode: 58, flags: $0.0, modifier: .option,
                                                   doubleTapMode: true, now: $0.1) },
                       [false, false, false, true])

        detector = ModifierHotkeyDetector()
        var fired: [Bool] = []
        for (index, step) in steps.enumerated() {
            if index == 2 { detector.disarm() } // KeyboardMonitor does this for a real key press
            fired.append(detector.handle(keyCode: 58, flags: step.0, modifier: .option,
                                         doubleTapMode: true, now: step.1))
        }
        XCTAssertEqual(fired, [false, false, false, false])
    }
}

final class KeyboardMonitorTests: XCTestCase {
    func testOwnKeyPressesAreRecognizedByTheirMarker() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        XCTAssertFalse(KeyboardMonitor.isSynthetic(event))
        event.setIntegerValueField(.eventSourceUserData, value: KeyboardMonitor.syntheticEventMarker)
        XCTAssertTrue(KeyboardMonitor.isSynthetic(event))
    }
}
