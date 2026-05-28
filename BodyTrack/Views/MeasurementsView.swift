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
                try? ctx.save()
            }
        }
        .sheet(item: $editingMeasurement) { m in
            MeasurementEditor(mode: .edit(m)) { _ in
                try? ctx.save()
            } onDelete: {
                ctx.delete(m)
                try? ctx.save()
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

struct SummaryStat: View {
    let label: String
    let value: String
    var detail: String? = nil
    var systemImage: String = "chart.bar"

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(label).eyebrow()
                Text(value)
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .measurementPanel(cornerRadius: Radius.md, fill: Palette.surface.opacity(0.72))
    }
}

private struct MeasurementActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var prominent: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(prominent ? Palette.background.opacity(0.16) : Color.white.opacity(0.055))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.bodyBold)
                    Text(subtitle)
                        .font(Typography.caption)
                        .opacity(0.62)
                }
            }
            .foregroundStyle(prominent ? Palette.background.opacity(0.92) : Palette.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(prominent ? Palette.accent : Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(prominent ? Color.white.opacity(0.18) : Palette.borderStrong, lineWidth: 0.5)
            )
            .scaleEffect(hovering ? 1.012 : 1)
        }
        .buttonStyle(MeasurementPressButtonStyle())
        .onHover { isHovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                hovering = isHovering
            }
        }
    }
}

private struct MeasurementPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private struct BreathingStatusDot: View {
    let color: Color
    @State private var active = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(active ? 0.22 : 0.08))
                .frame(width: 22, height: 22)
                .scaleEffect(active ? 1.08 : 0.82)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.65).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

private struct MetricChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow()
            Text(value)
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct WeekCadenceRail: View {
    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                WeekDayMark(date: day)
            }
        }
    }
}

private struct WeekDayMark: View {
    let date: Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEE"
        return f
    }()

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var isFullDay: Bool {
        Calendar.current.component(.weekday, from: date) == MeasurementCadence.fullCheckInWeekday
    }

    var body: some View {
        VStack(spacing: 7) {
            Text(Self.formatter.string(from: date))
                .font(Typography.captionBold)
                .foregroundStyle(isToday ? Palette.textPrimary : Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Capsule(style: .continuous)
                .fill(isFullDay ? Palette.accent : (isToday ? Palette.textSecondary : Palette.borderStrong))
                .frame(height: isFullDay || isToday ? 16 : 8)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isToday ? Color.white.opacity(0.22) : Color.clear, lineWidth: 0.5)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MeasurementDeltaPill: View {
    let delta: Double?
    var lowerIsBetter: Bool
    var unit: String

    private var tint: Color {
        guard let delta else { return Palette.textTertiary }
        let increased = delta > 0
        let isGood = lowerIsBetter ? !increased : increased
        return isGood ? Palette.positive : Palette.negative
    }

    private var text: String {
        guard let delta else { return "tek veri" }
        if abs(delta) < 0.005 { return "sabit" }
        return "\(Fmt.signed(delta, digits: 1)) \(unit)"
    }

    var body: some View {
        Text(text)
            .font(Typography.captionBold)
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct MetricBrief: View {
    let title: String
    let value: String
    let unit: String
    let delta: Double?
    var lowerIsBetter: Bool
    let points: [TrendPoint]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).eyebrow()
                Spacer(minLength: 8)
                MeasurementDeltaPill(delta: delta, lowerIsBetter: lowerIsBetter, unit: unit)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.hero(26))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 4)
            }

            Sparkline(points: points, accent: tint)
                .frame(height: 24)
                .opacity(points.count >= 2 ? 1 : 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)
        }
    }
}

private struct MeasurementChartBackdrop: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                Rectangle()
                    .fill(Palette.chartGrid)
                    .frame(height: 0.5)
                Spacer(minLength: 0)
            }
            Rectangle()
                .fill(Palette.chartGrid)
                .frame(height: 0.5)
        }
    }
}

private struct MeasurementPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var fill: Color
    var accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(accent, lineWidth: 0.6)
            )
            .shadow(color: Palette.background.opacity(0.28), radius: 28, x: 0, y: 18)
    }
}

