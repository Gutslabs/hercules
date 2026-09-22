import SwiftUI
import LucideKit
import SwiftData

/// Ölçümler — tasarım: "Hercules Mac Tasarımı" tuvali ▸ Ölçümler · V1 Eğri (sade grafik).
/// Üç panel: Kilo (borsa uygulaması dilinde tek yumuşak çizgi; imleç solu hedef yönüne göre
/// renkli, sağı gri; üstte imlecin gününün kilosu), Vücut (son tam ölçümün 4 değeri + haftalık
/// kıvrım) ve Kayıtlar (son tartılar, günlük değişim çubukla). Ekleme/düzenleme sheet'leri ve
/// "Tümü" penceresi (`MeasurementHistorySheet`) aynı.
struct MeasurementsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]

    @State private var showingNew = false
    @State private var editingMeasurement: Measurement? = nil
    @State private var newMeasurementKind: MeasurementEditor.CreateKind = .smart
    @State private var showAllMeasurements = false

    /// Önizleme/test kancası: grafiği bu günde imleç varmış gibi çizer (nil → normal hâl).
    private let scrubPreview: Date?

    init(scrubPreview: Date? = nil) {
        self.scrubPreview = scrubPreview
    }

    /// Kilo verme ve korumada düşüş olumlu; yalnız kütle alma hedefinde artış.
    private var lowerIsBetter: Bool { (profiles.first?.goal.calorieAdjustment ?? 0) <= 0 }

    /// Alt satırın (Vücut | Kayıtlar) sabit boyu; kalan yükseklik Kilo grafiğine gider.
    private static let bottomHeight: CGFloat = 446

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content(size: proxy.size)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
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

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if measurements.isEmpty {
            // Boş durum üste yapışmasın: viewport'un dikey ortasında dursun.
            EmptyMeasurementState(
                quickAction: { newMeasurementKind = .quick; showingNew = true },
                fullAction: { newMeasurementKind = .full; showingNew = true }
            )
            .frame(maxWidth: .infinity, minHeight: max(0, size.height - 36))
        } else {
            let innerW = max(320, size.width - 48)
            let wide = size.width >= 960
            let chart = max(wide ? 420 : 380, size.height - 36 - 24 - Self.bottomHeight)
            let checkIns = measurements.filter(\.isFullCheckIn).reversed().map { $0 }
            VStack(spacing: 24) {
                WeightFlowPanel(measurements: measurements, lowerIsBetter: lowerIsBetter,
                                scrubPreview: scrubPreview)
                    .frame(height: chart)
                if wide {
                    // Tasarım oranı: 733 | 736 (1.493'lük iç genişlikte).
                    let bodyW = ((innerW - 24) * 733 / 1469).rounded()
                    HStack(spacing: 24) {
                        bodyPanel(checkIns).frame(width: bodyW)
                        recentPanel
                    }
                    .frame(height: Self.bottomHeight)
                } else {
                    bodyPanel(checkIns).frame(height: Self.bottomHeight)
                    recentPanel.frame(height: Self.bottomHeight)
                }
            }
            .frame(width: innerW)
        }
    }

    private func bodyPanel(_ checkIns: [Measurement]) -> some View {
        BodyCheckInPanel(
            checkIns: checkIns,
            doneThisWeek: MeasurementCadence.hasFullCheckInThisWeek(Array(measurements)),
            onNewFull: { newMeasurementKind = .full; showingNew = true }
        )
    }

    private var recentPanel: some View {
        RecentMeasurementsPanel(
            measurements: measurements,
            lowerIsBetter: lowerIsBetter,
            onEdit: { editingMeasurement = $0 },
            onAll: { showAllMeasurements = true },
            onAdd: { newMeasurementKind = .quick; showingNew = true }
        )
    }
}

// MARK: - Kilo (sade akış grafiği)

private struct WeightFlowPanel: View {
    let measurements: [Measurement]
    let lowerIsBetter: Bool
    var scrubPreview: Date? = nil

