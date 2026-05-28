import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]
    @Query private var todaysFoods: [FoodEntry]
    @Query private var allWorkouts: [WorkoutSession]
    @State private var revealContent = false
    @State private var balancePeriod: DashboardBalancePeriod = .week
    @State private var balanceSummary: DashboardBalanceSummary?

    init(today: Date = .now) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? today
        _todaysFoods = Query(
            filter: #Predicate<FoodEntry> { entry in
                entry.date >= start && entry.date < end
            },
            sort: \FoodEntry.date,
            order: .reverse
        )
    }

    private var profile: UserProfile? { profiles.first }
    private var latest: Measurement? { measurements.first }

    private var todaysWorkout: WorkoutSession? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return allWorkouts.first { $0.weekday == weekday }
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
            manualOffsetMacro: profile.manualCalorieOffsetMacro,
            manualProteinGrams: profile.manualProteinGrams,
            manualCarbsGrams: profile.manualCarbsGrams,
            manualFatGrams: profile.manualFatGrams
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = proxy.size.width
            let compact = contentWidth < 1220
            let expansive = contentWidth >= 1500

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? Spacing.xl : Spacing.xxl) {
                    header(compact: compact)
                        .dashboardReveal(revealContent, delay: 0.02)
                    overviewMosaic(compact: compact, expansive: expansive)
                        .dashboardReveal(revealContent, delay: 0.08)
                    if let calorieResult {
                        caloriesSummary(calorieResult, compact: compact)
                            .dashboardReveal(revealContent, delay: 0.14)
                        balancePanel(calorieResult, compact: compact)
                            .dashboardReveal(revealContent, delay: 0.18)
                    } else {
                        setupNudge(compact: compact)
                            .dashboardReveal(revealContent, delay: 0.14)
                    }
                    quickCharts(compact: compact, expansive: expansive)
                        .dashboardReveal(revealContent, delay: 0.24)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, compact ? Spacing.xl : (expansive ? 44 : Spacing.xxl))
                .padding(.vertical, compact ? Spacing.xl : Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
        .onAppear {
            revealContent = true
            refreshBalanceSummary()
        }
        .onChange(of: balancePeriod) { _, _ in
            refreshBalanceSummary()
        }
        .onChange(of: todaysFoods.count) { _, _ in
            refreshBalanceSummary()
        }
        .onChange(of: consumedCalories) { _, _ in
            refreshBalanceSummary()
        }
    }

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                Text("Genel Bakış").eyebrow()
                Text("Hercules")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                if let last = latest {
                    lastUpdateBadge(last.date)
                        .padding(.top, 4)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Genel Bakış").eyebrow()
                    Text("Hercules")
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                if let last = latest {
                    lastUpdateBadge(last.date)
                }
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
                .fill(Palette.surface.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.5)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                .blendMode(.screen)
        }
    }

    @ViewBuilder
    private func overviewMosaic(compact: Bool, expansive: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: Spacing.md) {
                overviewHero(compact: true)
                signalRail(compact: true)
                heroMetrics(compact: true, expansive: expansive)
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    overviewHero(compact: false)
                        .frame(maxWidth: .infinity)
                    signalRail(compact: false)
                        .frame(width: expansive ? 360 : 320)
                }
                heroMetrics(compact: false, expansive: expansive)
            }
        }
    }

    @ViewBuilder
    private func overviewHero(compact: Bool) -> some View {
        let result = calorieResult
        let remaining = result.map(remainingCalories)
        let ringColor = result.map(remainingColor) ?? Palette.accent

        Group {
            if compact {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    heroCopy(result)
                    heroPlanBlock(result, remaining: remaining, ringColor: ringColor, compact: true)
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.xxl) {
                    heroCopy(result)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    heroPlanBlock(result, remaining: remaining, ringColor: ringColor, compact: false)
                        .frame(width: 292)
                }
            }
        }
        .padding(compact ? Spacing.xl : Spacing.xxl)
        .frame(maxWidth: .infinity, minHeight: compact ? 0 : 282, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(Palette.surface.opacity(0.82))
                DashboardHeroLines()
                    .stroke(Palette.borderStrong.opacity(0.55), lineWidth: 0.7)
                    .frame(width: 260, height: 220)
                    .offset(x: 28, y: -18)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.75)
        }
        .shadow(color: Palette.accent.opacity(0.08), radius: 34, x: 0, y: 22)
    }

    private func heroCopy(_ result: CalorieResult?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: 8) {
                BreathingStatusDot(color: result == nil ? Palette.warning : Palette.accent)
                Text(result == nil ? "Kurulum bekliyor" : "Canlı plan")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(greeting)
                    .font(Typography.display(46))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                Text(heroDetail(result))
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520, alignment: .leading)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) {
                    heroChips
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    heroChips
                }
            }
        }
    }

    @ViewBuilder
    private var heroChips: some View {
        DashboardMetricChip(
            icon: "target",
            label: "Hedef",
            value: goalTitle,
            tint: Palette.warning
        )
        DashboardMetricChip(
            icon: "calendar.badge.clock",
            label: "Ritim",
            value: cadenceTitle,
            tint: cadenceTint
        )
        if let workout = todaysWorkout {
            DashboardMetricChip(
                icon: "figure.strengthtraining.traditional",
                label: "Bugün",
                value: workout.name,
                tint: Palette.positive
            )
        }
    }

    @ViewBuilder
    private func heroPlanBlock(
        _ result: CalorieResult?,
        remaining: Double?,
        ringColor: Color,
        compact: Bool
    ) -> some View {
        if let result, let remaining {
            let isOver = remaining < 0
            VStack(alignment: .leading, spacing: Spacing.lg) {
                CalorieProgressRing(
                    progress: calorieProgress(result),
                    tint: ringColor,
                    value: "\(isOver ? "+" : "")\(Fmt.int(abs(remaining)))",
                    label: isOver ? "kcal fazla" : "kcal kaldı",
                    subtitle: "Hedef \(Fmt.int(result.goalCalories))"
                )
                .frame(width: compact ? 180 : 212, height: compact ? 180 : 212)

                HStack(spacing: Spacing.md) {
                    ringMetric("Tüketilen", value: "\(Fmt.int(consumedCalories)) kcal")
                    ringMetric("TDEE", value: "\(Fmt.int(result.tdee)) kcal")
                }
            }
            .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Image(systemName: "scope")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Palette.warning)
                Text(setupMissingTitle)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text(setupMissingDetail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Palette.surfaceElevated.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 0.5)
            )
        }
    }

    private func ringMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).eyebrow()
            Text(value)
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroDetail(_ result: CalorieResult?) -> String {
        guard let result else { return setupMissingDetail }
        let remaining = remainingCalories(result)
        if remaining < 0 {
            return "Bugünkü plan hedefin üzerinde. Makroları ve kalan ritmi aynı yerde tutup yarına daha sakin bir rota bırak."
        }
        if todaysFoods.isEmpty {
            return "Bugün henüz yemek girişi yok. İlk kayıt geldiğinde kalori, makro ve hedef sapması burada netleşir."
        }
        return "Bugünün kayıtları hedefle karşılaştırıldı. Kalan kalori, makrolar ve ölçüm ritmi tek bakışta okunuyor."
    }

    private func signalRail(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardSignalRow(
                icon: "waveform.path.ecg",
                eyebrow: "Ritim",
                title: cadenceTitle,
                detail: cadenceDetail,
                tint: cadenceTint
            )
            Hairline()
            DashboardSignalRow(
                icon: "chart.line.uptrend.xyaxis",
                eyebrow: "İlerleme",
                title: progressTitle(weightStats),
                detail: progressDetail(weightStats).isEmpty ? "Trend için en az iki ölçüm gerekli." : progressDetail(weightStats),
                tint: Palette.positive
            )
            Hairline()
            DashboardSignalRow(
                icon: "flag.checkered",
                eyebrow: "Hedef",
                title: goalTitle,
                detail: goalDetail.isEmpty ? "Profilde hedef ağırlık girilirse mesafe hesaplanır." : goalDetail,
                tint: Palette.warning
            )
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: compact ? 0 : 282, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surface.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func heroMetrics(compact: Bool, expansive: Bool) -> some View {
        let kinds: [MetricKind] = [.weight, .bodyFat, .leanMass, .waist]

        if compact {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
                spacing: Spacing.md
            ) {
                ForEach(kinds, id: \.self) { metricTile($0) }
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.md) {
                metricTile(.weight)
                    .frame(minWidth: expansive ? 420 : 340, maxWidth: .infinity)
                metricTile(.bodyFat)
                    .frame(width: expansive ? 290 : 240)
                metricTile(.leanMass)
                    .frame(width: expansive ? 290 : 240)
                metricTile(.waist)
                    .frame(width: expansive ? 290 : 240)
            }
        }
    }

    private func metricTile(_ kind: MetricKind) -> some View {
        let pts = TrendAnalysis.points(measurements, for: kind)
        let stats = TrendAnalysis.stats(pts)
        return MetricTile(
            label: kind.label,
            value: Fmt.numOpt(stats.current, digits: 1),
            unit: kind.unit,
            delta: stats.delta,
            lowerIsBetter: kind.lowerIsBetter,
            sparkline: pts,
            accent: metricAccent(kind)
        )
    }

    private func metricAccent(_ kind: MetricKind) -> Color {
        switch kind {
        case .weight: return Palette.accent
        case .bodyFat, .fatMass, .waist: return Palette.warning
        case .leanMass: return Palette.positive
        case .chest, .neck: return Palette.textSecondary
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

    private var cadenceDetail: String {
        guard let days = TrendAnalysis.daysSinceLast(measurements) else {
            return "İlk ölçüm geldikten sonra trend ritmi açılır."
        }
        if days == 0 { return "Bugünkü veri taze; plan hesapları güvenilir." }
        if days <= 3 { return "Ölçüm yakın tarihli, trend okumaları hala sağlam." }
        return "Yeni ölçüm girersen grafik ve hedef mesafesi keskinleşir."
    }

    private var cadenceTint: Color {
        guard let days = TrendAnalysis.daysSinceLast(measurements) else { return Palette.warning }
        if days <= 1 { return Palette.positive }
        if days <= 4 { return Palette.warning }
        return Palette.negative
    }

    private var setupMissingTitle: String {
        if profile == nil { return "Profil tamamlanmalı" }
        if latest?.weight == nil { return "Kilo ölçümü bekleniyor" }
        return "Plan verisi eksik"
    }

    private var setupMissingDetail: String {
        if profile == nil {
            return "Kalori ve makro hedefleri için profil bilgilerini ekle."
        }
        if latest?.weight == nil {
            return "Kalori hesabı için en az bir kilo ölçümü gerekli."
        }
        return "Hedef planını hesaplamak için eksik alanları tamamla."
    }

    private func setupNudge(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.warning)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.warning.opacity(0.12)))
            VStack(alignment: .leading, spacing: 5) {
                Text(setupMissingTitle)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text(setupMissingDetail)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? Spacing.lg : Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.5)
        )
    }

    private func calorieProgress(_ r: CalorieResult) -> Double {
        guard r.goalCalories > 0 else { return 0 }
        return min(1, max(0, consumedCalories / r.goalCalories))
    }

    private func caloriesSummary(_ r: CalorieResult, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Günlük Plan").eyebrow()
                if let w = todaysWorkout {
                    HStack(spacing: 5) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                        Text("\(w.name) · hedef sabit")
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

            if compact {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    calorieCore(r)
                    Hairline()
                    macroTargets(r, compact: true)
                    Hairline()
                    supportStats(r)
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    calorieCore(r)
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260, alignment: .leading)

                    Divider().background(Palette.border)

                    macroTargets(r, compact: false)
                        .frame(maxWidth: .infinity)

                    Divider().background(Palette.border)

                    supportStats(r)
                        .frame(minWidth: 160, idealWidth: 180, maxWidth: 200, alignment: .leading)
                }
            }

            if let warning = goalDeviationWarning(r) {
                warningBanner(warning)
            }

            Hairline()
            if todaysFoods.isEmpty {
                DashboardInlineEmptyState(
                    icon: "fork.knife",
                    title: "Bugün yemek kaydı yok",
                    detail: "İlk öğün eklendiğinde makro ve kalori sapması burada görünür."
                )
            } else {
                todaysFoodsList
            }
        }
        .padding(compact ? Spacing.lg : Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func calorieCore(_ r: CalorieResult) -> some View {
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
    }

    private func macroTargets(_ r: CalorieResult, compact: Bool) -> some View {
        VStack(spacing: Spacing.sm) {
            MacroBar(macros: r)
            if compact {
                VStack(spacing: Spacing.sm) {
                    MacroLegend(name: "Protein", grams: r.protein.grams, percent: r.protein.percent, tint: Palette.macroProtein, consumed: consumedProtein)
                    MacroLegend(name: "Karbonhidrat", grams: r.carbs.grams, percent: r.carbs.percent, tint: Palette.macroCarbs, consumed: consumedCarbs)
                    MacroLegend(name: "Yağ", grams: r.fat.grams, percent: r.fat.percent, tint: Palette.macroFat, consumed: consumedFat)
                }
            } else {
                HStack(spacing: Spacing.lg) {
                    MacroLegend(name: "Protein", grams: r.protein.grams, percent: r.protein.percent, tint: Palette.macroProtein, consumed: consumedProtein)
                    MacroLegend(name: "Karbonhidrat", grams: r.carbs.grams, percent: r.carbs.percent, tint: Palette.macroCarbs, consumed: consumedCarbs)
                    MacroLegend(name: "Yağ", grams: r.fat.grams, percent: r.fat.percent, tint: Palette.macroFat, consumed: consumedFat)
                }
            }
        }
    }

    private func supportStats(_ r: CalorieResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            StatRow(label: "Su", value: "\(Fmt.num(r.water, digits: 1)) L")
            StatRow(label: "Lif", value: "\(Fmt.int(r.fiber)) g")
            StatRow(label: "Yağsız Kütle", value: "\(Fmt.num(r.leanMass, digits: 1)) kg")
        }
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
                ViewThatFits(in: .horizontal) {
                    Text("\(todaysFoods.count) öğe · \(Fmt.int(consumedCalories)) kcal · P \(Fmt.int(consumedProtein))g · K \(Fmt.int(consumedCarbs))g · Y \(Fmt.int(consumedFat))g")
                    Text("\(todaysFoods.count) öğe · \(Fmt.int(consumedCalories)) kcal")
                }
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

    private func balancePanel(_ r: CalorieResult, compact: Bool) -> some View {
        let summary = balanceSummary
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    balanceHeader
                    Spacer()
                    balancePeriodSelector
                }
                VStack(alignment: .leading, spacing: Spacing.md) {
                    balanceHeader
                    balancePeriodSelector
                }
            }

            if let summary {
                if compact {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        balanceLead(summary)
                        Hairline()
                        balanceMetrics(summary, compact: true)
                    }
                } else {
                    HStack(alignment: .top, spacing: Spacing.xl) {
                        balanceLead(summary)
                            .frame(minWidth: 250, idealWidth: 320, maxWidth: 360, alignment: .leading)
                        Divider().background(Palette.border)
                        balanceMetrics(summary, compact: false)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            } else {
                DashboardInlineEmptyState(
                    icon: "chart.bar.xaxis",
                    title: "Kalori dengesi bekleniyor",
                    detail: "Yemek kaydı olan günlerde TDEE, adım ve spor yakımı birlikte hesaplanır."
                )
            }

            Text("Hesap: \(Fmt.int(r.tdee)) kcal TDEE tabanı + kayıtlı adım yakımı + gerçek antrenman; antrenman kaydı yoksa programdaki spor günü tahmini - tüketilen kalori.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? Spacing.lg : Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var balanceHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Kalori Dengesi").eyebrow()
            Text(balancePeriod.title)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private var balancePeriodSelector: some View {
        HStack(spacing: 4) {
            ForEach(DashboardBalancePeriod.allCases) { period in
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        balancePeriod = period
                    }
                } label: {
                    Text(period.shortLabel)
                        .font(Typography.captionBold)
                        .foregroundStyle(balancePeriod == period ? Palette.background : Palette.textSecondary)
                        .frame(minWidth: 42)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                .fill(balancePeriod == period ? Palette.textPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(period.title)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func balanceLead(_ summary: DashboardBalanceSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(summary.trackedDays > 0 ? "Net sonuç" : "Kayıt yok").eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(summary.displayValue)
                    .font(Typography.display(44))
                    .foregroundStyle(summary.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(summary.resultLabel)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Text(summary.detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func balanceMetrics(_ summary: DashboardBalanceSummary, compact: Bool) -> some View {
        let columns = compact
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.md) {
            balanceMetric("Tüketim", value: "\(Fmt.int(summary.foodCalories)) kcal", icon: "fork.knife", tint: Palette.textSecondary)
            balanceMetric("Adım", value: "\(Fmt.int(Double(summary.stepCount))) · \(Fmt.int(summary.stepCalories)) kcal", icon: "figure.walk", tint: Palette.positive)
            balanceMetric("Spor", value: "\(summary.workoutDays) gün · \(Fmt.int(summary.workoutCalories)) kcal", icon: "figure.strengthtraining.traditional", tint: Palette.warning)
            balanceMetric("Kayıtlı", value: "\(summary.trackedDays)/\(summary.calendarDays) gün", icon: "calendar", tint: Palette.accent)
        }
    }

    private func balanceMetric(_ label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(Typography.label)
                    .foregroundStyle(Palette.textQuaternary)
                Text(value)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.64))
        )
    }

    private func refreshBalanceSummary() {
        guard let result = calorieResult else {
            balanceSummary = nil
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let start = balancePeriod.startDate(endingAt: todayStart, calendar: calendar)

        let foods = fetchFoods(start: start, end: end)
        let steps = fetchSteps(start: start, end: end)
        let logs = fetchWorkoutLogs(start: start, end: end)

        let foodByDay = foods.reduce(into: [Date: Double]()) { dict, food in
            dict[calendar.startOfDay(for: food.date), default: 0] += food.calories
        }
        let latestStepByDay = latestStepsByDay(steps, calendar: calendar)
        let logByDay = latestWorkoutLogsByDay(logs, calendar: calendar)
        let programByWeekday = allWorkouts.reduce(into: [Int: WorkoutSession]()) { dict, workout in
            guard workout.estimatedCalories > 0 else { return }
            if dict[workout.weekday] == nil {
                dict[workout.weekday] = workout
            }
        }

        let firstDataDay = [foods.map(\.date).min(), steps.map(\.date).min(), logs.map(\.date).min()]
            .compactMap { $0 }
            .map { calendar.startOfDay(for: $0) }
            .min()
        let effectiveStart = start ?? firstDataDay ?? todayStart
        let calendarDays = max(1, (calendar.dateComponents([.day], from: effectiveStart, to: end).day ?? 1))

        let trackedDays = foodByDay.keys.sorted()
        var foodCalories: Double = 0
        var baseCalories: Double = 0
        var stepCalories: Double = 0
        var workoutCalories: Double = 0
        var stepCount = 0
        var workoutDays = 0

        for day in trackedDays {
            foodCalories += foodByDay[day] ?? 0
            baseCalories += result.tdee

            if let step = latestStepByDay[day] {
                stepCount += step.steps
                stepCalories += StepEntry.calorieBurn(for: step, weightKg: latest?.weight ?? 80)
            }

            if let log = logByDay[day] {
                workoutCalories += log.estimatedCalories
                workoutDays += 1
            } else {
                let weekday = calendar.component(.weekday, from: day)
                if let workout = programByWeekday[weekday], workout.estimatedCalories > 0 {
                    workoutCalories += workout.estimatedCalories
                    workoutDays += 1
                }
            }
        }

        balanceSummary = DashboardBalanceSummary(
            period: balancePeriod,
            startDate: effectiveStart,
            endDate: end,
            netDeficit: baseCalories + stepCalories + workoutCalories - foodCalories,
            foodCalories: foodCalories,
            baseCalories: baseCalories,
            stepCalories: stepCalories,
            workoutCalories: workoutCalories,
            stepCount: stepCount,
            workoutDays: workoutDays,
            trackedDays: trackedDays.count,
            calendarDays: calendarDays
        )
    }

    private func fetchFoods(start: Date?, end: Date) -> [FoodEntry] {
        let descriptor: FetchDescriptor<FoodEntry>
        if let start {
            descriptor = FetchDescriptor<FoodEntry>(
                predicate: #Predicate<FoodEntry> { entry in
                    entry.date >= start && entry.date < end
                },
                sortBy: [SortDescriptor(\.date)]
            )
        } else {
            descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)])
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    private func fetchSteps(start: Date?, end: Date) -> [StepEntry] {
        let descriptor: FetchDescriptor<StepEntry>
        if let start {
            descriptor = FetchDescriptor<StepEntry>(
                predicate: #Predicate<StepEntry> { entry in
                    entry.date >= start && entry.date < end
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<StepEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    private func fetchWorkoutLogs(start: Date?, end: Date) -> [WorkoutLog] {
        let descriptor: FetchDescriptor<WorkoutLog>
        if let start {
            descriptor = FetchDescriptor<WorkoutLog>(
                predicate: #Predicate<WorkoutLog> { log in
                    log.date >= start && log.date < end
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    private func latestStepsByDay(_ steps: [StepEntry], calendar: Calendar) -> [Date: StepEntry] {
        steps.reduce(into: [Date: StepEntry]()) { dict, entry in
            let day = calendar.startOfDay(for: entry.date)
            if let existing = dict[day], existing.date > entry.date {
                return
            }
            dict[day] = entry
        }
    }

    private func latestWorkoutLogsByDay(_ logs: [WorkoutLog], calendar: Calendar) -> [Date: WorkoutLog] {
        logs.reduce(into: [Date: WorkoutLog]()) { dict, log in
            let day = calendar.startOfDay(for: log.date)
            if let existing = dict[day], existing.date > log.date {
                return
            }
            dict[day] = log
        }
    }

    @ViewBuilder
    private func quickCharts(compact: Bool, expansive: Bool) -> some View {
        let weightPts = weightPoints
        let bodyFatPts = TrendAnalysis.points(measurements, for: .bodyFat)
        let weightGoal: (start: TrendPoint, end: TrendPoint)? = {
            guard let target = profile?.targetWeight else { return nil }
            return TrendAnalysis.goalBand(from: weightPts, target: target)
        }()

        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Trendler").eyebrow()
            if compact {
                VStack(spacing: Spacing.md) {
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
            } else {
                HStack(alignment: .top, spacing: Spacing.md) {
                    MetricChart(
                        title: MetricKind.weight.label,
                        unit: MetricKind.weight.unit,
                        points: weightPts,
                        goalBand: weightGoal,
                        height: 220
                    )
                    .frame(minWidth: 520, maxWidth: .infinity)

                    MetricChart(
                        title: MetricKind.bodyFat.label,
                        unit: MetricKind.bodyFat.unit,
                        points: bodyFatPts,
                        height: 220
                    )
                    .frame(width: expansive ? 520 : 420)
                }
            }
        }
    }
}

private enum DashboardBalancePeriod: String, CaseIterable, Identifiable {
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

private struct DashboardBalanceSummary {
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

private struct DashboardBackground: View {
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

private struct DashboardHeroLines: Shape {
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

private struct BreathingStatusDot: View {
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

private struct CalorieProgressRing: View {
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

private struct DashboardMetricChip: View {
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

private struct DashboardSignalRow: View {
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

private struct DashboardInlineEmptyState: View {
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

private extension View {
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
