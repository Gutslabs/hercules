import SwiftUI
import SwiftData

struct DayCell: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let consumed: Double
    let target: Double
    let monthlyGoal: MonthlyGoal?
    let onTap: () -> Void
    let onGoalTap: (MonthlyGoal) -> Void

    @State private var hovering = false

    private var dayNumber: String {
        Fmt.dayNumber.string(from: date)
    }

    private var ratio: Double {
        guard target > 0 else { return 0 }
        return min(1.0, consumed / target)
    }

    private var hasFood: Bool {
        consumed > 0
    }

    private var barColor: Color {
        guard target > 0, consumed > 0 else { return Palette.border }
        let r = consumed / target
        if r < 0.85 { return Palette.macroCarbs }
        if r <= 1.10 { return Palette.positive }
        if r <= 1.30 { return Palette.warning }
        return Palette.accent
    }

    private var dayColor: Color {
        if isToday { return Palette.accent }
        if inMonth { return Palette.textPrimary }
        return Palette.textQuaternary
    }

    private var borderColor: Color {
        if isSelected { return Palette.accent.opacity(0.62) }
        if isToday { return Palette.accent.opacity(0.55) }
        if hovering { return Palette.borderStrong }
        return Palette.border.opacity(inMonth ? 1 : 0.65)
    }

    private var fillColor: Color {
        if isSelected { return Palette.surfaceElevated.opacity(0.92) }
        if hovering { return Palette.surfaceElevated.opacity(0.72) }
        return Palette.surface.opacity(inMonth ? 0.70 : 0.34)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: 6) {
                    Text(dayNumber)
                        .font(.system(size: isToday ? 15 : 13, weight: isToday ? .semibold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(dayColor)

                    if isToday {
                        Text("BUGÜN")
                            .font(.system(size: 8.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.accent.opacity(0.14)))
                    }
                }

                Spacer(minLength: 0)

                if let g = monthlyGoal {
                    Button { onGoalTap(g) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "scope")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("\(Fmt.num(g.targetWeight, digits: 1)) kg")
                                .font(.system(size: 9.5, weight: .medium))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.surfaceElevated.opacity(0.78)))
                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        if hasFood {
                            Text("\(Fmt.int(consumed))")
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        } else {
                            Text("—")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Palette.textQuaternary)
                        }
                        Text("kcal")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textQuaternary)
                            .lineLimit(1)
                    }
                    // mini progress
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Palette.border)
                                .frame(height: 2.5)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(barColor)
                                .frame(width: max(0, geo.size.width * ratio), height: 2.5)
                        }
                    }
                        .frame(height: 2.5)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Palette.accent)
                        .frame(width: 2.5)
                        .padding(.vertical, 10)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected || isToday ? 0.85 : 0.5)
            )
            .opacity(inMonth ? 1.0 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.004 : 1)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct GoalRoadmapRow: View {
    let goal: MonthlyGoal
    let index: Int
    let isReached: Bool
    let currentWeight: Double?
    let onTap: () -> Void
    @State private var hovering = false

    private var monthLabel: String {
        Fmt.monthShort.string(from: goal.anchorDate).uppercased()
    }

    private var deltaText: String? {
        guard let currentWeight else { return nil }
        let diff = currentWeight - goal.targetWeight
        if abs(diff) < 0.05 { return "hedefte" }
        return diff > 0 ? "−\(Fmt.num(diff, digits: 1)) kg" : "+\(Fmt.num(abs(diff), digits: 1)) kg"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(isReached ? Palette.positive.opacity(0.16) : Palette.surfaceElevated)
                    Text("\(index)")
                        .font(Typography.captionBold)
                        .foregroundStyle(isReached ? Palette.positive : Palette.textSecondary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(monthLabel)
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.textTertiary)
                        if isReached {
                            Text("GEÇTİ")
                                .font(.system(size: 8.5, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Palette.positive)
                        }
                    }
                    Text("\(Fmt.num(goal.targetWeight, digits: 1)) kg")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: Spacing.sm)

                if let deltaText {
                    Text(deltaText)
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hovering ? Palette.accent : Palette.textQuaternary)
                    .opacity(hovering ? 1 : 0.4)
                    .help("Düzenle")
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(hovering ? Palette.surfaceElevated.opacity(0.76) : Palette.surface.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(hovering ? Palette.borderStrong : Palette.border, lineWidth: 0.55)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.004 : 1)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}


// MARK: - Plan setup sheet