    enum Span: String, CaseIterable, Identifiable {
        case month1 = "1A", month3 = "3A", month6 = "6A"
        var id: String { rawValue }
        var days: Int { self == .month1 ? 30 : (self == .month3 ? 91 : 182) }
        var label: String { self == .month1 ? "1 ay" : (self == .month3 ? "3 ay" : "6 ay") }
    }

    @State private var span: Span = .month6

    var body: some View {
        let model = WeightFlowModel(points: TrendAnalysis.points(measurements, for: .weight), span: span)
        RingsPanel(title: "Kilo") { size in
            if let model {
                WeightFlowChart(model: model, size: size, lowerIsBetter: lowerIsBetter,
                                scrubPreview: scrubPreview, spanLabel: span.label)
            }
            spanPicker
                .ringsPin(size.width - 24, 18, .topTrailing)
        }
    }

    private var spanPicker: some View {
        HStack(spacing: 2) {
            ForEach(Span.allCases) { s in
                Button { withAnimation(.snappy(duration: 0.25)) { span = s } } label: {
                    Text(s.rawValue)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(s == span ? Palette.textPrimary : Palette.textTertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(s == span ? Palette.textPrimary.opacity(0.08) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.textPrimary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.textPrimary.opacity(0.06), lineWidth: 1))
    }
}

/// Seçili aralığın tartıları + 7 günlük ortalama + çizilecek seyreltilmiş nokta dizisi.
private struct WeightFlowModel {
    /// Aralıktaki ham tartılar (tarihe göre artan).
    let raw: [TrendPoint]
    /// Her ham tartının günündeki 7 günlük ortalama (aralık dışındaki önceki günler de sayılır).
    let average: [TrendPoint]
    /// Yumuşak eğri için seyreltilmiş ortalama (son nokta dahil, ~32 nokta).
    let curve: [TrendPoint]

    init?(points all: [TrendPoint], span: WeightFlowPanel.Span) {
        guard let last = all.last else { return nil }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -span.days, to: cal.startOfDay(for: last.date)) ?? last.date
        let raw = all.filter { $0.date >= start }
        guard raw.count >= 2 else { return nil }
        let average = TrendAnalysis.trailingAverage(all, windowDays: 7)
            .filter { $0.date >= start }
        let step = max(1, average.count / 32)
        var curve = stride(from: 0, to: average.count, by: step).map { average[$0] }
        if curve.last?.date != average.last?.date, let tail = average.last { curve.append(tail) }
        self.raw = raw
        self.average = average
        self.curve = curve
    }

    /// Ortalama eğrinin `date` gününe denk gelen değeri (iki komşu arasında doğrusal).
    func averageValue(at date: Date) -> Double {
        guard let first = average.first, let last = average.last else { return 0 }
        if date <= first.date { return first.value }
        if date >= last.date { return last.value }
        guard let i = average.firstIndex(where: { $0.date >= date }), i > 0 else { return last.value }
        let a = average[i - 1], b = average[i]
        let t = date.timeIntervalSince(a.date) / max(1, b.date.timeIntervalSince(a.date))
        return a.value + (b.value - a.value) * t
    }

    /// `date`e en yakın ham tartı.
    func nearestRaw(to date: Date) -> TrendPoint {
        raw.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } ?? raw[raw.count - 1]
    }
}

private struct WeightFlowChart: View {
    let model: WeightFlowModel
    let size: CGSize
    let lowerIsBetter: Bool
    /// İmlecin günü (fare üstünde ya da önizleme); nil → normal hâl.
    let scrubPreview: Date?
    let spanLabel: String
    @State private var hoverDate: Date?
    private var scrub: Date? { hoverDate ?? scrubPreview }

    private let gray = Palette.textPrimary.opacity(0.22)

