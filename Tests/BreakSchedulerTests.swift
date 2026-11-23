// Unit tests for BreakScheduler countdowns, smart pause, sleep/wake, warnings, and postpone.

import XCTest
@testable import Grasslook

private final class MockSchedulerTimeProvider: @unchecked Sendable {
    private var now: Date
    private let lock = NSLock()

    init(initialDate: Date = Date(timeIntervalSince1970: 1000)) {
        self.now = initialDate
    }

    func currentDate() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return now
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor
final class BreakSchedulerTests: XCTestCase {

    func testMicroBreakCountdownAndCompletion() {
        let scheduler = BreakScheduler(
            microInterval: 10.0,
            microDuration: 5.0,
            longInterval: 100.0,
            longDuration: 20.0,
            smartPauseEnabled: false
        )

        var completedBreak: BreakType?
        scheduler.onBreakCompleted = { type in
            completedBreak = type
        }

        if case .countingDown(let remaining, let type) = scheduler.state {
            XCTAssertEqual(remaining, 10.0)
            XCTAssertEqual(type, .micro)
        } else {
            XCTFail("Expected countingDown state")
        }

        scheduler.tick(delta: 5.0)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 5.0)

        scheduler.tick(delta: 5.0)
        if case .inBreak(let type, let remaining) = scheduler.state {
            XCTAssertEqual(type, .micro)
            XCTAssertEqual(remaining, 5.0)
        } else {
            XCTFail("Expected inBreak state, got \(scheduler.state)")
        }

