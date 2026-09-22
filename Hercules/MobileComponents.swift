import SwiftUI
import LucideKit
import SwiftData
import UniformTypeIdentifiers

/// Mobil sekme şeridi. Antrenman ("Spor") sekmesi V1'de kaldırıldı — antrenman artık
/// Bugün içinde. Akış da menüden çıktı (Bugün başlığındaki gelen-kutusu butonundan açılır).
/// Yemek de menüden çıktı — Bugün'deki Yemekler bölümü ekleme (+) ve kaydırarak-silmeyle
/// tüm işlevi görüyor.
/// Dock sırası = bu bildirim sırası. Koç ortada duruyor: dock'ta ikon değil orb, ve
/// mockup'taki gibi merkezde olması gerekiyor.
enum MobileTab: Hashable, CaseIterable {
    case dashboard
    case recipes
    case ai
    case measurements
    case profile

    var title: String {
        switch self {
        case .dashboard: return "Hercules"
        case .ai: return "Koç"
        case .recipes: return "Tarifler"
        case .measurements: return "Ölçümler"
        case .profile: return "Profil"
        }
    }

    var shortTitle: String {
        switch self {
        case .dashboard: return "Bugün"
        case .ai: return "Koç"
        case .recipes: return "Tarif"
        case .measurements: return "Ölçüm"
        case .profile: return "Profil"
        }
    }

    var eyebrow: String {
        switch self {
        case .dashboard: return "Mobil"
        case .ai: return "AI"
        case .recipes: return "Mutfak"
        case .measurements: return "Takip"
        case .profile: return "Hesap"
        }
    }

    /// Dock ikonu — ince çizgi (outline) varyantları. V1 dock'u metinsiz: yalnızca ikon + nokta.
    var dockIcon: String {
        switch self {
        case .dashboard: return "house"
        case .ai: return "sparkles"
        case .recipes: return "book.closed"
        case .measurements: return "chart.line.uptrend.xyaxis"
        case .profile: return "person"
        }
    }
}

struct MobilePresetItem: Identifiable {
    let id: String
    let preset: FoodPreset
}

/// Dock'taki Koç orb'u — mockup'taki renkli küre, ama Hercules'in KENDİ sessiz
/// hue'larıyla (adaçayı · pirinç · grafik · mürekkep). Rainbow değil; palet nötr kalıyor.
/// Statik: dock hep ekranda olduğu için sürekli dönen animasyon yok.
struct MobileDockOrb: View {
    let active: Bool

    private var blobs: [(color: Color, x: CGFloat, y: CGFloat)] {
        [
            (Palette.macroCarbs, -5, -4),
            (Palette.macroFat,    5, -5),
            (Palette.chart,      -4,  5),
            (Palette.accent,      5,  5)
        ]
    }

    var body: some View {
        ZStack {
            Circle().fill(Palette.surfaceElevated)

            ZStack {
                ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                    Circle()
                        .fill(blob.color.opacity(active ? 0.85 : 0.42))
                        .frame(width: 17, height: 17)
                        .offset(x: blob.x, y: blob.y)
                }
            }
            .blur(radius: 5)

            // Cam hissi: sol-üstte tek parlama.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.5), .clear],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 0,
                        endRadius: 13
                    )
                )
        }
        .frame(width: 26, height: 26)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Palette.cardRim, lineWidth: 0.5))
        .scaleEffect(active ? 1.09 : 1)
        .shadow(color: Palette.cardShadowTight, radius: active ? 5 : 0, y: 1)
    }
}

/// Mobil kart: mockup dili — kenarlık neredeyse yok, köşe daha yumuşak, içeride
/// daha çok nefes. Yüzey/zemin kontrastı kartı zaten ayırıyor; çizgiyle çerçevelemiyoruz.
struct MobileCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MobileChrome.cardRadius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MobileChrome.cardRadius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
    }
}

