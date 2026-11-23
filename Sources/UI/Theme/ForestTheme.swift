import SwiftUI

/// Forest green color palette for Grasslook.
public enum ForestTheme {
    /// Dark pine green (#0B1C13)
    public static let deepPine = Color(red: 0.04, green: 0.11, blue: 0.07)

    /// Dark forest green (#1A4329)
    public static let forest = Color(red: 0.10, green: 0.26, blue: 0.16)

    /// Medium green (#2D6A4F)
    public static let lush = Color(red: 0.18, green: 0.42, blue: 0.31)

    /// Accent green (#40916C)
    public static let foliage = Color(red: 0.25, green: 0.57, blue: 0.42)

    /// Sage green (#52B788)
    public static let sage = Color(red: 0.32, green: 0.72, blue: 0.53)

    /// Light green (#74C69D)
    public static let leaf = Color(red: 0.45, green: 0.78, blue: 0.62)

    /// Pale green (#D8F3DC)
    public static let mist = Color(red: 0.85, green: 0.95, blue: 0.86)

    /// Gradient for buttons and progress rings
    public static var lushGradient: LinearGradient {
        LinearGradient(
            colors: [lush, sage],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Gradient for countdown rings
    public static var glowGradient: LinearGradient {
        LinearGradient(
            colors: [sage, leaf],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Gradient for breathing animations
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