    var body: some View {
        let cx0: CGFloat = 24
        let cx1 = size.width - 24
        let cy0: CGFloat = 150
        let cy1 = size.height - 36
        let first = model.raw[0].date
        let last = model.raw[model.raw.count - 1].date
        let total = max(1, last.timeIntervalSince(first))
        let values = model.curve.map(\.value)
        let pad = ((values.max() ?? 0) - (values.min() ?? 0)) * 0.12
        let lo = (values.min() ?? 0) - max(0.1, pad)
        let hi = (values.max() ?? 1) + max(0.1, pad)
        let x: (Date) -> CGFloat = { cx0 + (cx1 - cx0) * CGFloat($0.timeIntervalSince(first) / total) }
        let y: (Double) -> CGFloat = { cy1 - (cy1 - cy0) * CGFloat(($0 - lo) / (hi - lo)) }
        let pts = model.curve.map { CGPoint(x: x($0.date), y: y($0.value)) }
        let line = Self.smoothPath(pts)

        let shown = scrub.map { model.nearestRaw(to: $0) }
        let reading = shown ?? model.raw[model.raw.count - 1]
        let change = reading.value - model.raw[0].value
        let good = abs(change) < 0.05 ? nil : ((change < 0) == lowerIsBetter)
        let tint = good.map { $0 ? Palette.positive : Palette.negative } ?? Palette.textTertiary
        let sx = shown.map { x($0.date) } ?? size.width
        let sy = shown.map { y(model.averageValue(at: $0.date)) } ?? pts[pts.count - 1].y
        let parts = Fmt.num(reading.value, digits: 1).split(separator: ",", maxSplits: 1).map(String.init)

        return ZStack(alignment: .topLeading) {
            Canvas { ctx, canvas in
                var area = line
                area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: cy1))
                area.addLine(to: CGPoint(x: pts[0].x, y: cy1))
                area.closeSubpath()
                let top = line.boundingRect.minY
                let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                ctx.drawLayer { left in
                    left.clip(to: Path(CGRect(x: 0, y: 0, width: sx, height: canvas.height)))
                    left.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.10), tint.opacity(0)]),
                                                          startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: cy1)))
                    left.stroke(line, with: .color(tint), style: style)
                }
                ctx.drawLayer { right in
                    right.clip(to: Path(CGRect(x: sx, y: 0, width: max(0, canvas.width - sx), height: canvas.height)))
                    right.stroke(line, with: .color(gray), style: style)
                }
                if shown != nil {
                    var guide = Path()
                    guide.move(to: CGPoint(x: sx, y: cy0 - 20))
                    guide.addLine(to: CGPoint(x: sx, y: cy1 + 12))
                    ctx.stroke(guide, with: .color(Palette.textPrimary.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [1.5, 3.5]))
                }
                let dotX = shown != nil ? sx : pts[pts.count - 1].x
                ctx.fill(Path(ellipseIn: CGRect(x: dotX - 6, y: sy - 6, width: 12, height: 12)), with: .color(tint))
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .frame(width: size.width, height: max(0, cy1 - cy0 + 60))
                .position(x: size.width / 2, y: (cy0 + cy1) / 2)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        let t = min(1, max(0, (p.x - cx0) / max(1, cx1 - cx0)))
                        hoverDate = first.addingTimeInterval(Double(t) * total)
                    case .ended:
                        hoverDate = nil
                    }
                }

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(parts.first ?? "")
                    .foregroundStyle(Palette.textPrimary)
                Text(parts.count > 1 ? ",\(parts[1])" : "")
                    .foregroundStyle(Palette.textTertiary)
                Text("kg")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.leading, 8)
            }
            .font(.system(size: 56, weight: .semibold).monospacedDigit())
            .tracking(-1.4)
            .lineLimit(1)
            .ringsPin(24, 46)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(change < 0 ? "−" : (change > 0 ? "+" : ""))\(Fmt.num(abs(change), digits: 1)) kg")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                Text(shown.map { Fmt.dateMonthAxis.string(from: $0.date) } ?? spanLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
            }
            .lineLimit(1)
            .ringsPin(26, 116)
        }
    }

    /// Catmull-Rom → kübik Bezier: noktalardan geçen yumuşak eğri.
    static func smoothPath(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard let first = p.first else { return path }
        path.move(to: first)
        guard p.count > 1 else { return path }
        for i in 0..<(p.count - 1) {
            let p0 = i > 0 ? p[i - 1] : p[i]
            let p1 = p[i], p2 = p[i + 1]
            let p3 = i + 2 < p.count ? p[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

// MARK: - Vücut (son tam ölçüm)

private struct BodyCheckInPanel: View {
    /// Tam ölçümler, tarihe göre artan.
    let checkIns: [Measurement]
    let doneThisWeek: Bool
    let onNewFull: () -> Void

    private struct Metric {
        let name: String
        let unit: String
        let value: KeyPath<Measurement, Double?>
        /// nil → yön nötr (göğüs/boyun): değişim gri.
        let lowerIsBetter: Bool?
    }

    private let metrics: [Metric] = [
        Metric(name: "Yağ", unit: "%", value: \.bodyFat, lowerIsBetter: true),
        Metric(name: "Bel", unit: "cm", value: \.waist, lowerIsBetter: true),
        Metric(name: "Göğüs", unit: "cm", value: \.chest, lowerIsBetter: nil),
        Metric(name: "Boyun", unit: "cm", value: \.neck, lowerIsBetter: nil),
    ]

    var body: some View {
        RingsPanel(title: "Vücut", sub: checkIns.last.map { "tam ölçüm · \(Fmt.dateMonthAxis.string(from: $0.date))" }) { size in
            ZStack(alignment: .topLeading) {
                if checkIns.isEmpty {
                    VStack(spacing: 6) {
                        Text("Henüz tam ölçüm yok")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("Yağ oranı ve çevre ölçüleri haftada bir.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .frame(width: size.width, height: size.height)
                } else {
                    grid(size)
                }
                fullButton
                    .ringsPin(size.width - 18, 12, .topTrailing)
            }
        }
    }

    private var fullButton: some View {
        let next = MeasurementCadence.nextFullCheckIn()
        let badge = Calendar.current.isDateInToday(next) ? "bugün" : Fmt.weekdayShort(next)
        return Button(action: onNewFull) {
            HStack(spacing: 6) {
                Lucide(sf: "ruler", size: 13)
                Text("Tam ölçüm")
                    .font(.system(size: 13, weight: .medium))
                Text(badge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(doneThisWeek ? Palette.textTertiary : Palette.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill((doneThisWeek ? Palette.textTertiary : Palette.warning).opacity(0.14)))
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .flatButtonChrome(cornerRadius: 9)
        }
        .buttonStyle(.plain)
        .help(doneThisWeek ? "Bu haftanın tam ölçümü tamam · sıradaki \(Fmt.dateMonthAxis.string(from: next))"
                           : "Yağ + çevre ölçümlü tam kayıt · sıradaki \(Fmt.dateMonthAxis.string(from: next))")
    }

    private func grid(_ size: CGSize) -> some View {
        let cellW = (size.width - 48 - 25) / 2
        let rowH = max(120, (size.height - 64 - 20 - 22) / 2)
        let origins = [CGPoint(x: 24, y: 64), CGPoint(x: 24 + cellW + 25, y: 64),
                       CGPoint(x: 24, y: 64 + rowH + 22), CGPoint(x: 24 + cellW + 25, y: 64 + rowH + 22)]
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Palette.textPrimary.opacity(0.06))
                .frame(width: 1, height: max(0, size.height - 84))
                .position(x: 24 + cellW + 12.5, y: 64 + (size.height - 84) / 2)
            Rectangle()
                .fill(Palette.textPrimary.opacity(0.06))
                .frame(width: max(0, size.width - 48), height: 1)
                .position(x: size.width / 2, y: 64 + rowH + 11)
            ForEach(Array(metrics.enumerated()), id: \.offset) { i, metric in
                cell(metric, origin: origins[i], width: cellW)
            }
        }
    }

    @ViewBuilder
    private func cell(_ metric: Metric, origin o: CGPoint, width: CGFloat) -> some View {
        let series = checkIns.compactMap { m in m[keyPath: metric.value].map { (m.date, $0) } }
        Text(metric.name)
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.textSecondary)
            .ringsPin(o.x, o.y)
        if let latest = series.last {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.num(latest.1, digits: 1))
                    .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    .tracking(-0.8)
                    .foregroundStyle(Palette.textPrimary)
                Text(metric.unit)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
            }
            .ringsPin(o.x, o.y + 22)
            if series.count >= 2 {
                let delta = latest.1 - series[series.count - 2].1
                deltaLabel(delta, lowerIsBetter: metric.lowerIsBetter)
                    .ringsPin(o.x, o.y + 84)
                MeasureSparkline(values: series.suffix(20).map(\.1))
                    .frame(width: max(40, width - 184), height: 70)
                    .ringsPin(o.x + 176, o.y + 34)
            }
        } else {
            Text("—")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Palette.textQuaternary)
                .ringsPin(o.x, o.y + 22)
        }
    }

    @ViewBuilder
    private func deltaLabel(_ delta: Double, lowerIsBetter: Bool?) -> some View {
        if abs(delta) < 0.05 {
            Text("aynı")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
        } else {
            let good = lowerIsBetter.map { (delta < 0) == $0 }
            let color = good.map { $0 ? Palette.positive : Palette.negative } ?? Palette.textTertiary
            HStack(spacing: 2) {
                Lucide(delta < 0 ? "trending-down" : "trending-up", size: 13)
                Text(Fmt.num(abs(delta), digits: 1))
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
        }
    }
}

/// Haftalık tam ölçümlerin kıvrımı: düz parçalı çizgi + son nokta.
private struct MeasureSparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return }
            let span = max(0.2, hi - lo)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: size.height - size.height * CGFloat((v - lo) / span))
            }
            var path = Path()
            path.addLines(pts)
            ctx.stroke(path, with: .color(Palette.chart.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            if let last = pts.last {
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)),
                         with: .color(Palette.chart))
            }
        }
    }
}

