import SwiftUI

// MARK: - Grafikler · V1 "İzleme listesi"
//
// Tasarım: "Hercules Mac Tasarımı" tuvali ▸ Grafikler · V1 İzleme listesi (artboard 1829×1147;
// koordinatlar tasarım betiği mac_grafikler_v1.py ile birebir). Borsa uygulaması düzeni: solda
// seçili ölçümün büyük, tek çizgili grafiği (üstte değer + aralıktaki değişim; fareyle gezinince
// o günün değeri), sağda izleme listesi (ad · kıvılcım çizgi · değer · değişim hapı). Listeden
// satır seçmek grafiği değiştirir; aralık seçici (1A · 3A · 6A · Tümü) ikisini birlikte süzer.
// Kabuk ve yerleşim DashboardRings.swift'ten (RingsPanel, ringsPin).

// MARK: - Model

enum GraphSpan: String, CaseIterable, Identifiable {
    case month1 = "1A", month3 = "3A", month6 = "6A", all = "Tümü"

    var id: String { rawValue }

    /// Aralığın gün sayısı; nil → bütün kayıtlar.
    var days: Int? {
        switch self {
        case .month1: return 30
        case .month3: return 91
        case .month6: return 182
        case .all: return nil
        }
    }
}

/// İzleme listesindeki ölçüm: gövde ölçümleri (Measurement) ya da günlük toplamlar.
enum GraphMetric: Hashable, Identifiable {
    case body(MetricKind)
    case calories, protein, steps

    static let bodyMetrics: [GraphMetric] = [.body(.weight), .body(.bodyFat), .body(.leanMass),
                                             .body(.waist), .body(.chest), .body(.neck)]
    static let dailyMetrics: [GraphMetric] = [.calories, .protein, .steps]

    var id: String {
        switch self {
        case .body(let kind): return "body.\(kind.rawValue)"
        case .calories: return "calories"
        case .protein: return "protein"
        case .steps: return "steps"
        }
    }

    var name: String {
        switch self {
        case .body(let kind):
            switch kind {
            case .weight: return "Kilo"
            case .bodyFat: return "Yağ oranı"
            case .leanMass: return "Yağsız kütle"
            case .fatMass: return "Yağ kütlesi"
            case .waist: return "Bel"
            case .chest: return "Göğüs"
            case .neck: return "Boyun"
            }
        case .calories: return "Kalori"
        case .protein: return "Protein"
        case .steps: return "Adım"
        }
    }

    var isDaily: Bool {
        if case .body = self { return false }
        return true
    }

    var digits: Int { isDaily ? 0 : 1 }

    /// Değerin yanındaki birim; yağ oranında "%" değerin önüne yazıldığı için boş.
    var unit: String {
        switch self {
        case .body(let kind): return kind == .bodyFat ? "" : kind.unit
        case .calories: return "kalori"
        case .protein: return "g"
        case .steps: return "adım"
        }
    }

    /// Büyük başlıktaki birim — günlüklerde "/gün".
    var headerUnit: String { isDaily ? "\(unit)/gün" : unit }

    /// Değişimin birimi ("puan" yağ oranında).
    var changeUnit: String {
        if case .body(.bodyFat) = self { return "puan" }
        return unit
    }

    func format(_ value: Double) -> String {
        let text = digits == 0 ? Fmt.int(value) : Fmt.num(value, digits: digits)
        if case .body(.bodyFat) = self { return "%" + text }
        return text
    }

    /// İşaretli değer, tipografik eksiyle ("−3,9", "+158"); yuvarlanınca sıfırsa işaretsiz.
    func signed(_ value: Double, digits: Int? = nil) -> String {
        let d = digits ?? self.digits
        let text = d == 0 ? Fmt.int(abs(value)) : Fmt.num(abs(value), digits: d)
        let scale = pow(10, Double(d))
        guard (abs(value) * scale).rounded() > 0 else { return text }
        return (value < 0 ? "\u{2212}" : "+") + text
    }

    /// +1 artış iyi, −1 düşüş iyi, 0 nötr. Kilo hedefe göre: yalnız kütle almada artış iyi.
    func goodSign(weightLowerIsBetter: Bool) -> Int {
        switch self {
        case .body(let kind):
            switch kind {
            case .weight: return weightLowerIsBetter ? -1 : 1
            case .bodyFat, .fatMass, .waist: return -1
            case .leanMass: return 1
            case .chest, .neck: return 0
            }
        case .calories: return 0
        case .protein, .steps: return 1
        }
    }
}

