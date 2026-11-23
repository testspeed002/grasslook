// Checks per-browser AppleEvents Automation permissions off the main actor.

import ApplicationServices
import Foundation

/// Represents a browser profile paired with its current Automation permission state.
public struct BrowserPermissionSnapshot: Identifiable, Sendable, Equatable {
    public var id: String { profile.id }
    public let profile: BrowserProfile
    public let automationStatus: BrowserAutomationStatus

    /// Creates a permission snapshot for a browser profile.
    public init(profile: BrowserProfile, automationStatus: BrowserAutomationStatus) {
        self.profile = profile
        self.automationStatus = automationStatus
    }
}

/// Queries macOS Automation (AppleEvents) consent for scriptable browser targets.
public final class BrowserPermissionChecker: Sendable {
    /// Creates a browser permission checker.
    public init() {}

    /// Queries Automation permission status for a single browser profile off the main actor.
    public func checkStatus(
        for profile: BrowserProfile,
        askUserIfNeeded: Bool = false
    ) async -> BrowserAutomationStatus {
        guard profile.scriptingDialect.isScriptable else {
            return .notApplicable
        }

        let bundleIdentifier = profile.bundleIdentifier
        return await Task.detached(priority: .utility) {
            Self.queryAutomationStatus(
                bundleIdentifier: bundleIdentifier,
                askUserIfNeeded: askUserIfNeeded
            )
        }.value
    }

    /// Queries Automation permission status for all provided browser profiles, preserving input order.
    public func checkStatuses(for profiles: [BrowserProfile]) async -> [BrowserPermissionSnapshot] {
        guard !profiles.isEmpty else { return [] }

        return await withTaskGroup(of: (Int, BrowserPermissionSnapshot).self) { group in
            for (index, profile) in profiles.enumerated() {
                group.addTask {
                    let status = await self.checkStatus(for: profile, askUserIfNeeded: false)
                    return (index, BrowserPermissionSnapshot(profile: profile, automationStatus: status))
                }
            }

            var indexedResults: [(Int, BrowserPermissionSnapshot)] = []
            indexedResults.reserveCapacity(profiles.count)
            for await result in group {
                indexedResults.append(result)
            }

            return indexedResults
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        }
    }

    private static func queryAutomationStatus(
        bundleIdentifier: String,
        askUserIfNeeded: Bool
    ) -> BrowserAutomationStatus {
        guard let bundleData = bundleIdentifier.data(using: .utf8), !bundleData.isEmpty else {
            return .unknown
        }

        var targetDesc = AEAddressDesc()
        let createStatus = bundleData.withUnsafeBytes { rawBuffer -> OSErr in
            guard let baseAddress = rawBuffer.baseAddress else {
                return OSErr(paramErr)
            }
            return AECreateDesc(
                DescType(typeApplicationBundleID),
                baseAddress,
                rawBuffer.count,
                &targetDesc
            )
        }

        guard createStatus == noErr else {
            return .unknown
        }
        defer { AEDisposeDesc(&targetDesc) }

        let permissionStatus = AEDeterminePermissionToAutomateTarget(
            &targetDesc,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )

        switch permissionStatus {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(procNotFound), OSStatus(errAEEventWouldRequireUserConsent):
            return .prompt
        default:
            return .unknown
        }
    }
}
