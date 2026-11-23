// Full-screen break overlay view with countdown ring, strict mode, and dusk cue.

import SwiftUI

/// Full-screen break overlay with timer and guidance.
public struct BreakOverlayView: View {
    public let type: BreakType
    public let duration: TimeInterval
    public let strictMode: Bool
    public let isDuskCueActive: Bool
    public let onSkip: () -> Void
    public let onPostpone: () -> Void
    public let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewOpacity: Double = 0.0
    @State private var secondsRemaining: TimeInterval
    @State private var countdownTask: Task<Void, Never>?

    private var progress: Double {
        guard duration > 0 else { return 1.0 }
        return max(0.0, min(1.0, 1.0 - (secondsRemaining / duration)))
    }

    private var accentColor: Color {
        isDuskCueActive ? Color(red: 0.68, green: 0.60, blue: 0.86) : ForestTheme.sage
    }

    private var secondaryAccentColor: Color {
        isDuskCueActive ? Color(red: 0.76, green: 0.70, blue: 0.90) : ForestTheme.leaf
    }

    private var ringGradient: LinearGradient {
        if isDuskCueActive {
            return LinearGradient(
                colors: [Color(red: 0.38, green: 0.34, blue: 0.58), accentColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return ForestTheme.lushGradient
    }

    /// Creates a break overlay view.
    public init(
        type: BreakType,
        duration: TimeInterval,
        secondsRemaining: TimeInterval? = nil,
        strictMode: Bool = false,
        isDuskCueActive: Bool = false,
        onSkip: @escaping () -> Void,
        onPostpone: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.type = type
        self.duration = duration
        self.strictMode = strictMode
        self.isDuskCueActive = isDuskCueActive
        self.onSkip = onSkip
        self.onPostpone = onPostpone
        self.onComplete = onComplete
        _secondsRemaining = State(initialValue: secondsRemaining ?? duration)
    }

    public var body: some View {
        ZStack {
            VisualEffectBackgroundView(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()

            if isDuskCueActive {
                Color(red: 0.08, green: 0.07, blue: 0.16)
                    .opacity(0.28)
                    .ignoresSafeArea()
            }

            VStack(spacing: 32) {
                if isDuskCueActive {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        HStack(spacing: 6) {
                            Image(systemName: "moon.stars.fill")
                                .font(.caption)
                            Text(context.date, style: .time)
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(secondaryAccentColor.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(accentColor.opacity(0.14))
                        .clipShape(Capsule())
                    }
                }

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: type.sfSymbol)
                            .foregroundStyle(accentColor)
                            .font(.title2)
                        Text(type.title)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(type == .micro ? "20-20-20 Rule" : "Break")
                        .font(.subheadline)
                        .foregroundStyle(secondaryAccentColor.opacity(0.85))
                }

                ZStack {
                    Circle()
                        .stroke((isDuskCueActive ? accentColor : ForestTheme.forest).opacity(0.2), lineWidth: 8)
                        .frame(width: 180, height: 180)

                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            ringGradient,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 1.0), value: progress)

                    VStack(spacing: 4) {
                        Text(formattedTime(secondsRemaining))
                            .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .contentTransition(reduceMotion ? .identity : .numericText())

                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(secondaryAccentColor)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time remaining: \(formattedTime(secondsRemaining))")

                Text(type.guidance)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)

                HStack(spacing: 16) {
                    if !strictMode {
                        Button(action: onSkip) {
                            Text("Skip")
                                .frame(width: 120)
                                .padding(.vertical, 10)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                        .accessibilityLabel("Skip break")
                    }

                    Button(action: onPostpone) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Postpone 5m")
                        }
                        .frame(width: 150)
                        .padding(.vertical, 10)
                        .background((isDuskCueActive ? accentColor : ForestTheme.forest).opacity(0.35))
                        .foregroundStyle(ForestTheme.mist)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Postpone break by 5 minutes")
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
            )
            .frame(maxWidth: 520)
        }
        .opacity(viewOpacity)
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            countdownTask?.cancel()
        }
    }

    private func startCountdown() {
        guard !reduceMotion else {
            viewOpacity = 1.0
            runTimerLoop()
            return
        }

        withAnimation(.easeInOut(duration: 0.6)) {
            viewOpacity = 1.0
        }

        runTimerLoop()
    }

    private func runTimerLoop() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            while secondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                if reduceMotion {
                    secondsRemaining = max(0, secondsRemaining - 1)
                } else {
                    withAnimation(.linear(duration: 1.0)) {
                        secondsRemaining = max(0, secondsRemaining - 1)
                    }
                }

                if secondsRemaining == 0 {
                    onComplete()
                    break
                }
            }
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(seconds))
        let minutes = total / 60
        let secs = total % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        }
        return "\(secs)s"
    }
}
