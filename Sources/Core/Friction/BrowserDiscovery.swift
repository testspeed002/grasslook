// Seven-engine macOS browser discovery, web-handler gating, and profile cache.

import AppKit
import Foundation
import os

/// Discovers installed macOS browsers and classifies their rendering engines and scripting dialects.
public final class BrowserDiscovery: @unchecked Sendable {
    /// Shared singleton browser discovery instance.
    public static let shared = BrowserDiscovery()

    /// Curated seed bundle identifiers covering major and niche macOS browsers.
    public static let seedBundleIdentifiers: Set<String> = [
        // Apple / WebKit
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.apple.WebKit.MiniBrowser",
        "com.kagi.kagimacOS",
        "com.kagi.kagimacOS.RC",
        "com.kagi.orion",
        "com.sigmaos.sigmaos.macos",
        // Google Chrome & Chromium
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "org.chromium.Chromium",
        "com.ungoogled-software.ungoogled-chromium",
        "com.thorium.Thorium",
        "com.srware.iron",
        // Arc & Dia (The Browser Company)
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "com.dia.browser",
        // Helium
        "net.imput.helium",
        "com.koush.helium",
        "com.helium.app",
        "com.nicolaas.helium",
        // yab / Blanc / Deta Surf / Comet / Atlas / DuckDuckGo
        "dev.serafim.fast",
        "com.blanc.browser",
        "surf.deta.app",
        "com.perplexity.Comet",
        "ai.perplexity.comet",
        "com.openai.atlas",
        "com.chatgpt.atlas",
        "com.duckduckgo.macos.browser",
        // Brave / Edge / Vivaldi / Opera / Yandex
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi",
        "com.vivaldi.Vivaldi.snapshot",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.operasoftware.OperaAir",
        "com.operasoftware.OperaDeveloper",
        "ru.yandex.desktop.yandex-browser",
        // Gecko / Firefox family
        "org.mozilla.firefox",
        "org.mozilla.nightly",
        "org.mozilla.firefoxdeveloperedition",
        "one.ablaze.floorp",
        "app.zen-browser.zen",
        "org.torproject.torbrowser",
        "net.mullvad.MullvadBrowser",
        "net.waterfox.waterfox",
        "io.gitlab.librewolf-community.librewolf",
        "org.mozilla.librewolf",
        "org.palemoon.PaleMoon",
        // Ladybird
        "org.ladybird.Ladybird",
        "com.ladybird.Ladybird",
        // Productivity / Electron / CEF / Niche browsers
        "com.sidekickbrowser.Sidekick",
        "com.pushplaylabs.sidekick",
        "com.wavebox.wavebox",
        "com.ghostbrowser.app",
        "com.minbrowser.Min",
        "com.qutebrowser.qutebrowser",
        "com.polypane.app",
        "com.responsively.app",
        "com.sizzy.app",
        "com.tryshift.Shift",
        "com.shift.browser",
        "com.stackbrowser.Stack",
        "com.biscuit.Biscuit",
        "com.station.Station",
        "com.ferdium.Ferdium",
        "com.rambox.Rambox",
        "com.franz.Franz",
        "com.beakerbrowser.Beaker",
        "com.agregore.Agregore",
        "com.epicbrowser.Epic",
        "com.avast.browser",
        "com.avg.browser",
        "com.ccleaner.browser",
        "com.maxthon.Maxthon",
        "com.naver.Whale",
        "com.ecosia.browser",
        "com.startpage.browser",
        "com.ghostery.dawn",
        "com.aloha.browser",
        "com.mightyapp.Mighty",
        "dev.nyxt.nyxt",
    ]

    /// Media players and non-browser utilities excluded even when they register `http`/`https` handlers.
    public static let excludedBundleIdentifiers: Set<String> = [
        "org.videolan.vlc",
        "com.colliderli.iina",
        "io.mpv",
        "com.apple.QuickTimePlayerX",
    ]

    private static let seedBundleIdentifiersLowercased: Set<String> = Set(
        seedBundleIdentifiers.map { $0.lowercased() }
    )

    private static let excludedBundleIdentifiersLowercased: Set<String> = Set(
        excludedBundleIdentifiers.map { $0.lowercased() }
    )

    private static let knownWebKitBundleIdentifiers: Set<String> = [
        "com.apple.safari",
        "com.apple.safaritechnologypreview",
        "com.apple.webkit.minibrowser",
        "com.kagi.kagimacos",
        "com.kagi.kagimacos.rc",
        "com.kagi.orion",
        "com.sigmaos.sigmaos.macos",
    ]

