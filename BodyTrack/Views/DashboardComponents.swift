import SwiftUI
import SwiftData

enum DashboardBalancePeriod: String, CaseIterable, Identifiable {
    case week, month, threeMonths, year, allTime

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .week: return "1W"
        case .month: return "1M"
        case .threeMonths: return "3M"
        case .year: return "1Y"
        case .allTime: return "ALL"
        }
    }

    var title: String {
        switch self {
        case .week: return "Son 7 gün"
        case .month: return "Son 30 gün"
        case .threeMonths: return "Son 90 gün"
        case .year: return "Son 365 gün"
        case .allTime: return "Tüm zaman"
        }
    }

    func startDate(endingAt todayStart: Date, calendar: Calendar) -> Date? {
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: todayStart)
        case .month:
            return calendar.date(byAdding: .day, value: -29, to: todayStart)
        case .threeMonths:
            return calendar.date(byAdding: .day, value: -89, to: todayStart)
        case .year:
            return calendar.date(byAdding: .day, value: -364, to: todayStart)
        case .allTime:
            return nil
        }
    }
}

struct DashboardBalanceSummary {
    let period: DashboardBalancePeriod
    let startDate: Date
    let endDate: Date
    let netDeficit: Double
    let foodCalories: Double
    let baseCalories: Double
    let stepCalories: Double
    let workoutCalories: Double
    let stepCount: Int
    let workoutDays: Int
    let trackedDays: Int
    let calendarDays: Int

    var displayValue: String {
        guard trackedDays > 0 else { return "0" }
        let value = abs(netDeficit)
        return netDeficit < 0 ? "+\(Fmt.int(value))" : Fmt.int(value)
    }

    var resultLabel: String {
        guard trackedDays > 0 else { return "kcal" }
        if abs(netDeficit) < 1 { return "kcal dengede" }
        return netDeficit >= 0 ? "kcal açık" : "kcal fazla"
    }

    var tint: Color {
        guard trackedDays > 0 else { return Palette.textTertiary }
        if netDeficit < 0 { return Palette.negative }
        if netDeficit < 500 { return Palette.warning }
        return Palette.positive
    }

    var detail: String {
        guard trackedDays > 0 else {
            return "\(period.title) içinde yemek kaydı olan gün yok; açık hesaplanmadı."
        }
        let avg = netDeficit / Double(max(trackedDays, 1))
        let direction = netDeficit >= 0 ? "ortalama \(Fmt.int(abs(avg))) kcal açık" : "ortalama \(Fmt.int(abs(avg))) kcal fazla"
        return "\(trackedDays) yemek kayıtlı gün üzerinden \(direction)."
    }
}

struct DashboardBackground: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Palette.background
            VStack(spacing: 72) {
                ForEach(0..<18, id: \.self) { _ in
                    Rectangle()
                        .fill(Palette.border.opacity(0.55))
                        .frame(height: 0.5)
                }
            }
            .padding(.top, 42)
            HStack(spacing: 96) {
                ForEach(0..<12, id: \.self) { _ in
                    Rectangle()
                        .fill(Palette.border.opacity(0.28))
                        .frame(width: 0.5)
                }
            }
            .padding(.leading, 44)
        }
    }
}

struct DashboardHeroLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows: [CGFloat] = [0.18, 0.36, 0.58, 0.78]
        for (index, row) in rows.enumerated() {
            let y = rect.height * row
            path.move(to: CGPoint(x: rect.minX + CGFloat(index) * 18, y: y))
            path.addCurve(
                to: CGPoint(x: rect.maxX - CGFloat(index) * 10, y: y + CGFloat(index - 1) * 10),
                control1: CGPoint(x: rect.midX * 0.72, y: y - 36),
                control2: CGPoint(x: rect.midX * 1.18, y: y + 42)
            )
        }
        return path
    }
}

struct DashboardBreathingStatusDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 2.7 : 1)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

struct CalorieProgressRing: View {
    let progress: Double
    let tint: Color
    let value: String
    let label: String
    let subtitle: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.borderStrong, lineWidth: 13)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .stroke(tint.opacity(0.12), lineWidth: 1)
                .scaleEffect(pulse ? 0.92 : 0.82)

            VStack(spacing: 3) {
                Text(value)
                    .font(Typography.display(32))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(label)
                    .font(Typography.captionBold)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: progress)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct DashboardMetricChip: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textQuaternary)
                    .textCase(.uppercase)
                Text(value)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Palette.surfaceElevated.opacity(0.72))
        )
        .overlay(
            Capsule()
                .strokeBorder(Palette.borderStrong, lineWidth: 0.5)
        )
    }
}