// MARK: - Kayıtlar (son tartılar)

private struct RecentMeasurementsPanel: View {
    /// Tüm ölçümler, tarihe göre azalan.
    let measurements: [Measurement]
    let lowerIsBetter: Bool
    let onEdit: (Measurement) -> Void
    let onAll: () -> Void
    let onAdd: () -> Void

    private let rowHeight: CGFloat = 44

    var body: some View {
        RingsPanel(title: "Kayıtlar", sub: "\(measurements.count)") { size in
            ZStack(alignment: .topLeading) {
                let count = max(1, Int((size.height - 78) / rowHeight))
                VStack(spacing: 0) {
                    ForEach(Array(measurements.prefix(count).enumerated()), id: \.element.id) { i, m in
                        RecentMeasurementRow(
                            measurement: m,
                            previousWeight: measurements.dropFirst(i + 1).first(where: { $0.weight != nil })?.weight,
                            lowerIsBetter: lowerIsBetter,
                            width: size.width,
                            showsDivider: i > 0,
                            onEdit: { onEdit(m) }
                        )
                        .frame(height: rowHeight)
                    }
                }
                .frame(width: size.width, alignment: .topLeading)
                .offset(y: 64)
                HStack(spacing: 8) {
                    Button(action: onAll) {
                        HStack(spacing: 6) {
                            Lucide(sf: "arrow.up.right", size: 13)
                            Text("Tümü")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .flatButtonChrome(cornerRadius: 9)
                    }
                    .buttonStyle(.plain)
                    .help("Tüm ölçüm geçmişini ayrı pencerede aç")
                    Button(action: onAdd) {
                        HStack(spacing: 6) {
                            Lucide(sf: "plus", size: 13)
                            Text("Tartı ekle")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Palette.btnFg)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.btnBg))
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Hızlı tartı kaydı")
                }
                .ringsPin(size.width - 18, 12, .topTrailing)
            }
        }
    }
}

