// Unit tests for shield URL validation, zero-blur shield HTML, MockBrowserMonitor, and BrowserPermissionChecker.

import AppKit
import XCTest
@testable import Grasslook

final class BrowserEnforcementTests: XCTestCase {
    // MARK: - Return URL & Shield URL Validation

    func testValidatedReturnURLAllowsHTTPAndHTTPS() {
        let httpURL = BrowserMonitor.validatedReturnURL(from: "http://example.com/path?a=1")
        let httpsURL = BrowserMonitor.validatedReturnURL(from: "  https://news.ycombinator.com/item?id=42  ")

        XCTAssertEqual(httpURL?.absoluteString, "http://example.com/path?a=1")
        XCTAssertEqual(httpsURL?.absoluteString, "https://news.ycombinator.com/item?id=42")
    }

    func testValidatedReturnURLRejectsUnsafeAndMalformedSchemes() {
        let rejectedInputs: [String?] = [
            nil,
            "",
            "   ",
            "javascript:alert(1)",
            "JAVASCRIPT:void(0)",
            "data:text/html,<script>alert(1)</script>",
            "file:///etc/passwd",
            "ftp://example.com/file",
            "https://",
            "not a url at all"
        ]

        for rawInput in rejectedInputs {
            XCTAssertNil(
                BrowserMonitor.validatedReturnURL(from: rawInput),
                "Expected unsafe or malformed input to be rejected: \(String(describing: rawInput))"
            )
        }
    }

    func testBuildShieldURLIncludesValidatedFromAndRuleParameters() throws {
        let shieldFile = URL(fileURLWithPath: "/tmp/shield.html")
        let blocked = try XCTUnwrap(URL(string: "https://x.com/home"))

        let built = try XCTUnwrap(
            BrowserMonitor.buildShieldURL(
                blockedURL: blocked,
                ruleName: "Social Media",
                shieldFileURL: shieldFile
            )
        )

        let components = try XCTUnwrap(URLComponents(url: built, resolvingAgainstBaseURL: false))
        let queryMap = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )

        XCTAssertEqual(built.path, "/tmp/shield.html")
        XCTAssertEqual(queryMap["from"], "https://x.com/home")
        XCTAssertEqual(queryMap["rule"], "Social Media")
    }

    func testBuildShieldURLOmitsUnsafeBlockedURLScheme() throws {
        let shieldFile = URL(fileURLWithPath: "/tmp/shield.html")
        let unsafeBlocked = try XCTUnwrap(URL(string: "javascript:alert(1)"))

        let built = try XCTUnwrap(
            BrowserMonitor.buildShieldURL(
                blockedURL: unsafeBlocked,
                ruleName: "Focus",
                shieldFileURL: shieldFile
            )
        )

        let components = try XCTUnwrap(URLComponents(url: built, resolvingAgainstBaseURL: false))
        let queryNames = Set((components.queryItems ?? []).map { $0.name })
        XCTAssertFalse(queryNames.contains("from"))
        XCTAssertTrue(queryNames.contains("rule"))
    }

    // MARK: - Zero-CSS-Blur Static Assertion

    func testShieldHTMLHasZeroCSSBlurFiltersAndStrictSchemeValidation() throws {
        let testsFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testsFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let shieldHTMLURL = repoRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("shield.html", isDirectory: false)

        let html = try String(contentsOf: shieldHTMLURL, encoding: .utf8)

        XCTAssertFalse(html.contains("filter:"), "Resources/shield.html must not contain CSS filter:")
        XCTAssertFalse(html.contains("backdrop-filter:"), "Resources/shield.html must not contain CSS backdrop-filter:")
        XCTAssertFalse(html.contains("innerHTML"), "Resources/shield.html must not use innerHTML")
        XCTAssertTrue(html.contains("shield-bg.jpg"), "Resources/shield.html should reference relative shield-bg.jpg")
        XCTAssertTrue(html.contains("http:") && html.contains("https:"), "Resources/shield.html must validate http/https schemes")
    }

    // MARK: - MockBrowserMonitor Async Extraction & Enforcement

    func testMockBrowserMonitorExtractionAndEnforcementRecording() async throws {
        let targetURL = try XCTUnwrap(URL(string: "https://reddit.com/r/swift"))
        let shieldURL = URL(fileURLWithPath: "/tmp/shield.html")
        let mock = MockBrowserMonitor(
            mockURL: targetURL,
            supportedBundleIds: ["com.google.Chrome"],
            mockResult: .redirectedToShield(shieldURL)
        )

        let isChromeSupported = await mock.isSupportedBrowser(bundleIdentifier: "com.google.Chrome")
        XCTAssertTrue(isChromeSupported)

        await mock.registerCustomBrowser(bundleIdentifier: "com.custom.browser")
        let isCustomSupported = await mock.isSupportedBrowser(bundleIdentifier: "com.custom.browser")
        XCTAssertTrue(isCustomSupported)

        let customProfile = await mock.browserProfile(for: "com.custom.browser")
        XCTAssertNotNil(customProfile)

        let extracted = await mock.extractActiveURL(from: NSRunningApplication.current)
        XCTAssertEqual(extracted, targetURL)

        let options = BrowserEnforcementOptions(
            action: .redirectToShield,
            sendCmdWToNonScriptable: false,
            ruleName: "Reddit",
            blockedURL: targetURL
        )
        let result = await mock.enforceBlock(on: NSRunningApplication.current, options: options)

        XCTAssertEqual(result, .redirectedToShield(shieldURL))
        XCTAssertTrue(mock.didCallEnforceBlock)
        XCTAssertEqual(mock.lastEnforcedOptions, options)
        XCTAssertEqual(mock.enforcedCalls.count, 1)
    }

    // MARK: - BrowserPermissionChecker

    func testPermissionCheckerReturnsNotApplicableForNonScriptableEngines() async {
        let checker = BrowserPermissionChecker()
        let firefox = BrowserProfile(
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox",
            engine: .gecko,
            scriptingDialect: .none
        )
        let electronApp = BrowserProfile(
            bundleIdentifier: "com.electron.sample",
            displayName: "Electron Browser",
            engine: .electron,
            scriptingDialect: .none
        )

        let firefoxStatus = await checker.checkStatus(for: firefox)
        let electronStatus = await checker.checkStatus(for: electronApp)

        XCTAssertEqual(firefoxStatus, .notApplicable)
        XCTAssertEqual(firefoxStatus.displayName, "AX Only")
        XCTAssertEqual(electronStatus, .notApplicable)

        let snapshots = await checker.checkStatuses(for: [firefox, electronApp])
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].profile.bundleIdentifier, "org.mozilla.firefox")
        XCTAssertEqual(snapshots[0].automationStatus, .notApplicable)
        XCTAssertEqual(snapshots[1].profile.bundleIdentifier, "com.electron.sample")
        XCTAssertEqual(snapshots[1].automationStatus, .notApplicable)
    }
}
