// Unit tests for TargetRule matching, CooldownManager, BrowserMonitor, and AppInterceptionEngine.

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
        XCTAssertTrue(rule.matches(bundleIdentifier: "COM.HNC.DISCORD"))
        XCTAssertFalse(rule.matches(bundleIdentifier: "com.tinyspeck.slackmacgap"))
    }

    func testTargetRuleDomainMatching() {
        let rule = TargetRule(
            name: "Twitter / X",
            kind: .website(domainPattern: "x.com")
        )

        XCTAssertTrue(rule.matches(host: "x.com"))
        XCTAssertTrue(rule.matches(host: "mobile.x.com"))
        XCTAssertTrue(rule.matches(url: URL(string: "https://x.com/home")!))
        XCTAssertTrue(rule.matches(url: URL(string: "https://sub.x.com/user/123")!))

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
            cooldownDuration: 60.0
        )

        XCTAssertFalse(cooldownManager.isUnderCooldown(for: rule))

        cooldownManager.recordMindfulPass(for: rule)
        XCTAssertTrue(cooldownManager.isUnderCooldown(for: rule))
        XCTAssertEqual(cooldownManager.remainingCooldown(for: rule), 60.0)

        timeProvider.advance(by: 30.0)
        XCTAssertTrue(cooldownManager.isUnderCooldown(for: rule))
        XCTAssertEqual(cooldownManager.remainingCooldown(for: rule), 30.0)

        timeProvider.advance(by: 31.0)
        XCTAssertFalse(cooldownManager.isUnderCooldown(for: rule))
        XCTAssertNil(cooldownManager.remainingCooldown(for: rule))
    }

    func testUniversalBrowserBundleIdentifiers() async {
        let monitor = BrowserMonitor()

        let safari = await monitor.isSupportedBrowser(bundleIdentifier: "com.apple.Safari")
        let chrome = await monitor.isSupportedBrowser(bundleIdentifier: "com.google.Chrome")
        let arc = await monitor.isSupportedBrowser(bundleIdentifier: "company.thebrowser.Browser")
        let helium = await monitor.isSupportedBrowser(bundleIdentifier: "com.koush.helium")
        let dia = await monitor.isSupportedBrowser(bundleIdentifier: "com.dia.browser")
        let blanc = await monitor.isSupportedBrowser(bundleIdentifier: "com.blanc.browser")
        let orion = await monitor.isSupportedBrowser(bundleIdentifier: "com.kagi.kagimacOS")
        let zen = await monitor.isSupportedBrowser(bundleIdentifier: "app.zen-browser.zen")
        let vivaldi = await monitor.isSupportedBrowser(bundleIdentifier: "com.vivaldi.Vivaldi")
        let firefox = await monitor.isSupportedBrowser(bundleIdentifier: "org.mozilla.firefox")

        XCTAssertTrue(safari)
        XCTAssertTrue(chrome)
        XCTAssertTrue(arc)
        XCTAssertTrue(helium)
        XCTAssertTrue(dia)
        XCTAssertTrue(blanc)
        XCTAssertTrue(orion)
        XCTAssertTrue(zen)
        XCTAssertTrue(vivaldi)
        XCTAssertTrue(firefox)

        let customBefore = await monitor.isSupportedBrowser(bundleIdentifier: "com.custom.nicheapp")
        XCTAssertFalse(customBefore)
        await monitor.registerCustomBrowser(bundleIdentifier: "com.custom.nicheapp")
        let customAfter = await monitor.isSupportedBrowser(bundleIdentifier: "com.custom.nicheapp")
        XCTAssertTrue(customAfter)
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

    func testDismissInterventionWebsiteRoutesThroughEnforceBlock() async {
        let mockBrowser = MockBrowserMonitor(mockResult: .closedTabViaAppleScript)
        let engine = AppInterceptionEngine(
            rules: [TargetRule(name: "X", kind: .website(domainPattern: "x.com"))],
            browserMonitor: mockBrowser
        )
        engine.browserEnforcementAction = .closeTab
        engine.sendCmdWToNonScriptableBrowsers = true

        let app = NSRunningApplication.current
        let targetURL = URL(string: "https://x.com/home")!
        let intervention = AppInterceptionEngine.ActiveIntervention(
            rule: TargetRule(name: "X", kind: .website(domainPattern: "x.com")),
            application: app,
            targetURL: targetURL
        )

        XCTAssertFalse(mockBrowser.didCallEnforceBlock)
        let result = await engine.enforceDismissal(for: intervention)
        XCTAssertTrue(mockBrowser.didCallEnforceBlock)
        XCTAssertEqual(result, .closedTabViaAppleScript)
        XCTAssertEqual(mockBrowser.lastEnforcedOptions?.action, .closeTab)
        XCTAssertEqual(mockBrowser.lastEnforcedOptions?.sendCmdWToNonScriptable, true)
        XCTAssertEqual(mockBrowser.lastEnforcedOptions?.blockedURL, targetURL)
    }

    func testPollActiveBrowserOnceTriggersInterventionWhenFrontmostMatches() async {
        let app = NSRunningApplication.current
        let bundleId = app.bundleIdentifier ?? "com.apple.dt.xctest"
        let mockBrowser = MockBrowserMonitor(
            mockURL: URL(string: "https://x.com/home"),
            supportedBundleIds: [bundleId]
        )

        let engine = AppInterceptionEngine(
            rules: [TargetRule(name: "X", kind: .website(domainPattern: "x.com"))],
            browserMonitor: mockBrowser,
            frontmostPIDProvider: { app.processIdentifier }
        )
        engine.startMonitoring()
        defer { engine.stopMonitoring() }

        await engine.pollActiveBrowserOnce(for: app)
        XCTAssertEqual(engine.activeIntervention?.targetURL?.host, "x.com")
    }

    func testPollActiveBrowserOnceAbortsWhenFrontmostPIDMismatches() async {
        let app = NSRunningApplication.current
        let bundleId = app.bundleIdentifier ?? "com.apple.dt.xctest"
        let mockBrowser = MockBrowserMonitor(
            mockURL: URL(string: "https://x.com/home"),
            supportedBundleIds: [bundleId]
        )

        let mismatchedPID = app.processIdentifier + 999
        let engine = AppInterceptionEngine(
            rules: [TargetRule(name: "X", kind: .website(domainPattern: "x.com"))],
            browserMonitor: mockBrowser,
            frontmostPIDProvider: { mismatchedPID }
        )
        engine.startMonitoring()
        defer { engine.stopMonitoring() }

        await engine.pollActiveBrowserOnce(for: app)
        XCTAssertNil(engine.activeIntervention)
    }

    func testDeduplicationSuppressesRepeatedHostDuringWindowAndClearsOnHostChange() async throws {
        let app = NSRunningApplication.current
        let bundleId = app.bundleIdentifier ?? "com.apple.dt.xctest"
        let timeProvider = MockTimeProvider()
        let mockBrowser = MockBrowserMonitor(
            mockURL: URL(string: "https://x.com/home"),
            supportedBundleIds: [bundleId]
        )

        let engine = AppInterceptionEngine(
            rules: [
                TargetRule(name: "X", kind: .website(domainPattern: "x.com")),
                TargetRule(name: "Reddit", kind: .website(domainPattern: "reddit.com"))
            ],
            browserMonitor: mockBrowser,
            frontmostPIDProvider: { app.processIdentifier },
            dateProvider: { timeProvider.currentDate() }
        )
        engine.startMonitoring()
        defer { engine.stopMonitoring() }

        await engine.pollActiveBrowserOnce(for: app)
        let firstIntervention = try XCTUnwrap(engine.activeIntervention)
        _ = await engine.enforceDismissal(for: firstIntervention)
        XCTAssertNil(engine.activeIntervention)

        // Within 2.5s suppression window on same (pid, host) -> suppressed
        timeProvider.advance(by: 1.0)
        await engine.pollActiveBrowserOnce(for: app)
        XCTAssertNil(engine.activeIntervention)

        // Host changes -> suppression cleared and new host triggers immediately
        mockBrowser.mockURL = URL(string: "https://reddit.com/r/swift")
        await engine.pollActiveBrowserOnce(for: app)
        XCTAssertEqual(engine.activeIntervention?.targetURL?.host, "reddit.com")
    }
}