/// Bir ölçümün seçili aralıktaki serisi.
struct GraphSeries {
    let metric: GraphMetric
    /// Okumalar (tarihe göre artan): gövde ölçümlerinde kayıtlar, günlüklerde 7 günlük ortalama.
    let readings: [TrendPoint]
    /// Çizilen eğri: kiloda 7 günlük ortalama, günlüklerde seyreltilmiş okumalar, diğerlerinde okumalar.
    let curve: [TrendPoint]
    /// Günlüklerde aralıktaki gün toplamları (istatistik için); gövde ölçümlerinde boş.
    let dayTotals: [TrendPoint]
    let goodSign: Int

    var current: Double { readings[readings.count - 1].value }
    var start: Double { readings[0].value }
    var change: Double { current - start }

    /// Değişim hedef yönündeyse yeşil, tersiyse kırmızı; nötr ölçüm ya da ~0 değişim gri.
    func tint(for change: Double) -> Color {
        let threshold = metric.digits == 0 ? 0.5 : 0.05
        guard goodSign != 0, abs(change) >= threshold else { return Palette.textTertiary }
        return (change > 0) == (goodSign > 0) ? Palette.positive : Palette.negative
    }

    func nearest(to date: Date) -> TrendPoint {
        readings.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            ?? readings[readings.count - 1]
    }

    /// Eğrinin `date` gününe denk gelen değeri (iki komşu arasında doğrusal).
    func curveValue(at date: Date) -> Double {
        guard let first = curve.first, let last = curve.last else { return 0 }
        if date <= first.date { return first.value }
        if date >= last.date { return last.value }
        guard let i = curve.firstIndex(where: { $0.date >= date }), i > 0 else { return last.value }
        let a = curve[i - 1], b = curve[i]
        let t = date.timeIntervalSince(a.date) / max(1, b.date.timeIntervalSince(a.date))
        return a.value + (b.value - a.value) * t
    }

    /// Okumaların kapsadığı süre: "12 günde", "4 ayda".
    var spanLabel: String {
        let days = Int((readings[readings.count - 1].date.timeIntervalSince(readings[0].date) / 86_400).rounded())
        return days < 45 ? "\(max(1, days)) günde" : "\(Int((Double(days) / 30.44).rounded())) ayda"
    }

    /// Grafiğin altındaki üç sayı.
    var stats: [(label: String, value: String, unit: String)] {
        if metric.isDaily {
            let values = dayTotals.map(\.value)
            let mean = values.isEmpty ? current : values.reduce(0, +) / Double(values.count)
            return [("ortalama", metric.format(mean), metric.unit),
                    ("en düşük", values.min().map(metric.format) ?? "—", metric.unit),
                    ("en yüksek", values.max().map(metric.format) ?? "—", metric.unit)]
        }
        let values = readings.map(\.value)
        let extreme = goodSign > 0
            ? ("en yüksek", values.max().map(metric.format) ?? "—")
            : ("en düşük", values.min().map(metric.format) ?? "—")
        let spanDays = readings[readings.count - 1].date.timeIntervalSince(readings[0].date) / 86_400
        let weekly = spanDays >= 7 ? TrendAnalysis.linearFit(readings).map { metric.signed($0.slope * 7, digits: 2) } : nil
        return [("başlangıç", metric.format(start), metric.unit),
                (extreme.0, extreme.1, metric.unit),
                ("haftalık", weekly ?? "—", weekly == nil ? "" : metric.changeUnit)]
    }
}

/// Sayfanın ham verisi, bir kez toplanır: gövde ölçüm serileri ve gün gün toplamlar.
struct GraphSources {
    let body: [MetricKind: [TrendPoint]]
    let calories: [TrendPoint]
    let protein: [TrendPoint]
    let steps: [TrendPoint]

