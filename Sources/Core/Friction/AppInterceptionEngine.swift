// Monitors application switches and active browser tabs to present mindful friction.

import AppKit
import Foundation

/// Monitors app and browser tab switches to show mindful delays.
@MainActor
public final class AppInterceptionEngine: ObservableObject {
    // MARK: - Published Properties
    @Published public var rules: [TargetRule]
    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var activeIntervention: ActiveIntervention?
    @Published public var browserEnforcementAction: BrowserEnforcementAction = .redirectToShield
    @Published public var sendCmdWToNonScriptableBrowsers: Bool = false

    // MARK: - Dependencies
    private let browserMonitor: BrowserMonitorProtocol
    public let cooldownManager: CooldownManager
    private let pollingInterval: TimeInterval
    private let frontmostPIDProvider: @MainActor () -> pid_t?
    private let dateProvider: @Sendable () -> Date

    nonisolated(unsafe) private var workspaceObserver: (any NSObjectProtocol)?
    nonisolated(unsafe) private var pollingTask: Task<Void, Never>?
    private var lastSuppressedHit: (pid: pid_t, host: String, expiresAt: Date)?
    private let suppressionWindow: TimeInterval = 2.5

    // MARK: - Models
    public struct ActiveIntervention: Identifiable, Sendable {
        public var id: UUID { rule.id }
        public let rule: TargetRule
        public let application: NSRunningApplication
        public let targetURL: URL?
        public let startedAt: Date

        /// Creates an active intervention record for a triggered rule.
        public init(
            rule: TargetRule,
            application: NSRunningApplication,
            targetURL: URL? = nil,
            startedAt: Date = Date()
        ) {
            self.rule = rule
            self.application = application
            self.targetURL = targetURL
            self.startedAt = startedAt
        }
    }

    // MARK: - Callbacks
    public var onInterventionTriggered: ((ActiveIntervention) -> Void)?

    /// Creates an interception engine with configurable rules, browser monitor, and polling dependencies.
    public init(
        rules: [TargetRule] = TargetRule.defaults,
        browserMonitor: BrowserMonitorProtocol = BrowserMonitor(),
        cooldownManager: CooldownManager = CooldownManager(),
        pollingInterval: TimeInterval = 1.25,
        frontmostPIDProvider: @escaping @MainActor () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rules = rules
        self.browserMonitor = browserMonitor
        self.cooldownManager = cooldownManager
        self.pollingInterval = pollingInterval
        self.frontmostPIDProvider = frontmostPIDProvider
        self.dateProvider = dateProvider
    }

    deinit {
        pollingTask?.cancel()
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    /// Starts observing workspace app activations and polling active browser tabs.
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
            Task { @MainActor [weak self] in
                await self?.evaluateApplication(app)
            }
        }

