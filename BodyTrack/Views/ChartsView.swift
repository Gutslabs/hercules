import SwiftUI
import SwiftData

struct ChartsView: View {
    @Query(sort: \Measurement.date) private var measurements: [Measurement]
    @Query(sort: \FoodEntry.date) private var foodEntries: [FoodEntry]
    @Query private var profiles: [UserProfile]

    @State private var selectedCategory: MetricCategory = .composition
    @State private var focusedKind: MetricKind = .weight
    @State private var seriesSnapshots: [MetricKind: MetricSeriesSnapshot]? = nil
    @State private var appeared = false
    @Namespace private var categoryNamespace

    private var profile: UserProfile? { profiles.first }

    private var latestMeasurement: Measurement? {
        measurements.last
    }

    private var visibleKinds: [MetricKind] {
        MetricKind.allCases.filter { $0.category == selectedCategory }
    }

    private var activeFocusedKind: MetricKind {
        if focusedKind.category == selectedCategory {
            return focusedKind
        }
        return visibleKinds.first ?? focusedKind
    }

    var body: some View {
        let cacheKey = measurementCacheKey
        let series = seriesSnapshots ?? makeSeriesSnapshots()

        GeometryReader { proxy in
            let contentWidth = proxy.size.width
            let compact = contentWidth < 860
            let expansive = contentWidth >= 1500

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? Spacing.xl : Spacing.xxl) {
                    header(compact: compact, series: series)
                    categoryPicker(compact: compact)

                    if measurements.isEmpty && selectedCategory != .macros {
                        ChartsEmptyState()
                    } else if selectedCategory == .macros && foodEntries.isEmpty {
                        ChartsEmptyState()
                    } else {
                        focusStage(compact: compact, expansive: expansive, series: series)
                    }

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, compact ? Spacing.lg : (expansive ? 44 : Spacing.xxl))
                .padding(.vertical, compact ? Spacing.lg : Spacing.xxl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
            }
            .background(Palette.background.ignoresSafeArea())
        }
        .onAppear {
            refreshSeriesSnapshots()
            ensureFocusedKind()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .onChange(of: cacheKey) { _, _ in
            refreshSeriesSnapshots()
            ensureFocusedKind()
        }
        .onChange(of: selectedCategory) { _, _ in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                ensureFocusedKind()
            }
        }
    }

    private var measurementCacheKey: String {
        var parts = [
            cacheKeyValue(profile?.targetWeight ?? -1),
            cacheKeyValue(profile?.targetBodyFat ?? -1),
            cacheKeyValue(profile?.manualProteinGrams ?? -1),
            cacheKeyValue(profile?.manualCarbsGrams ?? -1),
            cacheKeyValue(profile?.manualFatGrams ?? -1),
        ]
        parts.append(contentsOf: measurements.map(measurementCacheRow))
        parts.append(contentsOf: foodEntries.map { "\($0.date.timeIntervalSinceReferenceDate):\(cacheKeyValue($0.protein ?? -1)):\(cacheKeyValue($0.carbs ?? -1)):\(cacheKeyValue($0.fat ?? -1))" })
        return parts.joined(separator: "|")
    }

    private func measurementCacheRow(_ measurement: Measurement) -> String {
            [
                cacheKeyValue(measurement.date.timeIntervalSinceReferenceDate),
                cacheKeyValue(measurement.weight ?? -1),
                cacheKeyValue(measurement.bodyFat ?? -1),
                cacheKeyValue(measurement.waist ?? -1),
                cacheKeyValue(measurement.chest ?? -1),
            cacheKeyValue(measurement.neck ?? -1)
        ].joined(separator: ":")
    }

    private func cacheKeyValue(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func refreshSeriesSnapshots() {
        seriesSnapshots = makeSeriesSnapshots()
    }

    private func makeSeriesSnapshots() -> [MetricKind: MetricSeriesSnapshot] {
        let macroDailyPoints = Self.aggregateMacroPoints(from: foodEntries)
        return Dictionary(uniqueKeysWithValues: MetricKind.allCases.map { kind in
            let points: [TrendPoint]
            switch kind {
            case .protein, .carbs, .fat:
                points = macroDailyPoints[kind] ?? []
            default:
                points = TrendAnalysis.points(measurements, for: kind)
            }
            return (
                kind,
                MetricSeriesSnapshot(
                    kind: kind,
                    points: points,
                    stats: TrendAnalysis.stats(points),
                    goalBand: goalBand(for: kind, points: points)
                )
            )
        })
    }

    /// Aggregate daily macro totals from FoodEntry into TrendPoints per macro kind.
    private static func aggregateMacroPoints(from entries: [FoodEntry]) -> [MetricKind: [TrendPoint]] {
        let calendar = Calendar.current
        var proteinByDay: [Date: Double] = [:]
        var carbsByDay: [Date: Double] = [:]
        var fatByDay: [Date: Double] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            proteinByDay[day, default: 0] += entry.protein ?? 0
            carbsByDay[day, default: 0] += entry.carbs ?? 0
            fatByDay[day, default: 0] += entry.fat ?? 0
        }

        func sorted(_ dict: [Date: Double]) -> [TrendPoint] {
            dict.map { TrendPoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        }

        return [
            .protein: sorted(proteinByDay),
            .carbs: sorted(carbsByDay),
            .fat: sorted(fatByDay),
        ]
    }

    private func seriesSnapshot(
        for kind: MetricKind,
        in series: [MetricKind: MetricSeriesSnapshot]
    ) -> MetricSeriesSnapshot {
        series[kind] ?? MetricSeriesSnapshot(
            kind: kind,
            points: [],
            stats: TrendAnalysis.stats([]),
            goalBand: nil
        )
    }

    private func ensureFocusedKind() {
        guard focusedKind.category != selectedCategory else { return }
        focusedKind = visibleKinds.first ?? .weight
    }

    private func header(compact: Bool, series: [MetricKind: MetricSeriesSnapshot]) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    headerCopy
                    overviewBadge(compact: true, series: series)
                }
            } else {
                HStack(alignment: .bottom, spacing: Spacing.xxxl) {
                    headerCopy
                    Spacer(minLength: Spacing.xxxl)
                    overviewBadge(compact: false, series: series)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BreathingDot(color: Palette.accent, size: 7)
                Text("Trend Lab").eyebrow()
            }

            Text("Grafikler")
                .font(Typography.display(44))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text("Ölçüm serilerini hedef bandı, haftalık hız ve oynaklıkla birlikte oku.")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    private func overviewBadge(compact: Bool, series: [MetricKind: MetricSeriesSnapshot]) -> some View {
        let activeSeries = visibleKinds.filter { !(series[$0]?.points.isEmpty ?? true) }.count
        let latestText = latestMeasurement.map { Fmt.relative($0.date) } ?? "veri bekleniyor"

        return HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Palette.accentSoft)
                    .frame(width: 34, height: 34)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Son okuma").eyebrow()
                Text(latestText)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("Aktif seri").eyebrow()
                Text("\(activeSeries)/\(visibleKinds.count)")
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: compact ? .infinity : 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.5)
        )
        .shadow(color: Palette.background.opacity(0.28), radius: 28, x: 0, y: 16)
    }

    @ViewBuilder
    private func categoryPicker(compact: Bool) -> some View {
        let countText: String = {
            if selectedCategory == .macros {
                return "\(foodEntries.count) besin kaydı"
            }
            return "\(measurements.count) ölçüm"
        }()

        if compact {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    categoryButtons(expanded: false)
                }
                Text(countText)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        } else {
            HStack(spacing: Spacing.md) {
                categoryButtons(expanded: true)
                    .frame(maxWidth: .infinity)
                Text(countText)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 86, alignment: .trailing)
            }
        }
    }

    private func categoryButtons(expanded: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(MetricCategory.allCases) { category in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        selectedCategory = category
                    }
                } label: {
                    ZStack {
                        if selectedCategory == category {
                            RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                .fill(Palette.surfaceElevated)
                                .matchedGeometryEffect(id: "category-selection", in: categoryNamespace)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: categoryIcon(category))
                                .font(.system(size: 12, weight: .semibold))
                            Text(category.label)
                                .font(Typography.bodyBold)
                        }
                        .foregroundStyle(selectedCategory == category ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: expanded ? .infinity : nil)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressedButtonStyle())
            }
        }
        .frame(maxWidth: expanded ? .infinity : nil)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func focusStage(
        compact: Bool,
        expansive: Bool,
        series: [MetricKind: MetricSeriesSnapshot]
    ) -> some View {
        let kind = activeFocusedKind
        let snapshot = seriesSnapshot(for: kind, in: series)

        let targetVal: Double? = goalBand(for: kind, points: snapshot.points).map { _ in
            switch kind {
            case .weight:   return profile?.targetWeight
            case .bodyFat:  return profile?.targetBodyFat
            case .leanMass: return profile.flatMap { targetLeanMass(profile: $0) }
            case .fatMass:  return profile.flatMap { targetFatMass(profile: $0) }
            case .protein:  return profile?.manualProteinGrams
            case .carbs:    return profile?.manualCarbsGrams
            case .fat:      return profile?.manualFatGrams
            default:        return nil
            }
        } ?? nil

        if compact {
            VStack(alignment: .leading, spacing: Spacing.md) {
                FocusChartPanel(kind: kind, points: snapshot.points, stats: snapshot.stats, goalBand: snapshot.goalBand, compact: true, targetValue: targetVal)
                metricRail(compact: true, series: series)
                TrendBriefPanel(kind: kind, points: snapshot.points, stats: snapshot.stats, goalBand: snapshot.goalBand)
            }
        } else {
            HStack(alignment: .top, spacing: expansive ? Spacing.xl : Spacing.md) {
                FocusChartPanel(
                    kind: kind,
                    points: snapshot.points,
                    stats: snapshot.stats,
                    goalBand: snapshot.goalBand,
                    compact: false,
                    chartHeight: expansive ? 390 : 350,
                    targetValue: targetVal
                )
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    TrendBriefPanel(kind: kind, points: snapshot.points, stats: snapshot.stats, goalBand: snapshot.goalBand)
                    metricRail(compact: false, series: series)
                }
                .frame(width: expansive ? 430 : 360)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricRail(compact: Bool, series: [MetricKind: MetricSeriesSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Seri seçimi").eyebrow()
                Spacer()
                Text("\(visibleKinds.count) seri")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }

            if compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(visibleKinds, id: \.self) { kind in
                            metricButton(for: kind, series: series)
                                .frame(width: 210)
                        }
                    }
                    .padding(.vertical, 1)
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
                    spacing: Spacing.sm
                ) {
                    ForEach(visibleKinds, id: \.self) { kind in
                        metricButton(for: kind, series: series)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func metricButton(for kind: MetricKind, series: [MetricKind: MetricSeriesSnapshot]) -> some View {
        let snapshot = seriesSnapshot(for: kind, in: series)

        return MetricSignalButton(
            kind: kind,
            stats: snapshot.stats,
            icon: metricIcon(kind),
            isSelected: activeFocusedKind == kind
        ) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                focusedKind = kind
            }
        }
    }

    private func goalBand(for kind: MetricKind, points: [TrendPoint]) -> (start: TrendPoint, end: TrendPoint)? {
        guard let profile else { return nil }
        switch kind {
        case .protein, .carbs, .fat:
            // Makro hedefleri: sabit yatay çizgi
            let target: Double?
            switch kind {
            case .protein: target = profile.manualProteinGrams
            case .carbs:   target = profile.manualCarbsGrams
            case .fat:     target = profile.manualFatGrams
            default:       target = nil
            }
            guard let t = target, let first = points.first, let last = points.last else { return nil }
            let endDate = Calendar.current.date(byAdding: .day, value: 84, to: last.date) ?? last.date
            return (TrendPoint(date: first.date, value: t), TrendPoint(date: endDate, value: t))
        default:
            let target: Double?
            switch kind {
            case .weight:   target = profile.targetWeight
            case .bodyFat:  target = profile.targetBodyFat
            case .leanMass: target = targetLeanMass(profile: profile)
            case .fatMass:  target = targetFatMass(profile: profile)
            default:        target = nil
            }
            guard let t = target else { return nil }
            return TrendAnalysis.goalBand(from: points, target: t)
        }
    }

    /// Hedef kilo + hedef yağ oranından hesaplanan hedef yağsız kütle
    private func targetLeanMass(profile: UserProfile) -> Double? {
        guard let w = profile.targetWeight, let bf = profile.targetBodyFat else { return nil }
        return w * (1 - bf / 100)
    }

    /// Hedef kilo + hedef yağ oranından hesaplanan hedef yağ kütlesi
    private func targetFatMass(profile: UserProfile) -> Double? {
        guard let w = profile.targetWeight, let bf = profile.targetBodyFat else { return nil }
        return w * (bf / 100)
    }

    private func categoryIcon(_ category: MetricCategory) -> String {
        switch category {
        case .composition: return "scalemass"
        case .torso: return "ruler"
        case .macros: return "fork.knife"
        }
    }

    private func metricIcon(_ kind: MetricKind) -> String {
        switch kind {
        case .weight: return "scalemass"
        case .bodyFat: return "drop"
        case .leanMass: return "bolt"
        case .fatMass: return "circle.hexagongrid"
        case .waist, .chest, .neck: return "ruler"
        case .protein: return "bolt.fill"
        case .carbs: return "leaf"
        case .fat: return "drop.fill"
        }
    }
}

