import Foundation
import AppKit

/// Observes frontmost application focus and browser tab switches to insert mindful delays.
@MainActor
public final class AppInterceptionEngine: ObservableObject {
    // MARK: - Published Properties
    @Published public var rules: [TargetRule]
    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var activeIntervention: ActiveIntervention?

    // MARK: - Dependencies
    private let browserMonitor: BrowserMonitorProtocol
    public let cooldownManager: CooldownManager
    private var workspaceObserver: (any NSObjectProtocol)?

    // MARK: - Models
    public struct ActiveIntervention: Identifiable, Sendable {
        public var id: UUID { rule.id }
        public let rule: TargetRule
        public let application: NSRunningApplication
        public let targetURL: URL?
        public let startedAt: Date

        public init(rule: TargetRule, application: NSRunningApplication, targetURL: URL? = nil, startedAt: Date = Date()) {
            self.rule = rule
            self.application = application
            self.targetURL = targetURL
            self.startedAt = startedAt
        }
    }

    // MARK: - Callbacks
    public var onInterventionTriggered: ((ActiveIntervention) -> Void)?

    public init(
        rules: [TargetRule] = TargetRule.defaults,
        browserMonitor: BrowserMonitorProtocol = BrowserMonitor(),
        cooldownManager: CooldownManager = CooldownManager()
    ) {
        self.rules = rules
        self.browserMonitor = browserMonitor
        self.cooldownManager = cooldownManager
    }

    // MARK: - Lifecycle

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.evaluateApplication(app)
            }
        }

        // Evaluate currently active frontmost application
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            evaluateApplication(frontmost)
        }
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        activeIntervention = nil
    }

    /// Evaluates an application against active rules and triggers friction if necessary.
    public func evaluateApplication(_ application: NSRunningApplication) {
        guard isMonitoring else { return }
        guard let bundleId = application.bundleIdentifier else { return }

        // 1. Check Native Desktop App Rules
        for rule in rules where rule.isEnabled {
            if case .application = rule.kind, rule.matches(bundleIdentifier: bundleId) {
                if !cooldownManager.isUnderCooldown(for: rule) {
                    triggerIntervention(for: rule, application: application, targetURL: nil)
                    return
                }
            }
        }

        // 2. Check Browser Website Rules (if app is a supported browser)
        if browserMonitor.isSupportedBrowser(bundleIdentifier: bundleId) {
            if let activeURL = browserMonitor.extractActiveURL(from: application) {
                for rule in rules where rule.isEnabled {
                    if case .website = rule.kind, rule.matches(url: activeURL) {
                        if !cooldownManager.isUnderCooldown(for: rule) {
                            triggerIntervention(for: rule, application: application, targetURL: activeURL)
                            return
                        }
                    }
                }
            }
        }
    }

    // MARK: - Intervention Actions

    public func proceedPastIntervention(for intervention: ActiveIntervention) {
        cooldownManager.recordMindfulPass(for: intervention.rule)
        activeIntervention = nil
    }

    public func dismissInterventionAndCloseApp(for intervention: ActiveIntervention) {
        activeIntervention = nil
        
        if let bundleId = intervention.application.bundleIdentifier,
           (intervention.targetURL != nil || browserMonitor.isSupportedBrowser(bundleIdentifier: bundleId)) {
            // Close the distracting tab and open a clean blank tab in the browser
            browserMonitor.closeDistractingTabAndOpenBlank(bundleIdentifier: bundleId)
        } else {
            // Hide the distracting desktop application
            intervention.application.hide()
        }
    }

    private func triggerIntervention(for rule: TargetRule, application: NSRunningApplication, targetURL: URL?) {
        let intervention = ActiveIntervention(rule: rule, application: application, targetURL: targetURL)
        self.activeIntervention = intervention
        onInterventionTriggered?(intervention)
    }
}
