// Async actor-backed browser URL extraction and distraction enforcement engine.

import AppKit
import ApplicationServices
import Foundation
import os

/// Configures how a distracting browser tab is handled when blocked.
public struct BrowserEnforcementOptions: Sendable, Equatable {
    public let action: BrowserEnforcementAction
    public let sendCmdWToNonScriptable: Bool
    public let ruleName: String?
    public let blockedURL: URL?

    /// Creates browser enforcement options for a block event.
    public init(
        action: BrowserEnforcementAction = .redirectToShield,
        sendCmdWToNonScriptable: Bool = false,
        ruleName: String? = nil,
        blockedURL: URL? = nil
    ) {
        self.action = action
        self.sendCmdWToNonScriptable = sendCmdWToNonScriptable
        self.ruleName = ruleName
        self.blockedURL = blockedURL
    }
}

/// Outcome returned after enforcing a block on a browser application.
public enum BrowserEnforcementResult: Sendable, Equatable {
    case redirectedToShield(URL)
    case closedTabViaAppleScript
    case sentCmdW
    case hidApplication
    case noAction
}

/// Asynchronous interface for inspecting active browser URLs and enforcing blocks.
public protocol BrowserMonitorProtocol: Sendable {
    func isSupportedBrowser(bundleIdentifier: String) async -> Bool
    func browserProfile(for bundleIdentifier: String) async -> BrowserProfile?
    func registerCustomBrowser(bundleIdentifier: String) async
    func extractActiveURL(from application: NSRunningApplication) async -> URL?
    func enforceBlock(on application: NSRunningApplication, options: BrowserEnforcementOptions) async -> BrowserEnforcementResult
}

/// Universal async browser monitor using AppleScript caching and bounded AXUIElement fallback.
public final class BrowserMonitor: BrowserMonitorProtocol, Sendable {
    private let discovery: BrowserDiscovery
    private let shieldResourceURL: URL?
    private let worker: BrowserMonitorWorker

    /// Creates a browser monitor backed by `BrowserDiscovery` and an internal actor worker.
    public init(
        discovery: BrowserDiscovery = .shared,
        customBrowserBundleIds: Set<String> = [],
        shieldResourceURL: URL? = nil
    ) {
        self.discovery = discovery
        self.shieldResourceURL = shieldResourceURL
        self.worker = BrowserMonitorWorker()
        for bundleID in customBrowserBundleIds {
            discovery.registerCustomBrowser(bundleIdentifier: bundleID)
        }
    }

    /// Returns whether the bundle identifier belongs to a known or custom browser.
    public func isSupportedBrowser(bundleIdentifier: String) async -> Bool {
        discovery.isBrowser(bundleIdentifier: bundleIdentifier)
    }

    /// Returns the resolved browser profile for the given bundle identifier, if recognized.
    public func browserProfile(for bundleIdentifier: String) async -> BrowserProfile? {
        discovery.profile(for: bundleIdentifier)
    }

    /// Registers an additional browser bundle identifier at runtime.
    public func registerCustomBrowser(bundleIdentifier: String) async {
        discovery.registerCustomBrowser(bundleIdentifier: bundleIdentifier)
    }

    /// Extracts the active tab URL from a running browser using AppleScript first, then AX fallback.
    public func extractActiveURL(from application: NSRunningApplication) async -> URL? {
        guard let bundleIdentifier = application.bundleIdentifier,
              let profile = discovery.profile(for: bundleIdentifier) else {
            return nil
        }

        if profile.scriptingDialect.isScriptable {
            if let scriptURL = await worker.extractURL(
                bundleIdentifier: profile.bundleIdentifier,
                dialect: profile.scriptingDialect
            ) {
                return scriptURL
            }
        }

        return await worker.extractURLViaAccessibility(
            pid: application.processIdentifier,
            requiresManualAccessibility: profile.requiresManualAccessibility,
            requiresEnhancedUserInterface: profile.requiresEnhancedUserInterface
        )
    }

