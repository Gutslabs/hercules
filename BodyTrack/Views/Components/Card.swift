import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.xl
    var cornerRadius: CGFloat = Radius.lg
    let content: Content

    init(padding: CGFloat = Spacing.xl, cornerRadius: CGFloat = Radius.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
    }
}

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow).eyebrow()
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
    }
}

struct PillTag: View {
    let text: String
    var tint: Color = Palette.textSecondary
    var body: some View {
        Text(text)
            .font(Typography.captionBold)
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(tint.opacity(0.10))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
            )
    }
}
