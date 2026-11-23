// Coordinates break timers, app delays, overlays, persistence, curfew, and notifications.

import Foundation
import os
import SwiftUI

/// Coordinates break timers, app delays, overlays, audio, persistence, and analytics.
@MainActor
public final class GrasslookCoordinator: ObservableObject {
    public static let shared = GrasslookCoordinator()

    public let configStore: GrasslookConfigStore
    @Published public var config: GrasslookConfig

    public let scheduler: BreakScheduler
    public let interception: AppInterceptionEngine
    public let overlays: OverlayWindowController
    public let audio: AudioFeedbackManager
    public let analytics: AnalyticsManager
    public let browserDiscovery: BrowserDiscovery
    public let permissionChecker: BrowserPermissionChecker
    public let launchAtLogin: LaunchAtLoginManager
    public let notifications: PreBreakNotificationManager

    private let dateProvider: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.grasslook.app", category: "Coordinator")

    /// Creates a coordinator hydrated from `configStore`, with optional injected dependencies for testing.
    public init(
        configStore: GrasslookConfigStore = GrasslookConfigStore(),
        scheduler: BreakScheduler? = nil,
        interception: AppInterceptionEngine? = nil,
        overlays: OverlayWindowController = OverlayWindowController(),
        audio: AudioFeedbackManager? = nil,
        analytics: AnalyticsManager = AnalyticsManager(),
        browserDiscovery: BrowserDiscovery = .shared,
        permissionChecker: BrowserPermissionChecker = BrowserPermissionChecker(),
        launchAtLogin: LaunchAtLoginManager? = nil,
        notifications: PreBreakNotificationManager? = nil,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        let loadedConfig = configStore.load()
        self.configStore = configStore
        self.config = loadedConfig
        self.dateProvider = dateProvider

        let resolvedScheduler = scheduler ?? BreakScheduler(
            microInterval: loadedConfig.microInterval,
            microDuration: loadedConfig.microDuration,
            longInterval: loadedConfig.longInterval,
            longDuration: loadedConfig.longDuration,
            idleThreshold: loadedConfig.idleThreshold,
            smartPauseEnabled: loadedConfig.smartPauseEnabled,
            dateProvider: dateProvider
        )
        resolvedScheduler.preBreakWarningEnabled = loadedConfig.preBreakWarningEnabled
        resolvedScheduler.preBreakWarningLeadSeconds = loadedConfig.preBreakWarningLeadSeconds
        self.scheduler = resolvedScheduler

        let cooldownManager = CooldownManager(
            initialCooldowns: loadedConfig.activeCooldowns,
            dateProvider: dateProvider
        )
        let resolvedInterception = interception ?? AppInterceptionEngine(
            rules: loadedConfig.targetRules,
            cooldownManager: cooldownManager,
            dateProvider: dateProvider
        )
        resolvedInterception.browserEnforcementAction = loadedConfig.browserEnforcementAction
        resolvedInterception.sendCmdWToNonScriptableBrowsers = loadedConfig.sendCmdWToNonScriptableBrowsers
        self.interception = resolvedInterception

        self.overlays = overlays
        self.audio = audio ?? AudioFeedbackManager(
            isSoundEnabled: loadedConfig.isSoundEnabled,
            volume: loadedConfig.audioVolume
        )
        self.analytics = analytics
        self.browserDiscovery = browserDiscovery
        self.permissionChecker = permissionChecker
        self.launchAtLogin = launchAtLogin ?? LaunchAtLoginManager()
        self.notifications = notifications ?? PreBreakNotificationManager()

        browserDiscovery.setCustomBrowsers(Set(loadedConfig.customBrowserBundleIds))

        resolvedInterception.cooldownManager.setOnChange { [weak self] activeCooldowns in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.config.activeCooldowns = activeCooldowns
                self.persistConfig()
            }
        }