    /// Enforces a block on the active tab or window of a running browser application.
    public func enforceBlock(
        on application: NSRunningApplication,
        options: BrowserEnforcementOptions
    ) async -> BrowserEnforcementResult {
        guard let bundleIdentifier = application.bundleIdentifier else {
            return .noAction
        }

        let profile = discovery.profile(for: bundleIdentifier)

        if options.action == .redirectToShield,
           let profile,
           profile.supportsInPlaceRedirect,
           let shieldURL = Self.buildShieldURL(
               blockedURL: options.blockedURL,
               ruleName: options.ruleName,
               shieldFileURL: shieldResourceURL
           ) {
            let redirected = await worker.redirectActiveTab(
                bundleIdentifier: profile.bundleIdentifier,
                dialect: profile.scriptingDialect,
                targetURL: shieldURL
            )
            if redirected {
                return .redirectedToShield(shieldURL)
            }
        }

        if options.action == .closeTab,
           let profile,
           profile.scriptingDialect.isScriptable {
            let closed = await worker.closeActiveTab(
                bundleIdentifier: profile.bundleIdentifier,
                dialect: profile.scriptingDialect
            )
            if closed {
                return .closedTabViaAppleScript
            }
        }

        if options.sendCmdWToNonScriptable && AXIsProcessTrusted() {
            let isFrontmost = await MainActor.run { application.isActive }
            if isFrontmost, await worker.sendCmdWShortcut() {
                return .sentCmdW
            }
        }

        await MainActor.run {
            _ = application.hide()
        }
        return .hidApplication
    }

