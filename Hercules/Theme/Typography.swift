import SwiftUI

enum Typography {
    static func display(_ size: CGFloat = 56) -> Font {
        .system(size: size, weight: .light, design: .default)
            .monospacedDigit()
    }

    static func hero(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .regular, design: .default)
            .monospacedDigit()
    }

    // Slightly lighter weights across the board — less "shouty"
    static let title       = Font.system(size: 21, weight: .medium)
    static let titleSmall  = Font.system(size: 16, weight: .medium)
    static let headline    = Font.system(size: 14, weight: .medium)
    static let body        = Font.system(size: 13, weight: .regular)
    static let bodyBold    = Font.system(size: 13, weight: .medium)
    static let caption     = Font.system(size: 11, weight: .regular)
    static let captionBold = Font.system(size: 11, weight: .medium)
    static let micro       = Font.system(size: 10, weight: .medium)

    static let mono      = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoLarge = Font.system(size: 17, weight: .regular, design: .monospaced)

    static let label = Font.system(size: 9.5, weight: .medium).leading(.tight)
}

extension Text {
    /// Buzz alt-bölüm etiketi (SubsectionLabel): 10pt semibold, uppercase,
    /// geniş izleme, muted — bölüm başlıklarının sessiz üst satırı.
    func eyebrow() -> some View {
        self.font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Palette.textTertiary)
    }
}
