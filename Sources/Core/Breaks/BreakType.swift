import Foundation

/// Defines the tier of scheduled wellness break.
public enum BreakType: String, CaseIterable, Codable, Sendable {
    case micro
    case long

    /// Default duration in seconds.
    public var defaultDuration: TimeInterval {
        switch self {
        case .micro: return 20.0       // 20 seconds (20-20-20 rule)
        case .long:  return 300.0      // 5 minutes
        }
    }

    /// Default interval in seconds between consecutive breaks.
    public var defaultInterval: TimeInterval {
        switch self {
        case .micro: return 20.0 * 60.0  // Every 20 minutes
        case .long:  return 60.0 * 60.0  // Every 60 minutes
        }
    }

    public var title: String {
        switch self {
        case .micro: return "Rest Your Eyes"
        case .long:  return "Time to Move"
        }
    }

    public var guidance: String {
        switch self {
        case .micro:
            return "Look at something 20 feet away to rest your eyes."
        case .long:
            return "Stand up, stretch, or take a short walk."
        }
    }

    public var sfSymbol: String {
        switch self {
        case .micro: return "eye.fill"
        case .long:  return "figure.walk"
        }
    }
}