    /// Builds a local `shield.html` URL with validated `from` and `rule` query parameters.
    public static func buildShieldURL(
        blockedURL: URL?,
        ruleName: String?,
        shieldFileURL: URL? = nil
    ) -> URL? {
        guard let baseURL = shieldFileURL ?? Bundle.main.url(forResource: "shield", withExtension: "html"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems: [URLQueryItem] = []

        if let blockedURL,
           let safeReturnURL = validatedReturnURL(from: blockedURL.absoluteString) {
            queryItems.append(URLQueryItem(name: "from", value: safeReturnURL.absoluteString))
        }

        if let ruleName {
            let trimmedRule = ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedRule.isEmpty {
                queryItems.append(URLQueryItem(name: "rule", value: trimmedRule))
            }
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    /// Validates that a raw return URL uses `http:` or `https:` and includes a non-empty host.
    public static func validatedReturnURL(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }
}

/// Isolated actor executing AppleScript (with compiled caching) and AXUIElement queries off `@MainActor`.
private actor BrowserMonitorWorker {
    private enum ScriptAction: Hashable, Sendable {
        case extractURL(AppleScriptDialect)
        case closeTab(AppleScriptDialect)
    }

    private struct ScriptCacheKey: Hashable, Sendable {
        let bundleIdentifier: String
        let action: ScriptAction
    }

    private var scriptCache: [ScriptCacheKey: NSAppleScript] = [:]
    private let logger = Logger(subsystem: "com.grasslook.app", category: "BrowserMonitor")

    func extractURL(bundleIdentifier: String, dialect: AppleScriptDialect) -> URL? {
        guard dialect.isScriptable else { return nil }
        let key = ScriptCacheKey(
            bundleIdentifier: bundleIdentifier.lowercased(),
            action: .extractURL(dialect)
        )
        let source = extractScriptSource(bundleIdentifier: bundleIdentifier, dialect: dialect)
        guard let script = compiledScript(for: key, source: source) else {
            return nil
        }

        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let errorDict {
            logAppleScriptError(errorDict, bundleIdentifier: bundleIdentifier, operation: "extractURL")
            return nil
        }

        guard let rawURL = result.stringValue else { return nil }
        return Self.normalizeURLString(rawURL)
    }

    func redirectActiveTab(
        bundleIdentifier: String,
        dialect: AppleScriptDialect,
        targetURL: URL
    ) -> Bool {
        let escapedBundleID = Self.escapeAppleScriptString(bundleIdentifier)
        let escapedURL = Self.escapeAppleScriptString(targetURL.absoluteString)

        let source: String
        switch dialect {
        case .chromiumActiveTab:
            source = """
            tell application id "\(escapedBundleID)"
                if (count of windows) > 0 then
                    set URL of active tab of front window to "\(escapedURL)"
                    return true
                end if
            end tell
            return false
            """
        case .safariCurrentTab:
            source = """
            tell application id "\(escapedBundleID)"
                if (count of windows) > 0 then
                    set URL of current tab of front window to "\(escapedURL)"
                    return true
                end if
            end tell
            return false
            """
        case .documentURL, .none:
            return false
        }

        guard let script = NSAppleScript(source: source) else { return false }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let errorDict {
            logAppleScriptError(errorDict, bundleIdentifier: bundleIdentifier, operation: "redirectActiveTab")
            return false
        }
        return result.booleanValue
    }

    func closeActiveTab(bundleIdentifier: String, dialect: AppleScriptDialect) -> Bool {
        guard dialect.isScriptable else { return false }
        let key = ScriptCacheKey(
            bundleIdentifier: bundleIdentifier.lowercased(),
            action: .closeTab(dialect)
        )
        let source = closeTabScriptSource(bundleIdentifier: bundleIdentifier, dialect: dialect)
        guard let script = compiledScript(for: key, source: source) else {
            return false
        }

        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let errorDict {
            logAppleScriptError(errorDict, bundleIdentifier: bundleIdentifier, operation: "closeActiveTab")
            return false
        }
        return result.booleanValue
    }

    func extractURLViaAccessibility(
        pid: pid_t,
        requiresManualAccessibility: Bool,
        requiresEnhancedUserInterface: Bool
    ) -> URL? {
        let appElement = AXUIElementCreateApplication(pid)

        if requiresManualAccessibility {
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        if requiresEnhancedUserInterface {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }

        guard let windowElement = copyAXUIElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement) else {
            return nil
        }

        if let docString = copyStringAttribute("AXDocument" as CFString, from: windowElement),
           let url = Self.normalizeURLString(docString) {
            return url
        }

        if let windowURLString = copyStringAttribute("AXURL" as CFString, from: windowElement),
           let url = Self.normalizeURLString(windowURLString) {
            return url
        }

        return boundedBFSURL(in: windowElement, maxDepth: 8, maxNodes: 120)
    }

    func sendCmdWShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }
        let wKeyCode: CGKeyCode = 13
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: wKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: wKeyCode, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - AppleScript Helpers

    private func compiledScript(for key: ScriptCacheKey, source: String) -> NSAppleScript? {
        if let cached = scriptCache[key] {
            return cached
        }
        guard let script = NSAppleScript(source: source) else {
            return nil
        }
        var compileError: NSDictionary?
        if script.compileAndReturnError(&compileError) {
            scriptCache[key] = script
            return script
        }
        return nil
    }

    private func extractScriptSource(bundleIdentifier: String, dialect: AppleScriptDialect) -> String {
        let escapedID = Self.escapeAppleScriptString(bundleIdentifier)
        switch dialect {
        case .safariCurrentTab:
            return """
            tell application id "\(escapedID)"
                if (count of windows) > 0 then
                    return URL of current tab of front window
                end if
            end tell
            """
        case .chromiumActiveTab:
            return """
            tell application id "\(escapedID)"
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            """
        case .documentURL:
            return """
            tell application id "\(escapedID)"
                if (count of documents) > 0 then
                    return URL of document 1
                else if (count of windows) > 0 then
                    return URL of front window
                end if
            end tell
            """
        case .none:
            return ""
        }
    }

    private func closeTabScriptSource(bundleIdentifier: String, dialect: AppleScriptDialect) -> String {
        let escapedID = Self.escapeAppleScriptString(bundleIdentifier)
        switch dialect {
        case .safariCurrentTab:
            return """
            tell application id "\(escapedID)"
                if (count of windows) > 0 then
                    tell front window
                        set targetTab to current tab
                        make new tab with properties {URL:"about:blank"}
                        close targetTab
                        return true
                    end tell
                end if
            end tell
            return false
            """
        case .chromiumActiveTab:
            return """
            tell application id "\(escapedID)"
                if (count of windows) > 0 then
                    tell front window
                        set targetTab to active tab
                        make new tab at end of tabs with properties {URL:"about:blank"}
                        close targetTab
                        return true
                    end tell
                end if
            end tell
            return false
            """
        case .documentURL:
            return """
            tell application id "\(escapedID)"
                if (count of documents) > 0 then
                    set URL of document 1 to "about:blank"
                    return true
                end if
            end tell
            return false
            """
        case .none:
            return ""
        }
    }

    private func logAppleScriptError(_ errorDict: NSDictionary, bundleIdentifier: String, operation: String) {
        let errorCode = (errorDict[NSAppleScript.errorNumber] as? Int) ?? 0
        if errorCode == -1743 {
            logger.debug("AppleEvents permission denied (-1743) for \(bundleIdentifier, privacy: .public) during \(operation, privacy: .public); falling back")
        } else {
            let message = (errorDict[NSAppleScript.errorMessage] as? String) ?? "unknown error"
            logger.debug("AppleScript error \(errorCode) for \(bundleIdentifier, privacy: .public) during \(operation, privacy: .public): \(message, privacy: .public)")
        }
    }

    private static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Accessibility BFS Helpers

    private func boundedBFSURL(in rootWindow: AXUIElement, maxDepth: Int, maxNodes: Int) -> URL? {
        var queue: [(element: AXUIElement, depth: Int)] = [(rootWindow, 0)]
        var head = 0
        var visited = 0
        var addressFieldCandidate: URL?

        while head < queue.count, visited < maxNodes {
            let (element, depth) = queue[head]
            head += 1
            visited += 1

            let role = copyStringAttribute(kAXRoleAttribute as CFString, from: element)

            if role == "AXWebArea",
               let webAreaURL = copyStringAttribute("AXURL" as CFString, from: element),
               let url = Self.normalizeURLString(webAreaURL) {
                return url
            }

            let domID = copyStringAttribute("AXDOMIdentifier" as CFString, from: element)
            if domID == "urlbar-input",
               let rawValue = copyStringAttribute(kAXValueAttribute as CFString, from: element),
               let url = Self.normalizeURLString(rawValue) {
                return url
            }

            if addressFieldCandidate == nil,
               role == (kAXTextFieldRole as String) || role == (kAXComboBoxRole as String),
               let rawValue = copyStringAttribute(kAXValueAttribute as CFString, from: element),
               let url = Self.normalizeURLString(rawValue) {
                addressFieldCandidate = url
            }

            guard depth < maxDepth else { continue }

            var childrenValue: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
               let children = childrenValue as? [AnyObject] {
                for childRef in children {
                    guard CFGetTypeID(childRef) == AXUIElementGetTypeID() else { continue }
                    let childElement = unsafeDowncast(childRef, to: AXUIElement.self)
                    queue.append((childElement, depth + 1))
                }
            }
        }

        return addressFieldCandidate
    }

    private func copyAXUIElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var rawValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
              let value = rawValue,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var rawValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
              let value = rawValue else {
            return nil
        }
        if let stringValue = value as? String {
            return stringValue
        }
        if let urlValue = value as? URL {
            return urlValue.absoluteString
        }
        return nil
    }

    private static func normalizeURLString(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        if trimmed.contains(".") && !trimmed.contains(" ") && !trimmed.contains("://") {
            return URL(string: "https://" + trimmed)
        }

        return nil
    }
}

/// Lock-protected mock browser monitor for deterministic unit testing.
public final class MockBrowserMonitor: BrowserMonitorProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _mockURL: URL?
    private var _supportedBundleIds: Set<String>
    private var _mockProfiles: [String: BrowserProfile] = [:]
    private var _mockResult: BrowserEnforcementResult
    private var _enforcedCalls: [(bundleIdentifier: String, options: BrowserEnforcementOptions)] = []

