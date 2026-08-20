import XCTest
@testable import Grasslook

@MainActor
final class AnalyticsTests: XCTestCase {

    func testAnalyticsRecordingAndCompliance() {
        let testDefaults = UserDefaults(suiteName: "GrasslookTests.Analytics")!
        testDefaults.removePersistentDomain(forName: "GrasslookTests.Analytics")

        let analytics = AnalyticsManager(userDefaults: testDefaults)

        XCTAssertEqual(analytics.breaksTaken, 0)
        XCTAssertEqual(analytics.breaksSkipped, 0)
        XCTAssertEqual(analytics.mindfulMinutes, 0)

        // Record 2 breaks taken (20s each) and 1 skipped
        analytics.recordBreakTaken(type: .micro, duration: 20.0)
        analytics.recordBreakTaken(type: .micro, duration: 20.0)
        analytics.recordBreakSkipped(type: .micro)

        XCTAssertEqual(analytics.breaksTaken, 2)
        XCTAssertEqual(analytics.breaksSkipped, 1)
        XCTAssertEqual(analytics.breakComplianceRate, 2.0 / 3.0, accuracy: 0.01)

        // Record distractions avoided (5s delay) and continued (5s delay)
        analytics.recordDistractionAvoided(delayDuration: 5.0)
        analytics.recordDistractionAvoided(delayDuration: 5.0)
        analytics.recordDistractionContinued(delayDuration: 5.0)

        XCTAssertEqual(analytics.distractionsAvoided, 2)
        XCTAssertEqual(analytics.distractionsContinued, 1)
        XCTAssertEqual(analytics.focusSuccessRate, 2.0 / 3.0, accuracy: 0.01)

        // Reset
        analytics.resetStats()
        XCTAssertEqual(analytics.breaksTaken, 0)
        XCTAssertEqual(analytics.distractionsAvoided, 0)
    }

    func testAnalyticsDivisionByZeroGuards() {
        let testDefaults = UserDefaults(suiteName: "GrasslookTests.AnalyticsZero")!
        testDefaults.removePersistentDomain(forName: "GrasslookTests.AnalyticsZero")

        let analytics = AnalyticsManager(userDefaults: testDefaults)

        // When 0 breaks and 0 distractions exist
        XCTAssertEqual(analytics.breakComplianceRate, 1.0)
        XCTAssertEqual(analytics.focusSuccessRate, 1.0)
        XCTAssertEqual(analytics.mindfulMinutes, 0)
    }
}