struct DashboardSignalRow: View {
    let icon: String
    let eyebrow: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow).eyebrow()
                Text(title)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DashboardInlineEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.035)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

extension View {
    func dashboardReveal(_ visible: Bool, delay: Double) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .animation(.spring(response: 0.58, dampingFraction: 0.86).delay(delay), value: visible)
    }
}

struct FoodRow: View {
    let food: FoodEntry
    var onDelete: () -> Void
    @State private var hovering = false

    private var timeString: String {
        Fmt.timeShort.string(from: food.date)
    }

    private var hasMacroData: Bool {
        food.protein != nil || food.carbs != nil || food.fat != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(Palette.accent).frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(food.name)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if let g = food.grams {
                        Text("· \(Fmt.int(g))g")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                if hasMacroData {
                    HStack(spacing: 8) {
                        macroBit(label: "P", value: food.protein, tint: Palette.macroProtein)
                        macroBit(label: "K", value: food.carbs, tint: Palette.macroCarbs)
                        macroBit(label: "Y", value: food.fat, tint: Palette.macroFat)
                    }
                } else {
                    Text("Makro yok")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(timeString)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(Fmt.int(food.calories))
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textSecondary)
                    Text("kcal")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(width: 70, alignment: .trailing)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Palette.surfaceElevated))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm - 2)
                .fill(hovering ? Color.white.opacity(0.025) : Color.clear)
        )
        .onHover { hovering = $0 }
    }

    private func macroBit(label: String, value: Double?, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 4, height: 4)
            Text("\(label) \(value.map { Fmt.int($0) } ?? "-")g")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
    }
}

struct InsightCard: View {
    let eyebrow: String
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text(eyebrow).eyebrow()
            }
            Text(title)
                .font(Typography.titleSmall)
                .foregroundStyle(Palette.textPrimary)
            // detail boş olsa bile aynı yüksekliği koruyacak placeholder
            Text(detail.isEmpty ? " " : detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .opacity(detail.isEmpty ? 0 : 1)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

struct MacroBar: View {
    let macros: CalorieResult
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Rectangle().fill(Palette.macroProtein)
                    .frame(width: width(for: macros.protein.percent, total: geo.size.width))
                Rectangle().fill(Palette.macroCarbs)
                    .frame(width: width(for: macros.carbs.percent, total: geo.size.width))
                Rectangle().fill(Palette.macroFat)
                    .frame(width: width(for: macros.fat.percent, total: geo.size.width))
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: 8)
    }

    private func width(for percent: Double, total: CGFloat) -> CGFloat {
        max(2, total * CGFloat(percent / 100.0) - 2)
    }
}

struct MacroLegend: View {
    let name: String
    let grams: Double          // hedef gram
    let percent: Double        // hedef kalori payı %
    let tint: Color
    var consumed: Double = 0   // bugün alınan gram

    private var progress: Double {
        guard grams > 0 else { return 0 }
        return consumed / grams
    }

    /// Hedefin %105'inin üstü = aşım.
    private var isOver: Bool { consumed > grams * 1.05 }

    /// İlerleme barının dolum rengi.
    private var fillColor: Color { isOver ? Palette.negative : tint }

    /// Alınan miktarın rengi (0 → soluk, hedefe yakın → pozitif, aşım → negatif).
    private var consumedColor: Color {
        if consumed <= 0 { return Palette.textTertiary }
        if isOver { return Palette.negative }
        if consumed >= grams * 0.85 { return Palette.positive }
        return Palette.textPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Başlık: renk noktası + isim · sağda hedefin kalori payı %
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(name)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 4)
                Text("%\(Fmt.int(percent))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
            }
            // Alınan / hedef — alınan vurgulu (loglandıkça artar)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.int(consumed))
                    .font(Typography.monoLarge)
                    .foregroundStyle(consumedColor)
                    .contentTransition(.numericText())
                Text("/ \(Fmt.int(grams)) g")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            // Tam genişlik, modern progress bar (yumuşak animasyonlu)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.surfaceElevated)
                    Capsule()
                        .fill(fillColor)
                        .frame(width: barWidth(total: geo.size.width))
                }
            }
            .frame(height: 7)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dolum genişliği: 0'da görünmez, biraz alındıysa min görünür uç, %100'de tam.
    private func barWidth(total: CGFloat) -> CGFloat {
        guard progress > 0 else { return 0 }
        return max(5, total * CGFloat(min(1, progress)))
    }
}