private struct MetricSeriesSnapshot {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?
}

private struct FocusChartPanel: View {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?
    let compact: Bool
    var chartHeight: CGFloat? = nil
    var targetValue: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        BreathingDot(color: points.isEmpty ? Palette.textQuaternary : Palette.accent, size: 6)
                        Text(points.isEmpty ? "veri bekliyor" : "\(points.count) nokta")
                            .font(Typography.captionBold)
                            .foregroundStyle(points.isEmpty ? Palette.textTertiary : Palette.accent)
                    }

                    Text(kind.label)
                        .font(Typography.display(compact ? 32 : 38))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Güncel").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(Fmt.numOpt(stats.current))
                            .font(Typography.hero(compact ? 28 : 34))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Text(kind.unit)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }

            TrendChart(points: points, goalBand: goalBand, height: resolvedChartHeight, accent: Palette.accent, unit: kind.unit)
                .padding(.top, 2)

        ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    FocusMetric(label: "Haftalık", value: stats.weeklyChange.map { Fmt.signed($0, digits: 2) } ?? "—", unit: "\(kind.unit)/hafta", tint: weeklyTint)
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1, height: 32)
                        .padding(.horizontal, Spacing.md)
                    FocusMetric(label: "Aralık", value: rangeText, unit: kind.unit, tint: Palette.textSecondary)
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1, height: 32)
                        .padding(.horizontal, Spacing.md)
                    FocusMetric(label: "Ortalama", value: Fmt.numOpt(stats.average), unit: kind.unit, tint: Palette.textSecondary)
                    if let t = targetValue {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 1, height: 32)
                            .padding(.horizontal, Spacing.md)
                        FocusMetric(label: "Hedef", value: Fmt.num(t, digits: 1), unit: kind.unit, tint: Palette.textSecondary)
                    }
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    FocusMetric(label: "Haftalık", value: stats.weeklyChange.map { Fmt.signed($0, digits: 2) } ?? "—", unit: "\(kind.unit)/hafta", tint: weeklyTint)
                    FocusMetric(label: "Aralık", value: rangeText, unit: kind.unit, tint: Palette.textSecondary)
                    FocusMetric(label: "Ortalama", value: Fmt.numOpt(stats.average), unit: kind.unit, tint: Palette.textSecondary)
                    if let t = targetValue {
                        FocusMetric(label: "Hedef", value: Fmt.num(t, digits: 1), unit: kind.unit, tint: Palette.textSecondary)
                    }
                }
            }
        }
        .padding(compact ? Spacing.lg : Spacing.xl)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Palette.surfaceElevated.opacity(0.98),
                                Palette.surface.opacity(0.94),
                                Palette.surface.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                // Subtle accent tint at top-left corner
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Palette.accent.opacity(0.04), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 400
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        )
        .shadow(color: Palette.accent.opacity(0.06), radius: 48, x: 0, y: 24)
        .shadow(color: Palette.background.opacity(0.35), radius: 36, x: 0, y: 22)
    }

    private var rangeText: String {
        "\(Fmt.numOpt(stats.min)) - \(Fmt.numOpt(stats.max))"
    }

    private var resolvedChartHeight: CGFloat {
        chartHeight ?? (compact ? 270 : 350)
    }

    private var weeklyTint: Color {
        guard let weekly = stats.weeklyChange else { return Palette.textTertiary }
        guard abs(weekly) >= 0.01 else { return Palette.textSecondary }
        let positive = weekly > 0
        let isGood = kind.lowerIsBetter ? !positive : positive
        return isGood ? Palette.positive : Palette.negative
    }
}