        startPollingLoop()

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            Task { @MainActor [weak self] in
                await self?.evaluateApplication(frontmost)
            }
        }
    }

    /// Stops observing workspace events and cancels active browser polling.
    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        pollingTask?.cancel()
        pollingTask = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        activeIntervention = nil
        lastSuppressedHit = nil
    }

    /// Evaluates an application against active rules and triggers friction if necessary.
    public func evaluateApplication(_ application: NSRunningApplication) async {
        guard isMonitoring, activeIntervention == nil else { return }
        guard let bundleId = application.bundleIdentifier else { return }

        // 1. Check Native Desktop App Rules
        for rule in rules where rule.isEnabled {
            if case .application = rule.kind, rule.matches(bundleIdentifier: bundleId) {
                if !cooldownManager.isUnderCooldown(for: rule) {
                    if let frontmostPID = frontmostPIDProvider(), frontmostPID != application.processIdentifier {
                        return
                    }
                    triggerIntervention(for: rule, application: application, targetURL: nil)
                    return
                }
            }
        }

        // 2. Check Browser Website Rules (if app is a supported browser)
        if await browserMonitor.isSupportedBrowser(bundleIdentifier: bundleId) {
            await pollActiveBrowserOnce(for: application)
        }
    }

    /// Performs a single active-tab inspection pass for a supported browser application.
    public func pollActiveBrowserOnce(for application: NSRunningApplication) async {
        guard isMonitoring, activeIntervention == nil else { return }
        guard let bundleId = application.bundleIdentifier else { return }
        guard await browserMonitor.isSupportedBrowser(bundleIdentifier: bundleId) else { return }

        guard let activeURL = await browserMonitor.extractActiveURL(from: application) else { return }

        // Verify frontmost PID is unchanged after async URL extraction before presenting an overlay.
        if let frontmostPID = frontmostPIDProvider(), frontmostPID != application.processIdentifier {
            return
        }
        guard isMonitoring, activeIntervention == nil else { return }

        let host = activeURL.host?.lowercased() ?? ""
        if isSuppressed(pid: application.processIdentifier, host: host) {
            return
        }

        for rule in rules where rule.isEnabled {
            if case .website = rule.kind, rule.matches(url: activeURL) {
                if !cooldownManager.isUnderCooldown(for: rule) {
                    triggerIntervention(for: rule, application: application, targetURL: activeURL)
                    return
                }
            }
        }
    }

    // MARK: - Intervention Actions

    /// Records a mindful pass cooldown and dismisses the active intervention.
    public func proceedPastIntervention(for intervention: ActiveIntervention) {
        cooldownManager.recordMindfulPass(for: intervention.rule)
        activeIntervention = nil
    }

    /// Enforces dismissal of a distracting target via browser redirect/close or hiding a desktop app.
    public func enforceDismissal(for intervention: ActiveIntervention) async -> BrowserEnforcementResult {
        activeIntervention = nil

        let host = intervention.targetURL?.host?.lowercased() ?? ""
        lastSuppressedHit = (
            pid: intervention.application.processIdentifier,
            host: host,
            expiresAt: dateProvider().addingTimeInterval(suppressionWindow)
        )

        if await shouldEnforceBrowserDismissal(for: intervention) {
            let options = BrowserEnforcementOptions(
                action: browserEnforcementAction,
                sendCmdWToNonScriptable: sendCmdWToNonScriptableBrowsers,
                ruleName: intervention.rule.name,
                blockedURL: intervention.targetURL
            )
            return await browserMonitor.enforceBlock(on: intervention.application, options: options)
        } else {
            intervention.application.hide()
            return .hidApplication
        }
    }

    private func shouldEnforceBrowserDismissal(for intervention: ActiveIntervention) async -> Bool {
        guard let bundleId = intervention.application.bundleIdentifier else {
            return false
        }
        if intervention.targetURL != nil {
            return true
        }
        return await browserMonitor.isSupportedBrowser(bundleIdentifier: bundleId)
    }

    /// Dismisses the active intervention and routes enforcement asynchronously.
    public func dismissInterventionAndCloseApp(for intervention: ActiveIntervention) {
        Task { @MainActor [weak self] in
            _ = await self?.enforceDismissal(for: intervention)
        }
    }

    // MARK: - Private Helpers

    private func startPollingLoop() {
        pollingTask?.cancel()
        let intervalNanos = UInt64(max(0.05, pollingInterval) * 1_000_000_000)

        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanos)
                } catch {
                    break
                }
                guard !Task.isCancelled, let self = self, self.isMonitoring else { break }
                guard self.activeIntervention == nil else { continue }
                guard let frontmostPID = self.frontmostPIDProvider() else { continue }
                guard let app = self.runningApplication(for: frontmostPID),
                      let bundleId = app.bundleIdentifier else {
                    continue
                }
                if await self.browserMonitor.isSupportedBrowser(bundleIdentifier: bundleId) {
                    await self.pollActiveBrowserOnce(for: app)
                }
            }
        }
    }

    private func runningApplication(for pid: pid_t) -> NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier == pid {
            return frontmost
        }
        return NSRunningApplication(processIdentifier: pid)
    }

    private func isSuppressed(pid: pid_t, host: String) -> Bool {
        guard let suppressed = lastSuppressedHit else { return false }
        if suppressed.pid == pid && suppressed.host == host {
            if dateProvider() < suppressed.expiresAt {
                return true
            }
        }
        lastSuppressedHit = nil
        return false
    }

    private func triggerIntervention(for rule: TargetRule, application: NSRunningApplication, targetURL: URL?) {
        let intervention = ActiveIntervention(
            rule: rule,
            application: application,
            targetURL: targetURL,
            startedAt: dateProvider()
        )
        self.activeIntervention = intervention
        onInterventionTriggered?(intervention)
    }
}
