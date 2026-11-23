// Native macOS preferences panes for break timers, curfew, delays, sound, stats, and permissions.

import ApplicationServices
import SwiftUI

/// Tabs available in the Grasslook preferences window.
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case breaks = "Breaks"
    case friction = "Delays"
    case sensory = "Sound"
    case stats = "Stats"
    case permissions = "Permissions"

    public var id: String { rawValue }

    /// Window title displayed when this tab is selected.
    public var title: String {
        switch self {
        case .breaks: return "Break Timers"
        case .friction: return "App & Web Delays"
        case .sensory: return "Sound"
        case .stats: return "Statistics"
        case .permissions: return "Permissions"
        }
    }

    /// Outline SF Symbol used in the preferences toolbar.
    public var systemImage: String {
        switch self {
        case .breaks: return "timer"
        case .friction: return "shield"
        case .sensory: return "speaker.wave.2"
        case .stats: return "chart.bar"
        case .permissions: return "lock.shield"
        }
    }

    /// Stable toolbar item identifier matching this preferences pane.
    public var toolbarItemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("com.grasslook.settings.\(rawValue.lowercased())")
    }

    /// Resolves a tab from its toolbar item identifier.
    public init?(toolbarItemIdentifier: NSToolbarItem.Identifier) {
        guard let matched = Self.allCases.first(where: { $0.toolbarItemIdentifier == toolbarItemIdentifier }) else {
            return nil
        }
        self = matched
    }

    /// Resolves a tab from a CLI argument name.
    public init?(cliName: String) {
        switch cliName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "breaks":
            self = .breaks
        case "delays", "friction":
            self = .friction
        case "sound", "sensory":
            self = .sensory
        case "stats", "statistics":
            self = .stats
        case "permissions":
            self = .permissions
        default:
            return nil
        }
    }
}

/// Native macOS preferences window scene backed by per-tab `SettingsPaneView` content.
public struct SettingsView: View {
    @ObservedObject public var scheduler: BreakScheduler
    @ObservedObject public var interception: AppInterceptionEngine
    @ObservedObject public var analytics: AnalyticsManager
    @ObservedObject public var audio: AudioFeedbackManager

    private let coordinator: GrasslookCoordinator?
    @State private var selectedTab: SettingsTab = .breaks

    /// Creates a settings view bound to a coordinator and its persisted configuration.
    public init(coordinator: GrasslookCoordinator) {
        self.init(
            scheduler: coordinator.scheduler,
            interception: coordinator.interception,
            analytics: coordinator.analytics,
            audio: coordinator.audio,
            coordinator: coordinator
        )
    }