    private static let knownChromiumBundleIdentifiers: Set<String> = [
        "com.google.chrome",
        "com.google.chrome.beta",
        "com.google.chrome.canary",
        "com.google.chrome.dev",
        "org.chromium.chromium",
        "company.thebrowser.browser",
        "company.thebrowser.dia",
        "com.dia.browser",
        "net.imput.helium",
        "com.koush.helium",
        "com.helium.app",
        "com.nicolaas.helium",
        "com.brave.browser",
        "com.brave.browser.beta",
        "com.brave.browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.beta",
        "com.microsoft.edgemac.dev",
        "com.microsoft.edgemac.canary",
        "com.vivaldi.vivaldi",
        "com.vivaldi.vivaldi.snapshot",
        "com.operasoftware.opera",
        "com.operasoftware.operagx",
        "com.operasoftware.operaair",
        "com.operasoftware.operadeveloper",
    ]

    private static let logger = Logger(subsystem: "com.grasslook.app", category: "BrowserDiscovery")

    private let lock = NSLock()
    private let appURLsProvider: @Sendable () -> [URL]
    private var customBundleIdentifiers: Set<String>
    private var cachedProfilesByBundleID: [String: BrowserProfile] = [:]
    private var hasDiscovered = false

    /// Creates a browser discovery instance with optional custom bundle IDs and an overridable app URL provider.
    public init(
        customBundleIdentifiers: Set<String> = [],
        appURLsProvider: (@Sendable () -> [URL])? = nil
    ) {
        self.customBundleIdentifiers = Set(
            customBundleIdentifiers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        self.appURLsProvider = appURLsProvider ?? Self.defaultAppURLsProvider
    }

    /// Discovers installed browsers, optionally bypassing the in-memory cache.
    @discardableResult
    public func discoverInstalledBrowsers(forceRefresh: Bool = false) -> [BrowserProfile] {
        if !forceRefresh {
            lock.lock()
            let alreadyDiscovered = hasDiscovered
            let snapshot = Array(cachedProfilesByBundleID.values)
            lock.unlock()

            if alreadyDiscovered {
                return Self.sortedProfiles(snapshot)
            }
        }

        let candidateURLs = appURLsProvider()
        var discovered: [String: BrowserProfile] = [:]

        for url in candidateURLs {
            guard let profile = inspectBundle(at: url, bypassWebHandlerGate: false) else {
                continue
            }
            let key = profile.bundleIdentifier.lowercased()
            if discovered[key] == nil {
                discovered[key] = profile
            }
        }

        lock.lock()
        cachedProfilesByBundleID = discovered
        hasDiscovered = true
        lock.unlock()

        return Self.sortedProfiles(Array(discovered.values))
    }

    /// Inspects a `.app` bundle on disk and returns its `BrowserProfile` if it qualifies as a browser.
    public func inspectBundle(at bundleURL: URL, bypassWebHandlerGate: Bool = false) -> BrowserProfile? {
        let infoPlistURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)

        guard let infoPlist = Self.loadInfoPlist(at: infoPlistURL),
              let rawBundleID = infoPlist["CFBundleIdentifier"] as? String else {
            return nil
        }

        let bundleIdentifier = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty else {
            return nil
        }

        let normalizedID = bundleIdentifier.lowercased()
        if Self.excludedBundleIdentifiersLowercased.contains(normalizedID) {
            return nil
        }

        if !bypassWebHandlerGate {
            let isSeed = Self.seedBundleIdentifiersLowercased.contains(normalizedID)
            let isCustom = isCustomBundleIdentifier(normalizedID)
            if !isSeed && !isCustom && !Self.handlesWebBrowsing(infoPlist: infoPlist) {
                return nil
            }
        }

        let displayName = Self.resolveDisplayName(from: infoPlist, bundleURL: bundleURL)
        let sdefResult = SdefScriptingInspector.inspect(bundleURL: bundleURL)
        let engine = Self.classifyEngine(
            bundleURL: bundleURL,
            bundleIdentifier: normalizedID,
            scriptingDialect: sdefResult.dialect
        )

        return BrowserProfile(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            bundleURL: bundleURL,
            engine: engine,
            scriptingDialect: sdefResult.dialect,
            sdefFilename: sdefResult.sdefFilename
        )
    }

    /// Returns the cached `BrowserProfile` for a bundle identifier, triggering discovery if needed.
    public func profile(for bundleIdentifier: String) -> BrowserProfile? {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        lock.lock()
        let alreadyDiscovered = hasDiscovered
        let cached = cachedProfilesByBundleID[normalized]
        lock.unlock()

        if alreadyDiscovered {
            return cached
        }

        _ = discoverInstalledBrowsers(forceRefresh: false)

        lock.lock()
        let resolved = cachedProfilesByBundleID[normalized]
        lock.unlock()
        return resolved
    }

