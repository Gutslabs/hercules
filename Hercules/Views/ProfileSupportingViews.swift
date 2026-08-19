import SwiftUI
import LucideKit
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ProfileEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Lucide(sf: icon, size: 18)
                .foregroundStyle(Palette.warning)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.warning.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

struct ProfilePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct ProfilePanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var fill: Color
    var accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
    }
}

extension View {
    func profilePanel(
        cornerRadius: CGFloat = Radius.lg,
        fill: Color = Palette.surface,
        accent: Color = Palette.border
    ) -> some View {
        modifier(ProfilePanelModifier(cornerRadius: cornerRadius, fill: fill, accent: accent))
    }

    func profileReveal(_ visible: Bool, delay: Double) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 10)
            .animation(.spring(response: 0.44, dampingFraction: 0.86).delay(delay), value: visible)
    }
}

// MARK: - Workout schedule
