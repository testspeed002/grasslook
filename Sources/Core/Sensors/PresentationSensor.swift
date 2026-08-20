import Foundation
import AppKit

public protocol PresentationSensorProtocol: Sendable {
    /// Returns true if a presentation, video meeting, or do-not-disturb activity is active.
    func isPresentationOrMeetingActive() -> Bool
}

/// Native sensor checking frontmost app fullscreen state and meeting apps.
public struct SystemPresentationSensor: PresentationSensorProtocol {
    private let meetingBundleIds: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.apple.FaceTime",
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan" // Google Meet PWA
    ]

    public init() {}

    public func isPresentationOrMeetingActive() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        
        // 1. Check if frontmost application is a known meeting tool
        if let bundleId = frontmost.bundleIdentifier, meetingBundleIds.contains(bundleId) {
            return true
        }

        // 2. Check if frontmost application is Keynote / PowerPoint / Presentation
        if let bundleId = frontmost.bundleIdentifier {
            if bundleId.contains("Keynote") || bundleId.contains("Powerpoint") {
                return true
            }
        }

        return false
    }
}

/// Mock presentation sensor for testing.
public final class MockPresentationSensor: PresentationSensorProtocol, @unchecked Sendable {
    public var isMeetingActive: Bool = false

    public init(isMeetingActive: Bool = false) {
        self.isMeetingActive = isMeetingActive
    }

    public func isPresentationOrMeetingActive() -> Bool {
        return isMeetingActive
    }
}
