import Foundation
import SwiftUI

/// Main application coordinator binding break scheduling, friction engine, overlays, audio, and analytics.
@MainActor
public final class GrasslookCoordinator: ObservableObject {
    public let scheduler: BreakScheduler
    public let interception: AppInterceptionEngine
    public let overlays: OverlayWindowController
    public let audio: AudioFeedbackManager
    public let analytics: AnalyticsManager

    public init(
        scheduler: BreakScheduler = BreakScheduler(),
        interception: AppInterceptionEngine = AppInterceptionEngine(),
        overlays: OverlayWindowController = OverlayWindowController(),
        audio: AudioFeedbackManager = AudioFeedbackManager(),
        analytics: AnalyticsManager = AnalyticsManager()
    ) {
        self.scheduler = scheduler
        self.interception = interception
        self.overlays = overlays
        self.audio = audio
        self.analytics = analytics

        setupBindings()
    }

    public func start() {
        scheduler.start()
        interception.startMonitoring()
    }

    public func stop() {
        scheduler.stop()
        interception.stopMonitoring()
        overlays.dismissOverlays()
    }

    private func setupBindings() {
        // 1. Break started -> Show overlay and play chime
        scheduler.onBreakStarted = { [weak self] type in
            guard let self = self else { return }
            self.audio.playBreakStartChime()
            self.overlays.presentBreakOverlay(
                type: type,
                duration: (type == .micro) ? self.scheduler.microDuration : self.scheduler.longDuration,
                secondsRemaining: (type == .micro) ? self.scheduler.microDuration : self.scheduler.longDuration,
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

        // 2. Break completed -> Play end chime, record analytics, dismiss overlay
        scheduler.onBreakCompleted = { [weak self] type in
            guard let self = self else { return }
            self.audio.playBreakEndChime()
            let duration = (type == .micro) ? self.scheduler.microDuration : self.scheduler.longDuration
            self.analytics.recordBreakTaken(type: type, duration: duration)
            self.overlays.dismissOverlays()
        }

        // 3. Break skipped -> Record analytics, dismiss overlay
        scheduler.onBreakSkipped = { [weak self] type in
            self?.analytics.recordBreakSkipped(type: type)
            self?.overlays.dismissOverlays()
        }

        // 4. App / URL Interception Triggered -> Present Mindful Friction Overlay
        interception.onInterventionTriggered = { [weak self] intervention in
            guard let self = self else { return }
            self.audio.playBreathingCue()

            let appName = intervention.application.localizedName ?? "Application"
            let domain = intervention.targetURL?.host

            self.overlays.presentFrictionOverlay(
                appName: appName,
                domainName: domain,
                duration: intervention.rule.delayDuration,
                onProceed: { [weak self] in
                    self?.analytics.recordDistractionContinued(delayDuration: intervention.rule.delayDuration)
                    self?.interception.proceedPastIntervention(for: intervention)
                },
                onCloseApp: { [weak self] in
                    self?.analytics.recordDistractionAvoided(delayDuration: intervention.rule.delayDuration)
                    self?.interception.dismissInterventionAndCloseApp(for: intervention)
                }
            )
        }
    }
}