    /// Creates a settings view with explicit service dependencies and an optional coordinator.
    public init(
        scheduler: BreakScheduler,
        interception: AppInterceptionEngine,
        analytics: AnalyticsManager,
        audio: AudioFeedbackManager,
        coordinator: GrasslookCoordinator? = nil
    ) {
        self.scheduler = scheduler
        self.interception = interception
        self.analytics = analytics
        self.audio = audio
        self.coordinator = coordinator
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsPaneView(
                    tab: tab,
                    scheduler: scheduler,
                    interception: interception,
                    analytics: analytics,
                    audio: audio,
                    coordinator: coordinator
                )
                .tabItem {
                    Label(tab.rawValue, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
    }
}

/// Two-column AppKit-hosted preferences pane sized dynamically to its content.
public struct SettingsPaneView: View {
    public let tab: SettingsTab
    @ObservedObject public var scheduler: BreakScheduler
    @ObservedObject public var interception: AppInterceptionEngine
    @ObservedObject public var analytics: AnalyticsManager
    @ObservedObject public var audio: AudioFeedbackManager

    private let coordinator: GrasslookCoordinator?
    private let onLayoutHeightChange: (() -> Void)?

    private static let labelColumnWidth: CGFloat = 175
    private static let sliderWidth: CGFloat = 220
    private static let listBoxWidth: CGFloat = 390

    @State private var newRuleName: String = ""
    @State private var newRulePattern: String = ""
    @State private var newRuleKindIndex: Int = 0
    @StateObject private var appsProvider = InstalledAppsProvider()
    @State private var selectedInstalledAppId: String = ""
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()

    @State private var focusSchedule: FocusScheduleConfig
    @State private var launchAtLoginEnabled: Bool
    @State private var launchAtLoginRequiresApproval: Bool
    @State private var launchAtLoginError: String?
    @State private var browserSnapshots: [BrowserPermissionSnapshot] = []
    @State private var permissionRefreshTask: Task<Void, Never>?

    /// Creates a preferences pane bound to a coordinator.
    public init(
        tab: SettingsTab,
        coordinator: GrasslookCoordinator,
        onLayoutHeightChange: (() -> Void)? = nil
    ) {
        self.init(
            tab: tab,
            scheduler: coordinator.scheduler,
            interception: coordinator.interception,
            analytics: coordinator.analytics,
            audio: coordinator.audio,
            coordinator: coordinator,
            onLayoutHeightChange: onLayoutHeightChange
        )
    }

    /// Creates a preferences pane with explicit service dependencies and an optional coordinator.
    public init(
        tab: SettingsTab,
        scheduler: BreakScheduler,
        interception: AppInterceptionEngine,
        analytics: AnalyticsManager,
        audio: AudioFeedbackManager,
        coordinator: GrasslookCoordinator? = nil,
        onLayoutHeightChange: (() -> Void)? = nil
    ) {
        self.tab = tab
        self.scheduler = scheduler
        self.interception = interception
        self.analytics = analytics
        self.audio = audio
        self.coordinator = coordinator
        self.onLayoutHeightChange = onLayoutHeightChange
        _focusSchedule = State(initialValue: coordinator?.config.focusSchedule ?? .default)
        _launchAtLoginEnabled = State(initialValue: coordinator?.launchAtLogin.isEnabled ?? false)
        _launchAtLoginRequiresApproval = State(initialValue: coordinator?.launchAtLogin.requiresApproval ?? false)
        _launchAtLoginError = State(initialValue: coordinator?.launchAtLogin.lastErrorMessage)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch tab {
            case .breaks:
                breaksPane
            case .friction:
                delaysPane
            case .sensory:
                soundPane
            case .stats:
                statsPane
            case .permissions:
                permissionsPane
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(width: SettingsWindowController.paneWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .controlSize(.regular)
        .onAppear {
            isAccessibilityTrusted = AXIsProcessTrusted()
            syncFromCoordinator()
            if tab == .permissions {
                startPermissionRefresh()
            }
        }
        .onDisappear {
            stopPermissionRefresh()
        }
        .onChange(of: tab) { _, newTab in
            syncFromCoordinator()
            if newTab == .permissions {
                startPermissionRefresh()
            } else {
                stopPermissionRefresh()
            }
            notifyHeightChange()
        }
        .onChange(of: interception.rules.count) { _, _ in
            notifyHeightChange()
        }
        .onChange(of: newRuleKindIndex) { _, _ in
            notifyHeightChange()
        }
        .onChange(of: browserSnapshots.count) { _, _ in
            notifyHeightChange()
        }
        .onChange(of: launchAtLoginRequiresApproval) { _, _ in
            notifyHeightChange()
        }
        .onChange(of: launchAtLoginError) { _, _ in
            notifyHeightChange()
        }
    }

    // MARK: - 1. Break Timers Pane

    private var breaksPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    formLabel("Eye rest duration:")
                    HStack(spacing: 8) {
                        Slider(value: microDurationBinding, in: 10...60, step: 5)
                            .frame(width: Self.sliderWidth)
                            .accessibilityLabel("Eye rest duration")
                            .accessibilityValue("\(Int(scheduler.microDuration)) seconds")

                        Text("\(Int(scheduler.microDuration))s")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .leading)
                    }
                }

                GridRow {
                    formLabel("Eye rest interval:")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Slider(value: microIntervalMinutesBinding, in: 10...45, step: 5)
                                .frame(width: Self.sliderWidth)
                                .accessibilityLabel("Eye rest interval")
                                .accessibilityValue("\(Int(scheduler.microInterval / 60.0)) minutes")

                            Text("\(Int(scheduler.microInterval / 60.0))m")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .leading)
                        }

                        Text("Every 20 minutes, look 20 feet away for 20 seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                sectionSpacerRow

                GridRow {
                    formLabel("Movement duration:")
                    HStack(spacing: 8) {
                        Slider(value: longDurationMinutesBinding, in: 2...15, step: 1)
                            .frame(width: Self.sliderWidth)
                            .accessibilityLabel("Movement duration")
                            .accessibilityValue("\(Int(scheduler.longDuration / 60.0)) minutes")

                        Text("\(Int(scheduler.longDuration / 60.0))m")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .leading)
                    }
                }

                GridRow {
                    formLabel("Movement interval:")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Slider(value: longIntervalMinutesBinding, in: 30...120, step: 15)
                                .frame(width: Self.sliderWidth)
                                .accessibilityLabel("Movement interval")
                                .accessibilityValue("\(Int(scheduler.longInterval / 60.0)) minutes")

                            Text("\(Int(scheduler.longInterval / 60.0))m")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .leading)
                        }

