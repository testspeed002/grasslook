// Coordinates proactive break countdowns, sleep/wake handling, and break lifecycle.

import AppKit
import Combine
import Foundation

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
    public var preBreakWarningEnabled: Bool = true
    public var preBreakWarningLeadSeconds: TimeInterval = 30.0

    // MARK: - Dependencies
    private let idleSensor: IdleSensorProtocol
    private let presentationSensor: PresentationSensorProtocol
    private let dateProvider: @Sendable () -> Date
    nonisolated(unsafe) private var tickerTask: Task<Void, Never>?
    nonisolated(unsafe) private var sleepObserver: (any NSObjectProtocol)?
    nonisolated(unsafe) private var wakeObserver: (any NSObjectProtocol)?
    private var userPauseExpiry: Date?
    private var sleepStartedAt: Date?
    private var hasFiredPreBreakWarning: Bool = false

    // MARK: - Callbacks
    public var onBreakStarted: ((BreakType) -> Void)?
    public var onBreakCompleted: ((BreakType) -> Void)?
    public var onBreakSkipped: ((BreakType) -> Void)?
    public var onPreBreakWarning: ((BreakType, TimeInterval) -> Void)?
    public var onBreakPostponed: ((BreakType) -> Void)?

    /// Creates a break scheduler with configurable intervals, sensors, and time provider.
    public init(
        microInterval: TimeInterval = BreakType.micro.defaultInterval,
        microDuration: TimeInterval = BreakType.micro.defaultDuration,
        longInterval: TimeInterval = BreakType.long.defaultInterval,
        longDuration: TimeInterval = BreakType.long.defaultDuration,
        idleThreshold: TimeInterval = 180.0,
        smartPauseEnabled: Bool = true,
        idleSensor: IdleSensorProtocol = SystemIdleSensor(),
        presentationSensor: PresentationSensorProtocol = SystemPresentationSensor(),
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.microInterval = microInterval
        self.microDuration = microDuration
        self.longInterval = longInterval
        self.longDuration = longDuration
        self.idleThreshold = idleThreshold
        self.smartPauseEnabled = smartPauseEnabled
        self.idleSensor = idleSensor
        self.presentationSensor = presentationSensor
        self.dateProvider = dateProvider

        self.secondsUntilNextMicro = microInterval
        self.secondsUntilNextLong = longInterval
        self.state = .countingDown(secondsRemaining: microInterval, nextType: .micro)

        registerSleepWakeObservers()
    }

    deinit {
        tickerTask?.cancel()
        let center = NSWorkspace.shared.notificationCenter
        if let sleepObserver = sleepObserver {
            center.removeObserver(sleepObserver)
        }
        if let wakeObserver = wakeObserver {
            center.removeObserver(wakeObserver)
        }
    }

    // MARK: - Lifecycle Controls

    /// Starts the 1-second break countdown ticker.
    public func start() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }
                guard !Task.isCancelled, let self = self else { break }
                self.tick(delta: 1.0)
            }
        }
    }

    /// Stops the countdown ticker and transitions to `.idle`.
    public func stop() {
        tickerTask?.cancel()
        tickerTask = nil
        state = .idle
    }

    /// Advance time by a deterministic delta (used by both the real timer and unit tests).
    public func tick(delta: TimeInterval = 1.0) {
        // 1. Check user manual pause
        if let expiry = userPauseExpiry {
            if dateProvider() < expiry {
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
            break

        case .paused:
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

                if preBreakWarningEnabled,
                   !hasFiredPreBreakWarning,
                   preBreakWarningLeadSeconds > 0,
                   nextRemaining <= preBreakWarningLeadSeconds {
                    hasFiredPreBreakWarning = true
                    onPreBreakWarning?(nextType, nextRemaining)
                }
            }
        }
    }

    // MARK: - Sleep / Wake

    /// Records the timestamp when the Mac enters sleep.
    public func handleSystemWillSleep() {
        sleepStartedAt = dateProvider()
    }

    /// Resets timers after a long sleep (>= `longDuration`) or resumes prior counters after a short sleep.
    public func handleSystemDidWake() {
        guard let sleepStart = sleepStartedAt else { return }
        sleepStartedAt = nil

        let sleepDuration = max(0, dateProvider().timeIntervalSince(sleepStart))
        if sleepDuration >= longDuration {
            secondsUntilNextMicro = microInterval
            secondsUntilNextLong = longInterval
            currentBreakSecondsRemaining = 0
            hasFiredPreBreakWarning = false

            if state != .idle && !state.isPaused {
                let nextType: BreakType = (secondsUntilNextLong < secondsUntilNextMicro) ? .long : .micro
                let nextRemaining = (nextType == .long) ? secondsUntilNextLong : secondsUntilNextMicro
                state = .countingDown(secondsRemaining: nextRemaining, nextType: nextType)
            }
        }
    }

    // MARK: - Actions

    /// Immediately starts a break of the given type.
    public func triggerBreakNow(type: BreakType) {
        startBreak(type: type)
    }

    /// Postpones the active or due break by `seconds` and clears the active break countdown.
    public func postponeBreak(by seconds: TimeInterval = 300.0) {
        let postponedType: BreakType
        switch state {
        case .inBreak(let type, _), .breakDue(let type), .countingDown(_, let type):
            postponedType = type
        default:
            return
        }

        if postponedType == .micro {
            secondsUntilNextMicro = seconds
        } else {
            secondsUntilNextLong = seconds
        }
        currentBreakSecondsRemaining = 0
        hasFiredPreBreakWarning = false

        let nextType: BreakType = (secondsUntilNextLong < secondsUntilNextMicro) ? .long : .micro
        let nextRemaining = (nextType == .long) ? secondsUntilNextLong : secondsUntilNextMicro
        state = .countingDown(secondsRemaining: nextRemaining, nextType: nextType)
        onBreakPostponed?(postponedType)
    }

    /// Skips the active or due break and resets its interval.
    public func skipCurrentBreak() {
        if case .inBreak(let type, _) = state {
            onBreakSkipped?(type)
            resetTimers(after: type)
        } else if case .breakDue(let type) = state {
            onBreakSkipped?(type)
            resetTimers(after: type)
        }
    }

    /// Marks the active break as completed and resets its interval.
    public func completeCurrentBreak() {
        if case .inBreak(let type, _) = state {
            onBreakCompleted?(type)
            resetTimers(after: type)
        }
    }

    /// Pauses break countdowns optionally for `duration` seconds.
    public func pause(for duration: TimeInterval? = nil) {
        if let duration = duration {
            userPauseExpiry = dateProvider().addingTimeInterval(duration)
            state = .paused(reason: .userManuallyPaused(until: userPauseExpiry))
        } else {
            userPauseExpiry = nil
            state = .paused(reason: .userManuallyPaused(until: nil))
        }
    }

    /// Resumes break countdowns from a manual pause.
    public func resume() {
        userPauseExpiry = nil
        let nextType: BreakType = (secondsUntilNextLong <= secondsUntilNextMicro) ? .long : .micro
        let nextSeconds = (nextType == .long) ? secondsUntilNextLong : secondsUntilNextMicro
        state = .countingDown(secondsRemaining: nextSeconds, nextType: nextType)
    }

    // MARK: - Private Helpers

    private func registerSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWillSleep()
            }
        }

        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemDidWake()
            }
        }
    }

    private func startBreak(type: BreakType) {
        let duration = (type == .micro) ? microDuration : longDuration
        currentBreakSecondsRemaining = duration
        hasFiredPreBreakWarning = false
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
        currentBreakSecondsRemaining = 0
        hasFiredPreBreakWarning = false
        let nextType: BreakType = (secondsUntilNextLong < secondsUntilNextMicro) ? .long : .micro
        let nextRemaining = (nextType == .long) ? secondsUntilNextLong : secondsUntilNextMicro
        state = .countingDown(secondsRemaining: nextRemaining, nextType: nextType)
    }
}
