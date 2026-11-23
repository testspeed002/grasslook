import Foundation

/// Defines whether a rule targets a desktop app or a web domain.
public enum TargetRuleKind: Codable, Sendable, Equatable {
    case application(bundleIdentifier: String)
    case website(domainPattern: String)
}

/// A rule for triggering breathing delays on target apps or websites.
public struct TargetRule: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var kind: TargetRuleKind
    public var delayDuration: TimeInterval // seconds of breathing delay (e.g. 3s - 10s)
    public var cooldownDuration: TimeInterval // seconds of access before asking again (e.g. 15 mins)
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: TargetRuleKind,
        delayDuration: TimeInterval = 5.0,
        cooldownDuration: TimeInterval = 900.0, // 15 minutes
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.delayDuration = delayDuration
        self.cooldownDuration = cooldownDuration
        self.isEnabled = isEnabled
    }

    /// Matches against a bundle identifier
    public func matches(bundleIdentifier: String) -> Bool {
        guard isEnabled else { return false }
        if case .application(let targetBundle) = kind {
            return bundleIdentifier.lowercased() == targetBundle.lowercased()
        }
        return false
    }

    /// Matches against a URL or domain string
    public func matches(url: URL) -> Bool {
        guard isEnabled else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return matches(host: host)
    }

    /// Matches against a normalized host string
    public func matches(host: String) -> Bool {
        guard isEnabled else { return false }
        if case .website(let pattern) = kind {
            let normalizedPattern = pattern.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            // Direct exact match
            if normalizedHost == normalizedPattern {
                return true
            }

            // Subdomain match: e.g. "x.com" matches "m.x.com" or "twitter.com" matches "mobile.twitter.com"
            if normalizedHost.hasSuffix("." + normalizedPattern) {
                return true
            }

            // Wildcard matching if pattern starts with "*."
            if normalizedPattern.hasPrefix("*.") {
                let suffix = String(normalizedPattern.dropFirst(2))
                if normalizedHost == suffix || normalizedHost.hasSuffix("." + suffix) {
                    return true
                }
            }
        }
        return false
    }

    /// Default starter friction targets
    public static var defaults: [TargetRule] {
        [
            TargetRule(name: "X / Twitter", kind: .website(domainPattern: "x.com"), delayDuration: 5.0, cooldownDuration: 900.0),
            TargetRule(name: "Twitter Legacy", kind: .website(domainPattern: "twitter.com"), delayDuration: 5.0, cooldownDuration: 900.0),
            TargetRule(name: "Reddit", kind: .website(domainPattern: "reddit.com"), delayDuration: 5.0, cooldownDuration: 900.0),
            TargetRule(name: "YouTube", kind: .website(domainPattern: "youtube.com"), delayDuration: 5.0, cooldownDuration: 900.0),
            TargetRule(name: "Instagram", kind: .website(domainPattern: "instagram.com"), delayDuration: 5.0, cooldownDuration: 900.0),
            TargetRule(name: "Discord", kind: .application(bundleIdentifier: "com.hnc.Discord"), delayDuration: 4.0, cooldownDuration: 1800.0)
        ]
    }
}