private struct TrendBriefPanel: View {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.accentSoft)
                        .frame(width: 34, height: 34)
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Okuma").eyebrow()
                    Text(narrative.title)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(narrative.detail)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Hairline()

            VStack(spacing: Spacing.sm) {
                SignalRow(label: "Veri yoğunluğu", value: "\(stats.pointCount) ölçüm", tint: densityTint)
                SignalRow(label: "Son kayıt", value: points.last.map { Fmt.dateLong.string(from: $0.date) } ?? "Yok", tint: Palette.textSecondary)
                SignalRow(label: "Hedef bandı", value: goalBand == nil ? "Kapalı" : "Açık", tint: goalBand == nil ? Palette.textTertiary : Palette.accent)
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var narrative: (title: String, detail: String) {
        guard stats.hasData else {
            return (
                "Bu seri sessiz",
                "\(kind.label) için ölçüm eklenince eğim, aralık ve hedef bandı burada okunur."
            )
        }

        guard stats.pointCount >= 3 else {
            return (
                "İlk izler oluşuyor",
                "\(stats.pointCount) ölçüm var. Güvenilir eğim için birkaç kayıt daha eklendiğinde regresyon bandı anlam kazanır."
            )
        }

        guard let weekly = stats.weeklyChange else {
            return (
                "Tempo nötr",
                "Veri mevcut, fakat haftalık hız için yeterli tarih aralığı oluşmadı."
            )
        }

        if abs(weekly) < 0.03 {
            return (
                "Çizgi dengede",
                "Haftalık değişim \(Fmt.signed(weekly, digits: 2)) \(kind.unit). Seri şu an bakım temposuna yakın."
            )
        }

        let positive = weekly > 0
        let isGood = kind.lowerIsBetter ? !positive : positive
        let direction = positive ? "yukarı" : "aşağı"
        let tone = isGood ? "hedef yönüyle uyumlu" : "hedefle ters yönde"
        return (
            "Eğim \(direction)",
            "\(Fmt.signed(weekly, digits: 2)) \(kind.unit)/hafta; mevcut hareket \(tone)."
        )
    }

    private var densityTint: Color {
        switch stats.pointCount {
        case 0...1: return Palette.textTertiary
        case 2...4: return Palette.warning
        default: return Palette.positive
        }
    }
}

