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
    @State private var selectedBodyMetric: MetricKind = .weight
    @State private var mealsExpanded = false

    /// Order of metrics in the Vücut card; the selected one fills the big slot,
    /// the rest become compact rows.
    private let bodyMetricOrder: [MetricKind] = [.weight, .bodyFat, .leanMass, .waist]

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

    private var consumedCalories: Double {
        todaysFoods.reduce(0) { $0 + $1.calories }
    }
    private var consumedProtein: Double { todaysFoods.compactMap(\.protein).reduce(0, +) }
    private var consumedCarbs: Double { todaysFoods.compactMap(\.carbs).reduce(0, +) }
    private var consumedFat: Double { todaysFoods.compactMap(\.fat).reduce(0, +) }

    private var weightStats: TrendStats {
        TrendAnalysis.stats(TrendAnalysis.points(measurements, for: .weight))
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
            let compact = proxy.size.width < 1180

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 18) {
                    header(compact: compact)
                        .dashboardReveal(revealContent, delay: 0.02)
                    heroCard(compact: compact)
                        .dashboardReveal(revealContent, delay: 0.08)
                    bodyCard(compact: compact)
                        .dashboardReveal(revealContent, delay: 0.14)
                    if let r = calorieResult {
                        balanceCard(r, compact: compact)
                            .dashboardReveal(revealContent, delay: 0.20)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, compact ? 20 : 40)
                .padding(.vertical, compact ? 24 : 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
        .onAppear {
            revealContent = true
            refreshBalanceSummary()
        }
        .onChange(of: balancePeriod) { _, _ in refreshBalanceSummary() }
        .onChange(of: todaysFoods.count) { _, _ in refreshBalanceSummary() }
        .onChange(of: consumedCalories) { _, _ in refreshBalanceSummary() }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                headerTitle
                if let last = latest { headerLastMeasure(last.date) }
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                headerTitle
                Spacer()
                if let last = latest { headerLastMeasure(last.date) }
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Genel Bakış").eyebrow()
            Text("Hercules")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
        }
    }

    private func headerLastMeasure(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Palette.accent).frame(width: 6, height: 6)
            Text("Son Ölçüm").eyebrow()
            Text(Fmt.dateLong.string(from: date))
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.textPrimary)
        }
    }

    // MARK: - Hero

    private func heroCard(compact: Bool) -> some View {
        VStack(spacing: 0) {
            heroMain(compact: compact)
                .padding(.horizontal, compact ? 22 : 36)
                .padding(.top, compact ? 24 : 32)
                .padding(.bottom, compact ? 22 : 26)
            Hairline()
            heroMealStrip
                .padding(.horizontal, compact ? 22 : 36)
                .padding(.vertical, 14)
            if mealsExpanded && !todaysFoods.isEmpty {
                mealsList
                    .padding(.horizontal, compact ? 22 : 36)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .dashboardCard()
    }

    private var mealsList: some View {
        VStack(spacing: 0) {
            ForEach(todaysFoods) { food in
                HeroMealRow(food: food) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        ctx.delete(food)
                        ctx.saveOrReport()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func heroMain(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 24) {
                heroLeft(compact: true)
                if let r = calorieResult {
                    heroRing(r)
                    Hairline()
                    heroMacros(r)
                } else {
                    heroSetup()
                }
            }
        } else {
            HStack(alignment: .top, spacing: 36) {
                heroLeft(compact: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let r = calorieResult {
                    heroRing(r)
                        .frame(width: 232)
                    heroMacros(r)
                        .frame(width: 340)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Palette.border)
                                .frame(width: 0.5)
                                .offset(x: -18)
                        }
                } else {
                    heroSetup()
                        .frame(width: 608)
                }
            }
        }
    }

    private func heroLeft(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(greeting)
                .font(.system(size: compact ? 32 : 40, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            Text(heroDetail(calorieResult))
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380, alignment: .leading)

            heroChips(compact: compact)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func heroChips(compact: Bool) -> some View {
        let goalSub = goalDetail.isEmpty ? nil : goalDetail
        let progressSub = progressDetail(weightStats).isEmpty ? nil : progressDetail(weightStats)

        if compact {
            VStack(alignment: .leading, spacing: 14) {
                HeroStatColumn(label: "Hedef", value: goalTitle, sub: goalSub)
                HeroStatColumn(label: "Ritim", value: cadenceTitle)
                HeroStatColumn(label: "İlerleme", value: progressTitle(weightStats), sub: progressSub)
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                HeroStatColumn(label: "Hedef", value: goalTitle, sub: goalSub)
                    .frame(maxWidth: 150, alignment: .leading)
                chipRule
                HeroStatColumn(label: "Ritim", value: cadenceTitle)
                    .frame(maxWidth: 150, alignment: .leading)
                chipRule
                HeroStatColumn(label: "İlerleme", value: progressTitle(weightStats), sub: progressSub)
                    .frame(maxWidth: 150, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }

    private var chipRule: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(width: 0.5, height: 40)
            .padding(.horizontal, 20)
    }

    private func heroRing(_ r: CalorieResult) -> some View {
        let remaining = remainingCalories(r)
        let isOver = remaining < 0
        return VStack(spacing: 16) {
            CalorieProgressRing(
                progress: calorieProgress(r),
                tint: ringTint(r),
                value: "\(isOver ? "+" : "")\(Fmt.int(abs(remaining)))",
                label: isOver ? "kcal fazla" : "kcal kaldı",
                subtitle: "Hedef \(Fmt.int(r.goalCalories))",
                labelColor: isOver ? ringTint(r) : Palette.textTertiary
            )
            .frame(width: 208, height: 208)

            HStack(spacing: 0) {
                ringStat("Tüketilen", "\(Fmt.int(consumedCalories)) kcal")
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 0.5, height: 28)
                    .padding(.horizontal, 18)
                ringStat("TDEE", "\(Fmt.int(r.tdee)) kcal")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func ringStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).eyebrow()
            Text(value)
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func heroMacros(_ r: CalorieResult) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Günlük Plan").eyebrow()
            HeroMacroRow(name: "Protein", consumed: consumedProtein, target: r.protein.grams, percent: r.protein.percent, tint: Palette.macroProtein)
            HeroMacroRow(name: "Karbonhidrat", consumed: consumedCarbs, target: r.carbs.grams, percent: r.carbs.percent, tint: Palette.macroCarbs)
            HeroMacroRow(name: "Yağ", consumed: consumedFat, target: r.fat.grams, percent: r.fat.percent, tint: Palette.macroFat)
            Hairline()
                .padding(.top, 2)
            HStack(alignment: .top, spacing: 0) {
                heroMicro("Su", "\(Fmt.num(r.water, digits: 1)) L")
                heroMicroDivider
                heroMicro("Lif", "\(Fmt.int(r.fiber)) g")
                heroMicroDivider
                heroMicro("Yağsız Kütle hedefi", "\(Fmt.num(r.leanMass, digits: 1)) kg")
            }
        }
    }

    private func heroMicro(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Typography.micro)
                .foregroundStyle(Palette.textQuaternary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroMicroDivider: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 12)
    }

    private func heroSetup() -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "scope")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Palette.warning)
                .frame(width: 40, height: 40)
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var heroMealStrip: some View {
        if todaysFoods.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                Text("Bugün yemek kaydı yok")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Text("İlk öğün eklendiğinde makro ve kalori sapması burada görünür.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        } else {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    mealsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                    Text("\(todaysFoods.count) öğün kayıtlı")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(Fmt.int(consumedCalories)) kcal · P \(Fmt.int(consumedProtein))g · K \(Fmt.int(consumedCarbs))g · Y \(Fmt.int(consumedFat))g")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.textQuaternary)
                        .rotationEffect(.degrees(mealsExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(mealsExpanded ? "Öğünleri gizle" : "Öğünleri aç — silmek için satırdaki çöp ikonunu kullan")
        }
    }

    // MARK: - Vücut (body composition)

    private func bodyCard(compact: Bool) -> some View {
        let selected = selectedBodyMetric
        let rows = bodyMetricOrder.filter { $0 != selected }

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Vücut").eyebrow()
                Text("Son 30 gün")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                Spacer()
            }

            if compact {
                VStack(alignment: .leading, spacing: 18) {
                    bodyBig(selected)
                    bodyRows(rows)
                }
            } else {
                HStack(alignment: .center, spacing: 48) {
                    bodyBig(selected)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    bodyRows(rows)
                        .frame(width: 380)
                }
            }
        }
        .padding(compact ? 22 : 28)
        .dashboardCard()
    }

    private func bodyBig(_ k: MetricKind) -> some View {
        let recent = recentPoints(k)
        let current = TrendAnalysis.stats(TrendAnalysis.points(measurements, for: k)).current
        let delta = windowDelta(recent)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(k.label)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textSecondary)
                DeltaBadge(delta: delta, lowerIsBetter: lowerIsBetter(k))
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(Fmt.numOpt(current, digits: 1))
                    .font(.system(size: 46, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.6)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(k.unit)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Palette.textQuaternary)
            }
            InteractiveSparkline(points: recent, accent: metricAccent(k), unit: k.unit)
                .frame(height: 96)
                .opacity(recent.count >= 2 ? 1 : 0)
        }
        .id(k)
        .transition(.opacity)
    }

    private func bodyRows(_ rows: [MetricKind]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element) { index, k in
                if index > 0 { Hairline() }
                let recent = recentPoints(k)
                let current = TrendAnalysis.stats(TrendAnalysis.points(measurements, for: k)).current
                BodyMetricRow(
                    name: k.label,
                    value: Fmt.numOpt(current, digits: 1),
                    unit: k.unit,
                    points: recent,
                    delta: windowDelta(recent),
                    lowerIsBetter: lowerIsBetter(k),
                    accent: metricAccent(k),
                    onTap: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            selectedBodyMetric = k
                        }
                    }
                )
            }
        }
    }

    /// Last `days` of measurement points; falls back to the full series when the
    /// window is too sparse to draw.
    private func recentPoints(_ k: MetricKind, days: Int = 30) -> [TrendPoint] {
        let all = TrendAnalysis.points(measurements, for: k)
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        let recent = all.filter { $0.date >= cutoff }
        return recent.count >= 2 ? recent : all
    }

    /// Change across the visible window (last − first), i.e. the 30-day delta.
    private func windowDelta(_ points: [TrendPoint]) -> Double? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        return last.value - first.value
    }

    /// Tüm trend çizgileri Görünüm ▸ Grafik Rengi'ni izler (spec: sparkline = chart).
    private func metricAccent(_ kind: MetricKind) -> Color {
        _ = kind
        return Palette.chart
    }

    /// Goal-aware "good direction": for weight, down is good only when cutting.
    private func lowerIsBetter(_ kind: MetricKind) -> Bool {
        switch kind {
        case .bodyFat, .fatMass, .waist: return true
        case .leanMass: return false
        case .weight: return (profile?.goal.calorieAdjustment ?? 0) < 0
        case .chest, .neck: return false
        }
    }

    // MARK: - Kalori Dengesi (balance)

    private func balanceCard(_ r: CalorieResult, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    balanceHeaderLabel
                    Spacer()
                    balancePeriodSelector
                }
                VStack(alignment: .leading, spacing: 12) {
                    balanceHeaderLabel
                    balancePeriodSelector
                }
            }

            if let summary = balanceSummary {
                if compact {
                    VStack(alignment: .leading, spacing: 18) {
                        balanceLead(summary)
                        balanceStats(summary, compact: true)
                    }
                } else {
                    HStack(alignment: .center, spacing: 40) {
                        balanceLead(summary)
                            .frame(width: 300, alignment: .leading)
                        balanceStats(summary, compact: false)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                DashboardInlineEmptyState(
                    icon: "chart.bar.xaxis",
                    title: "Kalori dengesi bekleniyor",
                    detail: "Yemek kaydı olan günlerde TDEE, adım ve spor yakımı birlikte hesaplanır."
                )
            }

            Text("Hesap: \(Fmt.int(r.tdee)) kcal TDEE tabanı + kayıtlı adım yakımı + gerçek antrenman; antrenman kaydı yoksa programdaki spor günü tahmini − tüketilen kalori.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 22 : 28)
        .dashboardCard()
    }

    private var balanceHeaderLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Kalori Dengesi").eyebrow()
            Text(balancePeriod.title)
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(summary.displayValue)
                    .font(.system(size: 38, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(summary.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(summary.resultLabel)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Text(summary.detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func balanceStats(_ summary: DashboardBalanceSummary, compact: Bool) -> some View {
        let columns = compact
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            BalanceStatColumn(label: "Tüketim", value: "\(Fmt.int(summary.foodCalories)) kcal")
            BalanceStatColumn(label: "Adım", value: "\(Fmt.int(Double(summary.stepCount))) · \(Fmt.int(summary.stepCalories)) kcal")
            BalanceStatColumn(label: "Spor", value: "\(summary.workoutDays) gün · \(Fmt.int(summary.workoutCalories)) kcal")
            BalanceStatColumn(label: "Kayıtlı", value: "\(summary.trackedDays)/\(summary.calendarDays) gün")
        }
    }

    // MARK: - Copy / derived values

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

    private func heroDetail(_ result: CalorieResult?) -> String {
        guard let result else { return setupMissingDetail }
        if remainingCalories(result) < 0 { return "Bugünkü plan hedefin üzerinde." }
        if todaysFoods.isEmpty { return "Henüz giriş yok." }
        return "Bugünün kayıtları hedefle karşılaştırıldı."
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

    // MARK: - Calorie math

    private func calorieProgress(_ r: CalorieResult) -> Double {
        guard r.goalCalories > 0 else { return 0 }
        return min(1, max(0, consumedCalories / r.goalCalories))
    }

    private func remainingCalories(_ r: CalorieResult) -> Double {
        r.goalCalories - consumedCalories  // negatif olabilir = hedef aşıldı
    }

    private func ringTint(_ r: CalorieResult) -> Color {
        let remaining = remainingCalories(r)
        if remaining < 0 { return Palette.negative }
        if remaining < r.goalCalories * 0.15 { return Palette.warning }
        return Palette.chart   // Görünüm ▸ Grafik Rengi seçimi
    }

    // MARK: - Balance computation

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
}
