// Browser engine, scripting dialect, and profile capability models.

import Foundation

/// Identifies the underlying rendering or host engine of a browser application.
public enum BrowserEngine: String, CaseIterable, Codable, Sendable, Hashable {
    case webkit
    case chromium
    case electron
    case dualCEFWebKit
    case cefNative
    case gecko
    case ladybird
    case unknown

    /// Human-readable name for the browser engine.
    public var displayName: String {
        switch self {
        case .webkit: return "WebKit"
        case .chromium: return "Chromium"
        case .electron: return "Electron"
        case .dualCEFWebKit: return "Dual CEF / WebKit"
        case .cefNative: return "CEF Native"
        case .gecko: return "Gecko"
        case .ladybird: return "Ladybird"
        case .unknown: return "Unknown"
        }
    }
}

/// Describes the AppleScript dictionary dialect supported by a browser.
public enum AppleScriptDialect: String, CaseIterable, Codable, Sendable, Hashable {
    case chromiumActiveTab
    case safariCurrentTab
    case documentURL
    case none

    /// Whether the browser supports AppleScript URL inspection.
    public var isScriptable: Bool {
        self != .none
    }

    /// Human-readable name for the scripting dialect.
    public var displayName: String {
        switch self {
        case .chromiumActiveTab: return "Chromium Active Tab"
        case .safariCurrentTab: return "Safari Current Tab"
        case .documentURL: return "Document URL"
        case .none: return "None (AX Only)"
        }
    }
}

/// Represents the Automation (AppleEvents) permission state for a browser.
public enum BrowserAutomationStatus: String, CaseIterable, Codable, Sendable, Hashable {
    case granted
    case denied
    case prompt
    case notApplicable
    case unknown

    /// Human-readable status label for settings and diagnostics UI.
    public var displayName: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .prompt: return "Prompt"
        case .notApplicable: return "AX Only"
        case .unknown: return "Unknown"
        }
    }
}

/// Describes a discovered or known browser and its automation capabilities.
public struct BrowserProfile: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String { bundleIdentifier.lowercased() }
    public let bundleIdentifier: String
    public let displayName: String
    public let bundleURL: URL?
    public let engine: BrowserEngine
    public let scriptingDialect: AppleScriptDialect
    public let sdefFilename: String?

    /// Creates a browser profile describing its engine and scripting capabilities.
    public init(
        bundleIdentifier: String,
        displayName: String,
        bundleURL: URL? = nil,
        engine: BrowserEngine,
        scriptingDialect: AppleScriptDialect,
        sdefFilename: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.bundleURL = bundleURL
        self.engine = engine
        self.scriptingDialect = scriptingDialect
        self.sdefFilename = sdefFilename
    }

    /// Whether the active tab URL can be redirected in-place via AppleScript.
    public var supportsInPlaceRedirect: Bool {
        scriptingDialect == .chromiumActiveTab || scriptingDialect == .safariCurrentTab
    }

    /// Whether Accessibility (`AXManualAccessibility`) must be enabled on the app element.
    public var requiresManualAccessibility: Bool {
        engine == .electron || engine == .cefNative || engine == .dualCEFWebKit || engine == .chromium
    }

    /// Whether Accessibility (`AXEnhancedUserInterface`) must be enabled on the app element.
    public var requiresEnhancedUserInterface: Bool {
        engine == .gecko
    }
}
