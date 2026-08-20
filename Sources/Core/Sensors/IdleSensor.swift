import Foundation
import CoreGraphics

public protocol IdleSensorProtocol: Sendable {
    /// Seconds since the user last interacted with the keyboard, mouse, or trackpad.
    func secondsSinceLastActivity() -> TimeInterval
}

/// Native macOS idle detection querying CGEventSource.
public struct SystemIdleSensor: IdleSensorProtocol {
    public init() {}

    public func secondsSinceLastActivity() -> TimeInterval {
        // CGEventType(rawValue: ~0) corresponds to kCGAnyInputEventType
        let anyEvent = CGEventType(rawValue: UInt32.max) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }
}

/// Mock idle sensor for deterministic unit tests.
public final class MockIdleSensor: IdleSensorProtocol, @unchecked Sendable {
    public var currentIdleSeconds: TimeInterval = 0

    public init(currentIdleSeconds: TimeInterval = 0) {
        self.currentIdleSeconds = currentIdleSeconds
    }

    public func secondsSinceLastActivity() -> TimeInterval {
        return currentIdleSeconds
    }
}