                        Text("Prompts you to stand up, stretch, and move.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                sectionSpacerRow

                GridRow {
                    formLabel("Automation:")
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Pause countdowns when away (idle > 3m)", isOn: smartPauseBinding)
                            .toggleStyle(.checkbox)

                        Toggle("Show 30s pre-break warning", isOn: preBreakWarningBinding)
                            .toggleStyle(.checkbox)

                        Toggle("Launch at Login", isOn: launchAtLoginBinding)
                            .toggleStyle(.checkbox)
                            .disabled(coordinator == nil)

                        if launchAtLoginRequiresApproval {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                                Text("Approve Grasslook in System Settings > General > Login Items.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.leading, 18)
                        }

                        if let launchAtLoginError {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                                    .accessibilityHidden(true)
                                Text(launchAtLoginError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding(.leading, 18)
                        }
                    }
                }

                sectionSpacerRow

                GridRow {
                    formLabel("Bedtime curfew:")
                    Toggle("Enable wind-down and strict curfew", isOn: focusScheduleEnabledBinding)
                        .toggleStyle(.checkbox)
                        .disabled(coordinator == nil)
                }

                GridRow {
                    formLabel("Curfew hours:")
                    HStack(spacing: 8) {
                        DatePicker(
                            "Curfew start",
                            selection: curfewStartDateBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .accessibilityLabel("Curfew start time")

                        Text("to")
                            .foregroundStyle(.secondary)

                        DatePicker(
                            "Curfew end",
                            selection: curfewEndDateBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .accessibilityLabel("Curfew end time")
                    }
                    .disabled(!focusSchedule.isEnabled || coordinator == nil)
                }

                GridRow {
                    formLabel("Wind-down:")
                    HStack(spacing: 8) {
                        Text("\(focusSchedule.windDownMinutes) min before curfew")
                            .monospacedDigit()

                        Stepper("", value: windDownMinutesBinding, in: 0...120, step: 5)
                            .labelsHidden()
                            .accessibilityLabel("Wind-down minutes")
                            .accessibilityValue("\(focusSchedule.windDownMinutes) minutes")
                    }
                    .disabled(!focusSchedule.isEnabled || coordinator == nil)
                }

                GridRow {
                    formLabel("Strictness:")
                    Picker("Strictness", selection: strictnessBinding) {
                        Text("Gentle").tag(StrictnessLevel.gentle)
                        Text("Strict Curfew").tag(StrictnessLevel.curfewStrict)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: Self.sliderWidth, alignment: .leading)
                    .disabled(!focusSchedule.isEnabled || coordinator == nil)
                }
            }

            paneFootnote("Timers pause automatically when your Mac sleeps.")
        }
    }

    // MARK: - 2. Delays Pane

    private var delaysPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    formLabel("Blocked targets:")
                        .gridCellAnchor(.topTrailing)

                    VStack(alignment: .leading, spacing: 0) {
                        if interception.rules.isEmpty {
                            Text("No blocked targets configured.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        } else {
                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(spacing: 0) {
                                    ForEach($interception.rules) { $rule in
                                        ruleRow(rule: $rule)
                                    }
                                }
                            }
                            .frame(height: min(CGFloat(interception.rules.count) * 32, 168))
                        }
                    }
                    .frame(width: Self.listBoxWidth, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                sectionSpacerRow

                GridRow {
                    formLabel("Add target:")
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Target kind", selection: $newRuleKindIndex) {
                            Text("Website Domain").tag(0)
                            Text("Desktop App").tag(1)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: Self.sliderWidth, alignment: .leading)

                        if newRuleKindIndex == 1 {
                            HStack(spacing: 8) {
                                Picker("Installed application", selection: $selectedInstalledAppId) {
                                    Text("Select from /Applications").tag("")
                                    ForEach(appsProvider.installedApps) { app in
                                        Text(app.name).tag(app.bundleIdentifier)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 240, alignment: .leading)
                                .onChange(of: selectedInstalledAppId) { _, newBundleId in
                                    if let found = appsProvider.installedApps.first(where: { $0.bundleIdentifier == newBundleId }) {
                                        newRuleName = found.name
                                        newRulePattern = found.bundleIdentifier
                                    }
                                }

                                Button("Browse...") {
                                    if let picked = InstalledAppsProvider.pickAppViaPanel() {
                                        newRuleName = picked.name
                                        newRulePattern = picked.bundleIdentifier
                                        selectedInstalledAppId = picked.bundleIdentifier
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            TextField(newRuleKindIndex == 0 ? "Name (e.g. YouTube)" : "App Name", text: $newRuleName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 145)

                            TextField(newRuleKindIndex == 0 ? "Domain (e.g. youtube.com)" : "Bundle ID", text: $newRulePattern)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 175)

                            Button("Add") {
                                addRule()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newRuleName.isEmpty || newRulePattern.isEmpty)
                        }
                    }
                }

                sectionSpacerRow

                GridRow {
                    formLabel("When leaving:")
                    Picker("Tab action", selection: browserActionBinding) {
                        Text("Redirect to Shield Page").tag(BrowserEnforcementAction.redirectToShield)
                        Text("Close Tab").tag(BrowserEnforcementAction.closeTab)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: Self.sliderWidth, alignment: .leading)
                }

                GridRow {
                    formLabel("Non-scriptable:")
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(
                            "Send Cmd+W to close tab in non-scriptable browsers",
                            isOn: sendCmdWBinding
                        )
                        .toggleStyle(.checkbox)

                        Text("When off, Grasslook hides the browser window instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 18)
                    }
                }
            }

            paneFootnote("Delays trigger when you open blocked apps or sites.")
        }
    }