private struct RecentMeasurementRow: View {
    let measurement: Measurement
    let previousWeight: Double?
    let lowerIsBetter: Bool
    let width: CGFloat
    let showsDivider: Bool
    let onEdit: () -> Void

    @State private var hovering = false

    var body: some View {
        let m = measurement
        let delta = m.weight.flatMap { w in previousWeight.map { w - $0 } }
        let barX = (width * 0.639).rounded()
        Button(action: onEdit) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.textPrimary.opacity(hovering ? 0.035 : 0))
                    .frame(width: width - 32, height: 40)
                    .position(x: width / 2, y: 22)
                if showsDivider {
                    Rectangle()
                        .fill(Palette.textPrimary.opacity(0.05))
                        .frame(width: width - 48, height: 1)
                        .position(x: width / 2, y: 0)
                }
                Text(Fmt.dateMonthAxis.string(from: m.date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .ringsPin(24, 14)
                Text(Fmt.weekdayShort(m.date))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                    .ringsPin(84, 15)
                if m.isFullCheckIn {
                    Text("tam")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.warning.opacity(0.14)))
                        .ringsPin(122, 13)
                }
                Rectangle()
                    .fill(Palette.textPrimary.opacity(0.12))
                    .frame(width: 1, height: 20)
                    .position(x: barX, y: 22)
                if let delta, abs(delta) >= 0.02 {
                    let w = min(60, CGFloat(abs(delta) / 0.5) * 60)
                    let good = (delta < 0) == lowerIsBetter
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill((good ? Palette.positive : Palette.negative).opacity(0.75))
                        .frame(width: w, height: 10)
                        .position(x: delta < 0 ? barX - w / 2 : barX + w / 2, y: 22)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(m.weight.map { Fmt.num($0, digits: 1) } ?? "—")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text("kg")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
                .ringsPin(width - 24, 11, .topTrailing)
            }
            .frame(width: width, height: 44, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(delta.map { "Önceki tartıya göre \($0 < 0 ? "−" : "+")\(Fmt.num(abs($0), digits: 1)) kg · düzenle" } ?? "Düzenle")
    }
}

