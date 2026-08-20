import XCTest
@testable import Grasslook

final class MockTimeProvider: @unchecked Sendable {
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
final class InterceptionTests: XCTestCase {

    func testTargetRuleAppMatching() {
        let rule = TargetRule(
            name: "Discord",
            kind: .application(bundleIdentifier: "com.hnc.Discord")
        )

        XCTAssertTrue(rule.matches(bundleIdentifier: "com.hnc.Discord"))
        XCTAssertTrue(rule.matches(bundleIdentifier: "COM.HNC.DISCORD")) // Case insensitive
        XCTAssertFalse(rule.matches(bundleIdentifier: "com.tinyspeck.slackmacgap"))
    }

    func testTargetRuleDomainMatching() {
        let rule = TargetRule(
            name: "Twitter / X",
            kind: .website(domainPattern: "x.com")
        )

        // Exact match
        XCTAssertTrue(rule.matches(host: "x.com"))
        // Subdomain match
        XCTAssertTrue(rule.matches(host: "mobile.x.com"))
        XCTAssertTrue(rule.matches(url: URL(string: "https://x.com/home")!))
        XCTAssertTrue(rule.matches(url: URL(string: "https://sub.x.com/user/123")!))

        // Non-match
        XCTAssertFalse(rule.matches(host: "notx.com"))
        XCTAssertFalse(rule.matches(host: "google.com"))
    }

    func testTargetRuleWildcardMatching() {
        let rule = TargetRule(
            name: "Reddit",
            kind: .website(domainPattern: "*.reddit.com")
        )

        XCTAssertTrue(rule.matches(host: "reddit.com"))
        XCTAssertTrue(rule.matches(host: "old.reddit.com"))
        XCTAssertTrue(rule.matches(host: "www.reddit.com"))
        XCTAssertFalse(rule.matches(host: "fakereddit.com"))
    }

    func testCooldownManagerExpiry() {
        let timeProvider = MockTimeProvider(initialDate: Date(timeIntervalSince1970: 1000))
        let cooldownManager = CooldownManager(dateProvider: { timeProvider.currentDate() })

        let rule = TargetRule(
            name: "Test Site",
            kind: .website(domainPattern: "distracting.com"),
            cooldownDuration: 60.0 // 1 minute
        )

        XCTAssertFalse(cooldownManager.isUnderCooldown(for: rule))

        // Record mindful pass
        cooldownManager.recordMindfulPass(for: rule)
        XCTAssertTrue(cooldownManager.isUnderCooldown(for: rule))
        XCTAssertEqual(cooldownManager.remainingCooldown(for: rule), 60.0)

        // Advance 30 seconds -> still under cooldown
        timeProvider.advance(by: 30.0)
        XCTAssertTrue(cooldownManager.isUnderCooldown(for: rule))
        XCTAssertEqual(cooldownManager.remainingCooldown(for: rule), 30.0)

        // Advance 31 more seconds -> cooldown expired
        timeProvider.advance(by: 31.0)
        XCTAssertFalse(cooldownManager.isUnderCooldown(for: rule))
        XCTAssertNil(cooldownManager.remainingCooldown(for: rule))
    }

    func testUniversalBrowserBundleIdentifiers() {
        let monitor = BrowserMonitor()
        // Mainstream
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "com.apple.Safari"))
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "com.google.Chrome"))
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "company.thebrowser.Browser")) // Arc
        // Niche browsers requested
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "com.koush.helium"))
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "com.dia.browser"))
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "com.blanc.browser"))
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "com.kagi.kagimacOS")) // Orion
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "app.zen-browser.zen")) // Zen
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "com.vivaldi.Vivaldi"))
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "org.mozilla.firefox"))

        // Custom registration
        XCTAssertFalse(monitor.isSupportedBrowser(bundleIdentifier: "com.custom.nicheapp"))
        monitor.registerCustomBrowser(bundleIdentifier: "com.custom.nicheapp")
        XCTAssertTrue(monitor.isSupportedBrowser(bundleIdentifier: "com.custom.nicheapp"))
    }

    func testCooldownManagerClearAll() {
        let cooldownManager = CooldownManager()
        let rule = TargetRule(
            name: "Test Site",
            kind: .website(domainPattern: "distracting.com"),
            cooldownDuration: 600.0
        )

        cooldownManager.recordMindfulPass(for: rule)
        XCTAssertTrue(cooldownManager.isUnderCooldown(for: rule))

        cooldownManager.clearAll()
        XCTAssertFalse(cooldownManager.isUnderCooldown(for: rule))
        XCTAssertNil(cooldownManager.remainingCooldown(for: rule))
    }

    func testTargetRuleMatchesVariousURLFormats() {
        let rule = TargetRule(
            name: "YouTube",
            kind: .website(domainPattern: "youtube.com")
        )

        XCTAssertTrue(rule.matches(url: URL(string: "https://www.youtube.com/watch?v=123")!))
        XCTAssertTrue(rule.matches(url: URL(string: "http://youtube.com/feed")!))
        XCTAssertTrue(rule.matches(url: URL(string: "https://m.youtube.com/")!))
        XCTAssertFalse(rule.matches(url: URL(string: "https://notyoutube.com")!))
    }

    func testDismissInterventionWebsiteClosesTab() {
        let mockBrowser = MockBrowserMonitor()
        let engine = AppInterceptionEngine(
            rules: [TargetRule(name: "X", kind: .website(domainPattern: "x.com"))],
            browserMonitor: mockBrowser
        )

        let app = NSRunningApplication.current
        let intervention = AppInterceptionEngine.ActiveIntervention(
            rule: TargetRule(name: "X", kind: .website(domainPattern: "x.com")),
            application: app,
            targetURL: URL(string: "https://x.com/home")!
        )

        XCTAssertFalse(mockBrowser.didCallCloseTab)
        engine.dismissInterventionAndCloseApp(for: intervention)
        XCTAssertTrue(mockBrowser.didCallCloseTab)
    }
}