    init(measurements: [Measurement], foods: [FoodEntry], steps stepEntries: [StepEntry],
         calendar: Calendar = .current) {
        var body: [MetricKind: [TrendPoint]] = [:]
        for case .body(let kind) in GraphMetric.bodyMetrics {
            body[kind] = TrendAnalysis.points(measurements, for: kind)
        }
        self.body = body
        var kcal: [Date: Double] = [:]
        var prot: [Date: Double] = [:]
        for food in foods {
            let day = calendar.startOfDay(for: food.date)
            kcal[day, default: 0] += food.calories
            prot[day, default: 0] += food.protein ?? 0
        }
        calories = kcal.keys.sorted().map { TrendPoint(date: $0, value: kcal[$0] ?? 0) }
        protein = prot.keys.sorted().map { TrendPoint(date: $0, value: prot[$0] ?? 0) }
        steps = StepEntry.preferredEntries(from: stepEntries, calendar: calendar)
            .map { TrendPoint(date: calendar.startOfDay(for: $0.date), value: Double($0.steps)) }
    }

    func series(_ metric: GraphMetric, span: GraphSpan, weightLowerIsBetter: Bool,
                calendar: Calendar = .current) -> GraphSeries? {
        let sign = metric.goodSign(weightLowerIsBetter: weightLowerIsBetter)
        func spanStart(_ last: Date) -> Date {
            guard let days = span.days else { return .distantPast }
            return calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: last)) ?? last
        }

        switch metric {
        case .body(let kind):
            let all = body[kind] ?? []
            guard let last = all.last else { return nil }
            let start = spanStart(last.date)
            let readings = all.filter { $0.date >= start }
            guard readings.count >= 2 else { return nil }
            guard kind == .weight else {
                return GraphSeries(metric: metric, readings: readings, curve: readings, dayTotals: [], goodSign: sign)
            }
            // Kilo: her tartının günündeki 7 günlük ortalama (aralık öncesi günler de sayılır),
            // ~26 noktaya seyreltilir — tek yumuşak çizgi.
            let average = TrendAnalysis.trailingAverage(all, windowDays: 7)
                .filter { $0.date >= start }
            let step = max(1, Int((Double(average.count) / 26).rounded()))
            return GraphSeries(metric: metric, readings: readings, curve: Self.thin(average, step: step),
                               dayTotals: [], goodSign: sign)

        case .calories, .protein, .steps:
            let totals = metric == .calories ? calories : (metric == .protein ? protein : steps)
            guard totals.count >= 2 else { return nil }
            // Kayıtlı günlerin 7 günlük ortalaması; ilk 6 gün (eksik pencere) atlanır.
            let rolling = TrendAnalysis.dailyAverage(totals, windowDays: 7, calendar: calendar)
            let usable = rolling.count > 8 ? Array(rolling.dropFirst(6)) : rolling
            guard let last = usable.last else { return nil }
            let start = spanStart(last.date)
            let readings = usable.filter { $0.date >= start }
            guard readings.count >= 2 else { return nil }
            return GraphSeries(metric: metric, readings: readings,
                               curve: Self.thin(readings, step: readings.count >= 60 ? 7 : 4),
                               dayTotals: totals.filter { $0.date >= start }, goodSign: sign)
        }
    }

    /// Her `step` noktadan biri; son nokta her zaman dahil.
    private static func thin(_ points: [TrendPoint], step: Int) -> [TrendPoint] {
        var out = stride(from: 0, to: points.count, by: max(1, step)).map { points[$0] }
        if out.last?.date != points.last?.date, let tail = points.last { out.append(tail) }
        return out
    }
}

// MARK: - Sol: büyük grafik

struct GraphChartPanel: View {
    let metric: GraphMetric
    let series: GraphSeries?
    @Binding var span: GraphSpan
    /// Önizleme/test kancası: grafiği bu günde imleç varmış gibi çizer.
    var scrubPreview: Date? = nil

    @State private var hoverDate: Date?

    var body: some View {
        RingsPanel(title: metric.name) { size in
            if let series {
                GraphChartDrawing(series: series, size: size, scrub: hoverDate ?? scrubPreview,
                                  onHover: { hoverDate = $0 })
            } else {
                Text("Bu aralıkta yeterli kayıt yok")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textTertiary)
                    .position(x: size.width / 2, y: size.height / 2)
            }
            spanPicker
                .ringsPin(size.width - 24, 16, .topTrailing)
        }
    }

    private var spanPicker: some View {
        HStack(spacing: 2) {
            ForEach(GraphSpan.allCases) { s in
                Button { withAnimation(.snappy(duration: 0.25)) { span = s } } label: {
                    Text(s.rawValue)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(s == span ? Palette.textPrimary : Palette.textTertiary)
                        .padding(.horizontal, 10)
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
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.textPrimary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.textPrimary.opacity(0.06), lineWidth: 1))
    }
}