        setupBindings()
    }

    /// Starts notifications, login-item status refresh, break scheduler, and app/browser interception.
    public func start() {
        notifications.configureIfAvailable()
        launchAtLogin.refreshStatus()
        scheduler.start()
        interception.startMonitoring()
    }

    /// Stops break scheduling, interception monitoring, and dismisses any open overlays.
    public func stop() {
        scheduler.stop()
        interception.stopMonitoring()
        notifications.clearPendingWarnings()
        overlays.dismissOverlays()
    }

    /// Syncs live component settings into `config` and atomically persists to disk.
    public func saveConfig() {
        config.microInterval = scheduler.microInterval
        config.microDuration = scheduler.microDuration
        config.longInterval = scheduler.longInterval
        config.longDuration = scheduler.longDuration
        config.idleThreshold = scheduler.idleThreshold
        config.smartPauseEnabled = scheduler.smartPauseEnabled
        config.preBreakWarningEnabled = scheduler.preBreakWarningEnabled
        config.preBreakWarningLeadSeconds = scheduler.preBreakWarningLeadSeconds
        config.targetRules = interception.rules
        config.browserEnforcementAction = interception.browserEnforcementAction
        config.sendCmdWToNonScriptableBrowsers = interception.sendCmdWToNonScriptableBrowsers
        config.isSoundEnabled = audio.isSoundEnabled
        config.audioVolume = audio.volume
        config.activeCooldowns = interception.cooldownManager.activeCooldownsSnapshot()
        browserDiscovery.setCustomBrowsers(Set(config.customBrowserBundleIds))
        persistConfig()
    }

    // MARK: - Focus Schedule & Curfew

    /// Current late-night focus phase evaluated at the current time.
    public var currentFocusPhase: FocusPhase {
        config.focusSchedule.phase(at: dateProvider())
    }

    /// Whether strict curfew enforcement is currently active.
    public var isStrictCurfewActive: Bool {
        config.focusSchedule.isStrictCurfewActive(at: dateProvider())
    }

    /// Whether the evening dusk visual cue window is currently active.
    public var isDuskCueActive: Bool {
        config.focusSchedule.isDuskCueActive(at: dateProvider())
    }

    /// Returns true if a nightly break-glass pass is currently available.
    public func canUseBreakGlassNow() -> Bool {
        config.breakGlassBudget.canUseBreakGlass(at: dateProvider(), config: config.focusSchedule)
    }

    /// Attempts to consume a break-glass pass with an intention note and persists if consumed.
    public func consumeBreakGlass(intentionNote: String, ruleName: String? = nil) -> Bool {
        let consumed = config.breakGlassBudget.consumePass(
            at: dateProvider(),
            intentionNote: intentionNote,
            ruleName: ruleName,
            config: config.focusSchedule
        )
        if consumed {
            persistConfig()
        }
        return consumed
    }

    // MARK: - Private Helpers

    private func persistConfig() {
        do {
            try configStore.save(config)
        } catch {
            logger.error("Failed to save Grasslook config: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setupBindings() {
        scheduler.onPreBreakWarning = { [weak self] type, leadSeconds in
            self?.notifications.postPreBreakWarning(for: type, leadSeconds: leadSeconds)
        }

        notifications.onSnoozeRequested = { [weak self] in
            self?.scheduler.postponeBreak(by: 300.0)
        }

        notifications.onStartNowRequested = { [weak self] type in
            self?.scheduler.triggerBreakNow(type: type)
        }

        scheduler.onBreakStarted = { [weak self] type in
            guard let self = self else { return }
            self.notifications.clearPendingWarnings()
            self.audio.playBreakStartChime()
            let duration = (type == .micro) ? self.scheduler.microDuration : self.scheduler.longDuration
            self.overlays.presentBreakOverlay(
                type: type,
                duration: duration,
                secondsRemaining: duration,
                strictMode: self.isStrictCurfewActive,
                isDuskCueActive: self.isDuskCueActive,
                onSkip: { [weak self] in
                    self?.scheduler.skipCurrentBreak()
                },
                onPostpone: { [weak self] in
                    self?.scheduler.postponeBreak(by: 300.0)
                },
                onComplete: { [weak self] in
                    self?.scheduler.completeCurrentBreak()
                }
            )
        }

        scheduler.onBreakCompleted = { [weak self] type in
            guard let self = self else { return }
            self.audio.playBreakEndChime()
            let duration = (type == .micro) ? self.scheduler.microDuration : self.scheduler.longDuration
            self.analytics.recordBreakTaken(type: type, duration: duration)
            self.overlays.dismissOverlays()
        }

        scheduler.onBreakSkipped = { [weak self] type in
            self?.analytics.recordBreakSkipped(type: type)
            self?.overlays.dismissOverlays()
        }

        scheduler.onBreakPostponed = { [weak self] _ in
            self?.overlays.dismissOverlays()
        }

        interception.onInterventionTriggered = { [weak self] intervention in
            guard let self = self else { return }
            self.audio.playBreathingCue()

            let now = self.dateProvider()
            let appName = intervention.application.localizedName ?? "Application"
            let domain = intervention.targetURL?.host
            let effectiveDuration = self.config.focusSchedule.effectiveDelayDuration(
                baseDuration: intervention.rule.delayDuration,
                at: now
            )
            let focusPhase = self.config.focusSchedule.phase(at: now)
            let strictCurfew = self.config.focusSchedule.isStrictCurfewActive(at: now)
            let duskCue = self.config.focusSchedule.isDuskCueActive(at: now)
            let canBreakGlass = self.canUseBreakGlassNow()

            self.overlays.presentFrictionOverlay(
                appName: appName,
                domainName: domain,
                duration: effectiveDuration,
                cooldownDuration: intervention.rule.cooldownDuration,
                focusPhase: focusPhase,
                isStrictCurfew: strictCurfew,
                isDuskCueActive: duskCue,
                canUseBreakGlass: canBreakGlass,
                breakGlassWaitSeconds: self.config.focusSchedule.breakGlassWaitSeconds,
                breakGlassMinNoteLength: self.config.focusSchedule.breakGlassMinNoteLength,
                onProceed: { [weak self] in
                    self?.analytics.recordDistractionContinued(delayDuration: effectiveDuration)
                    self?.interception.proceedPastIntervention(for: intervention)
                },
                onBreakGlass: { [weak self] intentionNote in
                    guard let self = self else { return }
                    if self.consumeBreakGlass(intentionNote: intentionNote, ruleName: intervention.rule.name) {
                        self.analytics.recordDistractionContinued(delayDuration: effectiveDuration)
                        self.interception.proceedPastIntervention(for: intervention)
                    }
                },
                onCloseApp: { [weak self] in
                    self?.analytics.recordDistractionAvoided(delayDuration: effectiveDuration)
                    self?.interception.dismissInterventionAndCloseApp(for: intervention)
                }
            )
        }
    }
}
