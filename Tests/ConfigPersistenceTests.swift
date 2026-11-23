// Unit tests for BrowserProfile, FocusSchedule, GrasslookConfigStore, and CooldownManager persistence.

import XCTest
@testable import Grasslook

final class ConfigPersistenceTests: XCTestCase {
    private var tempDirectory: URL!
    private var fixedCalendar: Calendar!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrasslookConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        fixedCalendar = calendar
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - BrowserProfile

    func testBrowserProfileCapabilityFlagsAcrossAllEngines() throws {
        let profiles: [(BrowserEngine, AppleScriptDialect, Bool, Bool, Bool)] = [
            (.webkit, .safariCurrentTab, true, false, false),
            (.chromium, .chromiumActiveTab, true, true, false),
            (.electron, .none, false, true, false),
            (.dualCEFWebKit, .documentURL, false, true, false),
            (.cefNative, .none, false, true, false),
            (.gecko, .none, false, false, true),
            (.ladybird, .none, false, false, false),
            (.unknown, .none, false, false, false)
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for (engine, dialect, expectedRedirect, expectedManualAX, expectedEnhancedUI) in profiles {
            let profile = BrowserProfile(
                bundleIdentifier: "com.Example.\(engine.rawValue)",
                displayName: engine.displayName,
                bundleURL: URL(fileURLWithPath: "/Applications/\(engine.rawValue).app"),
                engine: engine,
                scriptingDialect: dialect,
                sdefFilename: dialect.isScriptable ? "App.sdef" : nil
            )

            XCTAssertEqual(profile.id, "com.example.\(engine.rawValue.lowercased())")
            XCTAssertEqual(profile.supportsInPlaceRedirect, expectedRedirect)
            XCTAssertEqual(profile.requiresManualAccessibility, expectedManualAX)
            XCTAssertEqual(profile.requiresEnhancedUserInterface, expectedEnhancedUI)
            XCTAssertEqual(profile.scriptingDialect.isScriptable, dialect != .none)

            let encoded = try encoder.encode(profile)
            let decoded = try decoder.decode(BrowserProfile.self, from: encoded)
            XCTAssertEqual(decoded, profile)
        }

        XCTAssertEqual(BrowserAutomationStatus.notApplicable.displayName, "AX Only")
    }

    // MARK: - FocusSchedule & BreakGlassBudget

    func testFocusScheduleBoundaryMinutes() {
        let config = FocusScheduleConfig.default

        let cases: [(Int, Int, Int, FocusPhase, Bool, Bool, TimeInterval)] = [
            // day, hour, minute, phase, duskCue, strictCurfew, effectiveDelay (base 5s)
            (10, 21, 59, .daytime, false, false, 5.0),
            (10, 22, 00, .daytime, true, false, 5.0),
            (10, 22, 59, .daytime, true, false, 5.0),
            (10, 23, 00, .windDown, true, false, 20.0),
            (10, 23, 29, .windDown, true, false, 20.0),
            (10, 23, 30, .curfew, true, true, 5.0),
            (11, 00, 00, .curfew, true, true, 5.0),
            (11, 05, 59, .curfew, true, true, 5.0),
            (11, 06, 00, .daytime, false, false, 5.0)
        ]

        for (day, hour, minute, expectedPhase, expectedDusk, expectedStrict, expectedDelay) in cases {
            let date = makeUTCDate(year: 2026, month: 11, day: day, hour: hour, minute: minute)
            XCTAssertEqual(
                config.phase(at: date, calendar: fixedCalendar),
                expectedPhase,
                "Phase mismatch at day \(day) \(hour):\(minute)"
            )
            XCTAssertEqual(
                config.isDuskCueActive(at: date, calendar: fixedCalendar),
                expectedDusk,
                "Dusk cue mismatch at day \(day) \(hour):\(minute)"
            )
            XCTAssertEqual(
                config.isStrictCurfewActive(at: date, calendar: fixedCalendar),
                expectedStrict,
                "Strict curfew mismatch at day \(day) \(hour):\(minute)"
            )
            XCTAssertEqual(
                config.effectiveDelayDuration(baseDuration: 5.0, at: date, calendar: fixedCalendar),
                expectedDelay,
                "Delay mismatch at day \(day) \(hour):\(minute)"
            )
        }
    }

    func testMidnightWrappingWindDownAndDisabledSchedule() {
        var config = FocusScheduleConfig(
            isEnabled: true,
            curfewStart: TimeOfDay(hour: 0, minute: 15),
            curfewEnd: TimeOfDay(hour: 6, minute: 0),
            windDownMinutes: 30,
            windDownBreathingDuration: 25.0,
            strictness: .gentle
        )

        let beforeWindDown = makeUTCDate(year: 2026, month: 11, day: 10, hour: 23, minute: 44)
        let windDownStart = makeUTCDate(year: 2026, month: 11, day: 10, hour: 23, minute: 45)
        let windDownAfterMidnight = makeUTCDate(year: 2026, month: 11, day: 11, hour: 0, minute: 14)
        let curfewStart = makeUTCDate(year: 2026, month: 11, day: 11, hour: 0, minute: 15)

        XCTAssertEqual(config.phase(at: beforeWindDown, calendar: fixedCalendar), .daytime)
        XCTAssertEqual(config.phase(at: windDownStart, calendar: fixedCalendar), .windDown)
        XCTAssertEqual(config.phase(at: windDownAfterMidnight, calendar: fixedCalendar), .windDown)
        XCTAssertEqual(config.phase(at: curfewStart, calendar: fixedCalendar), .curfew)
        XCTAssertFalse(config.isStrictCurfewActive(at: curfewStart, calendar: fixedCalendar))
        XCTAssertEqual(config.effectiveDelayDuration(baseDuration: 5.0, at: windDownAfterMidnight, calendar: fixedCalendar), 25.0)

        config.windDownMinutes = 0
        XCTAssertEqual(config.phase(at: windDownStart, calendar: fixedCalendar), .daytime)

        config.isEnabled = false
        XCTAssertEqual(config.phase(at: curfewStart, calendar: fixedCalendar), .daytime)
        XCTAssertFalse(config.isDuskCueActive(at: curfewStart, calendar: fixedCalendar))
        XCTAssertFalse(config.isStrictCurfewActive(at: curfewStart, calendar: fixedCalendar))

        let clamped = TimeOfDay(hour: 29, minute: -5)
        XCTAssertEqual(clamped.hour, 23)
        XCTAssertEqual(clamped.minute, 0)
    }

    func testBreakGlassBudgetConsumptionAndRollover() {
        let config = FocusScheduleConfig.default
        var budget = BreakGlassBudget()

        let nightStart = makeUTCDate(year: 2026, month: 11, day: 10, hour: 23, minute: 45)
        let afterMidnight = makeUTCDate(year: 2026, month: 11, day: 11, hour: 1, minute: 30)
        let morningReset = makeUTCDate(year: 2026, month: 11, day: 11, hour: 6, minute: 0)

        XCTAssertEqual(config.rollingNightKey(for: nightStart, calendar: fixedCalendar), "2026-11-10")
        XCTAssertEqual(config.rollingNightKey(for: afterMidnight, calendar: fixedCalendar), "2026-11-10")
        XCTAssertEqual(config.rollingNightKey(for: morningReset, calendar: fixedCalendar), "2026-11-11")

        // Reject notes shorter than 4 non-whitespace characters
        XCTAssertFalse(budget.isValidIntentionNote("   ", config: config))
        XCTAssertFalse(budget.isValidIntentionNote(" ab ", config: config))
        XCTAssertFalse(budget.consumePass(at: nightStart, intentionNote: "no", config: config, calendar: fixedCalendar))
        XCTAssertEqual(budget.remainingPasses(at: nightStart, config: config, calendar: fixedCalendar), 1)

        // Consume the 1 allowed pass for the night
        XCTAssertTrue(budget.consumePass(at: nightStart, intentionNote: "Deploy hotfix", ruleName: "GitHub", config: config, calendar: fixedCalendar))
        XCTAssertEqual(budget.remainingPasses(at: nightStart, config: config, calendar: fixedCalendar), 0)
        XCTAssertFalse(budget.canUseBreakGlass(at: afterMidnight, config: config, calendar: fixedCalendar))
        XCTAssertFalse(budget.consumePass(at: afterMidnight, intentionNote: "Another try", config: config, calendar: fixedCalendar))

        // At 06:00 AM next day, rolling night key advances and budget resets
        XCTAssertTrue(budget.canUseBreakGlass(at: morningReset, config: config, calendar: fixedCalendar))
        XCTAssertEqual(budget.remainingPasses(at: morningReset, config: config, calendar: fixedCalendar), 1)

        budget.pruneExpired(before: morningReset, config: config, calendar: fixedCalendar)
        XCTAssertTrue(budget.records.isEmpty)
    }

    // MARK: - GrasslookConfigStore & CooldownManager Persistence

    func testConfigStoreRoundTripAndPruningAcrossReload() throws {
        let configURL = tempDirectory.appendingPathComponent("nested/config.json")
        let initialNow = makeUTCDate(year: 2026, month: 11, day: 10, hour: 23, minute: 45)
        let reloadNow = initialNow.addingTimeInterval(600) // +10 minutes

        let storeWriter = GrasslookConfigStore(fileURL: configURL, dateProvider: { initialNow }, calendar: fixedCalendar)

        var config = GrasslookConfig()
        config.microInterval = 1500
        config.customBrowserBundleIds = ["com.example.custom"]
        config.browserEnforcementAction = .closeTab
        config.sendCmdWToNonScriptableBrowsers = true
        config.activeCooldowns = [
            "web:expired.com": initialNow.addingTimeInterval(300), // expires at +5m
            "web:active.com": initialNow.addingTimeInterval(1200)  // expires at +20m
        ]
        _ = config.breakGlassBudget.consumePass(
            at: initialNow,
            intentionNote: "Check CI",
            ruleName: "GitHub",
            config: config.focusSchedule,
            calendar: fixedCalendar
        )

        try storeWriter.save(config)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))