private struct MetricSignalButton: View {
    let kind: MetricKind
    let stats: TrendStats
    let icon: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Palette.accent : Palette.textTertiary)
                        .frame(width: 18, height: 18)

                    Text(kind.label)
                        .font(Typography.captionBold)
                        .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 0)
                }

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Fmt.numOpt(stats.current))
                        .font(Typography.monoLarge)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(kind.unit)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }

                Text(deltaLine)
                    .font(Typography.caption)
                    .foregroundStyle(deltaTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? Palette.surfaceElevated : Color.white.opacity(0.018))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent.opacity(0.34) : Palette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressedButtonStyle())
        .help("\(kind.label) serisini ana grafiğe taşı")
    }

    private var deltaLine: String {
        guard let delta = stats.delta else { return "değişim yok" }
        return "\(Fmt.signed(delta, digits: 1)) \(kind.unit) son ölçüm"
    }

    private var deltaTint: Color {
        guard let delta = stats.delta else { return Palette.textTertiary }
        guard abs(delta) >= 0.05 else { return Palette.textSecondary }
        let positive = delta > 0
        let isGood = kind.lowerIsBetter ? !positive : positive
        return isGood ? Palette.positive : Palette.negative
    }
}

struct ChartTile: View {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?
    var isFocused: Bool = false
    var chartHeight: CGFloat = 220
    var onFocus: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        Button(action: onFocus) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(kind.label)
                            .font(Typography.titleSmall)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        HStack(spacing: 7) {
                            BreathingDot(color: points.isEmpty ? Palette.textQuaternary : Palette.accent, size: 5)
                            Text(points.isEmpty ? "veri bekliyor" : "\(points.count) ölçüm")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(Fmt.numOpt(stats.current))
                                .font(Typography.hero(28))
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                            Text(kind.unit)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }

