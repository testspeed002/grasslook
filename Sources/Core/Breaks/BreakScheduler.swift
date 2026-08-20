import Foundation
import Combine

/// Coordinates proactive break countdowns, smart pause sensors, and break lifecycle.
@MainActor
public final class BreakScheduler: ObservableObject {
    // MARK: - Published Properties
    @Published public private(set) var state: BreakState = .idle
    @Published public private(set) var secondsUntilNextMicro: TimeInterval
    @Published public private(set) var secondsUntilNextLong: TimeInterval
    @Published public private(set) var currentBreakSecondsRemaining: TimeInterval = 0

    // MARK: - Configuration
    public var microInterval: TimeInterval
    public var microDuration: TimeInterval
    public var longInterval: TimeInterval
    public var longDuration: TimeInterval
    public var idleThreshold: TimeInterval
    public var smartPauseEnabled: Bool

    // MARK: - Dependencies
    private let idleSensor: IdleSensorProtocol
    private let presentationSensor: PresentationSensorProtocol
    private var tickerTask: Task<Void, Never>?
    private var userPauseExpiry: Date?

    // MARK: - Callbacks
    public var onBreakStarted: ((BreakType) -> Void)?
    public var onBreakCompleted: ((BreakType) -> Void)?
    public var onBreakSkipped: ((BreakType) -> Void)?

    public init(
        microInterval: TimeInterval = BreakType.micro.defaultInterval,
        microDuration: TimeInterval = BreakType.micro.defaultDuration,
        longInterval: TimeInterval = BreakType.long.defaultInterval,
        longDuration: TimeInterval = BreakType.long.defaultDuration,
        idleThreshold: TimeInterval = 180.0,
        smartPauseEnabled: Bool = true,
        idleSensor: IdleSensorProtocol = SystemIdleSensor(),
        presentationSensor: PresentationSensorProtocol = SystemPresentationSensor()
    ) {
        self.microInterval = microInterval
        self.microDuration = microDuration
        self.longInterval = longInterval
        self.longDuration = longDuration
        self.idleThreshold = idleThreshold
        self.smartPauseEnabled = smartPauseEnabled
        self.idleSensor = idleSensor
        self.presentationSensor = presentationSensor

        self.secondsUntilNextMicro = microInterval
        self.secondsUntilNextLong = longInterval
        self.state = .countingDown(secondsRemaining: microInterval, nextType: .micro)
    }

    deinit {
        tickerTask?.cancel()
    }

    // MARK: - Lifecycle Controls

