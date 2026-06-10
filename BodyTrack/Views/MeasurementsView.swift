import SwiftUI
import SwiftData

struct MeasurementsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

    @State private var showingNew = false
    @State private var editingMeasurement: Measurement? = nil
    @State private var newMeasurementKind: MeasurementEditor.CreateKind = .smart
    @State private var showAllMeasurements = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 960

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(compact: compact)

                    if measurements.isEmpty {
                        EmptyMeasurementState(
                            quickAction: { newMeasurementKind = .quick; showingNew = true },
                            fullAction: { newMeasurementKind = .full; showingNew = true }
                        )
                    } else {
                        if compact {
                            VStack(alignment: .leading, spacing: 16) {
                                flowCard
                                rhythmCard
                            }
                        } else {
                            HStack(alignment: .top, spacing: 16) {
                                flowCard
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                rhythmCard
                                    .frame(width: 400)
                                    .frame(maxHeight: .infinity)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        minis(compact: compact)
                        historyCard(
                            compact: compact,
                            maxRows: compact ? 7 : fittingHistoryRows(viewportHeight: proxy.size.height)
                        )
                    }
                }
                .padding(.horizontal, compact ? 20 : 40)
                .padding(.vertical, compact ? 24 : 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
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
        .sheet(isPresented: $showAllMeasurements) {
            MeasurementHistorySheet()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                headerTitle
                if let last = measurements.first { headerLastRecord(last.date) }
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                headerTitle
                Spacer()
                if let last = measurements.first { headerLastRecord(last.date) }
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Ölçüm Defteri").eyebrow()
            Text("Vücut ölçümleri")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
        }
    }

    private func headerLastRecord(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Palette.accent).frame(width: 6, height: 6)
            Text("Son Kayıt").eyebrow()
            Text(Fmt.relative(date))
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Layer 1a · Ağırlık akışı

    private var flowCard: some View {
        let wp = weightPoints
        let stats = TrendAnalysis.stats(wp)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Trend Sinyali").eyebrow()
                Text("Ağırlık akışı")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                Spacer()
                Text("Haftalık Eğim").eyebrow()
                Text(stats.weeklyChange.map { "\(Fmt.signed($0, digits: 2)) kg" } ?? "—")
                    .font(Typography.mono)
                    .foregroundStyle(deltaTint(stats.weeklyChange, lowerIsBetter: true))
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(stats.current.map { Fmt.num($0, digits: 1) } ?? "—")
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                        .tracking(-0.6)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("kg")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Palette.textQuaternary)
                }
                DeltaBadge(delta: stats.delta, lowerIsBetter: true)
                Text("Günlük tartıyı sade tut, haftalık tam ölçümle yağ oranı ve çevreleri netleştir.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
            .padding(.top, 10)

            ZStack {
                SmoothedSparkline(raw: wp, windowDays: 7, accent: Palette.chart, unit: "kg")
                    .opacity(wp.count >= 2 ? 1 : 0)
                if wp.count < 2 {
                    Text("Trend için en az iki kilo kaydı gerekiyor.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(height: 132)
            .padding(.top, 10)

            HStack(spacing: 16) {
                TrendLegendMark(label: "7 gün ortalama", color: Palette.accent, bold: true)
                TrendLegendMark(label: "ham tartı", color: Palette.accent.opacity(0.45))
                Spacer(minLength: 0)
            }
            .padding(.top, 12)

            Spacer(minLength: 14)

            Hairline()

            HStack(spacing: 0) {
                avgColumn("7 gün ort", days: 7, leading: false)
                avgColumn("14 gün ort", days: 14, leading: true)
                avgColumn("30 gün ort", days: 30, leading: true)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .dashboardCard()
    }

    private func avgColumn(_ label: String, days: Int, leading: Bool) -> some View {
        let value = TrendAnalysis.movingAverageNow(weightPoints, windowDays: Double(days))
        return HStack(spacing: 0) {
            if leading {
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 0.5, height: 30)
                    .padding(.trailing, 20)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).eyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value.map { Fmt.num($0, digits: 1) } ?? "—")
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                    Text("kg")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Layer 1b · Ritim

    private var rhythmCard: some View {
        let isFullDay = MeasurementCadence.isFullCheckInDay()
        let hasThisWeekFull = MeasurementCadence.hasFullCheckInThisWeek(measurements)
        let nextFull = MeasurementCadence.nextFullCheckIn()

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Ritim").eyebrow()
                Text(isFullDay ? "Tam ölçüm bugün" : "Cumartesi tam ölçüm")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(checkInSubtitle(isFullDay: isFullDay, hasThisWeekFull: hasThisWeekFull, nextFull: nextFull))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RhythmWeekStrip()

            HStack(spacing: 8) {
                Text("Bu Hafta").eyebrow()
                Text(hasThisWeekFull ? "Tamam" : "Açık")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                rhythmPill("Tartı", prominent: false) { newMeasurementKind = .quick; showingNew = true }
                rhythmPill("Tam", prominent: true) { newMeasurementKind = .full; showingNew = true }
            }

            Spacer(minLength: 14)

            Hairline()

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 14) {
                rhythmCounter("Toplam ölçüm", "\(measurements.count)", "Tüm kayıtlar")
                rhythmCounter("Tam", "\(fullMeasurements.count)", "Yağ + çevre")
                rhythmCounter("Bu ay", "\(measurementsThisMonth)", "Aktif kayıt")
                rhythmCounter(
                    "Son tam",
                    fullMeasurements.first.map { Fmt.date.string(from: $0.date) } ?? "—",
                    fullMeasurements.first.map { Fmt.relative($0.date) } ?? "Bekleniyor"
                )
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .dashboardCard()
    }

    private func rhythmPill(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(prominent ? Palette.background : Palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(prominent ? Palette.accent : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(prominent ? Color.clear : Palette.border, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    private func rhythmCounter(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow()
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Palette.textQuaternary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkInSubtitle(isFullDay: Bool, hasThisWeekFull: Bool, nextFull: Date) -> String {
        if isFullDay {
            return hasThisWeekFull
                ? "Bu haftanın tam ölçümü girilmiş. İstersen yine de düzeltme/yenileme kaydı açabilirsin."
                : "Bugün kilo dışında yağ %, bel, göğüs ve boyun ölçülerini de gir."
        }
        return "Günlük akışta sadece kilo yeterli. Sıradaki tam ölçüm: \(Fmt.dateLong.string(from: nextFull))."
    }

    // MARK: - Layer 2 · Yağ + Bel

    @ViewBuilder
    private func minis(compact: Bool) -> some View {
        let bfp = bodyFatPoints
        let bfStats = TrendAnalysis.stats(bfp)
        let wstP = waistPoints
        let wStats = TrendAnalysis.stats(wstP)
        let columns = compact ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]

        LazyVGrid(columns: columns, spacing: 16) {
            MeasureMiniCard(
                name: "Yağ Oranı",
                value: bfStats.current.map { Fmt.num($0, digits: 1) } ?? "—",
                unit: "%",
                delta: bfStats.delta,
                lowerIsBetter: true,
                points: bfp,
                tint: Palette.warning
            )
            MeasureMiniCard(
                name: "Bel",
                value: wStats.current.map { Fmt.num($0, digits: 1) } ?? "—",
                unit: "cm",
                delta: wStats.delta,
                lowerIsBetter: true,
                points: wstP,
                tint: Palette.positive
            )
        }
    }

    // MARK: - Layer 3 · Kayıt geçmişi

    /// Masaüstünde geçmiş listesi, sayfa scroll'suz viewport'a sığacak kadar satır
    /// gösterir (mockup'taki gibi tek ekran). Üstteki kartların sabit maliyeti
    /// düşülür, kalan alana ~48pt'lik satırlar sığdırılır; 3–7 arası kıstırılır.
    private func fittingHistoryRows(viewportHeight: CGFloat) -> Int {
        let fixedOverhead: CGFloat = 800  // padding + header + trend/ritim + mini kartlar + liste kromu
        return min(7, max(3, Int((viewportHeight - fixedOverhead) / 48)))
    }

    private func historyCard(compact: Bool, maxRows: Int) -> some View {
        let rows = Array(measurements.prefix(maxRows))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Kayıt Akışı").eyebrow()
                Text("Son ölçüm geçmişi")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                Spacer()
                Text("\(measurements.count) kayıt")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            if !compact {
                measurementColumnHeader
                Hairline()
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, m in
                let prevFull = index > 0 ? rows[index - 1].isFullCheckIn : false
                MeasurementTableRow(
                    measurement: m,
                    isLatest: index == 0,
                    compact: compact,
                    topDivider: index > 0 && !m.isFullCheckIn && !prevFull,
                    onEdit: { editingMeasurement = m }
                )
            }

            if measurements.count > rows.count {
                Hairline()
                seeMoreRow(remaining: measurements.count - rows.count)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 22)
        .dashboardCard()
    }

    private var measurementColumnHeader: some View {
        HStack(spacing: 18) {
            Text("Tarih").eyebrow().padding(.leading, 14).frame(width: 230, alignment: .leading)
            Text("Tür").eyebrow().frame(width: 130, alignment: .leading)
            Text("Ağırlık").eyebrow().frame(width: 150, alignment: .leading)
            Text("Tam ölçüm").eyebrow().frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 34, height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func seeMoreRow(remaining: Int) -> some View {
        Button {
            showAllMeasurements = true
        } label: {
            HStack(spacing: 10) {
                Text("Devamını gör")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Kalan \(remaining) kaydı ayrı pencerede aç")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Tüm ölçüm geçmişini ayrı pencerede aç")
    }

    // MARK: - Derived

    private var weightPoints: [TrendPoint] { TrendAnalysis.points(measurements, for: .weight) }
    private var bodyFatPoints: [TrendPoint] { TrendAnalysis.points(measurements, for: .bodyFat) }
    private var waistPoints: [TrendPoint] { TrendAnalysis.points(measurements, for: .waist) }

    private var fullMeasurements: [Measurement] { measurements.filter(\.isFullCheckIn) }

    private var measurementsThisMonth: Int {
        let cal = Calendar.current
        let now = Date()
        return measurements.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }.count
    }

    private func deltaTint(_ value: Double?, lowerIsBetter: Bool) -> Color {
        guard let value else { return Palette.textTertiary }
        let increased = value > 0
        let isGood = lowerIsBetter ? !increased : increased
        return isGood ? Palette.positive : Palette.negative
    }
}

/// "Devamını gör" ile açılan tüm ölçüm geçmişi penceresi (ayrı sheet).
/// Kendi @Query'siyle canlıdır (silme/düzenleme anında yansır) ve kendi editör sheet'ini barındırır.
struct MeasurementHistorySheet: View {
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Measurement? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kayıt Akışı").eyebrow()
                    Text("Tüm ölçüm geçmişi")
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text("\(measurements.count) kayıt")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textQuaternary)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Palette.surfaceElevated))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Kapat")
            }
            .padding(Spacing.xl)

            Hairline()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(measurements.enumerated()), id: \.element.id) { index, m in
                        let prevFull = index > 0 ? measurements[index - 1].isFullCheckIn : false
                        MeasurementTableRow(
                            measurement: m,
                            isLatest: index == 0,
                            compact: false,
                            topDivider: index > 0 && !m.isFullCheckIn && !prevFull,
                            onEdit: { editing = m }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 820, height: 720)
        .background(Palette.background)
        .sheet(item: $editing) { m in
            MeasurementEditor(mode: .edit(m)) { _ in
                ctx.saveOrReport()
            } onDelete: {
                ctx.delete(m)
                ctx.saveOrReport()
            }
        }
    }
}
