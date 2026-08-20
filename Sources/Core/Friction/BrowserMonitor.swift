import Foundation
import AppKit
import ApplicationServices

public protocol BrowserMonitorProtocol: Sendable {
    func isSupportedBrowser(bundleIdentifier: String) -> Bool
    func extractActiveURL(from application: NSRunningApplication) -> URL?
    func closeDistractingTabAndOpenBlank(bundleIdentifier: String)
}

/// Universal browser URL extraction engine using Accessibility (AXUIElement) & AppleScript.
public final class BrowserMonitor: BrowserMonitorProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var customBrowserBundleIds: Set<String> = []

    public static let defaultBrowserBundleIds: Set<String> = [
        // Apple
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        // Chromium
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser", // Arc
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        // Niche & Modern Browsers
        "net.imput.helium",          // Official Helium browser
        "com.koush.helium",
        "com.helium.app",
        "com.nicolaas.helium",
        "company.thebrowser.dia",     // Dia browser
        "com.dia.browser",
        "com.blanc.browser",
        "com.kagi.kagimacOS",        // Orion
        "app.zen-browser.zen",        // Zen Browser
        "com.sigmaos.sigmaos.macos", // SigmaOS
        // Mozilla
        "org.mozilla.firefox",
        "org.mozilla.nightly"
    ]

    public init(customBrowserBundleIds: Set<String> = []) {
        self.customBrowserBundleIds = customBrowserBundleIds
    }

    public func registerCustomBrowser(bundleIdentifier: String) {
        lock.lock()
        defer { lock.unlock() }
        customBrowserBundleIds.insert(bundleIdentifier)
    }

    public func isSupportedBrowser(bundleIdentifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if Self.defaultBrowserBundleIds.contains(bundleIdentifier) || customBrowserBundleIds.contains(bundleIdentifier) {
            return true
        }

        // Dynamic heuristic: recognize any bundle containing "helium", "browser", "safari", "chrome", "firefox", "edge"
        let lower = bundleIdentifier.lowercased()
        if lower.contains("helium") || lower.contains("browser") {
            return true
        }

        return false
    }

    public func extractActiveURL(from application: NSRunningApplication) -> URL? {
        guard let bundleId = application.bundleIdentifier, isSupportedBrowser(bundleIdentifier: bundleId) else {
            return nil
        }

        // Tier 1: Try Universal AXUIElement inspection
        if let axURL = extractURLViaAccessibility(pid: application.processIdentifier) {
            return axURL
        }

        // Tier 2: Fallback to AppleScript if scriptable
        if let scriptURL = extractURLViaAppleScript(bundleIdentifier: bundleId) {
            return scriptURL
        }

        return nil
    }

    // MARK: - Tier 1: Accessibility (AXUIElement)

    private func extractURLViaAccessibility(pid: pid_t) -> URL? {
        let appElement = AXUIElementCreateApplication(pid)

        // 1. Check focused window document attribute
        var focusedWindowValue: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)
        guard windowResult == .success, let focusedWindow = focusedWindowValue else {
            return nil
        }

        let windowElement = focusedWindow as! AXUIElement

        // Check if window has AXDocument attribute directly (standard for Safari / WebKit)
        var documentValue: AnyObject?
        if AXUIElementCopyAttributeValue(windowElement, "AXDocument" as CFString, &documentValue) == .success,
           let docString = documentValue as? String,
           let url = URL(string: docString),
           url.scheme != nil {
            return url
        }

        // Check window AXURL attribute
        var urlValue: AnyObject?
        if AXUIElementCopyAttributeValue(windowElement, "AXURL" as CFString, &urlValue) == .success,
           let urlString = (urlValue as? URL)?.absoluteString ?? (urlValue as? String),
           let url = URL(string: urlString),
           url.scheme != nil {
            return url
        }

        // 2. Traverse UI tree to find address field with depth and node budget
        var visitedCount = 0
        return findAddressBarURL(in: windowElement, depth: 4, visitedCount: &visitedCount, maxNodes: 50)
    }

    private func findAddressBarURL(in element: AXUIElement, depth: Int, visitedCount: inout Int, maxNodes: Int) -> URL? {
        guard depth > 0, visitedCount < maxNodes else { return nil }
        visitedCount += 1

        // Check value if it looks like an address field
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String

        if role == (kAXTextFieldRole as String) || role == (kAXComboBoxRole as String) {
            var val: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &val) == .success,
               let text = val as? String {
                if let url = normalizeURLString(text) {
                    return url
                }
            }
        }

        // Inspect children
        var childrenValue: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                guard visitedCount < maxNodes else { break }
                if let found = findAddressBarURL(in: child, depth: depth - 1, visitedCount: &visitedCount, maxNodes: maxNodes) {
                    return found
                }
            }
        }

        return nil
    }

    private func normalizeURLString(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.starts(with: "http://") || trimmed.starts(with: "https://") {
            return URL(string: trimmed)
        }

        // If it looks like a domain (e.g. "x.com" or "reddit.com/r/swift")
        if trimmed.contains(".") && !trimmed.contains(" ") {
            return URL(string: "https://" + trimmed)
        }

        return nil
    }

    // MARK: - Tier 2: AppleScript Bridge

    private func extractURLViaAppleScript(bundleIdentifier: String) -> URL? {
        let scripts: [String]
        if bundleIdentifier == "com.apple.Safari" || bundleIdentifier == "com.apple.SafariTechnologyPreview" {
            scripts = [
                """
                tell application id "\(bundleIdentifier)"
                    if (count of windows) > 0 then
                        return URL of current tab of front window
                    end if
                end tell
                """
            ]
        } else if bundleIdentifier.lowercased().contains("helium") {
            scripts = [
                """
                tell application id "\(bundleIdentifier)"
                    if (count of documents) > 0 then
                        return URL of document 1
                    end if
                end tell
                """,
                """
                tell application id "\(bundleIdentifier)"
                    if (count of windows) > 0 then
                        return URL of front window
                    end if
                end tell
                """,
                """
                tell application id "\(bundleIdentifier)"
                    if (count of windows) > 0 then
                        return URL of active tab of front window
                    end if
                end tell
                """
            ]
        } else {
            scripts = [
                """
                tell application id "\(bundleIdentifier)"
                    if (count of windows) > 0 then
                        return URL of active tab of front window
                    end if
                end tell
                """
            ]
        }

        for scriptSource in scripts {
            guard let script = NSAppleScript(source: scriptSource) else { continue }
            var errorDict: NSDictionary?
            let result = script.executeAndReturnError(&errorDict)
            if errorDict == nil, let rawURL = result.stringValue, let url = normalizeURLString(rawURL) {
                return url
            }
        }

        return nil
    }

    /// Closes the currently active distracting tab and opens a clean blank tab (about:blank).
    public func closeDistractingTabAndOpenBlank(bundleIdentifier: String) {
        let scripts: [String]
        if bundleIdentifier == "com.apple.Safari" || bundleIdentifier == "com.apple.SafariTechnologyPreview" {
            scripts = [
                """
                tell application id "\(bundleIdentifier)"
                    if (count of windows) > 0 then
                        tell front window
                            set currentTab to current tab
                            make new tab with properties {URL:"about:blank"}
                            close currentTab
                        end tell
                    end if
                end tell
                """
            ]
        } else if bundleIdentifier.lowercased().contains("helium") {
            scripts = [
                """
                tell application id "\(bundleIdentifier)"
                    if (count of documents) > 0 then
                        set URL of document 1 to "about:blank"
                    else if (count of windows) > 0 then
                        tell front window
                            set oldTab to active tab
                            make new tab at end of tabs with properties {URL:"about:blank"}
                            close oldTab
                        end tell
                    end if
                end tell
                """
            ]
        } else {
            // Standard Chromium (Chrome, Brave, Edge, Arc, Dia, etc.)
            scripts = [
                """
                tell application id "\(bundleIdentifier)"
                    if (count of windows) > 0 then
                        tell front window
                            set oldTab to active tab
                            make new tab at end of tabs with properties {URL:"about:blank"}
                            close oldTab
                        end tell
                    end if
                end tell
                """
            ]
        }

        for source in scripts {
            guard let script = NSAppleScript(source: source) else { continue }
            var errorDict: NSDictionary?
            script.executeAndReturnError(&errorDict)
            if errorDict == nil {
                return
            }
        }
    }
}

/// Mock browser monitor for deterministic testing.
public final class MockBrowserMonitor: BrowserMonitorProtocol, @unchecked Sendable {
    public var mockURL: URL?
    public var didCallCloseTab: Bool = false
    public var supportedBundleIds: Set<String> = BrowserMonitor.defaultBrowserBundleIds

    public init(mockURL: URL? = nil) {
        self.mockURL = mockURL
    }

    public func isSupportedBrowser(bundleIdentifier: String) -> Bool {
        return supportedBundleIds.contains(bundleIdentifier)
    }

    public func extractActiveURL(from application: NSRunningApplication) -> URL? {
        return mockURL
    }

    public func closeDistractingTabAndOpenBlank(bundleIdentifier: String) {
        didCallCloseTab = true
    }
}