                        Image(systemName: isFocused ? "scope" : "plus.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isFocused ? Palette.accent : Palette.textTertiary)
                            .frame(width: 26, height: 24)
                    }
                }

                statSummary

                TrendChart(points: points, goalBand: goalBand, height: chartHeight, accent: Palette.accent, unit: kind.unit)
            }
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(isFocused ? Palette.surfaceElevated.opacity(0.92) : Palette.surface.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(isFocused ? Palette.accent.opacity(0.38) : Palette.border, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(PressedButtonStyle())
        .shadow(color: Palette.background.opacity(hovering ? 0.28 : 0.18), radius: hovering ? 26 : 14, x: 0, y: hovering ? 18 : 10)
        .scaleEffect(hovering ? 1.006 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: hovering)
        .onHover { hovering = $0 }
    }

    private var statSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ChartMicroStat(label: "Değişim", value: deltaText, unit: kind.unit, tint: deltaColor, detail: weeklyText)
                Divider().background(Palette.border).padding(.horizontal, Spacing.md)
                ChartMicroStat(label: "Aralık", value: rangeText, unit: kind.unit, tint: Palette.textSecondary, detail: "min - max")
                Divider().background(Palette.border).padding(.horizontal, Spacing.md)
                ChartMicroStat(label: "Ortalama", value: Fmt.numOpt(stats.average), unit: kind.unit, tint: Palette.textSecondary, detail: "\(stats.pointCount) ölçüm")
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ChartMicroStat(label: "Değişim", value: deltaText, unit: kind.unit, tint: deltaColor, detail: weeklyText)
                ChartMicroStat(label: "Aralık", value: rangeText, unit: kind.unit, tint: Palette.textSecondary, detail: "min - max")
                ChartMicroStat(label: "Ortalama", value: Fmt.numOpt(stats.average), unit: kind.unit, tint: Palette.textSecondary, detail: "\(stats.pointCount) ölçüm")
            }
        }
    }

    private var deltaText: String {
        guard let delta = stats.delta else { return "—" }
        return Fmt.signed(delta, digits: 1)
    }

    private var rangeText: String {
        "\(Fmt.numOpt(stats.min)) - \(Fmt.numOpt(stats.max))"
    }

    private var weeklyText: String {
        guard let weekly = stats.weeklyChange else { return "haftalık yok" }
        return "\(Fmt.signed(weekly, digits: 2))/hafta"
    }

    private var deltaColor: Color {
        guard let delta = stats.delta else { return Palette.textTertiary }
        guard abs(delta) >= 0.05 else { return Palette.textSecondary }
        let positive = delta > 0
        let isGood = kind.lowerIsBetter ? !positive : positive
        return isGood ? Palette.positive : Palette.negative
    }
}

