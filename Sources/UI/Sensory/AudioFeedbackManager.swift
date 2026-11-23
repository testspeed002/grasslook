import Foundation
import AppKit
import Combine

@MainActor
public protocol AudioFeedbackProtocol: AnyObject {
    func playBreakStartChime()
    func playBreakEndChime()
    func playBreathingCue()
}

/// Plays sound cues for breaks and breathing delays.
@MainActor
public final class AudioFeedbackManager: ObservableObject, AudioFeedbackProtocol {
    @Published public var isSoundEnabled: Bool = true
    @Published public var volume: Float = 0.6
    @Published public var breathingSoundName: String = "Breeze"

    public init(isSoundEnabled: Bool = true, volume: Float = 0.6, breathingSoundName: String = "Breeze") {
        self.isSoundEnabled = isSoundEnabled
        self.volume = volume
        self.breathingSoundName = breathingSoundName
    }

    public func playBreakStartChime() {
        guard isSoundEnabled else { return }
        if let sound = NSSound(named: "Glass") {
            sound.volume = volume
            sound.play()
        }
    }

    public func playBreakEndChime() {
        guard isSoundEnabled else { return }
        if let sound = NSSound(named: "Hero") {
            sound.volume = volume
            sound.play()
        }
    }

    public func playBreathingCue() {
        guard isSoundEnabled else { return }
        // Play Breeze sound cue, with graceful fallback to system airy Blow chime if Breeze is not bundled
        if let sound = NSSound(named: breathingSoundName) {
            sound.volume = volume
            sound.play()
        } else if let fallback = NSSound(named: "Blow") ?? NSSound(named: "Tink") {
            fallback.volume = volume
            fallback.play()
        }
    }
}