private extension View {
    func measurementPanel(
        cornerRadius: CGFloat = Radius.lg,
        fill: Color = Palette.surface,
        accent: Color = Palette.border
    ) -> some View {
        modifier(MeasurementPanelModifier(cornerRadius: cornerRadius, fill: fill, accent: accent))
    }
}

struct MeasurementTypeBadge: View {
    let isFull: Bool

    var body: some View {
        Label(isFull ? "Tam ölçüm" : "Tartı", systemImage: isFull ? "ruler" : "scalemass")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isFull ? Palette.accent : Palette.textTertiary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill((isFull ? Palette.accent : Color.white).opacity(isFull ? 0.14 : 0.07))
            )
    }
}

private struct MeasurementHistoryCard: View {
    let measurement: Measurement
    let isLatest: Bool
    var onEdit: () -> Void
    @State private var hovering = false

    private var accent: Color {
        measurement.isFullCheckIn ? Palette.accent : Palette.textSecondary
    }

    private var isFull: Bool {
        measurement.isFullCheckIn
    }

    private var metrics: [MeasurementHistoryMetric] {
        [
            measurement.bodyFat.map { MeasurementHistoryMetric(label: "Yağ", value: Fmt.num($0, digits: 1), unit: "%", tint: Palette.warning) },
            measurement.leanMass.map { MeasurementHistoryMetric(label: "Yağsız", value: Fmt.num($0, digits: 1), unit: "kg", tint: Palette.positive) },
            measurement.waist.map { MeasurementHistoryMetric(label: "Bel", value: Fmt.num($0, digits: 1), unit: "cm", tint: Palette.accent) },
            measurement.chest.map { MeasurementHistoryMetric(label: "Göğüs", value: Fmt.num($0, digits: 1), unit: "cm", tint: Palette.textSecondary) },
            measurement.neck.map { MeasurementHistoryMetric(label: "Boyun", value: Fmt.num($0, digits: 1), unit: "cm", tint: Palette.textSecondary) }
        ].compactMap { $0 }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                dateBlock
                    .frame(width: 178, alignment: .leading)
                weightBlock
                    .frame(width: 150, alignment: .leading)
                metricsBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                editButton
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    dateBlock
                    Spacer(minLength: Spacing.md)
                    editButton
                }
                HStack(alignment: .top, spacing: Spacing.lg) {
                    weightBlock
                    metricsBlock
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, isFull ? Spacing.lg : Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(
                    isFull
                        ? Palette.surfaceElevated.opacity(hovering ? 0.88 : 0.76)
                        : (hovering ? Palette.surfaceElevated.opacity(0.72) : Palette.surface.opacity(0.58))
                )
        )
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(isFull ? Palette.accent.opacity(0.075) : Color.clear)
                .blur(radius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isFull ? Palette.accent.opacity(hovering ? 0.44 : 0.30) : (hovering ? Palette.borderStrong : Palette.border), lineWidth: isFull ? 0.9 : 0.6)
        )
        .overlay(alignment: .top) {
            if isFull {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.045), lineWidth: 1)
                    .blendMode(.plusLighter)
            }
        }
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(accent.opacity(isFull ? 1 : 0.48))
                .frame(width: isFull ? 5 : 3)
                .padding(.vertical, isFull ? 11 : 14)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture(perform: onEdit)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
    }

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(Fmt.dateLong.string(from: measurement.date))
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                if isLatest {
                    Circle()
                        .fill(Palette.positive)
                        .frame(width: 6, height: 6)
                }
            }
            HStack(spacing: 6) {
                Text(Fmt.timeShort.string(from: measurement.date))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                MeasurementTypeBadge(isFull: measurement.isFullCheckIn)
            }
            if isFull {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Haftalık check-in")
                        .font(Typography.captionBold)
                }
                .foregroundStyle(Palette.accent)
            }
        }
    }

    private var weightBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Ağırlık").eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(Fmt.numOpt(measurement.weight, digits: 1))
                    .font(Typography.hero(28))
                    .foregroundStyle(measurement.weight == nil ? Palette.textQuaternary : Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("kg")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 4)
                    .opacity(measurement.weight == nil ? 0 : 1)
            }
        }
    }

    @ViewBuilder
    private var metricsBlock: some View {
        if metrics.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "scalemass")
                    .font(.system(size: 11, weight: .semibold))
                Text("Günlük tartı kaydı")
                    .font(Typography.captionBold)
            }
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: Spacing.sm)],
                alignment: .leading,
                spacing: Spacing.sm
            ) {
                ForEach(metrics) { metric in
                    MeasurementHistoryMetricChip(metric: metric, highlighted: isFull)
                }
            }
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isFull ? Palette.background.opacity(0.92) : (hovering ? Palette.textPrimary : Palette.textTertiary))
                .frame(width: isFull ? 34 : 30, height: isFull ? 34 : 30)
                .background(Circle().fill(isFull ? Palette.accent : Color.white.opacity(hovering ? 0.075 : 0.045)))
                .overlay(Circle().strokeBorder(isFull ? Color.white.opacity(0.18) : Palette.border, lineWidth: 0.5))
        }
        .buttonStyle(MeasurementPressButtonStyle())
        .help("Ölçümü düzenle")
    }
}