    /// Simulated active URL returned by `extractActiveURL(from:)`.
    public var mockURL: URL? {
        get { lock.withLock { _mockURL } }
        set { lock.withLock { _mockURL = newValue } }
    }

    /// Bundle identifiers treated as supported browsers by this mock.
    public var supportedBundleIds: Set<String> {
        get { lock.withLock { _supportedBundleIds } }
        set { lock.withLock { _supportedBundleIds = newValue } }
    }

    /// Optional custom browser profiles keyed by bundle identifier.
    public var mockProfiles: [String: BrowserProfile] {
        get { lock.withLock { _mockProfiles } }
        set { lock.withLock { _mockProfiles = newValue } }
    }

    /// Result returned by `enforceBlock(on:options:)`.
    public var mockResult: BrowserEnforcementResult {
        get { lock.withLock { _mockResult } }
        set { lock.withLock { _mockResult = newValue } }
    }

    /// Recorded enforcement invocations in call order.
    public private(set) var enforcedCalls: [(bundleIdentifier: String, options: BrowserEnforcementOptions)] {
        get { lock.withLock { _enforcedCalls } }
        set { lock.withLock { _enforcedCalls = newValue } }
    }

    /// Whether `enforceBlock(on:options:)` has been called at least once.
    public var didCallEnforceBlock: Bool {
        lock.withLock { !_enforcedCalls.isEmpty }
    }

