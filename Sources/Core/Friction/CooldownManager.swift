// Tracks mindful-pass cooldown windows for target rules with optional persistence callbacks.

import Foundation

/// Manages cooldowns after a user passes a delay.
public final class CooldownManager: @unchecked Sendable {
    private let lock = NSLock()
    private var cooldowns: [String: Date]
    private let dateProvider: @Sendable () -> Date
    private var onChange: (@Sendable ([String: Date]) -> Void)?

    /// Creates a cooldown manager pre-populated with any persisted active cooldowns.
    public init(
        initialCooldowns: [String: Date] = [:],
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        onChange: (@Sendable ([String: Date]) -> Void)? = nil
    ) {
        let now = dateProvider()
        self.cooldowns = initialCooldowns.filter { $0.value > now }
        self.dateProvider = dateProvider
        self.onChange = onChange
    }

    /// Registers or replaces the callback invoked outside the lock whenever cooldowns mutate.
    public func setOnChange(_ handler: (@Sendable ([String: Date]) -> Void)?) {
        lock.lock()
        onChange = handler
        lock.unlock()
    }

    /// Returns a snapshot of currently non-expired cooldown expiration dates keyed by rule cache key.
    public func activeCooldownsSnapshot() -> [String: Date] {
        let now = dateProvider()
        lock.lock()
        let active = cooldowns.filter { $0.value > now }
        lock.unlock()
        return active
    }

    /// Replaces the in-memory cooldowns without triggering `onChange`.
    public func replaceCooldowns(_ newCooldowns: [String: Date]) {
        let now = dateProvider()
        let filtered = newCooldowns.filter { $0.value > now }
        lock.lock()
        cooldowns = filtered
        lock.unlock()
    }

    /// Records that the user continued past the delay.
    public func recordMindfulPass(for rule: TargetRule) {
        let key = Self.cacheKey(for: rule)
        let expiration = dateProvider().addingTimeInterval(rule.cooldownDuration)

        lock.lock()
        cooldowns[key] = expiration
        let snapshot = cooldowns
        let handler = onChange
        lock.unlock()

        handler?(snapshot)
    }

    /// Checks if a rule is currently within its cooldown grace window.
    public func isUnderCooldown(for rule: TargetRule) -> Bool {
        let key = Self.cacheKey(for: rule)
        let now = dateProvider()

        lock.lock()
        guard let expiration = cooldowns[key] else {
            lock.unlock()
            return false
        }
        if now < expiration {
            lock.unlock()
            return true
        }
        cooldowns.removeValue(forKey: key)
        let snapshot = cooldowns
        let handler = onChange
        lock.unlock()

        handler?(snapshot)
        return false
    }

    /// Returns the remaining seconds in the cooldown window, or nil if inactive.
    public func remainingCooldown(for rule: TargetRule) -> TimeInterval? {
        let key = Self.cacheKey(for: rule)
        let now = dateProvider()

        lock.lock()
        guard let expiration = cooldowns[key] else {
            lock.unlock()
            return nil
        }
        let remaining = expiration.timeIntervalSince(now)
        if remaining > 0 {
            lock.unlock()
            return remaining
        }
        cooldowns.removeValue(forKey: key)
        let snapshot = cooldowns
        let handler = onChange
        lock.unlock()

        handler?(snapshot)
        return nil
    }

    /// Clears all active cooldowns.
    public func clearAll() {
        lock.lock()
        let hadEntries = !cooldowns.isEmpty
        cooldowns.removeAll()
        let snapshot = cooldowns
        let handler = onChange
        lock.unlock()

        if hadEntries {
            handler?(snapshot)
        }
    }

    /// Returns the stable persistence and lookup key for a target rule.
    public static func cacheKey(for rule: TargetRule) -> String {
        switch rule.kind {
        case .application(let bundleId):
            return "app:\(bundleId.lowercased())"
        case .website(let domain):
            return "web:\(domain.lowercased())"
        }
    }
}