    public func start() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled, let self = self else { break }
                    self.tick(delta: 1.0)
                } catch {
                    break
                }
            }
        }
    }

    public func stop() {
        tickerTask?.cancel()
        tickerTask = nil
        state = .idle
    }

    /// Advance time by a deterministic delta (used by both the real timer and unit tests).
    public func tick(delta: TimeInterval = 1.0) {
        // 1. Check user manual pause
        if let expiry = userPauseExpiry {
            if Date() < expiry {
                state = .paused(reason: .userManuallyPaused(until: expiry))
                return
            } else {
                userPauseExpiry = nil
            }
        }

        // 2. Check smart pause sensors (if in counting down mode and smart pause is enabled)
        if smartPauseEnabled {
            let idleSecs = idleSensor.secondsSinceLastActivity()
            if idleSecs >= idleThreshold {
                state = .paused(reason: .idleAwayFromKeyboard)
                return
            }

            if presentationSensor.isPresentationOrMeetingActive() {
                state = .paused(reason: .presentationOrVideoCall)
                return
            }
        }

        // 3. Process Active Break vs Countdown
        switch state {
        case .idle:
            // Remain idle
            break

        case .paused:
            // Sensors cleared; resume countdown
            let nextType: BreakType = (secondsUntilNextLong <= secondsUntilNextMicro) ? .long : .micro
            let nextSeconds = (nextType == .long) ? secondsUntilNextLong : secondsUntilNextMicro
            state = .countingDown(secondsRemaining: nextSeconds, nextType: nextType)

        case .inBreak(let type, let remaining):
            let updated = remaining - delta
            if updated <= 0 {
                completeCurrentBreak()
            } else {
                currentBreakSecondsRemaining = updated
                state = .inBreak(type: type, secondsRemaining: updated)
            }

        case .breakDue(let type):
            startBreak(type: type)

        case .countingDown:
            secondsUntilNextMicro = max(0, secondsUntilNextMicro - delta)
            secondsUntilNextLong = max(0, secondsUntilNextLong - delta)

            if secondsUntilNextLong <= 0 {
                state = .breakDue(type: .long)
                startBreak(type: .long)
            } else if secondsUntilNextMicro <= 0 {
                state = .breakDue(type: .micro)
                startBreak(type: .micro)
            } else {
                let nextType: BreakType = (secondsUntilNextLong < secondsUntilNextMicro) ? .long : .micro
                let nextRemaining = (nextType == .long) ? secondsUntilNextLong : secondsUntilNextMicro
                state = .countingDown(secondsRemaining: nextRemaining, nextType: nextType)
            }
        }
    }

    // MARK: - Actions

    public func triggerBreakNow(type: BreakType) {
        startBreak(type: type)
    }

    public func postponeBreak(by seconds: TimeInterval = 300.0) {
        if case .inBreak(let type, _) = state {
            if type == .micro {
                secondsUntilNextMicro = seconds
            } else {
                secondsUntilNextLong = seconds
            }
            state = .countingDown(secondsRemaining: seconds, nextType: type)
        } else if case .breakDue(let type) = state {
            if type == .micro {
                secondsUntilNextMicro = seconds
            } else {
                secondsUntilNextLong = seconds
            }
            state = .countingDown(secondsRemaining: seconds, nextType: type)
        }
    }

    public func skipCurrentBreak() {
        if case .inBreak(let type, _) = state {
            onBreakSkipped?(type)
            resetTimers(after: type)
        } else if case .breakDue(let type) = state {
            onBreakSkipped?(type)
            resetTimers(after: type)
        }
    }

    public func completeCurrentBreak() {
        if case .inBreak(let type, _) = state {
            onBreakCompleted?(type)
            resetTimers(after: type)
        }
    }

    public func pause(for duration: TimeInterval? = nil) {
        if let duration = duration {
            userPauseExpiry = Date().addingTimeInterval(duration)
            state = .paused(reason: .userManuallyPaused(until: userPauseExpiry))
        } else {
            userPauseExpiry = nil
            state = .paused(reason: .userManuallyPaused(until: nil))
        }
    }

    public func resume() {
        userPauseExpiry = nil
        let nextType: BreakType = (secondsUntilNextLong <= secondsUntilNextMicro) ? .long : .micro
        let nextSeconds = (nextType == .long) ? secondsUntilNextLong : secondsUntilNextMicro
        state = .countingDown(secondsRemaining: nextSeconds, nextType: nextType)
    }

    // MARK: - Private Helpers

    private func startBreak(type: BreakType) {
        let duration = (type == .micro) ? microDuration : longDuration
        currentBreakSecondsRemaining = duration
        state = .inBreak(type: type, secondsRemaining: duration)
        onBreakStarted?(type)
    }

    private func resetTimers(after type: BreakType) {
        if type == .micro {
            secondsUntilNextMicro = microInterval
        } else {
            secondsUntilNextLong = longInterval
            secondsUntilNextMicro = microInterval
        }
        let nextType: BreakType = (secondsUntilNextLong < secondsUntilNextMicro) ? .long : .micro
        let nextRemaining = (nextType == .long) ? secondsUntilNextLong : secondsUntilNextMicro
        state = .countingDown(secondsRemaining: nextRemaining, nextType: nextType)
    }
}