private struct FocusMetric: View {
    let label: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChartMicroStat: View {
    let label: String
    let value: String
    let unit: String
    let tint: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.mono)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SignalRow: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: Spacing.sm)
            Text(value)
                .font(Typography.captionBold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct ChartsEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(Palette.surface.opacity(0.78))
                    .frame(height: 280)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Palette.accent)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("İlk çizgi için veri bekleniyor")
                            .font(Typography.title)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Ölçümler sayfasından ağırlık, yağ oranı veya çevre ölçüsü eklediğinde bu ekran otomatik olarak trendleri çizer.")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textSecondary)
                            .lineSpacing(3)
                            .frame(maxWidth: 520, alignment: .leading)
                    }
                }
                .padding(Spacing.xl)
            }
        }
    }
}

private struct BreathingDot: View {
    let color: Color
    var size: CGFloat = 6
    @State private var active = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: size * 3.2, height: size * 3.2)
                .scaleEffect(active ? 1.12 : 0.72)
                .opacity(active ? 0.2 : 0.75)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.spring(response: 1.4, dampingFraction: 0.72).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

private struct ChartScanLine: View {
    @State private var active = false

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.055), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 42)
                .offset(y: active ? proxy.size.height : -48)
                .opacity(0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 4.2, dampingFraction: 0.96).repeatForever(autoreverses: false)) {
                active = true
            }
        }
    }
}

private struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
