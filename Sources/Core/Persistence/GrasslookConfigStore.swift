// Atomic JSON persistence store for Grasslook configuration and runtime state.

import Foundation
import os

/// Action taken when a distracting browser tab is dismissed or blocked.
public enum BrowserEnforcementAction: String, CaseIterable, Codable, Sendable, Equatable {
    case redirectToShield
    case closeTab
}

/// Complete persisted configuration and transient state for Grasslook.
public struct GrasslookConfig: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var microInterval: TimeInterval
    public var microDuration: TimeInterval
    public var longInterval: TimeInterval
    public var longDuration: TimeInterval
    public var idleThreshold: TimeInterval
    public var smartPauseEnabled: Bool
    public var preBreakWarningEnabled: Bool
    public var preBreakWarningLeadSeconds: TimeInterval
    public var targetRules: [TargetRule]
    public var customBrowserBundleIds: [String]
    public var browserEnforcementAction: BrowserEnforcementAction
    public var sendCmdWToNonScriptableBrowsers: Bool
    public var isSoundEnabled: Bool
    public var audioVolume: Float
    public var focusSchedule: FocusScheduleConfig
    public var breakGlassBudget: BreakGlassBudget
    public var activeCooldowns: [String: Date]

    /// Creates a configuration with default break intervals, friction rules, and focus schedule.
    public init(
        schemaVersion: Int = 1,
        microInterval: TimeInterval = BreakType.micro.defaultInterval,
        microDuration: TimeInterval = BreakType.micro.defaultDuration,
        longInterval: TimeInterval = BreakType.long.defaultInterval,
        longDuration: TimeInterval = BreakType.long.defaultDuration,
        idleThreshold: TimeInterval = 180.0,
        smartPauseEnabled: Bool = true,
        preBreakWarningEnabled: Bool = true,
        preBreakWarningLeadSeconds: TimeInterval = 30.0,
        targetRules: [TargetRule] = TargetRule.defaults,
        customBrowserBundleIds: [String] = [],
        browserEnforcementAction: BrowserEnforcementAction = .redirectToShield,
        sendCmdWToNonScriptableBrowsers: Bool = false,
        isSoundEnabled: Bool = true,
        audioVolume: Float = 0.7,
        focusSchedule: FocusScheduleConfig = .default,
        breakGlassBudget: BreakGlassBudget = BreakGlassBudget(),
        activeCooldowns: [String: Date] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.microInterval = microInterval
        self.microDuration = microDuration
        self.longInterval = longInterval
        self.longDuration = longDuration
        self.idleThreshold = idleThreshold
        self.smartPauseEnabled = smartPauseEnabled
        self.preBreakWarningEnabled = preBreakWarningEnabled
        self.preBreakWarningLeadSeconds = preBreakWarningLeadSeconds
        self.targetRules = targetRules
        self.customBrowserBundleIds = customBrowserBundleIds
        self.browserEnforcementAction = browserEnforcementAction
        self.sendCmdWToNonScriptableBrowsers = sendCmdWToNonScriptableBrowsers
        self.isSoundEnabled = isSoundEnabled
        self.audioVolume = audioVolume
        self.focusSchedule = focusSchedule
        self.breakGlassBudget = breakGlassBudget
        self.activeCooldowns = activeCooldowns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.microInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .microInterval) ?? BreakType.micro.defaultInterval
        self.microDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .microDuration) ?? BreakType.micro.defaultDuration
        self.longInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .longInterval) ?? BreakType.long.defaultInterval
        self.longDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .longDuration) ?? BreakType.long.defaultDuration
        self.idleThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .idleThreshold) ?? 180.0
        self.smartPauseEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartPauseEnabled) ?? true
        self.preBreakWarningEnabled = try container.decodeIfPresent(Bool.self, forKey: .preBreakWarningEnabled) ?? true
        self.preBreakWarningLeadSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .preBreakWarningLeadSeconds) ?? 30.0
        self.targetRules = try container.decodeIfPresent([TargetRule].self, forKey: .targetRules) ?? TargetRule.defaults
        self.customBrowserBundleIds = try container.decodeIfPresent([String].self, forKey: .customBrowserBundleIds) ?? []
        self.browserEnforcementAction = try container.decodeIfPresent(BrowserEnforcementAction.self, forKey: .browserEnforcementAction) ?? .redirectToShield
        self.sendCmdWToNonScriptableBrowsers = try container.decodeIfPresent(Bool.self, forKey: .sendCmdWToNonScriptableBrowsers) ?? false
        self.isSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSoundEnabled) ?? true
        self.audioVolume = try container.decodeIfPresent(Float.self, forKey: .audioVolume) ?? 0.7
        self.focusSchedule = try container.decodeIfPresent(FocusScheduleConfig.self, forKey: .focusSchedule) ?? .default
        self.breakGlassBudget = try container.decodeIfPresent(BreakGlassBudget.self, forKey: .breakGlassBudget) ?? BreakGlassBudget()
        self.activeCooldowns = try container.decodeIfPresent([String: Date].self, forKey: .activeCooldowns) ?? [:]
    }
}

/// Loads and atomically saves `GrasslookConfig` as JSON on disk.
public final class GrasslookConfigStore: @unchecked Sendable {
    public let fileURL: URL
    private let dateProvider: @Sendable () -> Date
    private let calendar: Calendar
    private let logger = Logger(subsystem: "com.grasslook.app", category: "ConfigStore")

    /// Default configuration file path in Application Support.
    public static func defaultConfigURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseDirectory
            .appendingPathComponent("Grasslook", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    /// Creates a config store backed by `fileURL`.
    public init(
        fileURL: URL = GrasslookConfigStore.defaultConfigURL(),
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.fileURL = fileURL
        self.dateProvider = dateProvider
        self.calendar = calendar
    }

    /// Loads configuration from disk, returning defaults if missing or corrupt.
    public func load() -> GrasslookConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return GrasslookConfig()
        }

        do {
            return try loadThrowing()
        } catch {
            logger.error("Failed to load config at \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return GrasslookConfig()
        }
    }

    /// Loads and prunes configuration from disk, throwing on read or decode errors.
    public func loadThrowing() throws -> GrasslookConfig {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var config = try decoder.decode(GrasslookConfig.self, from: data)

        let now = dateProvider()
        config.activeCooldowns = config.activeCooldowns.filter { $0.value > now }
        config.breakGlassBudget.pruneExpired(before: now, config: config.focusSchedule, calendar: calendar)
        return config
    }

    /// Atomically writes `config` to disk as pretty-printed ISO-8601 JSON.
    public func save(_ config: GrasslookConfig) throws {
        let parentDirectory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
