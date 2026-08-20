import SwiftUI

/// Unified monochromatic lush forest green design system for Grasslook.
public enum ForestTheme {
    /// Deep evergreen pine (#0B1C13)
    public static let deepPine = Color(red: 0.04, green: 0.11, blue: 0.07)

    /// Rich forest emerald (#1A4329)
    public static let forest = Color(red: 0.10, green: 0.26, blue: 0.16)

    /// Lush primary meadow (#2D6A4F)
    public static let lush = Color(red: 0.18, green: 0.42, blue: 0.31)

    /// Foliage accent green (#40916C)
    public static let foliage = Color(red: 0.25, green: 0.57, blue: 0.42)

    /// Calming herbal sage (#52B788)
    public static let sage = Color(red: 0.32, green: 0.72, blue: 0.53)

    /// Soft morning dew leaf (#74C69D)
    public static let leaf = Color(red: 0.45, green: 0.78, blue: 0.62)

    /// Pale mist green highlight (#D8F3DC)
    public static let mist = Color(red: 0.85, green: 0.95, blue: 0.86)

    /// Lush linear gradient for badges, buttons, and progress rings
    public static var lushGradient: LinearGradient {
        LinearGradient(
            colors: [lush, sage],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Soft glow gradient for countdowns and resting halos
    public static var glowGradient: LinearGradient {
        LinearGradient(
            colors: [sage, leaf],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Atmospheric radial gradient for mindful breathing and eye rest
    public static var atmosphericGradient: RadialGradient {
        RadialGradient(
            colors: [
                foliage.opacity(0.40),
                lush.opacity(0.20),
                Color.clear
            ],
            center: .center,
            startRadius: 20,
            endRadius: 130
        )
    }
}