/// Borsa dili: tek yumuşak çizgi, ızgara/eksen yok. Normal hâlde çizgi aralıktaki değişimin
/// renginde, ucunda parlayan nokta; imleçte solu renkli, sağı gri, noktalı dikey çizgi + nokta ve
/// üstte o günün değeri.
private struct GraphChartDrawing: View {
    let series: GraphSeries
    let size: CGSize
    let scrub: Date?
    let onHover: (Date?) -> Void

    private let gray = Palette.textPrimary.opacity(0.22)

    var body: some View {
        let metric = series.metric
        let cx0: CGFloat = 24
        let cx1 = size.width - 24
        let cy0: CGFloat = 196
        let cy1 = max(cy0 + 120, size.height - 160)
        let curve = series.curve
        let first = curve[0].date
        let total = max(1, curve[curve.count - 1].date.timeIntervalSince(first))
        let values = curve.map(\.value)
        let range = (values.max() ?? 1) - (values.min() ?? 0)
        let pad = range > 0 ? range * 0.12 : 1
        let lo = (values.min() ?? 0) - pad
        let hi = (values.max() ?? 1) + pad
        let x: (Date) -> CGFloat = { cx0 + (cx1 - cx0) * CGFloat($0.timeIntervalSince(first) / total) }
        let y: (Double) -> CGFloat = { cy1 - (cy1 - cy0) * CGFloat(($0 - lo) / (hi - lo)) }
        let pts = curve.map { CGPoint(x: x($0.date), y: y($0.value)) }
        let line = WatchlistPaths.smooth(pts)

        let shown = scrub.map { series.nearest(to: $0) }
        let reading = shown ?? series.readings[series.readings.count - 1]
        let change = reading.value - series.start
        let tint = series.tint(for: change)
        let sx = shown.map { x($0.date) } ?? size.width
        let sy = shown.map { y(series.curveValue(at: $0.date)) } ?? pts[pts.count - 1].y
        let text = metric.format(reading.value)
        let parts = text.split(separator: ",", maxSplits: 1).map(String.init)

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
                    left.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.12), tint.opacity(0)]),
                                                          startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: cy1)))
                    left.stroke(line, with: .color(tint), style: style)
                }
                if shown != nil {
                    ctx.drawLayer { right in
                        right.clip(to: Path(CGRect(x: sx, y: 0, width: max(0, canvas.width - sx), height: canvas.height)))
                        right.stroke(line, with: .color(gray), style: style)
                    }
                    var guide = Path()
                    guide.move(to: CGPoint(x: sx, y: cy0 - 20))
                    guide.addLine(to: CGPoint(x: sx, y: cy1 + 12))
                    ctx.stroke(guide, with: .color(Palette.textPrimary.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [1.5, 3.5]))
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - 6, y: sy - 6, width: 12, height: 12)), with: .color(tint))
                } else {
                    let end = pts[pts.count - 1]
                    ctx.drawLayer { glow in
                        glow.addFilter(.blur(radius: 5))
                        glow.fill(Path(ellipseIn: CGRect(x: end.x - 12.1, y: end.y - 12.1, width: 24.2, height: 24.2)),
                                  with: .color(tint.opacity(0.22)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: end.x - 5.5, y: end.y - 5.5, width: 11, height: 11)), with: .color(tint))
                }
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
                        onHover(first.addingTimeInterval(Double(t) * total))
                    case .ended:
                        onHover(nil)
                    }
                }

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Group {
                    Text(parts.first ?? "")
                        .foregroundStyle(Palette.textPrimary)
                    Text(parts.count > 1 ? ",\(parts[1])" : "")
                        .foregroundStyle(Palette.textTertiary)
                }
                .font(.system(size: 64, weight: .semibold).monospacedDigit())
                .tracking(-1.6)
                if !metric.headerUnit.isEmpty {
                    Text(metric.headerUnit)
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.leading, 8)
                }
            }
            .lineLimit(1)
            .ringsPin(24, 46)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(metric.signed(change)) \(metric.changeUnit)")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                Text(shown.map { Fmt.dateMonthAxis.string(from: $0.date) } ?? series.spanLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
            }
            .lineLimit(1)
            .ringsPin(26, 128)

            ForEach(Array(series.stats.enumerated()), id: \.offset) { index, stat in
                let sxPos = 24 + (size.width - 48) * CGFloat(index) / 3
                Text(stat.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                    .ringsPin(sxPos, size.height - 108)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(stat.value)
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    if !stat.unit.isEmpty {
                        Text(stat.unit)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .lineLimit(1)
                .ringsPin(sxPos, size.height - 88)
            }
        }
    }
}