/// Tüm ölçümler penceresi — tasarım: tuval ▸ Pencereler · Veriler (az yazı). Üstte bütün kilo
/// geçmişinin Grafikler dilindeki eğrisi (7 günlük ortalama; üzerine gelince o gün), altında aylara
/// bölünmüş liste. Kendi @Query'siyle canlıdır; satıra tıklayınca düzenleyici açılır.
struct MeasurementHistorySheet: View {
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Measurement? = nil
    @State private var hover: TrendPoint?

    private var lowerIsBetter: Bool { (profiles.first?.goal.calorieAdjustment ?? 0) <= 0 }

    var body: some View {
        let points = TrendAnalysis.trailingAverage(
            measurements.reversed().compactMap { m in m.weight.map { TrendPoint(date: m.date, value: $0) } },
            windowDays: 7)
        let tint = SadeLineChart.tint(change: (points.last?.value ?? 0) - (points.first?.value ?? 0), lowerIsBetter: lowerIsBetter)
        return SadeSheet(title: "Tüm ölçümler", subtitle: "\(measurements.count) kayıt", onClose: { dismiss() }) {
            VStack(spacing: 0) {
                SadeLineChart(points: points, tint: tint) { hover = $0 }
                    .frame(height: 130)
                    .overlay(alignment: .topLeading) {
                        if let hover {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(SadeFormat.num(hover.value)) kg")
                                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Palette.textPrimary)
                                Text(Fmt.dateMonthAxis.string(from: hover.date))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            .offset(x: 8, y: -6)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 18)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(months, id: \.key) { month in
                            monthHeader(month)
                            ForEach(month.rows, id: \.measurement.id) { row in
                                MeasurementHistoryRow(measurement: row.measurement, delta: row.delta,
                                                      isLatest: row.measurement === measurements.first) {
                                    editing = row.measurement
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 18)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        } footerLeading: {
            EmptyView()
        } footerTrailing: {
            EmptyView()
        }
        .frame(width: 880, height: 780)
        .sheet(item: $editing) { m in
            MeasurementEditor(mode: .edit(m)) { _ in
                ctx.saveOrReport()
            } onDelete: {
                ctx.delete(m)
                ctx.saveOrReport()
            }
        }
    }

    // MARK: Aylar

    private struct Month {
        let key: String
        let title: String
        let change: Double?
        let rows: [(measurement: Measurement, delta: Double?)]
    }

    /// Yeniden eskiye aylar; her satırın bir önceki tartıya göre farkı.
    private var months: [Month] {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: .now)
        var out: [Month] = []
        var bucket: [(measurement: Measurement, delta: Double?)] = []
        var bucketKey = ""
        var bucketDate = Date()
        func flush() {
            guard !bucket.isEmpty else { return }
            let weights = bucket.compactMap(\.measurement.weight)
            let change = weights.count >= 2 ? (weights.first ?? 0) - (weights.last ?? 0) : nil
            let year = cal.component(.year, from: bucketDate)
            let name = Self.monthName.string(from: bucketDate)
            out.append(Month(key: bucketKey, title: year == thisYear ? name : "\(name) \(year)", change: change, rows: bucket))
            bucket = []
        }
        for (index, m) in measurements.enumerated() {
            let comps = cal.dateComponents([.year, .month], from: m.date)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if key != bucketKey { flush(); bucketKey = key; bucketDate = m.date }
            let previous = measurements[(index + 1)...].first(where: { $0.weight != nil })?.weight
            bucket.append((m, m.weight.flatMap { w in previous.map { w - $0 } }))
        }
        flush()
        return out
    }

    private func monthHeader(_ month: Month) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(month.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 8)
            if let change = month.change {
                Text("\(SadeFormat.signed(change)) kg")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(SadeLineChart.tint(change: change, lowerIsBetter: lowerIsBetter))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "LLLL"
        return f
    }()
}

/// Tüm ölçümler satırı: gün · kilo · fark · (tam ölçümde) yağ ve çevreler; üzerine gelince kalem.
private struct MeasurementHistoryRow: View {
    let measurement: Measurement
    let delta: Double?
    let isLatest: Bool
    let onEdit: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isLatest ? Palette.positive : Color.clear)
                        .frame(width: 6, height: 6)
                    Text(Self.day.string(from: measurement.date))
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textPrimary)
                }
                .frame(width: 130, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(measurement.weight.map { SadeFormat.num($0) } ?? "—")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text("kg")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(width: 90, alignment: .trailing)
                Text(delta.map { SadeFormat.signed($0) } ?? "")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 56, alignment: .trailing)
                Text(metrics)
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Lucide(sf: "pencil", size: 13)
                    .foregroundStyle(Palette.textSecondary)
                    .opacity(hovering ? 1 : 0)
                    .frame(width: 30)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.textPrimary.opacity(hovering ? 0.045 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Düzenle")
    }

    /// "Yağ 19,8 % · Bel 92 · Göğüs 130 · Boyun 39" — yalnız dolu olanlar.
    private var metrics: String {
        var parts: [String] = []
        if let v = measurement.bodyFat { parts.append("Yağ \(SadeFormat.num(v)) %") }
        if let v = measurement.waist { parts.append("Bel \(SadeFormat.kg(v))") }
        if let v = measurement.chest { parts.append("Göğüs \(SadeFormat.kg(v))") }
        if let v = measurement.neck { parts.append("Boyun \(SadeFormat.kg(v))") }
        return parts.joined(separator: " · ")
    }

    /// "22 Eyl Sal"
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM EEE"
        return f
    }()
}
