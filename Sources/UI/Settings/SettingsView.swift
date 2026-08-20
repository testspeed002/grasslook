import SwiftUI
import ApplicationServices

public enum SettingsTab: String, CaseIterable, Identifiable {
    case breaks = "Break Timers"
    case friction = "Friction"
    case sensory = "Audio"
    case stats = "Stats"
    case permissions = "Permissions"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .breaks: return "Break Timers"
        case .friction: return "App & Web Friction"
        case .sensory: return "Sensory & Audio"
        case .stats: return "Stats & Analytics"
        case .permissions: return "System Permissions"
        }
    }

    public var systemImage: String {
        switch self {
        case .breaks: return "timer"
        case .friction: return "shield.lefthalf.filled"
        case .sensory: return "speaker.wave.2.fill"
        case .stats: return "chart.bar.xaxis"
        case .permissions: return "lock.shield.fill"
        }
    }
}

/// Native macOS 26 Keynote-style Preferences Window with classic two-column aligned layout.
public struct SettingsView: View {
    @ObservedObject public var scheduler: BreakScheduler
    @ObservedObject public var interception: AppInterceptionEngine
    @ObservedObject public var analytics: AnalyticsManager
    @ObservedObject public var audio: AudioFeedbackManager

    @State private var selectedTab: SettingsTab = .breaks
    @State private var newRuleName: String = ""
    @State private var newRulePattern: String = ""
    @State private var newRuleKindIndex: Int = 0 // 0 = website, 1 = app
    @StateObject private var appsProvider = InstalledAppsProvider()
    @State private var selectedInstalledAppId: String = ""
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()

