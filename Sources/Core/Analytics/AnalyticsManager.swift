import Foundation

/// Tracks break and delay statistics locally.
@MainActor
public final class AnalyticsManager: ObservableObject {
    @Published public private(set) var breaksTaken: Int = 0
    @Published public private(set) var breaksSkipped: Int = 0
    @Published public private(set) var distractionsAvoided: Int = 0
    @Published public private(set) var distractionsContinued: Int = 0
    @Published public private(set) var totalMindfulSeconds: TimeInterval = 0

    private let userDefaults: UserDefaults

    private enum Keys {
        static let breaksTaken = "grasslook.stats.breaksTaken"
        static let breaksSkipped = "grasslook.stats.breaksSkipped"
        static let distractionsAvoided = "grasslook.stats.distractionsAvoided"
        static let distractionsContinued = "grasslook.stats.distractionsContinued"
        static let mindfulSeconds = "grasslook.stats.mindfulSeconds"
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadStats()
    }

    public func recordBreakTaken(type: BreakType, duration: TimeInterval) {
        breaksTaken += 1
        totalMindfulSeconds += duration
        saveStats()
    }

    public func recordBreakSkipped(type: BreakType) {
        breaksSkipped += 1
        saveStats()
    }

    public func recordDistractionAvoided(delayDuration: TimeInterval) {
        distractionsAvoided += 1
        totalMindfulSeconds += delayDuration
        saveStats()
    }

    public func recordDistractionContinued(delayDuration: TimeInterval) {
        distractionsContinued += 1
        totalMindfulSeconds += delayDuration
        saveStats()
    }

    public func resetStats() {
        breaksTaken = 0
        breaksSkipped = 0
        distractionsAvoided = 0
        distractionsContinued = 0
        totalMindfulSeconds = 0
        saveStats()
    }

    public var mindfulMinutes: Int {
        Int(totalMindfulSeconds / 60.0)
    }

    public var breakComplianceRate: Double {
        let total = breaksTaken + breaksSkipped
        guard total > 0 else { return 1.0 }
        return Double(breaksTaken) / Double(total)
    }

    public var focusSuccessRate: Double {
        let total = distractionsAvoided + distractionsContinued
        guard total > 0 else { return 1.0 }
        return Double(distractionsAvoided) / Double(total)
    }

    private func loadStats() {
        breaksTaken = userDefaults.integer(forKey: Keys.breaksTaken)
        breaksSkipped = userDefaults.integer(forKey: Keys.breaksSkipped)
        distractionsAvoided = userDefaults.integer(forKey: Keys.distractionsAvoided)
        distractionsContinued = userDefaults.integer(forKey: Keys.distractionsContinued)
        totalMindfulSeconds = userDefaults.double(forKey: Keys.mindfulSeconds)
    }

    private func saveStats() {
        userDefaults.set(breaksTaken, forKey: Keys.breaksTaken)
        userDefaults.set(breaksSkipped, forKey: Keys.breaksSkipped)
        userDefaults.set(distractionsAvoided, forKey: Keys.distractionsAvoided)
        userDefaults.set(distractionsContinued, forKey: Keys.distractionsContinued)
        userDefaults.set(totalMindfulSeconds, forKey: Keys.mindfulSeconds)
    }
}
