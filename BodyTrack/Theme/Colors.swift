import SwiftUI

enum Palette {
    // Surfaces — lifted off pure black so contrast with text is gentler
    static let background      = Color(red: 0.070, green: 0.070, blue: 0.078)
    static let surface         = Color(red: 0.105, green: 0.105, blue: 0.115)
    static let surfaceElevated = Color(red: 0.145, green: 0.145, blue: 0.155)

    static let border       = Color.white.opacity(0.055)
    static let borderStrong = Color.white.opacity(0.105)

    // Text — primary still bright, but secondary/tertiary lifted so they're readable not just present
    static let textPrimary    = Color.white.opacity(0.94)
    static let textSecondary  = Color.white.opacity(0.66)
    static let textTertiary   = Color.white.opacity(0.46)
    static let textQuaternary = Color.white.opacity(0.28)

    // Accent — softer warm coral, still red but ~30% less saturated than before
    static let accent     = Color(red: 0.93, green: 0.48, blue: 0.45)
    static let accentSoft = Color(red: 0.93, green: 0.48, blue: 0.45).opacity(0.16)
    static let accentDim  = Color(red: 0.93, green: 0.48, blue: 0.45).opacity(0.38)

    // State colors — same family saturation, less aggressive
    static let positive = Color(red: 0.46, green: 0.78, blue: 0.62)
    static let negative = Color(red: 0.93, green: 0.52, blue: 0.50)
    static let warning  = Color(red: 0.94, green: 0.78, blue: 0.50)

    // Macro colors — all at similar low saturation so none "screams" louder than the others
    static let macroProtein = Color(red: 0.92, green: 0.52, blue: 0.50) // soft coral
    static let macroCarbs   = Color(red: 0.55, green: 0.78, blue: 0.68) // soft sage
    static let macroFat     = Color(red: 0.94, green: 0.80, blue: 0.52) // soft amber

    static let chartGrid       = Color.white.opacity(0.035)
    static let chartBand       = Color.white.opacity(0.055)
    static let chartBandStrong = Color.white.opacity(0.10)
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}
