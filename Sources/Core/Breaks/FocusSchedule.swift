// Late-night focus schedule, wind-down timing, and break-glass pass budget.

import Foundation

/// Represents the current late-night focus phase.
public enum FocusPhase: String, CaseIterable, Codable, Sendable, Equatable {
    case daytime
    case windDown
    case curfew
}

/// Controls how strictly curfew enforcement blocks distracting targets.
public enum StrictnessLevel: String, CaseIterable, Codable, Sendable, Equatable {
    case gentle
    case curfewStrict
}

/// Wall-clock hour and minute clamped to valid 24-hour bounds.
public struct TimeOfDay: Codable, Sendable, Equatable, Hashable {
    public var hour: Int {
        didSet { hour = Self.clampHour(hour) }
    }

    public var minute: Int {
        didSet { minute = Self.clampMinute(minute) }
    }

    /// Total minutes elapsed since midnight (0...1439).
    public var minutesFromMidnight: Int {
        hour * 60 + minute
    }

    /// Creates a clamped wall-clock time of day.
    public init(hour: Int, minute: Int) {
        self.hour = Self.clampHour(hour)
        self.minute = Self.clampMinute(minute)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawHour = try container.decode(Int.self, forKey: .hour)
        let rawMinute = try container.decode(Int.self, forKey: .minute)
        self.hour = Self.clampHour(rawHour)
        self.minute = Self.clampMinute(rawMinute)
    }

    private enum CodingKeys: String, CodingKey {
        case hour
        case minute
    }

    private static func clampHour(_ value: Int) -> Int {
        min(max(value, 0), 23)
    }

    private static func clampMinute(_ value: Int) -> Int {
        min(max(value, 0), 59)
    }
}

/// Configuration and pure evaluation logic for late-night wind-down and curfew.
public struct FocusScheduleConfig: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var curfewStart: TimeOfDay
    public var curfewEnd: TimeOfDay
    public var windDownMinutes: Int
    public var windDownBreathingDuration: TimeInterval
    public var strictness: StrictnessLevel
    public var duskCueStart: TimeOfDay
    public var breakGlassPassesPerNight: Int
    public var breakGlassWaitSeconds: TimeInterval
    public var breakGlassMinNoteLength: Int

    /// Default late-night focus schedule configuration.
    public static let `default` = FocusScheduleConfig()

    /// Creates a focus schedule configuration with default curfew and break-glass rules.
    public init(
        isEnabled: Bool = true,
        curfewStart: TimeOfDay = TimeOfDay(hour: 23, minute: 30),
        curfewEnd: TimeOfDay = TimeOfDay(hour: 6, minute: 0),
        windDownMinutes: Int = 30,
        windDownBreathingDuration: TimeInterval = 20.0,
        strictness: StrictnessLevel = .curfewStrict,
        duskCueStart: TimeOfDay = TimeOfDay(hour: 22, minute: 0),
        breakGlassPassesPerNight: Int = 1,
        breakGlassWaitSeconds: TimeInterval = 30.0,
        breakGlassMinNoteLength: Int = 4
    ) {
        self.isEnabled = isEnabled
        self.curfewStart = curfewStart
        self.curfewEnd = curfewEnd
        self.windDownMinutes = windDownMinutes
        self.windDownBreathingDuration = windDownBreathingDuration
        self.strictness = strictness
        self.duskCueStart = duskCueStart
        self.breakGlassPassesPerNight = breakGlassPassesPerNight
        self.breakGlassWaitSeconds = breakGlassWaitSeconds
        self.breakGlassMinNoteLength = breakGlassMinNoteLength
    }

    /// Evaluates the active focus phase at the given date.
    public func phase(at date: Date, calendar: Calendar = .current) -> FocusPhase {
        guard isEnabled else { return .daytime }

        let minutes = Self.minutesFromMidnight(for: date, calendar: calendar)
        let curfewStartMin = curfewStart.minutesFromMidnight
        let curfewEndMin = curfewEnd.minutesFromMidnight

        if Self.isMinute(minutes, inHalfOpenRangeFrom: curfewStartMin, to: curfewEndMin) {
            return .curfew
        }

        if windDownMinutes > 0 {
            let clampedWindDown = min(windDownMinutes, 1439)
            let windDownStartMin = ((curfewStartMin - clampedWindDown) % 1440 + 1440) % 1440
            if Self.isMinute(minutes, inHalfOpenRangeFrom: windDownStartMin, to: curfewStartMin) {
                return .windDown
            }
        }

        return .daytime
    }

    /// Returns true when strict curfew enforcement is currently active.
    public func isStrictCurfewActive(at date: Date, calendar: Calendar = .current) -> Bool {
        isEnabled && strictness == .curfewStrict && phase(at: date, calendar: calendar) == .curfew
    }

    /// Returns true when the evening dusk visual cue window is active.
    public func isDuskCueActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let minutes = Self.minutesFromMidnight(for: date, calendar: calendar)
        return Self.isMinute(
            minutes,
            inHalfOpenRangeFrom: duskCueStart.minutesFromMidnight,
            to: curfewEnd.minutesFromMidnight
        )
    }

    /// Returns the breathing delay duration adjusted for the current focus phase.
    public func effectiveDelayDuration(
        baseDuration: TimeInterval,
        at date: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        if phase(at: date, calendar: calendar) == .windDown {
            return max(baseDuration, windDownBreathingDuration)
        }
        return baseDuration
    }

    /// Returns the `YYYY-MM-DD` key of the evening that started the current night window.
    public func rollingNightKey(for date: Date, calendar: Calendar = .current) -> String {
        let minutes = Self.minutesFromMidnight(for: date, calendar: calendar)
        let anchorDate: Date
        if minutes < curfewEnd.minutesFromMidnight,
           let previousDay = calendar.date(byAdding: .day, value: -1, to: date) {
            anchorDate = previousDay
        } else {
            anchorDate = date
        }

        let components = calendar.dateComponents([.year, .month, .day], from: anchorDate)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func minutesFromMidnight(for date: Date, calendar: Calendar) -> Int {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return hour * 60 + minute
    }

    private static func isMinute(_ minute: Int, inHalfOpenRangeFrom start: Int, to end: Int) -> Bool {
        if start == end {
            return false
        }
        if start < end {
            return minute >= start && minute < end
        }
        return minute >= start || minute < end
    }
}