/// Mobil kromun tek kaynağı — kart yarıçapı ve sayfa nefesi tek yerden ayarlanır.
enum MobileChrome {
    static let cardRadius: CGFloat = 20
    static let pageInset: CGFloat = 18
    static let pageSpacing: CGFloat = 18
    /// Dock kartsız ve gradyanla siliniyor; içerik onun altında bitmeli.
    static let dockClearance: CGFloat = 108
    /// Chat composer'ı dock'un hemen üstüne oturtur (sayfa kaydırma payı değil).
    static let composerClearance: CGFloat = 64
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Ölçüm trend karuselinin tek serisi (masaüstü Trend Lab'in mobil karşılığı).
/// İstatistikler içeride hesaplanır — yalnız MetricKind + Foundation'a bağımlı
/// (TrendAnalysis iOS target'ında değil). Değerler/tarihler eskiden yeniye.
struct MeasurementSeries: Identifiable {
    let kind: MetricKind
    let values: [Double]
    let dates: [Date]
    var id: String { kind.rawValue }

    var current: Double? { values.last }
    /// Son iki değerin farkı (izleme listesindeki çip).
    var delta: Double? {
        guard values.count >= 2 else { return nil }
        return values[values.count - 1] - values[values.count - 2]
    }
}

/// Ölçüm grafiğinin bir noktası.
struct MeasurementPoint {
    let date: Date
    let value: Double
}

/// Ölçümler V2 dönem seçici.
enum MeasurementSpan: String, CaseIterable, Identifiable {
    case month = "1A", quarter = "3A", half = "6A", year = "1Y", all = "Tümü"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .month: return 30
        case .quarter: return 91
        case .half: return 182
        case .year: return 365
        case .all: return nil
        }
    }
}

/// Ölçümler V2 üst panel (tuval "Ölçümler · V2 İzleme"): seri adı, büyük değer (ondalık
/// soluk), değişim + hedefe kalan, borsa çizgisi, dönem seçici + tam ölçüm günü. Grafikte
/// yatay kaydırınca değer ve tarih o noktayı gösterir. Dönem ve gezinme burada tutulur ki
/// her parmak hareketinde kök gövde yeniden hesaplanmasın.
struct MeasurementTrendPanel: View {
    let series: MeasurementSeries
    /// true = düşük iyi, false = yüksek iyi, nil = nötr.
    let lowerIsBetter: Bool?
    /// Yalnız kilo: hedefe kalan (kg).
    let goalDistance: Double?
    let cadenceToday: Bool

    @State private var span: MeasurementSpan = .quarter
    @State private var scrub: Int?

    private static let inset: CGFloat = 28

