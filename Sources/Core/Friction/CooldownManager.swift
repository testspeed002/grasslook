import Foundation

/// Manages temporary allow-windows after the user mindfully passes a friction delay.
public final class CooldownManager: @unchecked Sendable {
    private let lock = NSLock()
    private var cooldowns: [String: Date] = [:] // Key: rule.id.uuidString or domain / bundleId -> Expiration Date
    private let dateProvider: @Sendable () -> Date

    public init(dateProvider: @escaping @Sendable () -> Date = { Date() }) {
        self.dateProvider = dateProvider
    }

    /// Records that the user consciously continued past the friction delay.
    public func recordMindfulPass(for rule: TargetRule) {
        lock.lock()
        defer { lock.unlock() }
        let expiration = dateProvider().addingTimeInterval(rule.cooldownDuration)
        cooldowns[cacheKey(for: rule)] = expiration
    }

    /// Checks if a rule is currently within its cooldown grace window.
    public func isUnderCooldown(for rule: TargetRule) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let expiration = cooldowns[cacheKey(for: rule)] else {
            return false
        }
        let now = dateProvider()
        if now < expiration {
            return true
        } else {
            cooldowns.removeValue(forKey: cacheKey(for: rule))
            return false
        }
    }

    /// Returns the remaining seconds in the cooldown window, or nil if inactive.
    public func remainingCooldown(for rule: TargetRule) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        guard let expiration = cooldowns[cacheKey(for: rule)] else {
            return nil
        }
        let remaining = expiration.timeIntervalSince(dateProvider())
        if remaining > 0 {
            return remaining
        } else {
            cooldowns.removeValue(forKey: cacheKey(for: rule))
            return nil
        }
    }

    /// Clears all active cooldowns.
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        cooldowns.removeAll()
    }

    private func cacheKey(for rule: TargetRule) -> String {
        switch rule.kind {
        case .application(let bundleId):
            return "app:\(bundleId.lowercased())"
        case .website(let domain):
            return "web:\(domain.lowercased())"
        }
    }
}