        // Simulate process restart 10 minutes later (same rolling night)
        let storeReader = GrasslookConfigStore(fileURL: configURL, dateProvider: { reloadNow }, calendar: fixedCalendar)
        let loaded = try storeReader.loadThrowing()

        XCTAssertEqual(loaded.microInterval, 1500)
        XCTAssertEqual(loaded.customBrowserBundleIds, ["com.example.custom"])
        XCTAssertEqual(loaded.browserEnforcementAction, .closeTab)
        XCTAssertTrue(loaded.sendCmdWToNonScriptableBrowsers)
        XCTAssertNil(loaded.activeCooldowns["web:expired.com"])
        XCTAssertEqual(loaded.activeCooldowns["web:active.com"], initialNow.addingTimeInterval(1200))
        XCTAssertEqual(loaded.breakGlassBudget.records.count, 1)

        // Simulate process restart after 06:00 AM rolling-night rollover
        let morningNow = makeUTCDate(year: 2026, month: 11, day: 11, hour: 6, minute: 0)
        let morningReader = GrasslookConfigStore(fileURL: configURL, dateProvider: { morningNow }, calendar: fixedCalendar)
        let loadedAfterMorning = try morningReader.loadThrowing()
        XCTAssertTrue(loadedAfterMorning.breakGlassBudget.records.isEmpty)
        XCTAssertTrue(loadedAfterMorning.activeCooldowns.isEmpty)
    }

    func testCooldownManagerPersistenceCallbackAndRehydration() throws {
        let configURL = tempDirectory.appendingPathComponent("cooldown-config.json")
        let timeProvider = MockTimeProvider(
            initialDate: makeUTCDate(year: 2026, month: 11, day: 10, hour: 14, minute: 0)
        )
        let store = GrasslookConfigStore(fileURL: configURL, dateProvider: { timeProvider.currentDate() })

        let rule = TargetRule(
            name: "Reddit",
            kind: .website(domainPattern: "reddit.com"),
            cooldownDuration: 300.0
        )

        final class CallbackRecorder: @unchecked Sendable {
            private let lock = NSLock()
            var count = 0
            var lastSnapshot: [String: Date] = [:]

            func record(_ snapshot: [String: Date]) {
                lock.lock()
                count += 1
                lastSnapshot = snapshot
                lock.unlock()
            }
        }

        let recorder = CallbackRecorder()

        let manager = CooldownManager(
            initialCooldowns: ["web:stale.com": timeProvider.currentDate().addingTimeInterval(-10)],
            dateProvider: { timeProvider.currentDate() }
        )
        XCTAssertTrue(manager.activeCooldownsSnapshot().isEmpty)

        manager.setOnChange { snapshot in
            // Calling activeCooldownsSnapshot() inside onChange verifies lock is NOT held during callback.
            _ = manager.activeCooldownsSnapshot()
            recorder.record(snapshot)

            var updated = store.load()
            updated.activeCooldowns = snapshot
            try? store.save(updated)
        }

        manager.recordMindfulPass(for: rule)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertNotNil(recorder.lastSnapshot[CooldownManager.cacheKey(for: rule)])

        // Rehydrate in a fresh CooldownManager from disk
        let reloadedConfig = store.load()
        let rehydrated = CooldownManager(
            initialCooldowns: reloadedConfig.activeCooldowns,
            dateProvider: { timeProvider.currentDate() }
        )
        XCTAssertTrue(rehydrated.isUnderCooldown(for: rule))

        // Replace cooldowns should not trigger onChange
        rehydrated.setOnChange { _ in
            XCTFail("replaceCooldowns must not invoke onChange")
        }
        rehydrated.replaceCooldowns([:])
        XCTAssertFalse(rehydrated.isUnderCooldown(for: rule))

        // Expiry purge on check invokes onChange outside lock
        timeProvider.advance(by: 400)
        XCTAssertFalse(manager.isUnderCooldown(for: rule))
        XCTAssertEqual(recorder.count, 2)
        XCTAssertTrue(recorder.lastSnapshot.isEmpty)

        // clearAll invokes onChange when non-empty and skips when already empty
        manager.clearAll()
        XCTAssertEqual(recorder.count, 2)
        manager.recordMindfulPass(for: rule)
        XCTAssertEqual(recorder.count, 3)
        manager.clearAll()
        XCTAssertEqual(recorder.count, 4)
        XCTAssertTrue(recorder.lastSnapshot.isEmpty)
    }

    func testConfigStoreCorruptJSONRecoveryAndPartialSchemaDefaults() throws {
        let configURL = tempDirectory.appendingPathComponent("corrupt.json")
        try Data("{ not valid json".utf8).write(to: configURL)

        let store = GrasslookConfigStore(fileURL: configURL)
        let recovered = store.load()
        XCTAssertEqual(recovered.schemaVersion, 1)
        XCTAssertEqual(recovered.microInterval, BreakType.micro.defaultInterval)
        XCTAssertEqual(recovered.focusSchedule, FocusScheduleConfig.default)
        XCTAssertEqual(recovered.targetRules.map(\.name), TargetRule.defaults.map(\.name))
        XCTAssertThrowsError(try store.loadThrowing())

        let partialURL = tempDirectory.appendingPathComponent("partial.json")
        try Data("{\"schemaVersion\": 1, \"audioVolume\": 0.25}".utf8).write(to: partialURL)
        let partialStore = GrasslookConfigStore(fileURL: partialURL)
        let partialLoaded = try partialStore.loadThrowing()
        XCTAssertEqual(partialLoaded.audioVolume, 0.25, accuracy: 0.0001)
        XCTAssertEqual(partialLoaded.microInterval, BreakType.micro.defaultInterval)
        XCTAssertEqual(partialLoaded.focusSchedule, FocusScheduleConfig.default)
    }

    // MARK: - Helpers

    private func makeUTCDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return fixedCalendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
