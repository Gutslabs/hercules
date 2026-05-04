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

    static let title = Font.system(size: 22, weight: .semibold)
    static let titleSmall = Font.system(size: 17, weight: .semibold)
    static let headline = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyBold = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionBold = Font.system(size: 11, weight: .semibold)
    static let micro = Font.system(size: 10, weight: .medium)

    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoLarge = Font.system(size: 17, weight: .medium, design: .monospaced)

    static let label = Font.system(size: 10, weight: .semibold).leading(.tight)
}

extension Text {
    func eyebrow() -> some View {
        self.font(Typography.label)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Palette.textTertiary)
    }
}