private struct MeasurementHistoryMetric: Identifiable {
    let label: String
    let value: String
    let unit: String
    let tint: Color

    var id: String { label }
}

private struct MeasurementHistoryMetricChip: View {
    let metric: MeasurementHistoryMetric
    var highlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(metric.tint)
                    .frame(width: 5, height: 5)
                Text(metric.label.uppercased())
                    .font(Typography.label)
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(metric.value)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(metric.unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(highlighted ? Color.white.opacity(0.070) : Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(highlighted ? metric.tint.opacity(0.18) : Color.clear, lineWidth: 0.6)
        )
    }
}

struct EmptyMeasurementState: View {
    var quickAction: () -> Void
    var fullAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xxl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(Palette.accent.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "ruler")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Henüz ölçüm yok")
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                    Text("İlk kayıtla trend çizgisi ve haftalık tam ölçüm ritmi burada görünür.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420, alignment: .leading)
                }
            }

            Spacer(minLength: Spacing.lg)

            VStack(alignment: .trailing, spacing: Spacing.sm) {
                MeasurementActionButton(
                    title: "Tartı Ekle",
                    subtitle: "Başlangıç",
                    systemImage: "scalemass",
                    prominent: false,
                    action: quickAction
                )
                MeasurementActionButton(
                    title: "Tam Ölçüm",
                    subtitle: "Detaylı kayıt",
                    systemImage: "ruler",
                    prominent: true,
                    action: fullAction
                )
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
        .measurementPanel(cornerRadius: Radius.xl)
    }
}

enum EditorMode {
    case create
    case edit(Measurement)
}

struct MeasurementEditor: View {
    enum CreateKind {
        case smart
        case quick
        case full
    }

    let mode: EditorMode
    var onSave: (Measurement) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var waist: Double?
    @State private var chest: Double?
    @State private var neck: Double?
    @State private var note: String
    @State private var showExtra: Bool
    @State private var confirmingDelete = false

