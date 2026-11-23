// Breathing delay and curfew break-glass overlay for blocked apps and websites.

import SwiftUI

/// Breathing delay view for blocked apps and websites.
public struct BreathingBubbleView: View {
    public let appName: String
    public let domainName: String?
    public let duration: TimeInterval
    public let cooldownDuration: TimeInterval
    public let focusPhase: FocusPhase
    public let isStrictCurfew: Bool
    public let isDuskCueActive: Bool
    public let canUseBreakGlass: Bool
    public let breakGlassWaitSeconds: TimeInterval
    public let breakGlassMinNoteLength: Int
    public let onProceed: () -> Void
    public let onBreakGlass: ((String) -> Void)?
    public let onCloseApp: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewOpacity: Double = 0.0
    @State private var phase: BreathingPhase = .inhale
    @State private var scale: CGFloat = 0.85
    @State private var timeRemaining: TimeInterval
    @State private var isBreathingComplete: Bool = false
    @State private var breathTask: Task<Void, Never>?

    @State private var isBreakGlassExpanded: Bool = false
    @State private var breakGlassSecondsRemaining: TimeInterval
    @State private var breakGlassNote: String = ""
    @State private var breakGlassTask: Task<Void, Never>?

    private enum BreathingPhase {
        case ready
        case inhale
        case hold
        case exhale
        case complete

        var text: String {
            switch self {
            case .ready: return "Get ready..."
            case .inhale: return "Inhale"
            case .hold: return "Hold"
            case .exhale: return "Exhale"
            case .complete: return "Ready"
            }
        }

        var sfSymbol: String {
            switch self {
            case .ready: return "leaf.fill"
            case .inhale: return "wind"
            case .hold: return "circle.dotted.and.circle"
            case .exhale: return "lungs.fill"
            case .complete: return "checkmark.circle.fill"
            }
        }
    }

    private var usesDuskStyling: Bool {
        isDuskCueActive || focusPhase == .windDown || focusPhase == .curfew
    }

    private var accentColor: Color {
        usesDuskStyling ? Color(red: 0.68, green: 0.60, blue: 0.86) : ForestTheme.sage
    }

    private var secondaryAccentColor: Color {
        usesDuskStyling ? Color(red: 0.76, green: 0.70, blue: 0.90) : ForestTheme.leaf
    }