    /// Returns whether the bundle identifier represents a recognized or user-registered browser.
    public func isBrowser(bundleIdentifier: String) -> Bool {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        if Self.excludedBundleIdentifiersLowercased.contains(normalized) {
            return false
        }
        if Self.seedBundleIdentifiersLowercased.contains(normalized) {
            return true
        }
        if isCustomBundleIdentifier(normalized) {
            return true
        }
        return profile(for: normalized) != nil
    }

    /// Registers an additional custom browser bundle identifier.
    public func registerCustomBrowser(bundleIdentifier: String) {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return
        }

        lock.lock()
        customBundleIdentifiers.insert(normalized)
        lock.unlock()
    }

    /// Replaces the set of custom browser bundle identifiers.
    public func setCustomBrowsers(_ bundleIdentifiers: Set<String>) {
        let normalized = Set(
            bundleIdentifiers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        lock.lock()
        customBundleIdentifiers = normalized
        lock.unlock()
    }

    private func isCustomBundleIdentifier(_ normalizedID: String) -> Bool {
        lock.lock()
        let contains = customBundleIdentifiers.contains(normalizedID)
        lock.unlock()
        return contains
    }

    private static func defaultAppURLsProvider() -> [URL] {
        guard let httpsURL = URL(string: "https://") else {
            logger.error("Failed to construct https:// URL for LaunchServices query")
            return []
        }
        return NSWorkspace.shared.urlsForApplications(toOpen: httpsURL)
    }

    private static func loadInfoPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }

    private static func resolveDisplayName(from infoPlist: [String: Any], bundleURL: URL) -> String {
        if let displayName = infoPlist["CFBundleDisplayName"] as? String,
           !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if let bundleName = infoPlist["CFBundleName"] as? String,
           !bundleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bundleName
        }
        return bundleURL.deletingPathExtension().lastPathComponent
    }

    private static func handlesWebBrowsing(infoPlist: [String: Any]) -> Bool {
        var supportsHTTP = false
        var supportsHTTPS = false

        if let urlTypes = infoPlist["CFBundleURLTypes"] as? [[String: Any]] {
            for entry in urlTypes {
                guard let schemes = entry["CFBundleURLSchemes"] as? [String] else {
                    continue
                }
                for scheme in schemes {
                    let lower = scheme.lowercased()
                    if lower == "http" {
                        supportsHTTP = true
                    } else if lower == "https" {
                        supportsHTTPS = true
                    }
                }
            }
        }

        guard supportsHTTP && supportsHTTPS else {
            return false
        }

        guard let documentTypes = infoPlist["CFBundleDocumentTypes"] as? [[String: Any]] else {
            return false
        }

        for entry in documentTypes {
            if let utis = entry["LSItemContentTypes"] as? [String],
               utis.contains(where: { $0.lowercased() == "public.html" }) {
                return true
            }
            if let extensions = entry["CFBundleTypeExtensions"] as? [String],
               extensions.contains(where: {
                   let lower = $0.lowercased()
                   return lower == "html" || lower == "htm"
               }) {
                return true
            }
            if let mimeTypes = entry["CFBundleTypeMIMETypes"] as? [String],
               mimeTypes.contains(where: { $0.lowercased() == "text/html" }) {
                return true
            }
        }

        return false
    }

    private static func classifyEngine(
        bundleURL: URL,
        bundleIdentifier: String,
        scriptingDialect: AppleScriptDialect
    ) -> BrowserEngine {
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let frameworksURL = contentsURL.appendingPathComponent("Frameworks", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        let frameworkNames = directoryEntryNamesLowercased(at: frameworksURL)
        let executableNames = directoryEntryNamesLowercased(at: macOSURL)

        if frameworkNames.contains("electron framework.framework") {
            return .electron
        }

        if frameworkNames.contains("chromium embedded framework.framework") {
            if hasWebKitSignature(
                bundleIdentifier: bundleIdentifier,
                frameworkNames: frameworkNames,
                macOSURL: macOSURL,
                executableNames: executableNames
            ) {
                return .dualCEFWebKit
            }
            return .cefNative
        }

        if hasChromiumFrameworkSignature(frameworkNames: frameworkNames)
            || scriptingDialect == .chromiumActiveTab
            || knownChromiumBundleIdentifiers.contains(bundleIdentifier) {
            return .chromium
        }

        if hasGeckoSignature(
            frameworkNames: frameworkNames,
            executableNames: executableNames,
            resourcesURL: resourcesURL
        ) {
            return .gecko
        }

        if hasLadybirdSignature(frameworkNames: frameworkNames, executableNames: executableNames) {
            return .ladybird
        }

        if hasWebKitSignature(
            bundleIdentifier: bundleIdentifier,
            frameworkNames: frameworkNames,
            macOSURL: macOSURL,
            executableNames: executableNames
        ) {
            return .webkit
        }

        return .unknown
    }

    private static func directoryEntryNamesLowercased(at directoryURL: URL) -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return Set(entries.map { $0.lastPathComponent.lowercased() })
    }

    private static func hasChromiumFrameworkSignature(frameworkNames: Set<String>) -> Bool {
        for name in frameworkNames {
            guard name.contains("framework") else {
                continue
            }
            if name.contains("chrome") || name.contains("chromium") || name.contains("helium") {
                return true
            }
        }
        return false
    }

    private static func hasGeckoSignature(
        frameworkNames: Set<String>,
        executableNames: Set<String>,
        resourcesURL: URL
    ) -> Bool {
        if executableNames.contains("xul") || executableNames.contains("libxul.dylib") {
            return true
        }
        if frameworkNames.contains("channelprefs.framework") {
            return true
        }
        let fileManager = FileManager.default
        let omniURL = resourcesURL.appendingPathComponent("omni.ja", isDirectory: false)
        let browserOmniURL = resourcesURL
            .appendingPathComponent("browser", isDirectory: true)
            .appendingPathComponent("omni.ja", isDirectory: false)
        return fileManager.fileExists(atPath: omniURL.path) || fileManager.fileExists(atPath: browserOmniURL.path)
    }

    private static func hasLadybirdSignature(
        frameworkNames: Set<String>,
        executableNames: Set<String>
    ) -> Bool {
        if executableNames.contains(where: { $0.contains("ladybird") }) {
            return true
        }
        if frameworkNames.contains(where: { $0.contains("ladybird") || $0.contains("libweb") }) {
            return true
        }
        return false
    }

    private static func hasWebKitSignature(
        bundleIdentifier: String,
        frameworkNames: Set<String>,
        macOSURL: URL,
        executableNames: Set<String>
    ) -> Bool {
        if knownWebKitBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        if frameworkNames.contains(where: { $0 == "webkit.framework" || $0.contains("webkit") }) {
            return true
        }

        let marker = Data("WebKit.framework".utf8)
        for executableName in executableNames {
            let executableURL = macOSURL.appendingPathComponent(executableName, isDirectory: false)
            if executableContainsMarker(executableURL, marker: marker) {
                return true
            }
        }

        return false
    }

    /// Inspects leading Mach-O header/load-command chunks (including universal fat slices) for a framework marker.
    private static func executableContainsMarker(_ executableURL: URL, marker: Data) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: executableURL) else {
            return false
        }
        defer { try? handle.close() }

        let chunkSize = 262_144
        guard let leadingChunk = try? handle.read(upToCount: chunkSize), !leadingChunk.isEmpty else {
            return false
        }
        if leadingChunk.range(of: marker) != nil {
            return true
        }
        guard leadingChunk.count >= 8 else {
            return false
        }

        let magic = readBigEndianUInt32(from: leadingChunk, at: 0)
        let isFat32 = magic == 0xCAFE_BABE
        let isFat64 = magic == 0xCAFE_BABF
        guard isFat32 || isFat64 else {
            return false
        }

        let rawArchCount = Int(readBigEndianUInt32(from: leadingChunk, at: 4))
        let archCount = min(rawArchCount, 16)
        let entrySize = isFat32 ? 20 : 32

        for index in 0..<archCount {
            let entryOffset = 8 + index * entrySize
            guard entryOffset + entrySize <= leadingChunk.count else { break }

            let sliceOffset: UInt64 = isFat32
                ? UInt64(readBigEndianUInt32(from: leadingChunk, at: entryOffset + 8))
                : readBigEndianUInt64(from: leadingChunk, at: entryOffset + 8)
            guard sliceOffset > 0 else { continue }

            do {
                try handle.seek(toOffset: sliceOffset)
                if let sliceChunk = try handle.read(upToCount: chunkSize),
                   sliceChunk.range(of: marker) != nil {
                    return true
                }
            } catch {
                continue
            }
        }

        return false
    }

    private static func readBigEndianUInt32(from data: Data, at offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    private static func readBigEndianUInt64(from data: Data, at offset: Int) -> UInt64 {
        (UInt64(readBigEndianUInt32(from: data, at: offset)) << 32)
            | UInt64(readBigEndianUInt32(from: data, at: offset + 4))
    }

    private static func sortedProfiles(_ profiles: [BrowserProfile]) -> [BrowserProfile] {
        profiles.sorted { lhs, rhs in
            let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.bundleIdentifier.localizedCaseInsensitiveCompare(rhs.bundleIdentifier) == .orderedAscending
        }
    }
}
