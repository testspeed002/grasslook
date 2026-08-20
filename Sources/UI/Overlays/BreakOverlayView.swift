import SwiftUI

/// Full-screen break overlay presenting eye relaxation or posture stretch guidance with a live animated countdown.
public struct BreakOverlayView: View {
    public let type: BreakType
    public let duration: TimeInterval
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

    public init(
        type: BreakType,
        duration: TimeInterval,
        secondsRemaining: TimeInterval? = nil,
        onSkip: @escaping () -> Void,
        onPostpone: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.type = type
        self.duration = duration
        self.onSkip = onSkip
        self.onPostpone = onPostpone
        self.onComplete = onComplete
        _secondsRemaining = State(initialValue: secondsRemaining ?? duration)
    }

    public var body: some View {
        ZStack {
            // Liquid Glass Background
            VisualEffectBackgroundView(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: type.sfSymbol)
                            .foregroundStyle(ForestTheme.sage)
                            .font(.title2)
                        Text(type.title)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(type == .micro ? "The 20-20-20 Rule" : "Physical Reset")
                        .font(.subheadline)
                        .foregroundStyle(ForestTheme.leaf.opacity(0.8))
                }

                // Central Countdown Ring
                ZStack {
                    Circle()
                        .stroke(ForestTheme.forest.opacity(0.2), lineWidth: 8)
                        .frame(width: 180, height: 180)

                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            ForestTheme.lushGradient,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 1.0), value: progress)

                    VStack(spacing: 4) {
                        Text(formattedTime(secondsRemaining))
                            .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())

                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(ForestTheme.leaf)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time remaining: \(formattedTime(secondsRemaining))")

                // Guidance Card
                Text(type.guidance)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)

                // Actions
                HStack(spacing: 16) {
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

                    Button(action: onPostpone) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Postpone 5m")
                        }
                        .frame(width: 150)
                        .padding(.vertical, 10)
                        .background(ForestTheme.forest.opacity(0.35))
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

                withAnimation(.linear(duration: 1.0)) {
                    secondsRemaining = max(0, secondsRemaining - 1)
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
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return String(format: "%d:%02d", m, s)
        }
        return "\(s)s"
    }
}