    private var primaryActionGradient: LinearGradient {
        if usesDuskStyling {
            return LinearGradient(
                colors: [Color(red: 0.25, green: 0.23, blue: 0.42), accentColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return ForestTheme.lushGradient
    }

    private var bubbleFillGradient: RadialGradient {
        if usesDuskStyling {
            return RadialGradient(
                colors: [
                    accentColor.opacity(0.36),
                    Color(red: 0.22, green: 0.20, blue: 0.38).opacity(0.22),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 130
            )
        }
        return ForestTheme.atmosphericGradient
    }

    private var targetDisplayTitle: String {
        if let domainName {
            return "Opening \(domainName)"
        }
        return "Opening \(appName)"
    }

    private var closeActionLabel: String {
        domainName != nil ? "Close Tab" : "Close App"
    }

    private var trimmedBreakGlassNote: String {
        breakGlassNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitBreakGlass: Bool {
        breakGlassSecondsRemaining <= 0 && trimmedBreakGlassNote.count >= breakGlassMinNoteLength
    }

    /// Creates a breathing delay overlay view.
    public init(
        appName: String,
        domainName: String? = nil,
        duration: TimeInterval = 12.0,
        cooldownDuration: TimeInterval = 900.0,
        focusPhase: FocusPhase = .daytime,
        isStrictCurfew: Bool = false,
        isDuskCueActive: Bool = false,
        canUseBreakGlass: Bool = false,
        breakGlassWaitSeconds: TimeInterval = 30.0,
        breakGlassMinNoteLength: Int = 4,
        onProceed: @escaping () -> Void,
        onBreakGlass: ((String) -> Void)? = nil,
        onCloseApp: @escaping () -> Void
    ) {
        self.appName = appName
        self.domainName = domainName
        self.duration = duration
        self.cooldownDuration = cooldownDuration
        self.focusPhase = focusPhase
        self.isStrictCurfew = isStrictCurfew
        self.isDuskCueActive = isDuskCueActive
        self.canUseBreakGlass = canUseBreakGlass
        self.breakGlassWaitSeconds = breakGlassWaitSeconds
        self.breakGlassMinNoteLength = breakGlassMinNoteLength
        self.onProceed = onProceed
        self.onBreakGlass = onBreakGlass
        self.onCloseApp = onCloseApp
        _timeRemaining = State(initialValue: max(1.0, duration))
        _breakGlassSecondsRemaining = State(initialValue: max(0.0, breakGlassWaitSeconds))
    }

    public var body: some View {
        ZStack {
            VisualEffectBackgroundView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            if usesDuskStyling {
                Color(red: 0.08, green: 0.07, blue: 0.16)
                    .opacity(0.30)
                    .ignoresSafeArea()
            }

            VStack(spacing: 24) {
                if usesDuskStyling {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        HStack(spacing: 6) {
                            Image(systemName: "moon.stars.fill")
                                .font(.caption)
                            Text(context.date, style: .time)
                                .font(.caption.monospacedDigit())
                            if focusPhase == .curfew {
                                Text("Curfew")
                                    .font(.caption.weight(.medium))
                            } else if focusPhase == .windDown {
                                Text("Wind-Down")
                                    .font(.caption.weight(.medium))
                            }
                        }
                        .foregroundStyle(secondaryAccentColor.opacity(0.95))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(accentColor.opacity(0.14))
                        .clipShape(Capsule())
                    }
                }

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(accentColor)
                            .font(.title2)
                        Text(targetDisplayTitle)
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Text("Take a breath before continuing.")
                        .font(.subheadline)
                        .foregroundStyle(secondaryAccentColor.opacity(0.85))
                }

                ZStack {
                    Circle()
                        .fill(bubbleFillGradient)
                        .frame(width: 220, height: 220)
                        .scaleEffect(reduceMotion ? 1.0 : scale)

                    Circle()
                        .strokeBorder(
                            phase == .hold ? accentColor.opacity(0.85) : secondaryAccentColor.opacity(0.55),
                            lineWidth: 3
                        )
                        .frame(width: 164, height: 164)
                        .scaleEffect(reduceMotion ? 1.0 : scale)

                    VStack(spacing: 8) {
                        Image(systemName: isBreathingComplete ? "checkmark.circle.fill" : phase.sfSymbol)
                            .font(.system(size: 32))
                            .foregroundStyle(isBreathingComplete ? accentColor : (phase == .hold ? secondaryAccentColor : .primary))

                        Text(isBreathingComplete ? "Ready" : phase.text)
                            .font(.headline.weight(.semibold))
                            .contentTransition(reduceMotion ? .identity : .numericText())

                        if !isBreathingComplete {
                            Text("\(Int(ceil(timeRemaining)))s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(secondaryAccentColor)
                        }
                    }
                }
                .frame(height: 224)

                VStack(spacing: 12) {
                    Text(isStrictCurfew ? "Curfew is active. Rest comes first." : "Do you still want to open this?")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button(action: onCloseApp) {
                        HStack(spacing: 8) {
                            Image(systemName: "leaf.fill")
                            Text(closeActionLabel)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(primaryActionGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: (usesDuskStyling ? accentColor : ForestTheme.forest).opacity(0.3), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(domainName != nil ? "Close tab" : "Close application")

                    if isStrictCurfew {
                        curfewControls
                    } else {
                        Button(action: onProceed) {
                            HStack(spacing: 6) {
                                Image(systemName: isBreathingComplete ? "arrow.forward.circle" : "lock.fill")
                                Text(isBreathingComplete ? "Continue (\(formattedCooldown(cooldownDuration)))" : "Continue")
                                    .font(.subheadline.weight(isBreathingComplete ? .medium : .regular))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isBreathingComplete ? (usesDuskStyling ? accentColor : ForestTheme.forest).opacity(0.25) : Color.primary.opacity(0.04))
                            .foregroundStyle(isBreathingComplete ? ForestTheme.mist : .secondary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isBreathingComplete)
                        .opacity(isBreathingComplete ? 1.0 : 0.5)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isBreathingComplete)
                        .accessibilityLabel(
                            isBreathingComplete
                                ? "Continue for \(formattedCooldown(cooldownDuration))"
                                : "Locked until breathing exercise finishes"
                        )
                    }
                }
                .frame(maxWidth: 360)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 15)
            )
            .frame(maxWidth: 480)
        }
        .opacity(viewOpacity)
        .onAppear {
            startBreathingCycle()
        }
        .onDisappear {
            breathTask?.cancel()
            breakGlassTask?.cancel()
        }
    }

    @ViewBuilder
    private var curfewControls: some View {
        if canUseBreakGlass {
            if isBreakGlassExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if breakGlassSecondsRemaining > 0 {
                        Text("Break-glass available in \(Int(ceil(breakGlassSecondsRemaining)))s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(secondaryAccentColor)
                    } else {
                        Text("Write a short intention note to unlock one pass:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Why do you need access right now?", text: $breakGlassNote)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Minimum \(breakGlassMinNoteLength) characters")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Use Break-Glass Pass") {
                            onBreakGlass?(trimmedBreakGlassNote)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canSubmitBreakGlass)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Button {
                    expandBreakGlass()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                        Text("Emergency Break-Glass")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("Break-glass passes used for tonight. Access resets when curfew ends.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func expandBreakGlass() {
        isBreakGlassExpanded = true
        breakGlassTask?.cancel()
        breakGlassSecondsRemaining = max(0.0, breakGlassWaitSeconds)
        guard breakGlassSecondsRemaining > 0 else { return }

        breakGlassTask = Task { @MainActor in
            while breakGlassSecondsRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                breakGlassSecondsRemaining = max(0, breakGlassSecondsRemaining - 1)
            }
        }
    }

    private func startBreathingCycle() {
        breathTask?.cancel()
        let total = max(1.0, duration)
        timeRemaining = total
        isBreathingComplete = false
        scale = reduceMotion ? 1.0 : 0.85

        if reduceMotion {
            viewOpacity = 1.0
        } else {
            withAnimation(.easeInOut(duration: 1.0)) {
                viewOpacity = 1.0
            }
        }

        breathTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
            }

            let inhaleTime = total * (4.0 / 12.0)
            let holdTime = total * (4.0 / 12.0)
            let exhaleTime = max(0.0, total - inhaleTime - holdTime)

            await runPhase(.inhale, duration: inhaleTime, targetScale: 1.25)
            guard !Task.isCancelled else { return }

            await runPhase(.hold, duration: holdTime, targetScale: 1.28, repeatPulse: true)
            guard !Task.isCancelled else { return }

            await runPhase(.exhale, duration: exhaleTime, targetScale: 0.85)
            guard !Task.isCancelled else { return }

            if reduceMotion {
                phase = .complete
                isBreathingComplete = true
                scale = 1.0
                timeRemaining = 0
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    phase = .complete
                    isBreathingComplete = true
                    scale = 1.0
                    timeRemaining = 0
                }
            }
        }
    }

    private func runPhase(
        _ targetPhase: BreathingPhase,
        duration phaseDuration: TimeInterval,
        targetScale: CGFloat,
        repeatPulse: Bool = false
    ) async {
        guard phaseDuration > 0, !Task.isCancelled else { return }
        phase = targetPhase

        if !reduceMotion {
            if repeatPulse {
                withAnimation(.easeInOut(duration: max(0.5, phaseDuration * 0.5)).repeatForever(autoreverses: true)) {
                    scale = targetScale
                }
            } else {
                withAnimation(.easeInOut(duration: phaseDuration)) {
                    scale = targetScale
                }
            }
        }

        var remainingInPhase = phaseDuration
        while remainingInPhase > 0 && !Task.isCancelled {
            let step = min(1.0, remainingInPhase)
            let nanos = UInt64((step * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            remainingInPhase -= step
            timeRemaining = max(0, timeRemaining - step)
        }
    }

    private func formattedCooldown(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 {
            let hours = Int(seconds / 3600)
            let mins = Int((seconds.truncatingRemainder(dividingBy: 3600) / 60).rounded())
            if mins > 0 {
                return "\(hours) hr \(mins) min"
            }
            return "\(hours) hr"
        }
        if seconds >= 60 {
            let minutes = max(1, Int((seconds / 60).rounded()))
            return "\(minutes) min"
        }
        return "\(max(1, Int(seconds.rounded())))s"
    }
}
