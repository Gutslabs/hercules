import SwiftUI

enum Palette {
    static let background = Color(red: 0.02, green: 0.02, blue: 0.02)
    static let surface = Color(red: 0.045, green: 0.045, blue: 0.05)
    static let surfaceElevated = Color(red: 0.07, green: 0.07, blue: 0.075)
    static let border = Color.white.opacity(0.06)
    static let borderStrong = Color.white.opacity(0.12)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)
    static let textQuaternary = Color.white.opacity(0.22)

    static let accent = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let accentSoft = Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.18)
    static let accentDim = Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.42)

    static let positive = Color(red: 0.30, green: 0.78, blue: 0.55)
    static let negative = Color(red: 0.95, green: 0.40, blue: 0.40)
    static let warning = Color(red: 0.97, green: 0.72, blue: 0.30)

    static let macroProtein = Color(red: 0.94, green: 0.27, blue: 0.27)   // red
    static let macroCarbs   = Color(red: 0.30, green: 0.78, blue: 0.55)   // green
    static let macroFat     = Color(red: 0.98, green: 0.82, blue: 0.30)   // yellow

    static let chartGrid = Color.white.opacity(0.04)
    static let chartBand = Color.white.opacity(0.07)
    static let chartBandStrong = Color.white.opacity(0.12)
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
