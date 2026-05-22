import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodEntry.date, order: .reverse) private var allFoods: [FoodEntry]
    @Query private var allWorkouts: [WorkoutSession]
    @Query(sort: \StepEntry.date, order: .reverse) private var allSteps: [StepEntry]

    private var profile: UserProfile? { profiles.first }
    private var latest: Measurement? { measurements.first }

    private var todaysWorkout: WorkoutSession? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return allWorkouts.first { $0.weekday == weekday }
    }

    private var todaysSteps: StepEntry? {
        let cal = Calendar.current
        return allSteps.first { cal.isDateInToday($0.date) }
    }

    private var stepCalories: Double {
        guard let entry = todaysSteps,
              let weight = latest?.weight else { return 0 }
        return StepEntry.calorieBurn(for: entry, weightKg: weight)
    }

    private var todaysFoods: [FoodEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return allFoods.filter { cal.isDate($0.date, inSameDayAs: today) }
    }

    private var consumedCalories: Double {
        todaysFoods.reduce(0) { $0 + $1.calories }
    }

    private var consumedProtein: Double {
        todaysFoods.compactMap(\.protein).reduce(0, +)
    }
    private var consumedCarbs: Double {
        todaysFoods.compactMap(\.carbs).reduce(0, +)
    }
    private var consumedFat: Double {
        todaysFoods.compactMap(\.fat).reduce(0, +)
    }

    private var weightPoints: [TrendPoint] {
        TrendAnalysis.points(measurements, for: .weight)
    }

    private var weightStats: TrendStats {
        TrendAnalysis.stats(weightPoints)
    }

    private var calorieResult: CalorieResult? {
        guard let profile = profile,
              let latest = latest,
              let weight = latest.weight else { return nil }
        return CalorieCalculator.compute(
            weight: weight,
            height: profile.height,
            age: profile.age,
            sex: profile.sex,
            bodyFat: latest.bodyFat ?? profile.manualBodyFat,
            activity: profile.activity,
            goal: profile.goal,
            manualOffset: profile.manualCalorieOffset,
            workoutCalories: todaysWorkout?.estimatedCalories ?? 0,
            stepCalories: stepCalories
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header
                heroMetrics
                insightsRow
                if let calorieResult { caloriesSummary(calorieResult) }
                quickCharts
                Spacer(minLength: 24)
            }
            .padding(Spacing.xxl)
        }
        .background(Palette.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Genel Bakış").eyebrow()
                Text(greeting)
                    .font(Typography.display(44))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            if let last = latest {
                lastUpdateBadge(last.date)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let salutation: String
        switch hour {
        case 5..<12: salutation = "Günaydın"
        case 12..<17: salutation = "İyi günler"
        case 17..<22: salutation = "İyi akşamlar"
        default: salutation = "İyi geceler"
        }
        let name = profile?.name.isEmpty == false ? ", \(profile!.name)" : ""
        return salutation + name
    }

    private func lastUpdateBadge(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Palette.accent).frame(width: 6, height: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Son ölçüm").eyebrow()
                Text(Fmt.dateLong.string(from: date))
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var heroMetrics: some View {
        let kinds: [MetricKind] = [.weight, .bodyFat, .leanMass, .waist]
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: kinds.count),
            spacing: Spacing.md
        ) {
            ForEach(kinds, id: \.self) { k in
                let pts = TrendAnalysis.points(measurements, for: k)
                let stats = TrendAnalysis.stats(pts)
                MetricTile(
                    label: k.label,
                    value: Fmt.numOpt(stats.current, digits: 1),
                    unit: k.unit,
                    delta: stats.delta,
                    lowerIsBetter: k.lowerIsBetter,
                    sparkline: pts
                )
            }
        }
    }

    private var insightsRow: some View {
        let stats = weightStats
        return HStack(alignment: .top, spacing: Spacing.md) {
            InsightCard(
                eyebrow: "Hatırlatma",
                title: cadenceTitle,
                detail: "",
                accent: Palette.accent
            )
            InsightCard(
                eyebrow: "İlerleme",
                title: progressTitle(stats),
                detail: progressDetail(stats),
                accent: Palette.positive
            )
            InsightCard(
                eyebrow: "Hedef",
                title: goalTitle,
                detail: goalDetail,
                accent: Palette.warning
            )
        }
    }

    private var cadenceTitle: String {
        guard let days = TrendAnalysis.daysSinceLast(measurements) else { return "İlk ölçümünü ekle" }
        if days == 0 { return "Bugün güncel" }
        if days == 1 { return "1 gün önce ölçüldü" }
        return "\(days) gün önce ölçüldü"
    }

    private func progressTitle(_ stats: TrendStats) -> String {
        guard let weekly = stats.weeklyChange else { return "—" }
        return "\(Fmt.signed(weekly, digits: 2)) kg/hafta"
    }

    private func progressDetail(_ stats: TrendStats) -> String {
        guard let total = stats.delta, stats.pointCount >= 2 else { return "" }
        return "Toplam \(Fmt.signed(total, digits: 1)) kg"
    }

    private var goalTitle: String {
        guard let p = profile else { return "—" }
        return p.goal.label
    }

    private var goalDetail: String {
        guard let p = profile else { return "" }
        if let target = p.targetWeight, let current = latest?.weight {
            let remaining = current - target
            if abs(remaining) < 0.2 { return "Hedefte" }
            return "\(Fmt.num(abs(remaining), digits: 1)) kg kaldı"
        }
        return ""
    }

    private func caloriesSummary(_ r: CalorieResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Günlük Plan").eyebrow()
                if let w = todaysWorkout {
                    HStack(spacing: 5) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                        Text("\(w.name) · +\(Fmt.int(w.estimatedCalories)) kcal")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Palette.surfaceElevated)
                    )
                }
                Spacer()
                PillTag(text: r.formula, tint: Palette.textSecondary)
            }

            HStack(alignment: .top, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Hedef Kalori").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        let remaining = remainingCalories(r)
                        let isOver = remaining < 0
                        Text("\(isOver ? "+" : "")\(Fmt.int(abs(remaining)))")
                            .font(Typography.display(48))
                            .foregroundStyle(remainingColor(r))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(isOver ? "kcal fazla" : "kcal kaldı")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                    Text("Hedef \(Fmt.int(r.goalCalories)) · Tüketilen \(Fmt.int(consumedCalories))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 260, alignment: .leading)

                Divider().background(Palette.border)

                VStack(spacing: Spacing.sm) {
                    MacroBar(macros: r)
                    HStack(spacing: Spacing.lg) {
                        MacroLegend(name: "Protein", grams: r.protein.grams, percent: r.protein.percent, tint: Palette.macroProtein, consumed: consumedProtein)
                        MacroLegend(name: "Karbonhidrat", grams: r.carbs.grams, percent: r.carbs.percent, tint: Palette.macroCarbs, consumed: consumedCarbs)
                        MacroLegend(name: "Yağ", grams: r.fat.grams, percent: r.fat.percent, tint: Palette.macroFat, consumed: consumedFat)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().background(Palette.border)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    StatRow(label: "Su", value: "\(Fmt.num(r.water, digits: 1)) L")
                    StatRow(label: "Lif", value: "\(Fmt.int(r.fiber)) g")
                    StatRow(label: "Yağsız Kütle", value: "\(Fmt.num(r.leanMass, digits: 1)) kg")
                }
                .frame(minWidth: 160, idealWidth: 180, maxWidth: 200, alignment: .leading)
            }

            if let warning = goalDeviationWarning(r) {
                warningBanner(warning)
            }

            if !todaysFoods.isEmpty {
                Hairline()
                todaysFoodsList
            }
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func remainingCalories(_ r: CalorieResult) -> Double {
        r.goalCalories - consumedCalories  // negatif olabilir = hedef aşıldı
    }

    private func remainingColor(_ r: CalorieResult) -> Color {
        let remaining = remainingCalories(r)
        if remaining < 0 { return Palette.negative }
        if remaining < r.goalCalories * 0.15 { return Palette.warning }
        return Palette.textPrimary
    }

    /// Kilogram başına yaklaşık 7700 kcal (yağ dokusu).
    private static let kcalPerKg: Double = 7700

    /// Hedef sapma uyarısı — sadece hedef aşıldığında dolu döner.
    private func goalDeviationWarning(_ r: CalorieResult) -> (title: String, detail: String, color: Color, icon: String)? {
        let overshoot = consumedCalories - r.goalCalories  // pozitif = aşıldı
        guard overshoot > 0 else { return nil }

        let actualSurplus = consumedCalories - r.tdee  // TDEE'ye göre gerçek fazla
        let goalAdj = profile?.goal.calorieAdjustment ?? 0

        if goalAdj < 0 {
            // Kilo verme hedefi
            if actualSurplus > 0 {
                let grams = (actualSurplus / Self.kcalPerKg) * 1000.0
                return (
                    "Bugün kilo alma günü oldu",
                    "Hedefin kilo verme ama \(Fmt.int(actualSurplus)) kcal fazla aldın → ~\(Fmt.int(grams)) g potansiyel artış. Yarın telafi et.",
                    Palette.negative,
                    "exclamationmark.triangle.fill"
                )
            } else {
                let extraDays = abs(overshoot / goalAdj)
                return (
                    "Açık küçüldü",
                    "Hedef açığını \(Fmt.int(overshoot)) kcal aştın → ~\(Fmt.num(extraDays, digits: 1)) gün gecikme.",
                    Palette.warning,
                    "exclamationmark.triangle"
                )
            }
        } else if goalAdj == 0 {
            // Koruma
            let grams = (max(0, actualSurplus) / Self.kcalPerKg) * 1000.0
            return (
                "Hedef üzerinde",
                "+\(Fmt.int(overshoot)) kcal · ~\(Fmt.int(grams)) g potansiyel artış.",
                Palette.warning,
                "info.circle"
            )
        } else {
            // Kilo alma — overshoot fazlası genelde sorun değil
            return (
                "Hedefin biraz üstünde",
                "+\(Fmt.int(overshoot)) kcal fazla aldın. Kilo alma hedefinde isen tempo iyi.",
                Palette.textSecondary,
                "info.circle"
            )
        }
    }

    private func warningBanner(_ w: (title: String, detail: String, color: Color, icon: String)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: w.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(w.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.title)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Text(w.detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var todaysFoodsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bugünün Yemekleri").eyebrow()
                Spacer()
                Text("\(todaysFoods.count) öğe · \(Fmt.int(consumedCalories)) kcal")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            VStack(spacing: 4) {
                ForEach(todaysFoods) { food in
                    FoodRow(food: food) {
                        ctx.delete(food)
                        try? ctx.save()
                    }
                }
            }
        }
    }

    private var quickCharts: some View {
        let weightPts = weightPoints
        let bodyFatPts = TrendAnalysis.points(measurements, for: .bodyFat)
        let weightGoal: (start: TrendPoint, end: TrendPoint)? = {
            guard let target = profile?.targetWeight else { return nil }
            return TrendAnalysis.goalBand(from: weightPts, target: target)
        }()

        return VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Trendler").eyebrow()
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
                spacing: Spacing.md
            ) {
                MetricChart(
                    title: MetricKind.weight.label,
                    unit: MetricKind.weight.unit,
                    points: weightPts,
                    goalBand: weightGoal,
                    height: 180
                )
                MetricChart(
                    title: MetricKind.bodyFat.label,
                    unit: MetricKind.bodyFat.unit,
                    points: bodyFatPts,
                    height: 180
                )
            }
        }
    }
}

struct FoodRow: View {
    let food: FoodEntry
    var onDelete: () -> Void
    @State private var hovering = false

    private var timeString: String {
        Fmt.timeShort.string(from: food.date)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Palette.accent).frame(width: 5, height: 5)
            Text(food.name)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            if let g = food.grams {
                Text("· \(Fmt.int(g))g")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
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
        return min(1.5, consumed / grams)  // 150% üstü clamp
    }

    private var consumedColor: Color {
        if consumed == 0 { return Palette.textQuaternary }
        if consumed > grams * 1.05 { return Palette.negative }
        if consumed >= grams * 0.85 { return Palette.positive }
        return Palette.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(name)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(Fmt.int(grams))
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
                Text("g")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                Text("· \(Fmt.int(percent))%")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            // Bugün alınan miktar — minimal progress
            HStack(spacing: 4) {
                Text("\(Fmt.int(consumed))/\(Fmt.int(grams)) g")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(consumedColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 3)
                        Capsule()
                            .fill(tint.opacity(0.85))
                            .frame(width: geo.size.width * CGFloat(min(1, progress)), height: 3)
                    }
                }
                .frame(width: 40, height: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
