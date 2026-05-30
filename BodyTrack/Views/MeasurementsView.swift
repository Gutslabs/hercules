import SwiftUI
import SwiftData

struct MeasurementsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

    @State private var showingNew = false
    @State private var editingMeasurement: Measurement? = nil
    @State private var newMeasurementKind: MeasurementEditor.CreateKind = .smart

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1040

            VStack(alignment: .leading, spacing: Spacing.xl) {
                headerGrid(compact: compact)
                signalDeck(compact: compact)
                measurementList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(measurementsBackground)
        .sheet(isPresented: $showingNew) {
            MeasurementEditor(mode: .create, createKind: newMeasurementKind) { m in
                ctx.insert(m)
                ctx.saveOrReport()
            }
        }
        .sheet(item: $editingMeasurement) { m in
            MeasurementEditor(mode: .edit(m)) { _ in
                ctx.saveOrReport()
            } onDelete: {
                ctx.delete(m)
                ctx.saveOrReport()
            }
        }
    }

    private var measurementsBackground: some View {
        ZStack(alignment: .topLeading) {
            Palette.background.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Palette.surfaceElevated.opacity(0.42),
                    Palette.background.opacity(0)
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func headerGrid(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: Spacing.md) {
                heroPanel
                cadencePanel
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.md) {
                heroPanel
                    .frame(maxWidth: .infinity)
                cadencePanel
                    .frame(width: 360)
            }
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ölçüm Defteri").eyebrow()
                    Text("Vücut ölçümleri")
                        .font(Typography.display(44))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("Günlük tartıyı sade tut, haftalık tam ölçümle yağ oranı ve çevreleri netleştir.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520, alignment: .leading)
                }

                Spacer(minLength: Spacing.lg)

                latestWeightReadout
            }

            HStack(alignment: .center, spacing: Spacing.sm) {
                MeasurementActionButton(
                    title: "Tartı Ekle",
                    subtitle: "Günlük kayıt",
                    systemImage: "scalemass",
                    prominent: false
                ) {
                    newMeasurementKind = .quick
                    showingNew = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Hızlı tartı ekle (⌘N)")

                MeasurementActionButton(
                    title: "Tam Ölçüm",
                    subtitle: "Kilo, yağ, çevre",
                    systemImage: "ruler",
                    prominent: true
                ) {
                    newMeasurementKind = .full
                    showingNew = true
                }
                .help("Kilo, yağ oranı ve çevreleri birlikte ekle")

                Spacer(minLength: 0)

                if let last = measurements.first {
                    lastUpdateBadge(last.date)
                }
            }
        }
        .padding(Spacing.xl)
        .measurementPanel(cornerRadius: Radius.xl)
    }

    @ViewBuilder
    private var latestWeightReadout: some View {
        if let latestWeight = measurements.compactMap(\.weight).first {
            VStack(alignment: .trailing, spacing: 5) {
                Text("Son kilo").eyebrow()
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(Fmt.num(latestWeight, digits: 1))
                        .font(Typography.display(42))
                        .foregroundStyle(Palette.textPrimary)
                    Text("kg")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.bottom, 5)
                }
            }
            .frame(minWidth: 118, alignment: .trailing)
        }
    }

    private func lastUpdateBadge(_ date: Date) -> some View {
        HStack(spacing: 8) {
            BreathingStatusDot(color: Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Son kayıt").eyebrow()
                Text(Fmt.relative(date))
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.5)
        )
    }

    private var cadencePanel: some View {
        let isFullDay = MeasurementCadence.isFullCheckInDay()
        let hasThisWeekFull = MeasurementCadence.hasFullCheckInThisWeek(measurements)
        let nextFull = MeasurementCadence.nextFullCheckIn()

        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill((isFullDay ? Palette.accent : Color.white).opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: isFullDay ? "ruler.fill" : "calendar.badge.clock")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isFullDay ? Palette.accent : Palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(isFullDay ? "Tam ölçüm bugün" : "Cumartesi tam ölçüm")
                            .font(Typography.titleSmall)
                            .foregroundStyle(Palette.textPrimary)
                        if hasThisWeekFull {
                            MeasurementTypeBadge(isFull: true)
                        }
                    }
                    Text(checkInSubtitle(isFullDay: isFullDay, hasThisWeekFull: hasThisWeekFull, nextFull: nextFull))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            WeekCadenceRail()

            HStack(spacing: Spacing.sm) {
                MetricChip(label: "Bu hafta", value: hasThisWeekFull ? "Tamam" : "Açık")
                MetricChip(label: "Bu ay", value: "\(measurementsThisMonth)")
                Spacer(minLength: 0)
                Button {
                    newMeasurementKind = isFullDay ? .full : .quick
                    showingNew = true
                } label: {
                    Image(systemName: isFullDay ? "ruler" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(MeasurementPressButtonStyle())
                .foregroundStyle(Palette.textPrimary)
                .background(Circle().fill(Palette.surfaceElevated))
                .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 0.5))
                .help(isFullDay ? "Tam ölçüm gir" : "Bugün tartı ekle")
            }
        }
        .padding(Spacing.xl)
        .measurementPanel(cornerRadius: Radius.xl, accent: isFullDay ? Palette.accent.opacity(0.45) : Palette.borderStrong)
    }

    private func checkInSubtitle(isFullDay: Bool, hasThisWeekFull: Bool, nextFull: Date) -> String {
        if isFullDay {
            return hasThisWeekFull
                ? "Bu haftanın tam ölçümü girilmiş. İstersen yine de düzeltme/yenileme kaydı açabilirsin."
                : "Bugün kilo dışında yağ %, bel, göğüs ve boyun ölçülerini de gir."
        }
        return "Günlük akışta sadece kilo yeterli. Sıradaki tam ölçüm: \(Fmt.dateLong.string(from: nextFull))."
    }

    @ViewBuilder
    private func signalDeck(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: Spacing.md) {
                weightTrendPanel
                summaryMosaic
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.md) {
                weightTrendPanel
                    .frame(maxWidth: .infinity)
                summaryMosaic
                    .frame(width: 374)
            }
        }
    }

    private var weightTrendPanel: some View {
        let stats = TrendAnalysis.stats(weightPoints)
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Trend Sinyali").eyebrow()
                    Text("Ağırlık akışı")
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                MeasurementDeltaPill(delta: stats.delta, lowerIsBetter: false, unit: "kg")
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(stats.current.map { Fmt.num($0, digits: 1) } ?? "—")
                    .font(Typography.display(50))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("kg")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 7)
                Spacer(minLength: Spacing.lg)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Haftalık eğim").eyebrow()
                    Text(stats.weeklyChange.map { "\(Fmt.signed($0, digits: 2)) kg" } ?? "—")
                        .font(Typography.monoLarge)
                        .foregroundStyle(deltaTint(stats.weeklyChange, lowerIsBetter: true))
                }
            }

            ZStack(alignment: .bottomLeading) {
                MeasurementChartBackdrop()
                Sparkline(points: weightPoints, accent: Palette.accent)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 8)
                    .opacity(weightPoints.count >= 2 ? 1 : 0)
                if weightPoints.count < 2 {
                    Text("Trend için en az iki kilo kaydı gerekiyor.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 86)

            HStack(spacing: Spacing.md) {
                MetricBrief(
                    title: "Yağ oranı",
                    value: bodyFatStats.current.map { Fmt.num($0, digits: 1) } ?? "—",
                    unit: "%",
                    delta: bodyFatStats.delta,
                    lowerIsBetter: true,
                    points: bodyFatPoints,
                    tint: Palette.warning
                )
                MetricBrief(
                    title: "Bel",
                    value: waistStats.current.map { Fmt.num($0, digits: 1) } ?? "—",
                    unit: "cm",
                    delta: waistStats.delta,
                    lowerIsBetter: true,
                    points: waistPoints,
                    tint: Palette.positive
                )
            }
        }
        .padding(Spacing.xl)
        .measurementPanel(cornerRadius: Radius.xl)
    }

    private var summaryMosaic: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SummaryStat(
                label: "Toplam Ölçüm",
                value: "\(measurements.count)",
                detail: "Tüm kayıtlar",
                systemImage: "list.bullet.rectangle"
            )
            HStack(spacing: Spacing.md) {
                SummaryStat(
                    label: "Tam",
                    value: "\(fullMeasurements.count)",
                    detail: "Yağ + çevre",
                    systemImage: "ruler"
                )
                SummaryStat(
                    label: "Bu Ay",
                    value: "\(measurementsThisMonth)",
                    detail: "Aktif kayıt",
                    systemImage: "calendar"
                )
            }
            SummaryStat(
                label: "Son Tam",
                value: fullMeasurements.first.map { Fmt.date.string(from: $0.date) } ?? "—",
                detail: fullMeasurements.first.map { Fmt.relative($0.date) } ?? "Bekleniyor",
                systemImage: "checkmark.seal"
            )
        }
    }

    private var weightPoints: [TrendPoint] {
        TrendAnalysis.points(measurements, for: .weight)
    }

    private var bodyFatPoints: [TrendPoint] {
        TrendAnalysis.points(measurements, for: .bodyFat)
    }

    private var waistPoints: [TrendPoint] {
        TrendAnalysis.points(measurements, for: .waist)
    }

    private var bodyFatStats: TrendStats {
        TrendAnalysis.stats(bodyFatPoints)
    }

    private var waistStats: TrendStats {
        TrendAnalysis.stats(waistPoints)
    }

    private var fullMeasurements: [Measurement] {
        measurements.filter(\.isFullCheckIn)
    }

    private var measurementsThisMonth: Int {
        let cal = Calendar.current
        let now = Date()
        return measurements.filter {
            cal.isDate($0.date, equalTo: now, toGranularity: .month)
        }.count
    }

    @ViewBuilder
    private var measurementList: some View {
        if measurements.isEmpty {
            EmptyMeasurementState(
                quickAction: {
                    newMeasurementKind = .quick
                    showingNew = true
                },
                fullAction: {
                    newMeasurementKind = .full
                    showingNew = true
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Kayıt Akışı").eyebrow()
                        Text("Son ölçüm geçmişi")
                            .font(Typography.titleSmall)
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Spacer()
                    Text("\(measurements.count) kayıt")
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.045)))
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)

                Hairline()

                measurementTimeline
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .measurementPanel(cornerRadius: Radius.xl)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private var measurementTimeline: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(measurements.enumerated()), id: \.element.id) { index, measurement in
                    MeasurementHistoryCard(
                        measurement: measurement,
                        isLatest: index == 0,
                        onEdit: { editingMeasurement = measurement }
                    )
                }
            }
            .padding(Spacing.lg)
        }
        .scrollIndicators(.visible)
        .background(Palette.background.opacity(0.10))
    }

    private func deltaTint(_ value: Double?, lowerIsBetter: Bool) -> Color {
        guard let value else { return Palette.textTertiary }
        let increased = value > 0
        let isGood = lowerIsBetter ? !increased : increased
        return isGood ? Palette.positive : Palette.negative
    }
}
