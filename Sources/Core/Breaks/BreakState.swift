import Foundation

/// Reason why break countdowns or active breaks are paused.
public enum PauseReason: Equatable, Codable, Sendable {
    case userManuallyPaused(until: Date?)
    case idleAwayFromKeyboard
    case presentationOrVideoCall

    public var displayTitle: String {
        switch self {
        case .userManuallyPaused(let until):
            if let until = until {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return "Paused until \(formatter.string(from: until))"
            }
            return "Paused indefinitely"
        case .idleAwayFromKeyboard:
            return "Paused (Away from Mac)"
        case .presentationOrVideoCall:
            return "Paused (Meeting / Presentation)"
        }
    }
}

/// State machine states for the BreakScheduler.
public enum BreakState: Equatable, Sendable {
    case idle
    case countingDown(secondsRemaining: TimeInterval, nextType: BreakType)
    case breakDue(type: BreakType)
    case inBreak(type: BreakType, secondsRemaining: TimeInterval)
    case paused(reason: PauseReason)

    public var isActiveBreak: Bool {
        if case .inBreak = self { return true }
        if case .breakDue = self { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}