    var body: some View {
        // Kilo günlük tartıyla gürültülü: grafik ve değişim 7 günlük ortalamadan.
        let smoothed = series.kind == .weight
            ? Self.weeklyAverage(series.dates, series.values)
            : zip(series.dates, series.values).map { MeasurementPoint(date: $0, value: $1) }
        let points = Self.window(smoothed, span: span)
        let spanTrend = points.count >= 2
            ? Self.trend(points[points.count - 1].value - points[0].value, lowerIsBetter: lowerIsBetter)
            : nil
        let shown = scrub.flatMap { points.indices.contains($0) ? points[$0] : nil }
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.sentenceCase(series.kind.label))
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Self.inset)
            valueRow(shown?.value ?? series.current ?? 0)
                .padding(.horizontal, Self.inset)
                .padding(.top, 2)
            changeRow(change: headerChange(smoothed), scrubbed: shown)
                .padding(.horizontal, Self.inset)
                .padding(.top, 2)
            MeasurementStockChart(points: points, tint: Self.color(spanTrend), scrub: $scrub)
                .frame(height: 150)
                .padding(.top, 10)
            spanRow
                .padding(.top, 10)
        }
        .onChange(of: series.id) { _, _ in scrub = nil }
        .onChange(of: span) { _, _ in scrub = nil }
    }

    private func valueRow(_ value: Double) -> some View {
        let parts = Fmt.num(value, digits: 1).split(separator: ",", maxSplits: 1).map(String.init)
        let whole = Text(parts.first ?? "")
        let decimals = Text(parts.count > 1 ? "," + parts[1] : "").foregroundStyle(Palette.textTertiary)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            (whole + decimals)
                .font(.system(size: 60, weight: .light))
                .tracking(-2)
                .foregroundStyle(Palette.textPrimary)
                // Tuvalde satır yüksekliği 64; SF'nin doğal satırı ~8 pt uzun (simülatörde ölçüldü).
                .padding(.top, -1)
                .padding(.bottom, -4.7)
            Text(series.kind.unit)
                .font(.system(size: 17))
                .foregroundStyle(Palette.textTertiary)
        }
        .monospacedDigit()
    }

    private func changeRow(change: (value: Double, label: String)?, scrubbed: MeasurementPoint?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let scrubbed {
                Text(Fmt.dayMonth.string(from: scrubbed.date))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            } else if let change {
                Text("\(Self.signedText(change.value)) \(series.kind.unit)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Self.color(Self.trend(change.value, lowerIsBetter: lowerIsBetter)))
                Text(change.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 8)
            if let goalDistance {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("hedefe")
                        .foregroundStyle(Palette.textTertiary)
                    Text("\(Fmt.num(goalDistance, digits: 1)) kg")
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.textSecondary)
                }
                .font(.system(size: 13))
            }
        }
        .monospacedDigit()
    }

    /// Kilo: 7 günlük ortalamanın son 7 gündeki değişimi. Diğerleri: önceki ölçüme göre.
    private func headerChange(_ smoothed: [MeasurementPoint]) -> (value: Double, label: String)? {
        guard let last = smoothed.last else { return nil }
        if series.kind == .weight {
            let cutoff = last.date.addingTimeInterval(-7 * 86_400)
            guard let reference = smoothed.last(where: { $0.date <= cutoff }) else { return nil }
            return (last.value - reference.value, "son 7 gün")
        }
        guard let delta = series.delta else { return nil }
        return (delta, "önceki ölçüme göre")
    }

    private var spanRow: some View {
        HStack(spacing: 2) {
            ForEach(MeasurementSpan.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { span = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(span == item ? Palette.textPrimary : Palette.textTertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(span == item ? Palette.textPrimary.opacity(0.10) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            // Cumartesi tam ölçüm günü (yağ %, bel, göğüs, boyun da girilir).
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.positive)
                    .frame(width: 6, height: 6)
                Text(cadenceToday ? "Bugün tam ölçüm" : "Cmt tam ölçüm")
                    .font(.system(size: 12.5))
                    .foregroundStyle(cadenceToday ? Palette.textSecondary : Palette.textTertiary)
            }
        }
        .padding(.leading, Self.inset - 11)
        .padding(.trailing, Self.inset)
    }

    // ── ortak kurallar ──

    /// true = iyi yön, false = kötü yön, nil = nötr (≈0 ya da yönsüz seri).
    static func trend(_ change: Double, lowerIsBetter: Bool?) -> Bool? {
        guard let lowerIsBetter, abs(change) >= 0.05 else { return nil }
        return lowerIsBetter ? change < 0 : change > 0
    }

    static func color(_ trend: Bool?) -> Color {
        guard let trend else { return Palette.textSecondary }
        return trend ? Palette.positive : Palette.negative
    }

    /// "−0,3" / "+0,2" / "0,0" — tipografik eksi.
    static func signedText(_ value: Double) -> String {
        guard abs(value) >= 0.05 else { return Fmt.num(0, digits: 1) }
        return (value < 0 ? "−" : "+") + Fmt.num(abs(value), digits: 1)
    }

    /// "Vücut Ağırlığı" → "Vücut ağırlığı".
    static func sentenceCase(_ text: String) -> String {
        let tr = Locale(identifier: "tr_TR")
        let lower = text.lowercased(with: tr)
        return lower.prefix(1).uppercased(with: tr) + lower.dropFirst()
    }

    /// Her ölçüm için son 7 günün ortalaması (kayan pencere, tek geçiş).
    static func weeklyAverage(_ dates: [Date], _ values: [Double]) -> [MeasurementPoint] {
        var out: [MeasurementPoint] = []
        out.reserveCapacity(values.count)
        var start = 0
        var sum = 0.0
        for i in values.indices {
            sum += values[i]
            let cutoff = dates[i].addingTimeInterval(-7 * 86_400)
            while start < i, dates[start] <= cutoff {
                sum -= values[start]
                start += 1
            }
            out.append(MeasurementPoint(date: dates[i], value: sum / Double(i - start + 1)))
        }
        return out
    }

    /// Son noktadan geriye dönem kadar; en az iki nokta.
    static func window(_ points: [MeasurementPoint], span: MeasurementSpan) -> [MeasurementPoint] {
        guard let days = span.days, let last = points.last else { return points }
        let cutoff = last.date.addingTimeInterval(-Double(days) * 86_400)
        let inside = points.filter { $0.date >= cutoff }
        return inside.count >= 2 ? inside : Array(points.suffix(2))
    }
}

/// Borsa çizgisi (Grafikler dili): tek yumuşak çizgi 3 pt, altında renk %12 → 0 geçiş,
/// ızgara/eksen yok, uçta parlayan nokta. Yatay kaydırınca gezer: kesikli dikey çizgi +
/// nokta, çizginin sağı griye döner (dikey kaydırma sayfayı kaydırır).
struct MeasurementStockChart: View {
    let points: [MeasurementPoint]
    let tint: Color
    @Binding var scrub: Int?
    var inset: CGFloat = 14
    var top: CGFloat = 16
    var bottom: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let xy = positions(in: geo.size)
            let line = Self.smooth(xy)
            let stroke = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            ZStack(alignment: .topLeading) {
                if xy.count >= 2 {
                    Self.area(line, xy: xy, bottom: geo.size.height - bottom)
                        .fill(LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    line.stroke(scrub == nil ? tint : Palette.textQuaternary, style: stroke)
                    if let i = scrub, xy.indices.contains(i) {
                        line.stroke(tint, style: stroke)
                            .mask(alignment: .leading) { Rectangle().frame(width: xy[i].x) }
                    }
                }
                if let i = scrub, xy.indices.contains(i) {
                    Path { p in
                        p.move(to: CGPoint(x: xy[i].x, y: 0))
                        p.addLine(to: CGPoint(x: xy[i].x, y: geo.size.height))
                    }
                    .stroke(Palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    Circle()
                        .fill(tint)
                        .frame(width: 11, height: 11)
                        .position(xy[i])
                } else if let end = xy.last {
                    Circle()
                        .fill(tint.opacity(0.22))
                        .frame(width: 24, height: 24)
                        .blur(radius: 5)
                        .position(end)
                    Circle()
                        .fill(tint)
                        .frame(width: 11, height: 11)
                        .position(end)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        // Dikey hareket sayfayı kaydırsın; yalnız yatay başlayan sürükleme gezer.
                        if scrub == nil, abs(value.translation.width) <= abs(value.translation.height) { return }
                        scrub = Self.nearest(xy, x: value.location.x)
                    }
                    .onEnded { _ in scrub = nil }
            )
            .sensoryFeedback(.selection, trigger: scrub)
        }
        .accessibilityHidden(true)
    }

    /// x zamana orantılı (seyrek seriler dürüst görünsün), y aralığın %12 fazlası.
    private func positions(in size: CGSize) -> [CGPoint] {
        guard let first = points.first, let last = points.last else { return [] }
        let t0 = first.date.timeIntervalSinceReferenceDate
        let duration = max(last.date.timeIntervalSinceReferenceDate - t0, 1)
        let values = points.map(\.value)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let pad = hi > lo ? (hi - lo) * 0.12 : 1
        let minV = lo - pad
        let maxV = hi + pad
        let width = size.width - 2 * inset
        let height = size.height - top - bottom
        return points.map { point in
            let x = points.count == 1
                ? size.width / 2
                : inset + CGFloat((point.date.timeIntervalSinceReferenceDate - t0) / duration) * width
            let y = top + CGFloat((maxV - point.value) / (maxV - minV)) * height
            return CGPoint(x: x, y: y)
        }
    }

    private static func nearest(_ xy: [CGPoint], x: CGFloat) -> Int? {
        xy.indices.min { abs(xy[$0].x - x) < abs(xy[$1].x - x) }
    }

    /// Catmull-Rom → kübik Bezier (Mac'teki borsa çizgisiyle aynı).
    static func smooth(_ pts: [CGPoint]) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            guard pts.count > 1 else { return }
            for i in 0..<(pts.count - 1) {
                let p0 = i > 0 ? pts[i - 1] : pts[i]
                let p1 = pts[i]
                let p2 = pts[i + 1]
                let p3 = i + 2 < pts.count ? pts[i + 2] : p2
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                p.addCurve(to: p2, control1: c1, control2: c2)
            }
        }
    }

    private static func area(_ line: Path, xy: [CGPoint], bottom: CGFloat) -> Path {
        var path = line
        if let last = xy.last, let first = xy.first {
            path.addLine(to: CGPoint(x: last.x, y: bottom))
            path.addLine(to: CGPoint(x: first.x, y: bottom))
            path.closeSubpath()
        }
        return path
    }
}

