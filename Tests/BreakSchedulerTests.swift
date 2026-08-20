import XCTest
@testable import Grasslook

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

        // Initially counting down for micro-break
        if case .countingDown(let remaining, let type) = scheduler.state {
            XCTAssertEqual(remaining, 10.0)
            XCTAssertEqual(type, .micro)
        } else {
            XCTFail("Expected countingDown state")
        }

        // Advance 5 seconds
        scheduler.tick(delta: 5.0)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 5.0)

        // Advance 5 more seconds -> Should trigger micro break
        scheduler.tick(delta: 5.0)
        if case .inBreak(let type, let remaining) = scheduler.state {
            XCTAssertEqual(type, .micro)
            XCTAssertEqual(remaining, 5.0)
        } else {
            XCTFail("Expected inBreak state, got \(scheduler.state)")
        }

        // Advance break duration by 5s -> Should complete break
        scheduler.tick(delta: 5.0)
        XCTAssertEqual(completedBreak, .micro)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 10.0)
    }

    func testLongBreakPrecedenceOverMicro() {
        let scheduler = BreakScheduler(
            microInterval: 20.0,
            microDuration: 5.0,
            longInterval: 10.0, // Long break due first
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

    func testPostponeBreak() {
        let scheduler = BreakScheduler(
            microInterval: 10.0,
            microDuration: 5.0,
            longInterval: 100.0,
            smartPauseEnabled: false
        )

        scheduler.triggerBreakNow(type: .micro)
        XCTAssertTrue(scheduler.state.isActiveBreak)

        // Postpone by 300 seconds (5m)
        scheduler.postponeBreak(by: 300.0)
        XCTAssertFalse(scheduler.state.isActiveBreak)
        XCTAssertEqual(scheduler.secondsUntilNextMicro, 300.0)
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
        let scheduler = BreakScheduler(
            microInterval: 20.0,
            idleThreshold: 100.0,
            smartPauseEnabled: true,
            idleSensor: mockIdle
        )

        scheduler.tick(delta: 1.0)
        XCTAssertFalse(scheduler.state.isPaused)

        // Simulate user idle for 120s
        mockIdle.currentIdleSeconds = 120.0
        scheduler.tick(delta: 1.0)
        XCTAssertTrue(scheduler.state.isPaused)
        XCTAssertEqual(scheduler.state, .paused(reason: .idleAwayFromKeyboard))

        // Simulate user activity returning
        mockIdle.currentIdleSeconds = 0.0
        scheduler.tick(delta: 1.0)
        XCTAssertFalse(scheduler.state.isPaused)
    }

    func testSmartPauseWhenInMeeting() {
        let mockMeeting = MockPresentationSensor(isMeetingActive: false)
        let scheduler = BreakScheduler(
            microInterval: 20.0,
            smartPauseEnabled: true,
            presentationSensor: mockMeeting
        )

        scheduler.tick(delta: 1.0)
        XCTAssertFalse(scheduler.state.isPaused)

        // Simulate meeting started
        mockMeeting.isMeetingActive = true
        scheduler.tick(delta: 1.0)
        XCTAssertTrue(scheduler.state.isPaused)
        XCTAssertEqual(scheduler.state, .paused(reason: .presentationOrVideoCall))

        // Meeting ended
        mockMeeting.isMeetingActive = false
        scheduler.tick(delta: 1.0)
        XCTAssertFalse(scheduler.state.isPaused)
    }
}
