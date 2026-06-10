import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ProfileAvatar: View {
    let initial: String
    let color: Color
    @State private var active = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.32), Palette.surfaceElevated],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .strokeBorder(active ? Palette.borderStrong : Palette.border, lineWidth: 0.8)
                    .scaleEffect(active ? 1.04 : 0.98)
                Text(initial)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: 74, height: 74)

            Circle()
                .fill(Palette.positive)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                .offset(x: -4, y: -4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

struct ProfileBreathingStatusDot: View {
    let color: Color
    @State private var active = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(active ? 0.22 : 0.08))
                .frame(width: 20, height: 20)
                .scaleEffect(active ? 1.08 : 0.82)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

struct ProfileNudgeRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.warning)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Palette.warning.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.warning.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

struct ProfileEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
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

struct ProfileHeroLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rowHeight = rect.height / 5
        for index in 0...5 {
            let y = CGFloat(index) * rowHeight
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: y))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: y + rowHeight * 0.34),
                control1: CGPoint(x: rect.midX * 0.72, y: y - 24),
                control2: CGPoint(x: rect.midX * 1.28, y: y + 38)
            )
        }
        return path
    }
}

struct ProfileBackgroundLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let columns = 7
        for index in 0...columns {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(columns)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.width * 0.18, y: rect.maxY))
        }
        let rows = 5
        for index in 0...rows {
            let y = rect.minY + rect.height * CGFloat(index) / CGFloat(rows)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y + rect.height * 0.08))
        }
        return path
    }
}

struct SexSwitch: View {
    @Binding var sex: Sex
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Sex.allCases) { s in
                Button { sex = s } label: {
                    Text(s.label)
                        .font(.system(size: 12, weight: sex == s ? .semibold : .medium))
                        .foregroundStyle(sex == s ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(sex == s ? Palette.track : Color.clear)
                        )
                }
                .buttonStyle(ProfilePressButtonStyle())
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
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

struct NumberField: View {
    @Binding var value: Double?
    var unit: String
    var digits: Int = 1
    var placeholder: String = "0"

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, value: $value, format: .number.precision(.fractionLength(0...digits)).locale(Locale(identifier: "tr_TR")))
                .textFieldStyle(.plain)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct ActivityPicker: View {
    @Binding var selection: ActivityLevel

    var body: some View {
        Menu {
            ForEach(ActivityLevel.allCases) { a in
                Button {
                    selection = a
                } label: {
                    if a == selection {
                        Label("\(a.label) · ×\(Fmt.num(a.multiplier, digits: 2))", systemImage: "checkmark")
                    } else {
                        Text("\(a.label) · ×\(Fmt.num(a.multiplier, digits: 2))")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.surfaceElevated))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aktivite").eyebrow()
                    Text(selection.label)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("×\(Fmt.num(selection.multiplier, digits: 2)) çarpan")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

struct GoalPicker: View {
    @Binding var selection: Goal

    var body: some View {
        Menu {
            ForEach(Goal.allCases) { g in
                Button {
                    selection = g
                } label: {
                    if g == selection {
                        Label("\(g.label) · \(g.detail)", systemImage: "checkmark")
                    } else {
                        Text("\(g.label) · \(g.detail)")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "target")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.surfaceElevated))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hedef").eyebrow()
                    Text(selection.label)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(selection.detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

// MARK: - Workout schedule
