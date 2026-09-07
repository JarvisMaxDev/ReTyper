struct StatusBarFeedbackState {
    static let failureFlashDuration = 1.5

    var isRecoveryAvailable = false {
        didSet {
            if oldValue && !isRecoveryAvailable { lastFailure = nil }
        }
    }
    private var failureFlashDeadline: Double?
    private var lastFailure: ReplacementOutcome?

    /// Retained independently of the brief menu-bar animation, until the next outcome.
    mutating func recordOutcome(_ outcome: ReplacementOutcome) {
        guard outcome != .aborted(.busy) else { return }
        lastFailure = outcome.isFailure ? outcome : nil
        if !outcome.isFailure { failureFlashDeadline = nil }
    }

    var outcomeMessage: String? {
        if isRecoveryAvailable {
            return "Replacement could not be confirmed. Inspect the field and use Copy Original Text if needed. Automatic replacement is paused until you clear recovery."
        }
        switch lastFailure {
        case .aborted(.unsupportedField):
            return "Text replacement is unavailable in this field. No text was sent. There is nothing to recover."
        case .aborted(.noTextAccess), .aborted(.invalidSnapshot):
            return "The field's text could not be read reliably. No text was sent."
        case .aborted(.contextChanged):
            return "The input or active field changed. No text was sent."
        case .aborted(.selectionNotEstablished):
            return "The selection could not be confirmed. No text was sent."
        case .aborted(.inputUnavailable):
            return "Text input could not be prepared. No text was sent."
        case .aborted(.inputCancelled):
            return "Replacement was cancelled before delivery. No text was sent."
        case .restoredAfterFailure:
            return "Replacement could not be completed. The original text was restored."
        default:
            return nil
        }
    }

    mutating func flashFailure(at uptime: Double) {
        failureFlashDeadline = uptime + Self.failureFlashDuration
    }

    // Reads and older timers must not shorten a newer warning.
    func showsWarning(at uptime: Double) -> Bool {
        isRecoveryAvailable || (failureFlashDeadline.map { uptime < $0 } ?? false)
    }
}