    private func ruleRow(rule: Binding<TargetRule>) -> some View {
        let currentRule = rule.wrappedValue
        return HStack(spacing: 8) {
            Toggle("", isOn: rule.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Enable \(currentRule.name)")
                .onChange(of: currentRule.isEnabled) { _, _ in
                    persistInterceptionConfig()
                }

            Image(systemName: currentRule.kindSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(currentRule.name)
                .lineLimit(1)

            Text(currentRule.kindDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button {
                deleteRule(id: currentRule.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete rule")
            .accessibilityLabel("Delete \(currentRule.name)") // [VERIFY] confirm delete label
            .accessibilityInputLabels(["Delete \(currentRule.name)", "Remove \(currentRule.name)"])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - 3. Sound Pane

    private var soundPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    formLabel("Sound effects:")
                    Toggle("Play sound for breaks and breathing cues", isOn: soundEnabledBinding)
                        .toggleStyle(.checkbox)
                }

                GridRow {
                    formLabel("Volume:")
                    HStack(spacing: 8) {
                        Slider(value: audioVolumeBinding, in: 0.1...1.0)
                            .frame(width: Self.sliderWidth)
                            .disabled(!audio.isSoundEnabled)
                            .accessibilityLabel("Sound volume")
                            .accessibilityValue("\(Int(audio.volume * 100)) percent")

                        Text("\(Int(audio.volume * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .leading)
                    }
                }

                sectionSpacerRow

                GridRow {
                    formLabel("Preview:")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button("Test Break Sound") {
                                audio.playBreakStartChime()
                            }
                            .disabled(!audio.isSoundEnabled)

                            Button("Test Breathing Sound") {
                                audio.playBreathingCue()
                            }
                            .disabled(!audio.isSoundEnabled)
                        }

                        Text("Plays Glass when a break starts, Hero when it ends, and Breeze for breathing cues.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            paneFootnote("Audio follows macOS volume and mute settings.")
        }
    }

    // MARK: - 4. Stats Pane

    private var statsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    formLabel("Break time:")
                    statValueRow("\(analytics.mindfulMinutes) min", symbol: "clock")
                }

                GridRow {
                    formLabel("Breaks taken:")
                    statValueRow("\(analytics.breaksTaken)", symbol: "eye")
                }

                GridRow {
                    formLabel("Distractions avoided:")
                    statValueRow("\(analytics.distractionsAvoided)", symbol: "shield")
                }

                GridRow {
                    formLabel("Avoided rate:")
                    statValueRow("\(Int(analytics.focusSuccessRate * 100))%", symbol: "leaf")
                }

                sectionSpacerRow

                GridRow {
                    formLabel("Data:")
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Reset Statistics", role: .destructive) {
                            analytics.resetStats()
                        }

                        Text("Clears counters for breaks taken and time saved. All statistics stay on your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statValueRow(_ value: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    // MARK: - 5. Permissions Pane

    private var permissionsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    formLabel("Accessibility:")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(isAccessibilityTrusted ? Color.green : Color.orange)
                                .accessibilityHidden(true)

                            Text(isAccessibilityTrusted ? "Accessibility access granted" : "Accessibility permission required")
                                .fontWeight(.medium)
                        }

                        Text("Required to inspect active tabs across browsers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    formLabel("Actions:")
                        .gridCellAnchor(.topTrailing)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if isAccessibilityTrusted {
                                Button("Prompt Access") {
                                    promptAccessibilityAccess()
                                }
                            } else {
                                Button("Prompt Access") {
                                    promptAccessibilityAccess()
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button("Open Accessibility") {
                                openSystemAccessibilitySettings()
                            }

                            Button("Open Automation") {
                                openSystemAutomationSettings()
                            }
                        }

                        HStack(spacing: 8) {
                            Button("Re-check") {
                                isAccessibilityTrusted = AXIsProcessTrusted()
                                refreshBrowserStatusesNow(forceDiscovery: true)
                            }

                            Button("Relaunch App") {
                                relaunchApp()
                            }
                        }

                        Text("Enable Grasslook in System Settings > Privacy & Security > Accessibility, then relaunch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                sectionSpacerRow

                GridRow {
                    formLabel("Detected browsers:")
                        .gridCellAnchor(.topTrailing)

                    VStack(alignment: .leading, spacing: 0) {
                        if browserSnapshots.isEmpty {
                            Text("Scanning installed browsers...")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        } else {
                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(spacing: 0) {
                                    ForEach(browserSnapshots) { snapshot in
                                        browserSnapshotRow(snapshot)
                                    }
                                }
                            }
                            .frame(height: min(CGFloat(browserSnapshots.count) * 44, 176))
                        }
                    }
                    .frame(width: Self.listBoxWidth, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            paneFootnote("Used only to check active browser tabs.")
        }
    }

    private func browserSnapshotRow(_ snapshot: BrowserPermissionSnapshot) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.profile.displayName)
                    .lineLimit(1)

                Text("\(snapshot.profile.engine.displayName), \(snapshot.profile.scriptingDialect.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Image(systemName: statusSymbol(for: snapshot.automationStatus))
                    .foregroundStyle(statusColor(for: snapshot.automationStatus))
                    .accessibilityHidden(true)

                Text(snapshot.automationStatus.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor(for: snapshot.automationStatus))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(for: snapshot.automationStatus).opacity(0.14))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Layout Building Blocks

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: Self.labelColumnWidth, alignment: .trailing)
    }

    private var sectionSpacerRow: some View {
        GridRow {
            Color.clear
                .frame(height: 8)
                .gridCellColumns(2)
                .gridCellUnsizedAxes([.horizontal, .vertical])
        }
    }

    private func paneFootnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Config Bindings

    private var microDurationBinding: Binding<TimeInterval> {
        Binding(
            get: { scheduler.microDuration },
            set: { newValue in
                scheduler.microDuration = newValue
                coordinator?.config.microDuration = newValue
                coordinator?.saveConfig()
            }
        )
    }

    private var microIntervalMinutesBinding: Binding<Double> {
        Binding(
            get: { scheduler.microInterval / 60.0 },
            set: { newMinutes in
                let seconds = newMinutes * 60.0
                scheduler.microInterval = seconds
                coordinator?.config.microInterval = seconds
                coordinator?.saveConfig()
            }
        )
    }

    private var longDurationMinutesBinding: Binding<Double> {
        Binding(
            get: { scheduler.longDuration / 60.0 },
            set: { newMinutes in
                let seconds = newMinutes * 60.0
                scheduler.longDuration = seconds
                coordinator?.config.longDuration = seconds
                coordinator?.saveConfig()
            }
        )
    }

    private var longIntervalMinutesBinding: Binding<Double> {
        Binding(
            get: { scheduler.longInterval / 60.0 },
            set: { newMinutes in
                let seconds = newMinutes * 60.0
                scheduler.longInterval = seconds
                coordinator?.config.longInterval = seconds
                coordinator?.saveConfig()
            }
        )
    }

    private var smartPauseBinding: Binding<Bool> {
        Binding(
            get: { scheduler.smartPauseEnabled },
            set: { newValue in
                scheduler.smartPauseEnabled = newValue
                coordinator?.config.smartPauseEnabled = newValue
                coordinator?.saveConfig()
            }
        )
    }

    private var preBreakWarningBinding: Binding<Bool> {
        Binding(
            get: { scheduler.preBreakWarningEnabled },
            set: { newValue in
                scheduler.preBreakWarningEnabled = newValue
                coordinator?.config.preBreakWarningEnabled = newValue
                coordinator?.saveConfig()
                if newValue {
                    Task {
                        _ = await coordinator?.notifications.requestAuthorizationIfNeeded()
                    }
                }
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { newValue in
                guard let coordinator else { return }
                coordinator.launchAtLogin.setEnabled(newValue)
                launchAtLoginEnabled = coordinator.launchAtLogin.isEnabled
                launchAtLoginRequiresApproval = coordinator.launchAtLogin.requiresApproval
                launchAtLoginError = coordinator.launchAtLogin.lastErrorMessage
            }
        )
    }

    private var focusScheduleEnabledBinding: Binding<Bool> {
        Binding(
            get: { focusSchedule.isEnabled },
            set: { newValue in
                focusSchedule.isEnabled = newValue
                persistFocusSchedule()
            }
        )
    }

    private var curfewStartDateBinding: Binding<Date> {
        Binding(
            get: { date(from: focusSchedule.curfewStart) },
            set: { newDate in
                focusSchedule.curfewStart = timeOfDay(from: newDate)
                persistFocusSchedule()
            }
        )
    }

    private var curfewEndDateBinding: Binding<Date> {
        Binding(
            get: { date(from: focusSchedule.curfewEnd) },
            set: { newDate in
                focusSchedule.curfewEnd = timeOfDay(from: newDate)
                persistFocusSchedule()
            }
        )
    }

    private var windDownMinutesBinding: Binding<Int> {
        Binding(
            get: { focusSchedule.windDownMinutes },
            set: { newValue in
                focusSchedule.windDownMinutes = newValue
                persistFocusSchedule()
            }
        )
    }

    private var strictnessBinding: Binding<StrictnessLevel> {
        Binding(
            get: { focusSchedule.strictness },
            set: { newValue in
                focusSchedule.strictness = newValue
                persistFocusSchedule()
            }
        )
    }

    private var browserActionBinding: Binding<BrowserEnforcementAction> {
        Binding(
            get: { interception.browserEnforcementAction },
            set: { newValue in
                interception.browserEnforcementAction = newValue
                coordinator?.config.browserEnforcementAction = newValue
                coordinator?.saveConfig()
            }
        )
    }

    private var sendCmdWBinding: Binding<Bool> {
        Binding(
            get: { interception.sendCmdWToNonScriptableBrowsers },
            set: { newValue in
                interception.sendCmdWToNonScriptableBrowsers = newValue
                coordinator?.config.sendCmdWToNonScriptableBrowsers = newValue
                coordinator?.saveConfig()
            }
        )
    }

    private var soundEnabledBinding: Binding<Bool> {
        Binding(
            get: { audio.isSoundEnabled },
            set: { newValue in
                audio.isSoundEnabled = newValue
                coordinator?.config.isSoundEnabled = newValue
                coordinator?.saveConfig()
            }
        )
    }

    private var audioVolumeBinding: Binding<Float> {
        Binding(
            get: { audio.volume },
            set: { newValue in
                audio.volume = newValue
                coordinator?.config.audioVolume = newValue
                coordinator?.saveConfig()
            }
        )
    }

    // MARK: - Helpers

    private func notifyHeightChange() {
        Task { @MainActor in
            onLayoutHeightChange?()
        }
    }

    private func syncFromCoordinator() {
        guard let coordinator else { return }
        focusSchedule = coordinator.config.focusSchedule
        coordinator.launchAtLogin.refreshStatus()
        launchAtLoginEnabled = coordinator.launchAtLogin.isEnabled
        launchAtLoginRequiresApproval = coordinator.launchAtLogin.requiresApproval
        launchAtLoginError = coordinator.launchAtLogin.lastErrorMessage
    }

    private func persistFocusSchedule() {
        coordinator?.config.focusSchedule = focusSchedule
        coordinator?.saveConfig()
    }

    private func persistInterceptionConfig() {
        coordinator?.config.targetRules = interception.rules
        coordinator?.config.browserEnforcementAction = interception.browserEnforcementAction
        coordinator?.config.sendCmdWToNonScriptableBrowsers = interception.sendCmdWToNonScriptableBrowsers
        coordinator?.saveConfig()
    }

    private func startPermissionRefresh() {
        permissionRefreshTask?.cancel()
        guard tab == .permissions, let coordinator else { return }

        permissionRefreshTask = Task { @MainActor in
            while !Task.isCancelled && tab == .permissions {
                isAccessibilityTrusted = AXIsProcessTrusted()
                let browsers = coordinator.browserDiscovery.discoverInstalledBrowsers(forceRefresh: false)
                let snapshots = await coordinator.permissionChecker.checkStatuses(for: browsers)
                guard !Task.isCancelled else { break }
                browserSnapshots = snapshots
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func stopPermissionRefresh() {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = nil
    }

    private func refreshBrowserStatusesNow(forceDiscovery: Bool) {
        guard let coordinator else { return }
        Task { @MainActor in
            let browsers = coordinator.browserDiscovery.discoverInstalledBrowsers(forceRefresh: forceDiscovery)
            browserSnapshots = await coordinator.permissionChecker.checkStatuses(for: browsers)
        }
    }

    private func statusSymbol(for status: BrowserAutomationStatus) -> String {
        switch status {
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .prompt:
            return "questionmark.circle"
        case .notApplicable:
            return "accessibility"
        case .unknown:
            return "ellipsis.circle"
        }
    }

    private func statusColor(for status: BrowserAutomationStatus) -> Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .red
        case .prompt:
            return .orange
        case .notApplicable:
            return .secondary
        case .unknown:
            return .yellow
        }
    }

    private func date(from time: TimeOfDay) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components) ?? Date()
    }

    private func timeOfDay(from date: Date) -> TimeOfDay {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return TimeOfDay(hour: hour, minute: minute)
    }

    private func addRule() {
        let kind: TargetRuleKind = (newRuleKindIndex == 0)
            ? .website(domainPattern: newRulePattern)
            : .application(bundleIdentifier: newRulePattern)
        let rule = TargetRule(name: newRuleName, kind: kind, delayDuration: 5.0, cooldownDuration: 900.0)
        interception.rules.append(rule)
        persistInterceptionConfig()
        newRuleName = ""
        newRulePattern = ""
        selectedInstalledAppId = ""
    }

    private func deleteRule(id: UUID) {
        interception.rules.removeAll { $0.id == id }
        persistInterceptionConfig()
    }

    private func promptAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func openSystemAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openSystemAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.2; /usr/bin/open -n \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

private extension TargetRule {
    var kindSymbol: String {
        switch kind {
        case .application: return "macwindow"
        case .website: return "globe"
        }
    }

    var kindDetail: String {
        switch kind {
        case .application(let bundle): return bundle
        case .website(let domain): return domain
        }
    }
}