/// İzleme listesindeki küçük kıvrım (son ~30 değer).
struct MeasurementSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let range = max(hi - lo, 0.0001)
            let step = (geo.size.width - 2) / CGFloat(max(1, values.count - 1))
            let pts = values.enumerated().map { i, v in
                CGPoint(x: 1 + CGFloat(i) * step, y: 2 + CGFloat((hi - v) / range) * (geo.size.height - 4))
            }
            MeasurementStockChart.smooth(pts)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Sola kaydırınca kırmızı "Sil" aksiyonu açan satır sarmalayıcı (List gerektirmez,
/// custom kart UI ile uyumlu). Butona basınca onDelete tetiklenir; "emin misin" onayını
/// üst katman (alert) gösterir. Satır arka planı kart rengiyle (surface) aynı olmalı.
struct MobileSwipeToDelete<Content: View>: View {
    var onDelete: () -> Void
    /// Satır zemini — kaydırınca kırmızıyı gizler. Kart içinde `surface`, Tek Akış
    /// sayfasında `background` ver ki satır akışla aynı renkte kalsın.
    var rowBackground: Color = Palette.surface
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    private let revealWidth: CGFloat = 88

    var body: some View {
        ZStack(alignment: .trailing) {
            // Kırmızı yalnız kaydırırken: dururken satırın kenar yumuşatmasından ince
            // kırmızı bir çerçeve sızıyordu (kartsız sayfalarda göze batıyor).
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.negative)
                .opacity(offset < 0 ? 1 : 0)
                .overlay(alignment: .trailing) {
                    Button {
                        close()
                        onDelete()
                    } label: {
                        VStack(spacing: 3) {
                            Lucide(sf: "trash.fill", size: 15)
                            Text("Sil")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(width: revealWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, max(startOffset + value.translation.width, -revealWidth))
                        }
                        .onEnded { value in
                            let projected = startOffset + value.translation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                offset = projected < -revealWidth / 2 ? -revealWidth : 0
                            }
                            startOffset = offset
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { offset = 0 }
        startOffset = 0
    }
}

/// Bugün (V12 "Çizgi") kalori çizgisinin bir öğünü.
struct MealLineSegment {
    let time: Date
    let calories: Double
}

/// Bugün V12: kalori çizgisi öğünlere bölünmüş — parça boyu öğünün kalorisi, aralarında
/// 3 pt boşluk, her parçanın üstünde saati (komşusuna çarpan saat atlanır); ucunda parlayan
/// düğme. Hedef aşılınca ölçek yenene göre kurulur, hedefin yerinde ince bir çentik kalır
/// ve düğme kırmızıya döner.
struct MealSegmentLine: View {
    let meals: [MealLineSegment]
    let intake: Double
    let goal: Double

    /// Saat bandı (14) + çizgiyle arası (8).
    private static let labelBand: CGFloat = 22
    private static let segmentGap: CGFloat = 3
    private static let minLabelSpacing: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scale = width / CGFloat(max(goal, intake, 1))
            let parts = layout(width: width, scale: scale)
            let lineY = Self.labelBand + 6
            let over = goal > 0 && intake > goal
            let knob = over ? Palette.negative : Palette.textPrimary
            ZStack(alignment: .topLeading) {
                ForEach(parts.labels.indices, id: \.self) { i in
                    Text(parts.labels[i].text)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textQuaternary)
                        .fixedSize()
                        .position(x: parts.labels[i].x, y: 11)
                }
                Capsule()
                    .fill(Palette.track)
                    .frame(width: width, height: 2)
                    .offset(y: lineY - 1)
                ForEach(parts.bars.indices, id: \.self) { i in
                    Capsule()
                        .fill(Palette.textPrimary)
                        .frame(width: parts.bars[i].width, height: 2)
                        .offset(x: parts.bars[i].x, y: lineY - 1)
                }
                if over {
                    Rectangle()
                        .fill(Palette.textTertiary)
                        .frame(width: 1, height: 10)
                        .offset(x: CGFloat(goal) * scale - 0.5, y: lineY - 5)
                }
                Circle()
                    .fill(knob)
                    .frame(width: 12, height: 12)
                    .shadow(color: knob.opacity(0.45), radius: 7)
                    .offset(x: min(CGFloat(intake) * scale, width) - 6, y: lineY - 6)
            }
        }
        .frame(height: Self.labelBand + 12)
        .accessibilityHidden(true)
    }

    private func layout(width: CGFloat, scale: CGFloat)
        -> (bars: [(x: CGFloat, width: CGFloat)], labels: [(x: CGFloat, text: String)]) {
        var bars: [(x: CGFloat, width: CGFloat)] = []
        var labels: [(x: CGFloat, text: String)] = []
        var x: CGFloat = 0
        var lastLabel = -CGFloat.infinity
        for (index, meal) in meals.enumerated() {
            let w = CGFloat(max(meal.calories, 0)) * scale
            let gap = index < meals.count - 1 ? Self.segmentGap : 0
            bars.append((x, max(1, w - gap)))
            let center = min(max(x + w / 2, 14), width - 14)
            if center - lastLabel >= Self.minLabelSpacing {
                labels.append((center, Fmt.timeShort.string(from: meal.time)))
                lastLabel = center
            }
            x += w
        }
        return (bars, labels)
    }
}

/// Tarif satırının makro çubuğu (tuval "Tarifler · V1"): protein · karb · yağın kalori payı,
/// aralarında 1.5 pt boşluk. Makro yoksa boş ray.
struct RecipeMacroBar: View {
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    var width: CGFloat = 80
    var height: CGFloat = 3
    var spacing: CGFloat = 1.5

    var body: some View {
        let kcal = [(protein ?? 0) * 4, (carbs ?? 0) * 4, (fat ?? 0) * 9]
        let total = kcal.reduce(0, +)
        let colors = [Palette.macroProtein, Palette.macroCarbs, Palette.macroFat]
        let parts = kcal.indices.filter { kcal[$0] > 0 }
        let usable = width - spacing * CGFloat(max(parts.count - 1, 0))
        HStack(spacing: spacing) {
            if total > 0 {
                ForEach(parts, id: \.self) { i in
                    Capsule()
                        .fill(colors[i])
                        .frame(width: max(1, usable * CGFloat(kcal[i] / total)), height: height)
                }
            } else {
                Capsule()
                    .fill(Palette.track)
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, alignment: .leading)
        .accessibilityHidden(true)
    }
}