        scheduler.tick(delta: 5.0)
        XCTAssertEqual(completedBreak, .micro)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 10.0)
    }

    func testLongBreakPrecedenceOverMicro() {
        let scheduler = BreakScheduler(
            microInterval: 20.0,
            microDuration: 5.0,
            longInterval: 10.0,
            longDuration: 15.0,
            smartPauseEnabled: false
        )

        scheduler.tick(delta: 10.0)
        if case .inBreak(let type, let remaining) = scheduler.state {
            XCTAssertEqual(type, .long)
            XCTAssertEqual(remaining, 15.0)
        } else {
            XCTFail("Expected long break to trigger, got \(scheduler.state)")
        }
    }

    func testPostponeBreakClearsRemainingAndNotifies() {
        let scheduler = BreakScheduler(
            microInterval: 10.0,
            microDuration: 5.0,
            longInterval: 100.0,
            smartPauseEnabled: false
        )

        var postponedType: BreakType?
        scheduler.onBreakPostponed = { type in
            postponedType = type
        }

        scheduler.triggerBreakNow(type: .micro)
        XCTAssertTrue(scheduler.state.isActiveBreak)
        XCTAssertEqual(scheduler.currentBreakSecondsRemaining, 5.0)

        scheduler.postponeBreak(by: 300.0)
        XCTAssertFalse(scheduler.state.isActiveBreak)
        XCTAssertEqual(scheduler.currentBreakSecondsRemaining, 0)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 300.0)
        XCTAssertEqual(postponedType, .micro)
    }

    func testTriggerBreakNowMidCountdown() {
        let scheduler = BreakScheduler(
            microInterval: 1200.0,
            microDuration: 20.0,
            longInterval: 3600.0,
            longDuration: 300.0,
            smartPauseEnabled: false
        )

        XCTAssertFalse(scheduler.state.isActiveBreak)
        scheduler.triggerBreakNow(type: .micro)
        XCTAssertTrue(scheduler.state.isActiveBreak)
        if case .inBreak(let type, let remaining) = scheduler.state {
            XCTAssertEqual(type, .micro)
            XCTAssertEqual(remaining, 20.0)
        } else {
            XCTFail("Expected inBreak state")
        }
    }

    func testSkipBreak() {
        let scheduler = BreakScheduler(
            microInterval: 10.0,
            microDuration: 5.0,
            smartPauseEnabled: false
        )

        var skippedBreak: BreakType?
        scheduler.onBreakSkipped = { type in
            skippedBreak = type
        }

        scheduler.triggerBreakNow(type: .micro)
        scheduler.skipCurrentBreak()

        XCTAssertEqual(skippedBreak, .micro)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 10.0)
    }

    func testSmartPauseWhenIdle() {
        let mockIdle = MockIdleSensor(currentIdleSeconds: 0)
        let mockMeeting = MockPresentationSensor(isMeetingActive: false)
        let scheduler = BreakScheduler(
            microInterval: 20.0,
            idleThreshold: 100.0,
            smartPauseEnabled: true,
            idleSensor: mockIdle,
            presentationSensor: mockMeeting
        )

        scheduler.tick(delta: 1.0)
        XCTAssertFalse(scheduler.state.isPaused)

        mockIdle.currentIdleSeconds = 120.0
        scheduler.tick(delta: 1.0)
        XCTAssertTrue(scheduler.state.isPaused)
        XCTAssertEqual(scheduler.state, .paused(reason: .idleAwayFromKeyboard))

        mockIdle.currentIdleSeconds = 0.0
        scheduler.tick(delta: 1.0)
        XCTAssertFalse(scheduler.state.isPaused)
    }

    func testSmartPauseWhenInMeeting() {
        let mockIdle = MockIdleSensor(currentIdleSeconds: 0)
        let mockMeeting = MockPresentationSensor(isMeetingActive: false)
        let scheduler = BreakScheduler(
            microInterval: 20.0,
            smartPauseEnabled: true,
            idleSensor: mockIdle,
            presentationSensor: mockMeeting
        )

        scheduler.tick(delta: 1.0)
        XCTAssertFalse(scheduler.state.isPaused)

        mockMeeting.isMeetingActive = true
        scheduler.tick(delta: 1.0)
        XCTAssertTrue(scheduler.state.isPaused)
        XCTAssertEqual(scheduler.state, .paused(reason: .presentationOrVideoCall))

        mockMeeting.isMeetingActive = false
        scheduler.tick(delta: 1.0)
        XCTAssertFalse(scheduler.state.isPaused)
    }

    func testShortSleepResumesPriorCountersWithoutOverdueBreak() {
        let timeProvider = MockSchedulerTimeProvider()
        let scheduler = BreakScheduler(
            microInterval: 100.0,
            microDuration: 20.0,
            longInterval: 300.0,
            longDuration: 120.0,
            smartPauseEnabled: false,
            dateProvider: { timeProvider.currentDate() }
        )

        scheduler.tick(delta: 40.0)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 60.0)
        XCTAssertEqual(scheduler.secondsUntilNextLong, 260.0)

        scheduler.handleSystemWillSleep()
        timeProvider.advance(by: 90.0) // Less than longDuration (120s)
        scheduler.handleSystemDidWake()

        XCTAssertFalse(scheduler.state.isActiveBreak)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 60.0)
        XCTAssertEqual(scheduler.secondsUntilNextLong, 260.0)
    }

    func testLongSleepResetsBothTimers() {
        let timeProvider = MockSchedulerTimeProvider()
        let scheduler = BreakScheduler(
            microInterval: 100.0,
            microDuration: 20.0,
            longInterval: 300.0,
            longDuration: 120.0,
            smartPauseEnabled: false,
            dateProvider: { timeProvider.currentDate() }
        )

        scheduler.tick(delta: 80.0)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 20.0)
        XCTAssertEqual(scheduler.secondsUntilNextLong, 220.0)

        scheduler.handleSystemWillSleep()
        timeProvider.advance(by: 120.0) // >= longDuration
        scheduler.handleSystemDidWake()

        XCTAssertEqual(scheduler.secondsUntilNextMicro, 100.0)
        XCTAssertEqual(scheduler.secondsUntilNextLong, 300.0)
        XCTAssertEqual(scheduler.currentBreakSecondsRemaining, 0)
    }

    func testPreBreakWarningFiresOncePerCycle() {
        let scheduler = BreakScheduler(
            microInterval: 50.0,
            microDuration: 10.0,
            longInterval: 500.0,
            smartPauseEnabled: false
        )
        scheduler.preBreakWarningEnabled = true
        scheduler.preBreakWarningLeadSeconds = 30.0

        var warningCalls: [(BreakType, TimeInterval)] = []
        scheduler.onPreBreakWarning = { type, remaining in
            warningCalls.append((type, remaining))
        }

        // Remaining: 40s (above 30s lead) -> no warning
        scheduler.tick(delta: 10.0)
        XCTAssertEqual(warningCalls.count, 0)

        // Remaining: 30s -> fires once
        scheduler.tick(delta: 10.0)
        XCTAssertEqual(warningCalls.count, 1)
        XCTAssertEqual(warningCalls.first?.0, .micro)
        XCTAssertEqual(warningCalls.first?.1, 30.0)

        // Remaining: 20s, 10s -> does not fire again in same cycle
        scheduler.tick(delta: 10.0)
        scheduler.tick(delta: 10.0)
        XCTAssertEqual(warningCalls.count, 1)

        // Complete break and tick into next cycle's warning window -> fires again
        scheduler.tick(delta: 10.0) // starts break
        scheduler.tick(delta: 10.0) // completes break, resets micro to 50s
        scheduler.tick(delta: 25.0) // remaining: 25s <= 30s
        XCTAssertEqual(warningCalls.count, 2)
    }

    func testPostponeBreakDuringCountdownResetsTimerAndReArmsPreBreakWarning() {
        let scheduler = BreakScheduler(
            microInterval: 60.0,
            microDuration: 15.0,
            longInterval: 600.0,
            smartPauseEnabled: false
        )
        scheduler.preBreakWarningEnabled = true
        scheduler.preBreakWarningLeadSeconds = 30.0

        var warningCalls: [BreakType] = []
        scheduler.onPreBreakWarning = { type, _ in
            warningCalls.append(type)
        }

        var postponedTypes: [BreakType] = []
        scheduler.onBreakPostponed = { type in
            postponedTypes.append(type)
        }

        // Tick into pre-break warning window (remaining: 25s <= 30s)
        scheduler.tick(delta: 35.0)
        XCTAssertEqual(warningCalls.count, 1)
        XCTAssertEqual(scheduler.state, .countingDown(secondsRemaining: 25.0, nextType: .micro))

        // Snooze 5m while still counting down
        scheduler.postponeBreak(by: 300.0)
        XCTAssertEqual(postponedTypes, [.micro])
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 300.0)
        XCTAssertEqual(scheduler.state, .countingDown(secondsRemaining: 300.0, nextType: .micro))

        // Tick down into warning window again (300 - 280 = 20s <= 30s) -> warning re-fires
        scheduler.tick(delta: 280.0)
        XCTAssertEqual(warningCalls.count, 2)
    }
}
