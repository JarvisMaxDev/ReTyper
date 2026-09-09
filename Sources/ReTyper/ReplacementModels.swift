import ApplicationServices
import Foundation

enum FragmentOrigin {
    case userSelection
    case systemSelection
    case caretBoundary
}

enum TextWindowSource {
    case field
    case application
}

/// Capabilities are eligibility checks, not proof that a keyboard command was applied.
struct TextAccessCapability {
    /// Recipient of the annotated hotkey event; it may own a nonactivating panel.
    let applicationPID: pid_t
    /// NSWorkspace activation witness captured with the hotkey, not the recipient.
    let activationPID: pid_t
    let element: AXUIElement
    let window: AXUIElement
    let windowSource: TextWindowSource
    let elementRole: String
    let canSetValue: Bool
    let canSetSelection: Bool

    var supportsReplacement: Bool {
        ["AXTextField", "AXTextArea", "AXComboBox"].contains(elementRole)
            && canSetValue && canSetSelection
    }

    /// A nonactivating receiver needs affirmative field-focus evidence in addition
    /// to the unchanged activation witness. Neither observation is an app ACK.
    func acceptsActivation(_ currentPID: pid_t?, fieldFocused: Bool?) -> Bool {
        applicationPID > 0 && activationPID > 0 && currentPID == activationPID
            && (applicationPID == activationPID || fieldFocused == true)
    }
}

/// Offsets are UTF-16 units. A nonempty range starts at the selection start,
/// which is not necessarily its active end or a terminal's command-line cursor.
struct TextSnapshot: Equatable {
    let value: String
    let caretLocation: Int
    let selectionLength: Int
    let selectedText: String?

    var hasSelection: Bool { selectionLength > 0 }

    func matches(value expected: String, range: Range<Int>) -> Bool {
        value.utf16.elementsEqual(expected.utf16)
            && caretLocation == range.lowerBound && selectionLength == range.count
    }
}

struct ReplacementFragment: Equatable {
    let text: String
    let range: Range<Int>
    let origin: FragmentOrigin
}

enum TextAccessError: Error, Equatable {
    case unavailable
    case focusChanged
    case inconsistentSnapshot
    case invalidValue
    case timeout
    case system(Int32)
}

/// Deadlines use systemUptime and include the time spent in synchronous AX calls.
protocol TextAccessProviding {
    func captureCapability(applicationPID: pid_t, activationPID: pid_t, deadline: TimeInterval) throws -> TextAccessCapability
    func isFocused(_ target: TextAccessCapability, deadline: TimeInterval) throws -> Bool
    func snapshot(_ target: TextAccessCapability, deadline: TimeInterval) throws -> TextSnapshot
    func selectRange(_ range: Range<Int>, in target: TextAccessCapability, deadline: TimeInterval) throws
}

struct PreparedTextInput: Hashable {
    let id: Int64
}

enum InputDelivery: Equatable {
    case queued
    case cancelled
    /// Passed our event gate, NOT an acknowledgement from the receiving application.
    case handedOff
}

protocol ReplacementInputProviding {
    var activityGeneration: UInt64 { get }
    func prepare(_ text: String, targetPID: pid_t, activationPID: pid_t, generation: UInt64, deadline: TimeInterval) -> PreparedTextInput?
    func send(_ input: PreparedTextInput)
    func delivery(of input: PreparedTextInput) -> InputDelivery
    @discardableResult func cancel(_ input: PreparedTextInput) -> InputDelivery
    func finish(_ input: PreparedTextInput)
}

struct ReplacementOptions {
    let applicationPID: pid_t
    let activationPID: pid_t
    let inputGeneration: UInt64
    let triggeredAt: TimeInterval
    let onlyLastWord: Bool
    let availableLayoutIDs: [String]
}

enum AbortReason: String {
    case noTextAccess
    case unsupportedField
    case invalidSnapshot
    case contextChanged
    case selectionNotEstablished
    case inputUnavailable
    case inputCancelled
    case recoveryPending
    case busy
}

enum ReplacementOutcome: Equatable {
    case replaced
    case layoutOnly
    case aborted(AbortReason)
    case restoredAfterFailure
    case needsRecovery

    var isFailure: Bool {
        switch self {
        case .replaced, .layoutOnly: return false
        case .aborted(.busy): return false
        default: return true
        }
    }
}

enum LayoutSwitchAction: Equatable {
    case next
    case select(String)
}

struct ReplacementResult {
    let outcome: ReplacementOutcome
    var targetLayoutID: String? = nil

    func layoutSwitchAction(activationPID: pid_t?, currentActivationPID: pid_t?,
                            inputGeneration: UInt64, currentInputGeneration: UInt64) -> LayoutSwitchAction? {
        guard let activationPID, activationPID > 0, currentActivationPID == activationPID,
              currentInputGeneration == inputGeneration else { return nil }
        switch outcome {
        case .replaced:
            return targetLayoutID.map(LayoutSwitchAction.select)
        case .layoutOnly:
            return .next
        case .aborted(let reason) where reason != .busy && reason != .contextChanged && reason != .recoveryPending:
            return .next
        default:
            return nil
        }
    }
}