    init(
        mode: EditorMode,
        createKind: CreateKind = .smart,
        onSave: @escaping (Measurement) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .create:
            _date = State(initialValue: .now)
            _weight = State(initialValue: nil)
            _bodyFat = State(initialValue: nil)
            _waist = State(initialValue: nil)
            _chest = State(initialValue: nil)
            _neck = State(initialValue: nil)
            _note = State(initialValue: "")
            let shouldShowExtra: Bool
            switch createKind {
            case .smart:
                shouldShowExtra = MeasurementCadence.isFullCheckInDay()
            case .quick:
                shouldShowExtra = false
            case .full:
                shouldShowExtra = true
            }
            _showExtra = State(initialValue: shouldShowExtra)
        case .edit(let m):
            _date = State(initialValue: m.date)
            _weight = State(initialValue: m.weight)
            _bodyFat = State(initialValue: m.bodyFat)
            _waist = State(initialValue: m.waist)
            _chest = State(initialValue: m.chest)
            _neck = State(initialValue: m.neck)
            _note = State(initialValue: m.note ?? "")
            let hasExtra = m.bodyFat != nil || m.waist != nil || m.chest != nil || m.neck != nil
            _showExtra = State(initialValue: hasExtra)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var saveButtonTitle: String {
        if isEditing { return "Kaydet" }
        return showExtra ? "Tam Ölçüm Ekle" : "Tartı Ekle"
    }

    private var editorTitle: String {
        if isEditing { return "Ölçümü düzenle" }
        return showExtra ? "Tam ölçüm" : "Tartı ekle"
    }

    private var editorSubtitle: String {
        if showExtra {
            return "Kilo, yağ oranı ve çevre ölçülerini tek kayıtta topla."
        }
        return "Günlük akış için sadece kilo yeterli; detay alanları kapalı kalır."
    }

    private var modeHint: String {
        if showExtra {
            return "Haftalık ana kayıt: kilo + yağ % + bel + göğüs + boyun."
        }
        return "Hızlı tartı: kilo gir, devam et."
    }

    private var validationMessage: String? {
        if weight == nil {
            return "Kilo alanı gerekli."
        }

        if showExtra && bodyFat == nil && waist == nil && chest == nil && neck == nil {
            return "Tam ölçüm için en az bir detay alanı gir."
        }

        return nil
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var fatMass: Double? {
        guard let weight, let bodyFat else { return nil }
        return weight * bodyFat / 100
    }

    private var leanMass: Double? {
        guard let weight, let bodyFat else { return nil }
        return weight * (1 - bodyFat / 100)
    }

    private var editorWidth: CGFloat {
        showExtra ? 760 : 700
    }

    private var editorHeight: CGFloat {
        showExtra ? 720 : 620
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            Hairline()

            HStack(alignment: .top, spacing: Spacing.xl) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        modeSection
                        dateSection
                        weightSection

                        if showExtra {
                            fullMeasurementSection
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        noteSection
                    }
                    .padding(Spacing.xl)
                }
                .scrollContentBackground(.hidden)

                editorSummary
                    .frame(width: 230)
                    .padding(.top, Spacing.xl)
                    .padding(.trailing, Spacing.xl)
                    .padding(.bottom, Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Hairline()

            editorFooter
        }
        .frame(width: editorWidth, height: editorHeight)
        .background(editorBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.7)
        )
        .shadow(color: Palette.background.opacity(0.45), radius: 34, x: 0, y: 22)
        .preferredColorScheme(.dark)
        .onAppear {
            if case .create = mode {
                date = .now
            }
        }
        .confirmationDialog("Bu ölçüm silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Ölçümü Sil", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill((showExtra ? Palette.accent : Color.white).opacity(showExtra ? 0.16 : 0.07))
                    .frame(width: 46, height: 46)
                Image(systemName: showExtra ? "ruler" : "scalemass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(showExtra ? Palette.accent : Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isEditing ? "KAYIT" : "YENİ KAYIT")
                    .font(Typography.label)
                    .tracking(1)
                    .foregroundStyle(Palette.textQuaternary)
                Text(editorTitle)
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Text(editorSubtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: Spacing.lg)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(MeasurementPressButtonStyle())
            .foregroundStyle(Palette.textSecondary)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                Circle()
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    private var modeSection: some View {
        MeasurementEditorSection(
            title: "Kayıt modu",
            subtitle: modeHint,
            systemImage: showExtra ? "ruler" : "scalemass"
        ) {
            HStack(spacing: Spacing.sm) {
                MeasurementEditorModeButton(
                    title: "Tartı",
                    subtitle: "Sadece kilo",
                    systemImage: "scalemass",
                    selected: !showExtra
                ) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        showExtra = false
                    }
                }

                MeasurementEditorModeButton(
                    title: "Tam ölçüm",
                    subtitle: "Kilo + detay",
                    systemImage: "ruler",
                    selected: showExtra
                ) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        showExtra = true
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        MeasurementEditorSection(
            title: "Zaman",
            subtitle: "Kaydın tartıya çıktığın ana bağlansın.",
            systemImage: "calendar.badge.clock"
        ) {
            StyledDateField(label: "Tarih ve saat", date: $date)
        }
    }

    private var weightSection: some View {
        MeasurementEditorSection(
            title: "Tartı",
            subtitle: showExtra ? "Tam ölçümün merkez değeri." : "Günlük trend için tek zorunlu alan.",
            systemImage: "scalemass"
        ) {
            MeasurementEditorNumberField(
                label: "Kilo",
                unit: "kg",
                value: $weight,
                placeholder: "0.0",
                required: true
            )

            if !showExtra {
                Text("Yağ oranı ve çevreleri haftalık tam ölçümde aç.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    private var fullMeasurementSection: some View {
        MeasurementEditorSection(
            title: "Tam ölçüm",
            subtitle: "Detay alanları opsiyonel; en az birini doldurman yeterli.",
            systemImage: "ruler"
        ) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.md),
                    GridItem(.flexible(), spacing: Spacing.md)
                ],
                spacing: Spacing.md
            ) {
                MeasurementEditorNumberField(
                    label: "Yağ oranı",
                    unit: "%",
                    value: $bodyFat,
                    placeholder: "0.0"
                )
                MeasurementEditorNumberField(
                    label: "Bel",
                    unit: "cm",
                    value: $waist,
                    placeholder: "0.0"
                )
                MeasurementEditorNumberField(
                    label: "Göğüs",
                    unit: "cm",
                    value: $chest,
                    placeholder: "0.0"
                )
                MeasurementEditorNumberField(
                    label: "Boyun",
                    unit: "cm",
                    value: $neck,
                    placeholder: "0.0"
                )
            }

            Link(destination: URL(string: "https://www.agirsaglam.com/vucut-yag-orani-hesaplama/")!) {
                Label("Yağ oranı hesapla", systemImage: "arrow.up.right")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var noteSection: some View {
        MeasurementEditorSection(
            title: "Not",
            subtitle: "Koşul bilgisi ileride sapmaları okumayı kolaylaştırır.",
            systemImage: "text.alignleft"
        ) {
            TextField("ör: sabah aç karnına, antrenman sonrası", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(3...5)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        }
    }

    private var editorSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: 9) {
                BreathingStatusDot(color: canSave ? Palette.positive : Palette.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(canSave ? "Kayıt hazır" : "Eksik alan")
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text(showExtra ? "Tam ölçüm" : "Hızlı tartı")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                MeasurementEditorStat(label: "Kilo", value: weightText, unit: "kg")
                MeasurementEditorStat(label: "Yağ oranı", value: optionalText(bodyFat), unit: "%")

                if showExtra {
                    MeasurementEditorStat(label: "Yağsız kütle", value: optionalText(leanMass), unit: "kg")
                    MeasurementEditorStat(label: "Yağ kütlesi", value: optionalText(fatMass), unit: "kg")
                }
            }

            Hairline()

            VStack(alignment: .leading, spacing: 8) {
                Text("Alan durumu").eyebrow()
                MeasurementFieldStatus(label: "Tartı", filled: weight != nil)
                if showExtra {
                    MeasurementFieldStatus(label: "Yağ", filled: bodyFat != nil)
                    MeasurementFieldStatus(label: "Bel", filled: waist != nil)
                    MeasurementFieldStatus(label: "Göğüs", filled: chest != nil)
                    MeasurementFieldStatus(label: "Boyun", filled: neck != nil)
                }
            }

            Spacer(minLength: 0)

            Text(Fmt.dateLong.string(from: date))
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var editorFooter: some View {
        HStack(spacing: Spacing.md) {
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.warning)
                    .lineLimit(2)
            } else {
                Label(showExtra ? "Detaylı kayıt kaydedilecek." : "Hızlı tartı kaydedilecek.", systemImage: "checkmark.circle")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.positive)
            }

            Spacer(minLength: Spacing.md)

            if isEditing, onDelete != nil {
                Button {
                    confirmingDelete = true
                } label: {
                    Label("Sil", systemImage: "trash")
                        .font(Typography.bodyBold)
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                }
                .buttonStyle(MeasurementPressButtonStyle())
                .foregroundStyle(Palette.negative)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.negative.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Palette.negative.opacity(0.22), lineWidth: 0.5)
                )
            }

            Button("Vazgeç") {
                dismiss()
            }
            .font(Typography.bodyBold)
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)

            Button {
                guard canSave else { return }
                save()
                dismiss()
            } label: {
                Label(saveButtonTitle, systemImage: showExtra ? "ruler" : "scalemass")
                    .font(Typography.bodyBold)
                    .padding(.horizontal, 15)
                    .frame(height: 38)
            }
            .buttonStyle(MeasurementPressButtonStyle())
            .foregroundStyle(canSave ? Palette.background.opacity(0.92) : Palette.textQuaternary)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(canSave ? Palette.accent : Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(canSave ? Color.white.opacity(0.18) : Palette.border, lineWidth: 0.5)
            )
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    private var editorBackground: some View {
        ZStack(alignment: .topLeading) {
            Palette.surface
            LinearGradient(
                colors: [
                    (showExtra ? Palette.accent : Color.white).opacity(showExtra ? 0.14 : 0.055),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
    }

    private var weightText: String {
        guard let weight else { return "—" }
        return Fmt.num(weight, digits: 1)
    }

    private func optionalText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Fmt.num(value, digits: 1)
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedBodyFat = showExtra ? bodyFat : nil
        let savedWaist = showExtra ? waist : nil
        let savedChest = showExtra ? chest : nil
        let savedNeck = showExtra ? neck : nil

        switch mode {
        case .create:
            let m = Measurement(
                date: date,
                weight: weight,
                bodyFat: savedBodyFat,
                waist: savedWaist,
                chest: savedChest,
                neck: savedNeck,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            onSave(m)
        case .edit(let m):
            m.date = date
            m.weight = weight
            m.bodyFat = savedBodyFat
            m.waist = savedWaist
            m.chest = savedChest
            m.neck = savedNeck
            m.note = trimmedNote.isEmpty ? nil : trimmedNote
            onSave(m)
        }
    }
}

private struct MeasurementEditorSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(Spacing.lg)
        .measurementPanel(cornerRadius: Radius.lg, fill: Palette.surface.opacity(0.62))
    }
}

private struct MeasurementEditorModeButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? Palette.accent.opacity(0.16) : Color.white.opacity(0.045))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.bodyBold)
                    Text(subtitle)
                        .font(Typography.caption)
                        .opacity(0.7)
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Palette.accent : Palette.textQuaternary)
            }
            .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.055) : Palette.surfaceElevated.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.opacity(0.45) : Palette.border, lineWidth: 0.6)
            )
        }
        .buttonStyle(MeasurementPressButtonStyle())
    }
}

private struct MeasurementEditorNumberField: View {
    let label: String
    let unit: String
    @Binding var value: Double?
    var placeholder: String
    var required = false

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(label).eyebrow()
                if required {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 4, height: 4)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                TextField(
                    placeholder,
                    value: $value,
                    format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))
                )
                .textFieldStyle(.plain)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
                .focused($focused)
                .multilineTextAlignment(.leading)

                Text(unit)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(focused ? Palette.accent.opacity(0.45) : Palette.border, lineWidth: 0.6)
            )
        }
    }
}

private struct MeasurementEditorStat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.hero(25))
                    .foregroundStyle(value == "—" ? Palette.textQuaternary : Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .opacity(value == "—" ? 0 : 1)
                    .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MeasurementFieldStatus: View {
    let label: String
    let filled: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: filled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? Palette.positive : Palette.textQuaternary)
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(filled ? Palette.textSecondary : Palette.textTertiary)
            Spacer(minLength: 0)
        }
    }
}