    public init(
        scheduler: BreakScheduler,
        interception: AppInterceptionEngine,
        analytics: AnalyticsManager,
        audio: AudioFeedbackManager
    ) {
        self.scheduler = scheduler
        self.interception = interception
        self.analytics = analytics
        self.audio = audio
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. Top macOS Preferences Toolbar
            topToolbar
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(Color.black.opacity(0.1))

            Divider()

            // MARK: - 2. Native Two-Column Content Area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .breaks:
                        breaksSettingsPane
                    case .friction:
                        frictionSettingsPane
                    case .sensory:
                        sensorySettingsPane
                    case .stats:
                        statsSettingsPane
                    case .permissions:
                        permissionsSettingsPane
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 530)
        .background(VisualEffectBackgroundView(material: .underWindowBackground, blendingMode: .behindWindow))
        .tint(ForestTheme.sage)
        .onAppear {
            isAccessibilityTrusted = AXIsProcessTrusted()
            updateWindowTitle()
        }
        .onChange(of: selectedTab) { _, _ in
            updateWindowTitle()
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: 14) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20))
                            .frame(height: 24)

                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selectedTab == tab ? ForestTheme.mist : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedTab == tab ? ForestTheme.forest.opacity(0.45) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(selectedTab == tab ? ForestTheme.sage.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 1. Break Timers Pane

    private var breaksSettingsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Row 1: Eye Rest (20-20-20)
            HStack(alignment: .top, spacing: 18) {
                Text("Eye Rest:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Duration:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)

                        Slider(value: $scheduler.microDuration, in: 10...60, step: 5)
                            .frame(width: 180)
                            .accessibilityLabel("Micro break duration")
                            .accessibilityValue("\(Int(scheduler.microDuration)) seconds")

                        Text("\(Int(scheduler.microDuration))s")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 40, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        Text("Interval:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)

                        Slider(value: Binding(
                            get: { scheduler.microInterval / 60.0 },
                            set: { scheduler.microInterval = $0 * 60.0 }
                        ), in: 10...45, step: 5)
                        .frame(width: 180)
                        .accessibilityLabel("Micro break interval")
                        .accessibilityValue("\(Int(scheduler.microInterval / 60.0)) minutes")

                        Text("\(Int(scheduler.microInterval / 60.0))m")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 40, alignment: .leading)
                    }

                    Text("Follows the 20-20-20 rule to relieve ocular eye strain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Row 2: Movement (Long Breaks)
            HStack(alignment: .top, spacing: 18) {
                Text("Movement:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Duration:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)

                        Slider(value: Binding(
                            get: { scheduler.longDuration / 60.0 },
                            set: { scheduler.longDuration = $0 * 60.0 }
                        ), in: 2...15, step: 1)
                        .frame(width: 180)
                        .accessibilityLabel("Long break duration")
                        .accessibilityValue("\(Int(scheduler.longDuration / 60.0)) minutes")

                        Text("\(Int(scheduler.longDuration / 60.0))m")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 40, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        Text("Interval:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)

                        Slider(value: Binding(
                            get: { scheduler.longInterval / 60.0 },
                            set: { scheduler.longInterval = $0 * 60.0 }
                        ), in: 30...120, step: 15)
                        .frame(width: 180)
                        .accessibilityLabel("Long break interval")
                        .accessibilityValue("\(Int(scheduler.longInterval / 60.0)) minutes")

                        Text("\(Int(scheduler.longInterval / 60.0))m")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 40, alignment: .leading)
                    }

                    Text("Prompts posture movement, shoulder stretching, and hydration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Row 3: Automation
            HStack(alignment: .top, spacing: 18) {
                Text("Automation:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Pause countdowns when away (idle > 3m)", isOn: $scheduler.smartPauseEnabled)
                        .toggleStyle(.checkbox)
                        .font(.subheadline)

                    Text("Uses low-power CoreGraphics idle sensing to prevent break popups while away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("Breaks run locally and pause automatically during Mac sleep.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - 2. Friction Settings Pane

    private var frictionSettingsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Row 1: Active Rules List
            HStack(alignment: .top, spacing: 18) {
                Text("Rules:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 8) {
                    if interception.rules.isEmpty {
                        Text("No target rules added yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach($interception.rules) { $rule in
                                HStack(spacing: 8) {
                                    Toggle("", isOn: $rule.isEnabled)
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()

                                    Image(systemName: rule.kindSymbol)
                                        .foregroundStyle(ForestTheme.sage)
                                        .frame(width: 16)

                                    Text(rule.name)
                                        .font(.subheadline.weight(.medium))

                                    Text("(\(rule.kindDescription))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Button {
                                        deleteRule(id: rule.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red.opacity(0.75))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete rule")
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }

            Divider()

            // Row 2: Add New Rule
            HStack(alignment: .top, spacing: 18) {
                Text("Add Target:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $newRuleKindIndex) {
                        Text("Website Domain").tag(0)
                        Text("Desktop App").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    if newRuleKindIndex == 1 {
                        HStack(spacing: 8) {
                            Picker("", selection: $selectedInstalledAppId) {
                                Text("— Select from /Applications —").tag("")
                                ForEach(appsProvider.installedApps) { app in
                                    Text(app.name).tag(app.bundleIdentifier)
                                }
                            }
                            .frame(width: 200)
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
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(newRuleKindIndex == 0 ? "Name (e.g. YouTube)" : "App Name", text: $newRuleName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

                        TextField(newRuleKindIndex == 0 ? "Domain (e.g. youtube.com)" : "Bundle ID", text: $newRulePattern)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)

                        Button("Add") {
                            addRule()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newRuleName.isEmpty || newRulePattern.isEmpty)
                    }
                }
            }

            Spacer()

            Text("Mindful breathing delays trigger automatically upon opening target apps/sites.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - 3. Sensory Settings Pane

    private var sensorySettingsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Row 1: Audio Feedback
            HStack(alignment: .top, spacing: 18) {
                Text("Sound:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Play binaural chimes for eye rest & breath cues", isOn: $audio.isSoundEnabled)
                        .toggleStyle(.checkbox)
                        .font(.subheadline)

                    HStack(spacing: 10) {
                        Text("Volume:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)

                        Slider(value: $audio.volume, in: 0.1...1.0)
                            .frame(width: 180)
                            .disabled(!audio.isSoundEnabled)
                            .accessibilityLabel("Sound volume")
                            .accessibilityValue("\(Int(audio.volume * 100)) percent")

                        Text("\(Int(audio.volume * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 40, alignment: .leading)
                    }
                }
            }

            Divider()

            // Row 2: Audio Cues & Testing
            HStack(alignment: .top, spacing: 18) {
                Text("Audio Tests:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button("Test Break Chime") {
                            audio.playBreakStartChime()
                        }
                        .controlSize(.small)
                        .disabled(!audio.isSoundEnabled)

                        Button("Test Breeze Cue") {
                            audio.playBreathingCue()
                        }
                        .controlSize(.small)
                        .disabled(!audio.isSoundEnabled)
                    }

                    Text("Includes the gentle 'Hero' chime for eye rest and 'Breeze' for breathing transitions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("Audio cues respect macOS system volume and mute states.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - 4. Stats Settings Pane

    private var statsSettingsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Row 1: Metrics
            HStack(alignment: .top, spacing: 18) {
                Text("Metrics:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 20) {
                        statItem(label: "Mindful Rest", value: "\(analytics.mindfulMinutes) min", icon: "sparkles")
                        statItem(label: "Breaks Taken", value: "\(analytics.breaksTaken)", icon: "eye.fill")
                    }

                    HStack(spacing: 20) {
                        statItem(label: "Distractions Avoided", value: "\(analytics.distractionsAvoided)", icon: "shield.fill")
                        statItem(label: "Focus Resistance", value: "\(Int(analytics.focusSuccessRate * 100))%", icon: "leaf.fill")
                    }
                }
            }

            Divider()

            // Row 2: Data Management
            HStack(alignment: .top, spacing: 18) {
                Text("Data:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 8) {
                    Button("Reset Statistics", role: .destructive) {
                        analytics.resetStats()
                    }
                    .controlSize(.small)

                    Text("Clears local counters for breaks taken and mindful minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("All statistics are stored locally on your Mac with zero telemetry.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func statItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(ForestTheme.sage)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 170, alignment: .leading)
    }

    // MARK: - 5. Permissions Settings Pane

    private var permissionsSettingsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Row 1: Status
            HStack(alignment: .top, spacing: 18) {
                Text("Status:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isAccessibilityTrusted ? ForestTheme.sage : .yellow)

                        Text(isAccessibilityTrusted ? "Accessibility Access Granted" : "Accessibility Permission Required")
                            .font(.subheadline.weight(.semibold))
                    }

                    Text("Required for universal browser tab extraction (Safari, Chrome, Helium, Dia, etc.).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Row 2: Setup Actions
            HStack(alignment: .top, spacing: 18) {
                Text("Setup:")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Button("Prompt Dialog") {
                            let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(options)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Open System Settings") {
                            openSystemAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Re-check") {
                            isAccessibilityTrusted = AXIsProcessTrusted()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Relaunch App") {
                            relaunchApp()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("How to grant:\n1. Open System Settings ➔ Privacy & Security ➔ Accessibility.\n2. Enable Grasslook.\n3. Click 'Relaunch App' to activate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }

            Spacer()

            Text("Accessibility is only used for local tab monitoring on this Mac.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Helpers

    private func addRule() {
        let kind: TargetRuleKind = (newRuleKindIndex == 0) ? .website(domainPattern: newRulePattern) : .application(bundleIdentifier: newRulePattern)
        let rule = TargetRule(name: newRuleName, kind: kind, delayDuration: 5.0, cooldownDuration: 900.0)
        interception.rules.append(rule)
        newRuleName = ""
        newRulePattern = ""
        selectedInstalledAppId = ""
    }

    private func deleteRule(id: UUID) {
        interception.rules.removeAll { $0.id == id }
    }

    private func updateWindowTitle() {
        NSApp.windows.first(where: { $0.delegate is SettingsWindowController })?.title = selectedTab.title
    }

    private func openSystemAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
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

    var kindDescription: String {
        switch kind {
        case .application(let bundle): return "App: \(bundle)"
        case .website(let domain): return "Site: \(domain)"
        }
    }
}
