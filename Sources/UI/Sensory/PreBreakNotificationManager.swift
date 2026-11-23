// Pre-break macOS notification manager with snooze and start-now actions.

import Foundation
import UserNotifications
import os

/// Manages macOS user notifications for upcoming scheduled breaks.
@MainActor
public final class PreBreakNotificationManager: NSObject, ObservableObject {
    /// Notification category identifier for pre-break warnings.
    public static let categoryIdentifier = "GRASSLOOK_PRE_BREAK"

    /// Notification action identifier for postponing the upcoming break by 5 minutes.
    public static let snoozeActionIdentifier = "GRASSLOOK_PRE_BREAK_SNOOZE"

    /// Notification action identifier for starting the upcoming break immediately.
    public static let startNowActionIdentifier = "GRASSLOOK_PRE_BREAK_START_NOW"

    private static let warningRequestIdentifier = "com.grasslook.prebreak.warning"

    /// Called when the user selects Snooze 5m from a pre-break notification.
    public var onSnoozeRequested: (() -> Void)?

    /// Called when the user selects Start Now from a pre-break notification.
    public var onStartNowRequested: ((BreakType) -> Void)?

    private let logger = Logger(subsystem: "com.grasslook.app", category: "PreBreakNotifications")
    private var isConfigured = false

    private var isNotificationCenterAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var notificationCenter: UNUserNotificationCenter? {
        guard isNotificationCenterAvailable else { return nil }
        return UNUserNotificationCenter.current()
    }

    /// Creates a pre-break notification manager.
    public override init() {
        super.init()
    }

    /// Registers notification categories and delegate when running inside a `.app` bundle.
    public func configureIfAvailable() {
        guard let center = notificationCenter else { return }
        guard !isConfigured else { return }
        isConfigured = true

        center.delegate = self

        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Snooze 5m",
            options: []
        )
        let startNowAction = UNNotificationAction(
            identifier: Self.startNowActionIdentifier,
            title: "Start Now",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [snoozeAction, startNowAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Requests notification authorization if not already determined, returning whether delivery is allowed.
    public func requestAuthorizationIfNeeded() async -> Bool {
        configureIfAvailable()
        guard let center = notificationCenter else { return false }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                logger.error("Failed to request notification authorization: \(error.localizedDescription, privacy: .public)")
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Posts an immediate pre-break warning notification with Snooze 5m and Start Now actions.
    public func postPreBreakWarning(for type: BreakType, leadSeconds: TimeInterval) {
        configureIfAvailable()
        guard let center = notificationCenter else { return }

        let roundedSeconds = max(1, Int(leadSeconds.rounded()))
        let content = UNMutableNotificationContent()
        content.title = "\(type.title) in \(roundedSeconds)s"
        content.body = type.guidance
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["breakType": type.rawValue]

        let request = UNNotificationRequest(
            identifier: Self.warningRequestIdentifier,
            content: content,
            trigger: nil
        )

        Task { @MainActor [weak self] in
            do {
                try await center.add(request)
            } catch {
                self?.logger.error("Failed to post pre-break warning: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Removes any pending or delivered pre-break warning notifications.
    public func clearPendingWarnings() {
        guard let center = notificationCenter else { return }
        center.removePendingNotificationRequests(withIdentifiers: [Self.warningRequestIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.warningRequestIdentifier])
    }

    private func handleNotificationAction(actionIdentifier: String, breakTypeRawValue: String?) {
        if actionIdentifier == Self.snoozeActionIdentifier {
            onSnoozeRequested?()
        } else if actionIdentifier == Self.startNowActionIdentifier {
            let breakType = breakTypeRawValue.flatMap(BreakType.init(rawValue:)) ?? .micro
            onStartNowRequested?(breakType)
        }
    }
}

extension PreBreakNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        let rawType = response.notification.request.content.userInfo["breakType"] as? String
        await MainActor.run {
            self.handleNotificationAction(actionIdentifier: actionIdentifier, breakTypeRawValue: rawType)
        }
    }
}