    /// Options passed to the most recent `enforceBlock(on:options:)` call, if any.
    public var lastEnforcedOptions: BrowserEnforcementOptions? {
        lock.withLock { _enforcedCalls.last?.options }
    }

    /// Creates a mock browser monitor with configurable URL, supported IDs, and enforcement result.
    public init(
        mockURL: URL? = nil,
        supportedBundleIds: Set<String> = BrowserDiscovery.seedBundleIdentifiers,
        mockResult: BrowserEnforcementResult = .closedTabViaAppleScript
    ) {
        self._mockURL = mockURL
        self._supportedBundleIds = supportedBundleIds
        self._mockResult = mockResult
    }

    public func isSupportedBrowser(bundleIdentifier: String) async -> Bool {
        let lower = bundleIdentifier.lowercased()
        return lock.withLock {
            _supportedBundleIds.contains { $0.lowercased() == lower }
        }
    }

    public func browserProfile(for bundleIdentifier: String) async -> BrowserProfile? {
        let lower = bundleIdentifier.lowercased()
        return lock.withLock {
            if let exact = _mockProfiles[bundleIdentifier] {
                return exact
            }
            if let matched = _mockProfiles.first(where: { $0.key.lowercased() == lower })?.value {
                return matched
            }
            guard _supportedBundleIds.contains(where: { $0.lowercased() == lower }) else {
                return nil
            }
            return BrowserProfile(
                bundleIdentifier: bundleIdentifier,
                displayName: bundleIdentifier,
                engine: .chromium,
                scriptingDialect: .chromiumActiveTab
            )
        }
    }

    public func registerCustomBrowser(bundleIdentifier: String) async {
        _ = lock.withLock {
            _supportedBundleIds.insert(bundleIdentifier)
        }
    }

    public func extractActiveURL(from application: NSRunningApplication) async -> URL? {
        lock.withLock { _mockURL }
    }

    public func enforceBlock(
        on application: NSRunningApplication,
        options: BrowserEnforcementOptions
    ) async -> BrowserEnforcementResult {
        let bundleIdentifier = application.bundleIdentifier ?? ""
        return lock.withLock {
            _enforcedCalls.append((bundleIdentifier: bundleIdentifier, options: options))
            return _mockResult
        }
    }
}
