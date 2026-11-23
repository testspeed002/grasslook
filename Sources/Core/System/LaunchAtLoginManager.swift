// Manages macOS Login Item registration for Grasslook via SMAppService.

import Foundation
import ServiceManagement
import os

/// Wraps `SMAppService.mainApp` to manage launch-at-login registration state.
@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var requiresApproval: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    private let logger = Logger(subsystem: "com.grasslook.app", category: "LaunchAtLogin")

    /// Creates a launch-at-login manager and reads the current system registration status.
    public init() {
        refreshStatus()
    }

    /// Refreshes `isEnabled` and `requiresApproval` from `SMAppService.mainApp`.
    public func refreshStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
        case .requiresApproval:
            isEnabled = true
            requiresApproval = true
        case .notRegistered, .notFound:
            isEnabled = false
            requiresApproval = false
        @unknown default:
            isEnabled = false
            requiresApproval = false
        }
    }

    /// Registers or unregisters Grasslook as a login item.
    public func setEnabled(_ enabled: Bool) {
        lastErrorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            logger.error("Failed to update launch-at-login (\(enabled, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
    }
}
