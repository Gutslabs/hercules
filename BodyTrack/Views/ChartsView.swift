import SwiftUI
import SwiftData

struct ChartsView: View {
    @Query(sort: \Measurement.date) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]

    @State private var focusedKind: MetricKind = .weight
    @State private var seriesSnapshots: [MetricKind: MetricSeriesSnapshot]? = nil

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        let series = seriesSnapshots ?? makeSeriesSnapshots()
        let snapshot = seriesSnapshot(for: focusedKind, in: series)

        GeometryReader { proxy in
            let compact = proxy.size.width < 1040

            if compact {
                // Dar pencere: doğal yükseklik + scroll.
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(compact: true)
                        if measurements.isEmpty {
                            ChartsEmptyState()
                        } else {
                            mainCard(snapshot)
                            readingPanel(snapshot)
                            seriesCard(series)
                        }
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Masaüstü: mockup tek ekran — scroll yok, kartlar viewport'u doldurur
                // (grafik esner, footer'lar kart dibinde; sağ kolon aynı hizada biter).
                VStack(alignment: .leading, spacing: 16) {
                    header(compact: false)
                    if measurements.isEmpty {
                        ChartsEmptyState()
                        Spacer(minLength: 0)
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            mainCard(snapshot)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            VStack(spacing: 16) {
                                readingPanel(snapshot)
                                seriesCard(series)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(width: 392)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
        .onAppear { refreshSeriesSnapshots() }
        .onChange(of: measurementCacheKey) { _, _ in refreshSeriesSnapshots() }
    }

    private func readingPanel(_ snapshot: MetricSeriesSnapshot) -> some View {
        ChartReadingPanel(
            kind: snapshot.kind,
            stats: snapshot.stats,
            points: snapshot.points,
            goalBand: snapshot.goalBand,
            lowerIsBetter: lowerIsBetter(snapshot.kind)
        )
    }

    // MARK: - Header

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                headerTitle
                headerLastReading
            }
        } else {
            HStack(alignment: .bottom) {
                headerTitle
                Spacer()
                headerLastReading
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Trend Lab").eyebrow()
            Text("Grafikler")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
            Text("Ölçüm serilerini hedef bandı, haftalık hız ve oynaklıkla birlikte oku.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var headerLastReading: some View {
        if let last = measurements.last {
            HStack(spacing: 8) {
                Circle().fill(Palette.accent).frame(width: 6, height: 6)
                Text("Son Okuma").eyebrow()
                Text(Fmt.relative(last.date))
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Main chart card

    private func mainCard(_ s: MetricSeriesSnapshot) -> some View {
        let stats = s.stats
        let unit = s.kind.unit
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(Palette.accent).frame(width: 6, height: 6)
                Text(s.points.isEmpty ? "veri bekliyor" : "\(s.points.count) nokta")
                    .font(Typography.captionBold)
                    .foregroundStyle(s.points.isEmpty ? Palette.textTertiary : Palette.textSecondary)
                Text(measurementWindowText)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                Spacer()
                Text("Güncel").eyebrow()
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(s.kind.label)
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                DeltaBadge(delta: stats.delta, lowerIsBetter: lowerIsBetter(s.kind))
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(Fmt.numOpt(stats.current))
                        .font(.system(size: 38, weight: .bold))
                        .monospacedDigit()
                        .tracking(-0.5)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            .padding(.top, 4)

            // Hedef bandını grafiğe geçirmiyoruz: 12 haftalık hedef projeksiyonu
            // Y/X domain'i şişirip veriyi köşeye sıkıştırıyordu. TrendChart zaten
            // veri aralığı üstüne dar bir regresyon (trend) bandı çiziyor — mockup
            // görünümü bu. (Hedef durumu sağdaki Okuma panelinde kalıyor.)
            TrendChart(points: s.points, goalBand: nil, height: 260, accent: Palette.chart, unit: unit, fills: true)
                .padding(.top, 10)

            Hairline().padding(.top, 14)
            HStack(spacing: 0) {
                chartStatColumn("7 gün ort", movingAvg(s.points, 7), unit: unit, leading: false)
                chartStatColumn("14 gün ort", movingAvg(s.points, 14), unit: unit, leading: true)
                chartStatColumn("30 gün ort", movingAvg(s.points, 30), unit: unit, leading: true)
            }
            .padding(.top, 13)

            Hairline().padding(.top, 13)
            HStack(spacing: 0) {
                chartStatColumn(
                    "Haftalık",
                    stats.weeklyChange.map { "\(Fmt.signed($0, digits: 2)) \(unit)/hafta" } ?? "—",
                    unit: "",
                    leading: false,
                    tint: weeklyTint(stats, lowerIsBetter: lowerIsBetter(s.kind))
                )
                chartStatColumn("Aralık", rangeText(stats), unit: unit, leading: true)
                chartStatColumn("Ortalama", Fmt.numOpt(stats.average), unit: unit, leading: true)
            }
            .padding(.top, 13)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .dashboardCard()
    }

    private func chartStatColumn(_ label: String, _ value: String, unit: String, leading: Bool, tint: Color = Palette.textPrimary) -> some View {
        HStack(spacing: 0) {
            if leading {
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 0.5, height: 30)
                    .padding(.trailing, 22)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).eyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 14.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Palette.textQuaternary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Series selector

    private func seriesCard(_ series: [MetricKind: MetricSeriesSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Seri Seçimi").eyebrow()
                Spacer()
                Text("\(MetricKind.allCases.count) seri · \(measurements.count) ölçüm")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }

            ForEach(MetricCategory.allCases) { category in
                let kinds = MetricKind.allCases.filter { $0.category == category }
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.label.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(Palette.textQuaternary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(kinds, id: \.self) { kind in
                            ChartSeriesTile(
                                kind: kind,
                                stats: seriesSnapshot(for: kind, in: series).stats,
                                lowerIsBetter: lowerIsBetter(kind),
                                isSelected: focusedKind == kind
                            ) {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    focusedKind = kind
                                }
                            }
                        }
                    }
                }
                .padding(.top, 14)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .dashboardCard()
    }

    // MARK: - Derived

    private func movingAvg(_ points: [TrendPoint], _ days: Int) -> String {
        TrendAnalysis.movingAverageNow(points, windowDays: Double(days)).map { Fmt.num($0, digits: 1) } ?? "—"
    }

    private func rangeText(_ stats: TrendStats) -> String {
        guard let mn = stats.min, let mx = stats.max else { return "—" }
        return "\(Fmt.num(mn, digits: 1)) – \(Fmt.num(mx, digits: 1))"
    }

    private func weeklyTint(_ stats: TrendStats, lowerIsBetter: Bool) -> Color {
        guard let weekly = stats.weeklyChange, abs(weekly) >= 0.01 else { return Palette.textSecondary }
        let positive = weekly > 0
        let good = lowerIsBetter ? !positive : positive
        return good ? Palette.positive : Palette.negative
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

    private var measurementWindowText: String {
        guard let first = measurements.first?.date, let last = measurements.last?.date else {
            return "Veri bekleniyor"
        }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return Fmt.dateLong.string(from: last)
        }
        return "\(Fmt.date.string(from: first)) – \(Fmt.dateLong.string(from: last))"
    }

    // MARK: - Snapshots

    private var measurementCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(profile?.targetWeight)
        hasher.combine(measurements.count)
        for m in measurements {
            hasher.combine(m.date)
            hasher.combine(m.weight)
            hasher.combine(m.bodyFat)
            hasher.combine(m.waist)
            hasher.combine(m.chest)
            hasher.combine(m.neck)
        }
        return hasher.finalize()
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

    private func goalBand(for kind: MetricKind, points: [TrendPoint]) -> (start: TrendPoint, end: TrendPoint)? {
        guard kind == .weight, let target = profile?.targetWeight else { return nil }
        return TrendAnalysis.goalBand(from: points, target: target)
    }
}
