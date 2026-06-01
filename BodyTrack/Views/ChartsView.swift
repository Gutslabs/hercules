import SwiftUI
import SwiftData

struct ChartsView: View {
    @Query(sort: \Measurement.date) private var measurements: [Measurement]
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

                    if measurements.isEmpty {
                        ChartsEmptyState()
                    } else {
                        focusStage(compact: compact, expansive: expansive, series: series)
                        chartWall(compact: compact, expansive: expansive, series: series)
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
        var parts = [cacheKeyValue(profile?.targetWeight ?? -1)]
        parts.append(contentsOf: measurements.map(measurementCacheRow))
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
        Dictionary(uniqueKeysWithValues: MetricKind.allCases.map { kind in
            let points = TrendAnalysis.points(measurements, for: kind)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
        let countText = "\(measurements.count) ölçüm"

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

        if compact {
            VStack(alignment: .leading, spacing: Spacing.md) {
                FocusChartPanel(kind: kind, points: snapshot.points, stats: snapshot.stats, goalBand: snapshot.goalBand, compact: true)
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
                    chartHeight: expansive ? 390 : 350
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

    private func chartWall(
        compact: Bool,
        expansive: Bool,
        series: [MetricKind: MetricSeriesSnapshot]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seri Duvarı").eyebrow()
                    Text(selectedCategory.label)
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text(measurementWindowText)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }

            if compact {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(Array(visibleKinds.enumerated()), id: \.element) { index, kind in
                        chartTile(for: kind, index: index, compact: true, series: series)
                    }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: expansive ? 430 : 360), spacing: Spacing.md)],
                    spacing: Spacing.md
                ) {
                    ForEach(Array(visibleKinds.enumerated()), id: \.element) { index, kind in
                        chartTile(for: kind, index: index, compact: false, series: series)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartTile(
        for kind: MetricKind,
        index: Int,
        compact: Bool,
        series: [MetricKind: MetricSeriesSnapshot]
    ) -> some View {
        let snapshot = seriesSnapshot(for: kind, in: series)
        let baseHeight: CGFloat = compact ? 210 : (index % 3 == 0 ? 250 : 214)

        return ChartTile(
            kind: kind,
            points: snapshot.points,
            stats: snapshot.stats,
            goalBand: snapshot.goalBand,
            isFocused: activeFocusedKind == kind,
            chartHeight: baseHeight
        ) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                focusedKind = kind
            }
        }
    }

    private var measurementWindowText: String {
        guard let first = measurements.first?.date, let last = measurements.last?.date else {
            return "Veri bekleniyor"
        }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return Fmt.dateLong.string(from: last)
        }
        return "\(Fmt.date.string(from: first)) - \(Fmt.dateLong.string(from: last))"
    }

    private func goalBand(for kind: MetricKind, points: [TrendPoint]) -> (start: TrendPoint, end: TrendPoint)? {
        guard kind == .weight, let target = profile?.targetWeight else { return nil }
        return TrendAnalysis.goalBand(from: points, target: target)
    }

    private func categoryIcon(_ category: MetricCategory) -> String {
        switch category {
        case .composition: return "scalemass"
        case .torso: return "ruler"
        }
    }

    private func metricIcon(_ kind: MetricKind) -> String {
        switch kind {
        case .weight: return "scalemass"
        case .bodyFat: return "drop"
        case .leanMass: return "bolt"
        case .fatMass: return "circle.hexagongrid"
        case .waist, .chest, .neck: return "ruler"
        }
    }
}
