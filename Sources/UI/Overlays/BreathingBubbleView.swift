import SwiftUI

/// Calming mindful breathing bubble view presented upon opening distracting apps or domains.
public struct BreathingBubbleView: View {
    public let appName: String
    public let domainName: String?
    public let duration: TimeInterval
    public let onProceed: () -> Void
    public let onCloseApp: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewOpacity: Double = 0.0
    @State private var phase: BreathingPhase = .inhale
    @State private var scale: CGFloat = 0.8
    @State private var timeRemaining: TimeInterval
    @State private var isBreathingComplete: Bool = false
    @State private var breathTask: Task<Void, Never>?

    private enum BreathingPhase {
        case ready
        case inhale
        case hold
        case exhale
        case complete

        var text: String {
            switch self {
            case .ready:    return "Prepare to Breathe..."
            case .inhale:   return "Breathe In..."
            case .hold:     return "Hold Gently (4s)..."
            case .exhale:   return "Release & Relax..."
            case .complete: return "Intention Set"
            }
        }

        var sfSymbol: String {
            switch self {
            case .ready:    return "leaf.fill"
            case .inhale:   return "wind"
            case .hold:     return "circle.dotted.and.circle"
            case .exhale:   return "lungs.fill"
            case .complete: return "checkmark.circle.fill"
            }
        }
    }

    public init(
        appName: String,
        domainName: String? = nil,
        duration: TimeInterval = 12.0,
        onProceed: @escaping () -> Void,
        onCloseApp: @escaping () -> Void
    ) {
        self.appName = appName
        self.domainName = domainName
        self.duration = duration
        self.onProceed = onProceed
        self.onCloseApp = onCloseApp
        _timeRemaining = State(initialValue: max(12.0, duration))
    }

    public var body: some View {
        ZStack {
            // Liquid Glass Background Blur
            VisualEffectBackgroundView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // Header Alert
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(ForestTheme.sage)
                            .font(.title2)
                        Text(domainName != nil ? "Opening \(domainName!)" : "Opening \(appName)")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Text("Take a mindful pause before proceeding.")
                        .font(.subheadline)
                        .foregroundStyle(ForestTheme.leaf.opacity(0.8))
                }

                // Breathing Bubble Canvas
                ZStack {
                    Circle()
                        .fill(ForestTheme.atmosphericGradient)
                        .frame(width: 230, height: 230)
                        .scaleEffect(scale)

                    Circle()
                        .strokeBorder(phase == .hold ? ForestTheme.sage.opacity(0.85) : ForestTheme.foliage.opacity(0.55), lineWidth: 3)
                        .frame(width: 170, height: 170)
                        .scaleEffect(scale)

                    VStack(spacing: 8) {
                        Image(systemName: isBreathingComplete ? "checkmark.circle.fill" : phase.sfSymbol)
                            .font(.system(size: 32))
                            .foregroundStyle(isBreathingComplete ? ForestTheme.sage : (phase == .hold ? ForestTheme.leaf : .primary))

                        Text(isBreathingComplete ? "Intention Set" : phase.text)
                            .font(.headline.weight(.semibold))
                            .contentTransition(.numericText())

                        if !isBreathingComplete {
                            Text("\(Int(ceil(timeRemaining)))s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ForestTheme.leaf)
                        }
                    }
                }
                .frame(height: 240)

                // Decision Action Card
                VStack(spacing: 12) {
                    Text("Is using this app intentional right now?")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button(action: onCloseApp) {
                        HStack(spacing: 8) {
                            Image(systemName: "leaf.fill")
                            Text(domainName != nil ? "Step Away & Open Blank Tab" : "Step Away & Close App")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ForestTheme.lushGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: ForestTheme.forest.opacity(0.3), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(domainName != nil ? "Step away and open blank tab" : "Step away and close application")

                    Button(action: onProceed) {
                        HStack(spacing: 6) {
                            Image(systemName: isBreathingComplete ? "arrow.forward.circle" : "lock.fill")
                            Text(isBreathingComplete ? "Continue for 15m Session" : "Continue (Complete Breathing to Unlock)")
                                .font(.subheadline.weight(isBreathingComplete ? .medium : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isBreathingComplete ? ForestTheme.forest.opacity(0.25) : Color.primary.opacity(0.04))
                        .foregroundStyle(isBreathingComplete ? ForestTheme.mist : .secondary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isBreathingComplete)
                    .opacity(isBreathingComplete ? 1.0 : 0.5)
                    .animation(.easeInOut(duration: 0.3), value: isBreathingComplete)
                    .accessibilityLabel(isBreathingComplete ? "Continue to application for fifteen minutes" : "Button locked until breathing exercise is complete")
                }
                .frame(maxWidth: 360)
            }
            .padding(40)
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
        }
    }

    private func startBreathingCycle() {
        guard !reduceMotion else {
            viewOpacity = 1.0
            isBreathingComplete = true
            phase = .complete
            return
        }

        // 1-Second Smooth Fade-In
        withAnimation(.easeInOut(duration: 1.0)) {
            viewOpacity = 1.0
        }

        breathTask?.cancel()
        breathTask = Task { @MainActor in
            // Wait 1.0 second for the fade-in animation to complete before starting breathing
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            let inhaleTime: TimeInterval = 4.0
            let holdTime: TimeInterval = 4.0
            let exhaleTime: TimeInterval = 4.0
            let total = inhaleTime + holdTime + exhaleTime
            timeRemaining = total

            // 1. INHALE (4s)
            phase = .inhale
            withAnimation(.easeInOut(duration: inhaleTime)) {
                scale = 1.25
            }

            for _ in 0..<Int(inhaleTime) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                timeRemaining = max(0, timeRemaining - 1)
            }

            // 2. HOLD (4s)
            phase = .hold
            withAnimation(.easeInOut(duration: holdTime * 0.5).repeatForever(autoreverses: true)) {
                scale = 1.28
            }

            for _ in 0..<Int(holdTime) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                timeRemaining = max(0, timeRemaining - 1)
            }

            // 3. EXHALE (4s)
            phase = .exhale
            withAnimation(.easeInOut(duration: exhaleTime)) {
                scale = 0.85
            }

            for _ in 0..<Int(exhaleTime) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                timeRemaining = max(0, timeRemaining - 1)
            }

            // 4. COMPLETE / INTENTION SET
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                phase = .complete
                isBreathingComplete = true
                scale = 1.0
                timeRemaining = 0
            }
        }
    }
}