/// Records a single break-glass override used during curfew.
public struct BreakGlassRecord: Codable, Sendable, Equatable {
    public let nightKey: String
    public let usedAt: Date
    public let intentionNote: String
    public let ruleName: String?

    /// Creates a break-glass usage record.
    public init(nightKey: String, usedAt: Date, intentionNote: String, ruleName: String? = nil) {
        self.nightKey = nightKey
        self.usedAt = usedAt
        self.intentionNote = intentionNote
        self.ruleName = ruleName
    }
}

/// Tracks and enforces nightly break-glass pass allowances.
public struct BreakGlassBudget: Codable, Sendable, Equatable {
    public private(set) var records: [BreakGlassRecord]

    /// Creates a break-glass budget from persisted records.
    public init(records: [BreakGlassRecord] = []) {
        self.records = records
    }

    /// Number of break-glass passes remaining for the rolling night containing `date`.
    public func remainingPasses(
        at date: Date,
        config: FocusScheduleConfig,
        calendar: Calendar = .current
    ) -> Int {
        let key = config.rollingNightKey(for: date, calendar: calendar)
        let usedCount = records.filter { $0.nightKey == key }.count
        return max(0, config.breakGlassPassesPerNight - usedCount)
    }

    /// Returns true if at least one break-glass pass remains for the current rolling night.
    public func canUseBreakGlass(
        at date: Date,
        config: FocusScheduleConfig,
        calendar: Calendar = .current
    ) -> Bool {
        remainingPasses(at: date, config: config, calendar: calendar) > 0
    }

    /// Validates that an intention note meets the minimum non-whitespace length requirement.
    public func isValidIntentionNote(_ note: String, config: FocusScheduleConfig) -> Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).count >= config.breakGlassMinNoteLength
    }

    /// Consumes a break-glass pass if budget remains and the intention note is valid.
    public mutating func consumePass(
        at date: Date,
        intentionNote: String,
        ruleName: String? = nil,
        config: FocusScheduleConfig,
        calendar: Calendar = .current
    ) -> Bool {
        guard canUseBreakGlass(at: date, config: config, calendar: calendar),
              isValidIntentionNote(intentionNote, config: config) else {
            return false
        }

        let trimmedNote = intentionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = BreakGlassRecord(
            nightKey: config.rollingNightKey(for: date, calendar: calendar),
            usedAt: date,
            intentionNote: trimmedNote,
            ruleName: ruleName
        )
        records.append(record)
        return true
    }

    /// Drops break-glass records that do not belong to the rolling night of `date`.
    public mutating func pruneExpired(
        before date: Date,
        config: FocusScheduleConfig,
        calendar: Calendar = .current
    ) {
        let currentNightKey = config.rollingNightKey(for: date, calendar: calendar)
        records.removeAll { $0.nightKey != currentNightKey }
    }
}
