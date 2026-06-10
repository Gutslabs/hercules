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
        Palette.background
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
    /// Center label color; defaults to `tint` so callers can keep a neutral
    /// caption while the stroke stays accented.
    var labelColor: Color? = nil
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
                    .font(Typography.display(34))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(label)
                    .font(Typography.captionBold)
                    .foregroundStyle(labelColor ?? tint)
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
                .background(Circle().fill(Palette.fieldFill))
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

// MARK: - V1 "Tek Akış" building blocks

/// Card surface used by every overview section — flat fill, thin hairline border.
extension View {
    /// V1 kart kromu + derinlik: opak taban (koyu temada yarı saydam yüzeyin gölgesi
    /// kaybolmasın diye) üzerine çift gölge — yaygın ortam + sıkı temas — ve üstten
    /// alta sönen ışık rim'li kenarlık. Kart "zeminden hafif kalkık" okunur.
    func dashboardCard(radius: CGFloat = Radius.lg) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Palette.background)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Palette.surface)
                }
                .compositingGroup()
                .shadow(color: Palette.cardShadow, radius: 18, x: 0, y: 9)
                .shadow(color: Palette.cardShadowTight, radius: 3, x: 0, y: 1.5)
            )

    }
}

/// Hero left-column stat (Hedef / Ritim / İlerleme): cap label, value, optional sub.
struct HeroStatColumn: View {
    let label: String
    let value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).eyebrow()
            Text(value)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let sub, !sub.isEmpty {
                Text(sub)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Compact macro row for the hero plan column: dot + name, consumed/target + share %, thin progress.
struct HeroMacroRow: View {
    let name: String
    let consumed: Double
    let target: Double
    let percent: Double
    let tint: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, consumed / target))
    }
    private var isOver: Bool { consumed > target * 1.05 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(name)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.int(consumed))
                        .font(Typography.mono)
                        .foregroundStyle(isOver ? Palette.negative : Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text("/ \(Fmt.int(target)) g")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .lineLimit(1)
                Text("%\(Fmt.int(percent))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                    .frame(width: 34, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceElevated)
                    Capsule()
                        .fill(isOver ? Palette.negative : tint)
                        .frame(width: progress > 0 ? max(4, geo.size.width * progress) : 0)
                }
            }
            .frame(height: 5)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
        }
    }
}

/// Hero öğün satırı — saat + isim + makro özeti; hover'da silme butonu belirginleşir.
struct HeroMealRow: View {
    let food: FoodEntry
    var onDelete: () -> Void
    @State private var hovering = false

    private var detail: String {
        var parts = ["\(Fmt.int(food.calories)) kcal"]
        if let g = food.grams { parts.append("\(Fmt.int(g)) g") }
        if let p = food.protein { parts.append("P \(Fmt.int(p))g") }
        if let c = food.carbs { parts.append("K \(Fmt.int(c))g") }
        if let f = food.fat { parts.append("Y \(Fmt.int(f))g") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Hairline().opacity(0.7)
            HStack(spacing: 12) {
                Text(Fmt.timeShort.string(from: food.date))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                Text(food.name)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(detail)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(hovering ? Palette.negative : Palette.textQuaternary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(hovering ? Palette.negative.opacity(0.1) : Color.clear))
                }
                .buttonStyle(.plain)
                .help("Öğünü sil")
            }
            .padding(.vertical, 8)
        }
        .background(hovering ? Palette.fieldFill : Color.clear)
        .onHover { hovering = $0 }
    }
}

/// Goal-aware delta badge (▲/▼ + magnitude); green when the change moves toward the goal.
struct DeltaBadge: View {
    let delta: Double?
    var lowerIsBetter: Bool = false
    var digits: Int = 1

    private var color: Color {
        guard let d = delta, d != 0 else { return Palette.textTertiary }
        let positiveChange = d > 0
        let good = lowerIsBetter ? !positiveChange : positiveChange
        return good ? Palette.positive : Palette.negative
    }

    private var symbol: String {
        guard let d = delta else { return "—" }
        if d > 0 { return "▲" }
        if d < 0 { return "▼" }
        return "—"
    }

    var body: some View {
        if let d = delta {
            HStack(spacing: 3) {
                Text(symbol).font(.system(size: 8, weight: .bold))
                Text(Fmt.num(abs(d), digits: digits))
                    .font(Typography.captionBold)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(color)
        }
    }
}

/// Compact secondary metric row for the Vücut card — tap promotes it into the big slot.
struct BodyMetricRow: View {
    let name: String
    let value: String
    let unit: String
    let points: [TrendPoint]
    let delta: Double?
    let lowerIsBetter: Bool
    let accent: Color
    var onTap: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 21, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Sparkline(points: points, accent: accent)
                .frame(width: 88, height: 30)
                .opacity(points.count >= 2 ? 0.9 : 0)

            DeltaBadge(delta: delta, lowerIsBetter: lowerIsBetter)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(hovering ? Palette.fieldFill : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
    }
}

/// Balance accounting column with a leading hairline rule (Tüketim / Adım / Spor / Kayıtlı).
struct BalanceStatColumn: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(Palette.border)
                .frame(width: 0.5, height: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(label).eyebrow()
                Text(value)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func dashboardReveal(_ visible: Bool, delay: Double) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .animation(.spring(response: 0.58, dampingFraction: 0.86).delay(delay), value: visible)
    }
}