// MARK: - Sağ: izleme listesi

struct GraphWatchlistPanel: View {
    let bodyRows: [(GraphMetric, GraphSeries?)]
    let dailyRows: [(GraphMetric, GraphSeries?)]
    let selected: GraphMetric
    let onSelect: (GraphMetric) -> Void

    static let rowHeight: CGFloat = 84

    var body: some View {
        RingsPanel(title: "Vücut") { size in
            let dailyTitle = 52 + CGFloat(bodyRows.count) * Self.rowHeight + 24
            ZStack(alignment: .topLeading) {
                rows(bodyRows, top: 52, width: size.width)
                RingsPanelTitle(title: "Günlük ortalama", sub: "7 gün")
                    .ringsPin(24, dailyTitle)
                rows(dailyRows, top: dailyTitle + 32, width: size.width)
            }
        }
    }

    private func rows(_ items: [(GraphMetric, GraphSeries?)], top: CGFloat, width: CGFloat) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            GraphWatchRow(metric: item.0, series: item.1, selected: item.0 == selected, width: width) {
                onSelect(item.0)
            }
            .position(x: width / 2, y: top + CGFloat(index) * Self.rowHeight + Self.rowHeight / 2)
        }
    }
}

/// Satır: ad · kıvılcım çizgi (aralık, değişim renginde) · değer · değişim hapı.
private struct GraphWatchRow: View {
    let metric: GraphMetric
    let series: GraphSeries?
    let selected: Bool
    let width: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let h = GraphWatchlistPanel.rowHeight
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.textPrimary.opacity(selected ? 0.055 : (hovering ? 0.028 : 0)))
                    .frame(width: max(0, width - 16), height: h - 8)
                    .position(x: width / 2, y: h / 2)
                Text(metric.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .ringsPin(24, 33)
                if let series {
                    let tint = series.tint(for: series.change)
                    sparkline(series, tint: tint)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.format(series.current))
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                        if !metric.unit.isEmpty {
                            Text(metric.unit)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .lineLimit(1)
                    .ringsPin(width - 24, 18, .topTrailing)
                    Text(metric.signed(series.change))
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.13)))
                        .ringsPin(width - 24, 44, .topTrailing)
                } else {
                    Text("—")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.textQuaternary)
                        .ringsPin(width - 24, 30, .topTrailing)
                }
            }
            .frame(width: width, height: h)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sparkline(_ series: GraphSeries, tint: Color) -> some View {
        // Tasarım ölçüsünde (440) 158…268; dar listede değer sütununa yer bırakıp sola kayar.
        let x1 = min(268, width - 140)
        let x0 = max(128, x1 - 110)
        let y0: CGFloat = 26, y1: CGFloat = 58
        let curve = series.curve
        let first = curve[0].date
        let total = max(1, curve[curve.count - 1].date.timeIntervalSince(first))
        let values = curve.map(\.value)
        let range = (values.max() ?? 1) - (values.min() ?? 0)
        let pad = range > 0 ? range * 0.08 : 1
        let lo = (values.min() ?? 0) - pad
        let hi = (values.max() ?? 1) + pad
        let pts = curve.map { p in
            CGPoint(x: x0 + (x1 - x0) * CGFloat(p.date.timeIntervalSince(first) / total),
                    y: y1 - (y1 - y0) * CGFloat((p.value - lo) / (hi - lo)))
        }
        let end = pts[pts.count - 1]
        return ZStack(alignment: .topLeading) {
            WatchlistPaths.smooth(pts)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .position(end)
        }
        .allowsHitTesting(false)
    }

    private var accessibilityText: String {
        guard let series else { return "\(metric.name), veri yok" }
        let unit = metric.unit.isEmpty ? "" : " \(metric.unit)"
        return "\(metric.name) \(metric.format(series.current))\(unit), değişim \(metric.signed(series.change))"
    }
}

enum WatchlistPaths {
    /// Catmull-Rom → kübik Bezier: noktalardan geçen yumuşak eğri.
    static func smooth(_ p: [CGPoint]) -> Path {
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
