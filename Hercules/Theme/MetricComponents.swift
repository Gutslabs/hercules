import SwiftUI
import LucideKit

/// Paylaşılan metrik/grafik primitive'leri — Mac ve iOS target'ının İKİSİ de derler.
///
/// Bu dosya bilinçli olarak `Theme/` altında: `Views/Components/` yalnız Mac,
/// `Mobile*` yalnız iOS target'ında. Ortak bir UI parçası ancak burada yaşayabilir.
/// Bu yüzden `TrendPoint`/`TrendAnalysis` (Mac-only) veya `Charts` KULLANILMAZ —
/// girdiler düz `[Double]` ve `String`, çizim saf `Path`/`Canvas`.
///
/// Renkler her zaman `Palette`'ten ya da çağıranın verdiği `tint`'ten gelir;
/// hiçbir yerde sabit kodlanmış marka rengi yoktur (tema anahtarı çalışmaya devam eder).

// MARK: - Hareket

/// Bu dosyadaki tüm girişlerin ortak ritmi. Tek yerden ayarlanır ki farklı
/// sayfalardaki kartlar aynı hızda açılsın.
enum MetricMotion {
    /// Kademeli girişte her eleman arasındaki gecikme.
    static let step: Double = 0.06
    /// Metin/blok "blur-in" girişi.
    static var reveal: Animation { .easeOut(duration: 0.5) }
    /// Çizginin soldan sağa çizilmesi.
    static let drawDuration: Double = 0.85
    static var draw: Animation { .easeOut(duration: drawDuration) }
    /// Ray/bar dolumu — hedefe yaslanırken hafif yay.
    static var fill: Animation { .spring(response: 0.75, dampingFraction: 0.9) }
}

private struct MetricRevealKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    /// Alt ağaçtaki metrik bileşenlerinin giriş animasyonu oynatıp oynatmayacağı.
    var metricReveal: Bool {
        get { self[MetricRevealKey.self] }
        set { self[MetricRevealKey.self] = newValue }
    }
}

extension View {
    /// Giriş animasyonlarını bir alt ağaç için kapatır — sayfa geçişi anında olsun
    /// istenen yerlerde (bkz. Mac perf pası) tek satırla susturulur.
    func metricReveal(_ enabled: Bool) -> some View {
        environment(\.metricReveal, enabled)
    }
}

/// Kademeli "blur-in" girişi: bulanık + saydam + birkaç px aşağıdan yerine oturur.
struct RevealModifier: ViewModifier {
    var order: Int = 0
    var delay: Double = 0
    var blur: CGFloat = 6
    var rise: CGFloat = 5

    @Environment(\.metricReveal) private var revealEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let animates = revealEnabled && !reduceMotion
        let settled = shown || !animates
        return content
            .blur(radius: settled ? 0 : blur)
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : rise)
            .onAppear {
                guard animates, !shown else { return }
                withAnimation(MetricMotion.reveal.delay(delay + Double(order) * MetricMotion.step)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// `order` arttıkça giriş gecikir — bir kartın satırlarını sırayla açmak için.
    func reveal(_ order: Int = 0, delay: Double = 0) -> some View {
        modifier(RevealModifier(order: order, delay: delay))
    }
}

/// `Animatable` olduğu için SwiftUI iki değer arasını ara karelerde doldurur —
/// `contentTransition(.numericText())`'in aksine gerçek sayma efekti verir.
private struct AnimatableNumberText: View, Animatable {
    var value: Double
    var digits: Int

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(digits <= 0 ? Fmt.int(value) : Fmt.num(value, digits: digits))
    }
}

/// 0'dan hedefe sayarak açılan sayı. Değer sonradan değişirse yeni değere
/// yine sayarak gider (sıfırdan başlamaz).
struct CountUpText: View {
    let value: Double
    var digits: Int = 0
    var font: Font = Typography.hero(28)
    var color: Color = Palette.textPrimary
    var tracking: CGFloat = 0
    var delay: Double = 0

    @Environment(\.metricReveal) private var revealEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0
    @State private var started = false

    var body: some View {
        AnimatableNumberText(value: shown, digits: digits)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .onAppear {
                guard !started else { return }
                started = true
                guard revealEnabled, !reduceMotion else { shown = value; return }
                withAnimation(.easeOut(duration: 0.85).delay(delay)) { shown = value }
            }
            .onChange(of: value) { _, new in
                guard revealEnabled, !reduceMotion else { shown = new; return }
                withAnimation(.easeOut(duration: 0.5)) { shown = new }
            }
    }
}

// MARK: - Kart kabuğu

// MARK: - Barlar

/// `GoalBar` üzerinde bir referans çizgisi (hedef, ortalama, MEV/MRV, …).
struct BarMarker {
    /// 0…1 — ray genişliğine göre konum.
    var ratio: Double
    /// nil → `Palette.textPrimary`.
    var color: Color? = nil
    /// Çizginin tepesindeki nokta.
    var cap: Bool = true
    /// Çizginin rayın üstüne taşma payı (pt). Kapaklı işarette nokta buraya oturur;
    /// sade eşik çizgilerinde 2–4 yeter.
    var extends: CGFloat = 8
}

/// `GoalBar` üzerinde "ideal aralık" şeridi — MEV–MRV bandı, hedef aralığı, sağlıklı bant.
struct BarBand {
    /// 0…1 aralığında başlangıç/bitiş.
    var from: Double
    var to: Double
    var color: Color
}

/// Eğik tarama deseni — dolgunun üstüne "doku" katar (düz renk yerine).
struct DiagonalStripes: Shape {
    var spacing: CGFloat = 7
    /// Yükseklik başına yatay kaçıklık; 0 = dik, 1 = 45°.
    var slant: CGFloat = 0.55

    func path(in rect: CGRect) -> Path {
        Path { p in
            guard spacing > 0, rect.width > 0, rect.height > 0 else { return }
            let dx = rect.height * slant
            var x = rect.minX - dx
            while x <= rect.maxX + dx {
                p.move(to: CGPoint(x: x, y: rect.maxY))
                p.addLine(to: CGPoint(x: x + dx, y: rect.minY))
                x += spacing
            }
        }
    }
}

/// Kalın hedef rayı: taranmış degrade dolgu + dolgunun ucunda kafa işareti,
/// istenirse ek referans işaretleri. Hedef aşılırsa renk `overflowTint`'e döner.
struct GoalBar: View {
    let value: Double
    let goal: Double
    var tint: Color = Palette.chart
    /// nil → tint'ten türetilen iki duraklı degrade.
    var gradient: [Color]? = nil
    var height: CGFloat = 26
    var hatched: Bool = true
    var hatchColor: Color = Color.black.opacity(0.09)
    var hatchSpacing: CGFloat = 7
    var hatchWidth: CGFloat = 3
    /// Dolgunun ucundaki dikey işaret ("şu andasın").
    var headMarker: Bool = true
    var markers: [BarMarker] = []
    /// Rayın altında duran "ideal aralık" şeridi.
    var band: BarBand? = nil
    var overflowTint: Color = Palette.warning
    /// Hangi orandan sonra "hedefi aştın" sayılsın. 1.05 = %5 tolerans.
    var overflowAt: Double = 1
    /// nil → tint'ten türetilen soluk ray.
    var trackColor: Color? = nil
    var delay: Double = 0

    @Environment(\.metricReveal) private var revealEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: Double = 0
    @State private var started = false

    /// İşaretlerin rayın üstünde kapladığı en büyük pay. İşaret yoksa 0 —
    /// ince barlarda boşuna yer kaplamasın.
    private var capOverhang: CGFloat {
        var m: CGFloat = headMarker ? 8 : 0
        for marker in markers { m = max(m, marker.extends) }
        return m
    }

    private var ratio: Double {
        guard goal > 0, value.isFinite else { return 0 }
        return max(0, min(value / goal, 1))
    }

    private var isOver: Bool { goal > 0 && value > goal * overflowAt }

    private var fillColors: [Color] {
        if isOver { return [overflowTint.opacity(0.72), overflowTint] }
        return gradient ?? [tint.opacity(0.72), tint]
    }

    var body: some View {
        GeometryReader { geo in
            bar(width: geo.size.width)
        }
        .frame(height: height + capOverhang)
        .onAppear {
            guard !started else { return }
            started = true
            guard revealEnabled, !reduceMotion else { drawn = 1; return }
            withAnimation(MetricMotion.fill.delay(delay)) { drawn = 1 }
        }
    }

    private func bar(width: CGFloat) -> some View {
        let filled = max(0, width * CGFloat(ratio) * CGFloat(drawn))
        let allMarkers = markers + (headMarker ? [BarMarker(ratio: ratio * drawn, color: Palette.textPrimary)] : [])
        return ZStack(alignment: .bottomLeading) {
            Capsule()
                .fill(trackColor ?? (isOver ? overflowTint.opacity(0.14) : tint.opacity(0.13)))
                .frame(height: height)
                .overlay(alignment: .leading) {
                    if let band {
                        let from = CGFloat(max(0, min(band.from, 1)))
                        let to = CGFloat(max(0, min(band.to, 1)))
                        Rectangle()
                            .fill(band.color)
                            .frame(width: max(0, width * (to - from)), height: height)
                            .offset(x: width * from)
                    }
                }
                .clipShape(Capsule())

            Capsule()
                .fill(
                    LinearGradient(colors: fillColors, startPoint: .leading, endPoint: .trailing)
                )
                .overlay {
                    if hatched {
                        DiagonalStripes(spacing: hatchSpacing)
                            .stroke(hatchColor, lineWidth: hatchWidth)
                    }
                }
                .clipShape(Capsule())
                .frame(width: filled, height: height)
                .animation(reduceMotion ? nil : MetricMotion.fill, value: ratio)

            ForEach(Array(allMarkers.enumerated()), id: \.offset) { _, m in
                markerView(m)
                    .offset(x: width * CGFloat(max(0, min(m.ratio, 1))) - 0.7)
            }
        }
        .frame(width: width, height: height + capOverhang, alignment: .bottomLeading)
    }

    private func markerView(_ m: BarMarker) -> some View {
        let color = m.color ?? Palette.textPrimary
        return VStack(spacing: 0) {
            if m.cap {
                Circle()
                    .fill(color)
                    .frame(width: 4.5, height: 4.5)
            }
            Rectangle()
                .fill(color)
                .frame(width: 1.4)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 4.5, height: height + m.extends)
    }
}

/// Bölgeli skala + imleç: "hangi banttayım" sorusuna tek bakışlık cevap.
/// Hız bandı, VKİ/yağ oranı bantları, nabız bölgeleri — eşikleri olan her metrik.
struct ZoneBar: View {
    struct Zone {
        /// Toplam içindeki pay (mutlak değer değil — kendi içinde normalize edilir).
        var width: Double
        var color: Color
        var label: String = ""
        /// İdeal/hedef bölge — etiketi kalın ve `highlightColor` ile yazılır.
        var highlighted: Bool = false
    }

    let zones: [Zone]
    /// 0…1 — imlecin skala üzerindeki konumu.
    let position: Double
    var height: CGFloat = 10
    var cursorHeight: CGFloat = 22
    /// nil → `Palette.textPrimary` (açık temada mürekkep, koyuda kağıt).
    var cursorColor: Color? = nil
    var showLabels: Bool = true
    var labelColor: Color = Palette.textSecondary
    var highlightColor: Color = Palette.positive
    var delay: Double = 0

    @Environment(\.metricReveal) private var revealEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: Double = 0
    @State private var started = false

    private var total: Double {
        max(0.0001, zones.reduce(0) { $0 + max(0, $1.width) })
    }

    private var hasLabels: Bool {
        showLabels && zones.contains { !$0.label.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                bar(width: geo.size.width)
            }
            .frame(height: cursorHeight)
            if hasLabels {
                GeometryReader { geo in
                    labels(width: geo.size.width)
                }
                .frame(height: 14)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            guard revealEnabled, !reduceMotion else { drawn = 1; return }
            withAnimation(MetricMotion.fill.delay(delay)) { drawn = 1 }
        }
    }

    private func bar(width w: CGFloat) -> some View {
        let clamped = max(0, min(position, 1))
        let x = w * CGFloat(clamped * drawn)
        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(Array(zones.enumerated()), id: \.offset) { _, z in
                    Rectangle()
                        .fill(z.color)
                        .frame(width: w * CGFloat(max(0, z.width) / total))
                }
            }
            .frame(height: height)
            .clipShape(Capsule())

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(cursorColor ?? Palette.textPrimary)
                .frame(width: 2.5, height: cursorHeight)
                .offset(x: min(w - 2.5, max(0, x - 1.25)))
                .animation(reduceMotion ? nil : MetricMotion.fill, value: clamped)
        }
        .frame(width: w, height: cursorHeight, alignment: .leading)
    }

    private func labels(width w: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                Text(z.label)
                    .font(.system(size: 11.5, weight: z.highlighted ? .semibold : .regular))
                    .foregroundStyle(z.highlighted ? highlightColor : labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(
                        width: w * CGFloat(max(0, z.width) / total),
                        alignment: i == 0 ? .leading : (i == zones.count - 1 ? .trailing : .center)
                    )
            }
        }
    }
}

// MARK: - Okumalar

// MARK: - Grafik

/// Noktalı eksen rayı — kılavuz çizgisi yerine sessiz bir zemin ritmi.
struct DottedAxisRail: View {
    var count: Int = 26
    var color: Color = Palette.textQuaternary
    var dot: CGFloat = 2

    var body: some View {
        Canvas { ctx, size in
            guard count > 1, size.width > 0 else { return }
            let step = size.width / CGFloat(count - 1)
            for i in 0..<count {
                let x = CGFloat(i) * step
                let rect = CGRect(
                    x: x - dot / 2,
                    y: (size.height - dot) / 2,
                    width: dot,
                    height: dot
                )
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .frame(height: max(dot, 6))
        .allowsHitTesting(false)
    }
}

/// Mutlak noktalardan çizilen çoklu-çizgi. `path(in:)` rect'i yok sayar —
/// noktalar dışarıda hesaplanır, böylece `.trim` ile soldan sağa çizdirilebilir.
private struct PolylineShape: Shape {
    let pts: [CGPoint]

    func path(in rect: CGRect) -> Path {
        Path { p in
            guard pts.count >= 2 else { return }
            p.move(to: pts[0])
            for q in pts.dropFirst() { p.addLine(to: q) }
        }
    }
}

/// Kart içi trend çizgisi: soldan sağa çizilir, uçta nokta + tarih/değer notu,
/// isteğe bağlı soluk projeksiyon kuyruğu ve noktalı eksen rayı.
///
/// Girdi düz `[Double]` (eskiden yeniye) — hem Mac hem mobil tarafta aynı çağrılır.
struct TrendSpark: View {
    /// Gerçekleşmiş seri, eskiden yeniye.
    let values: [Double]
    /// Ucun ardından devam eden tahmin (soluk çizilir). Boş bırakılabilir.
    var projection: [Double] = []
    var tint: Color = Palette.chart
    var lineWidth: CGFloat = 2
    /// Serinin ucundaki noktanın çapı. Satır-içi mini grafiklerde 3–4 yeter.
    var dotSize: CGFloat = 7
    /// Uç noktanın üstünde beliren not (ör. "11 Ağu").
    var calloutTitle: String? = nil
    /// Uç noktanın solunda beliren not (ör. "146 kg").
    var calloutValue: String? = nil
    var showAxisDots: Bool = true
    var axisDotCount: Int = 26
    /// Uç noktadan eksene inen dikey kılavuz.
    var showDropLine: Bool = true
    var height: CGFloat = 96
    var delay: Double = 0

    @Environment(\.metricReveal) private var revealEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var tail = false
    @State private var started = false

    private let topInset: CGFloat = 16
    private let axisGap: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            chart(in: geo.size)
        }
        .frame(height: height)
        .onAppear {
            guard !started else { return }
            started = true
            guard revealEnabled, !reduceMotion else { drawn = 1; tail = true; return }
            withAnimation(MetricMotion.draw.delay(delay)) { drawn = 1 }
            withAnimation(MetricMotion.reveal.delay(delay + MetricMotion.drawDuration * 0.82)) { tail = true }
        }
    }

    private func chart(in size: CGSize) -> some View {
        let w = size.width
        // Paylar yalnızca gerçekten çizilen parçalar için ayrılır — 20pt'lik satır-içi
        // sparkline'da 16pt üst boşluk grafiği yok ederdi.
        let axisH: CGFloat = showAxisDots ? 6 : 0
        let topPad: CGFloat = calloutTitle == nil ? 2 : topInset
        let bottomPad: CGFloat = (showAxisDots || showDropLine) ? axisGap : 2
        let plotBottom = max(topPad + 1, size.height - axisH - bottomPad)
        let plotH = plotBottom - topPad

        let all = values + projection
        let lo = all.min() ?? 0
        let hi = all.max() ?? 1
        // Tüm değerler eşitse (tek ölçüm, sabit seri) çizgi dibe yapışmasın — ortada dursun.
        let flat = (hi - lo) < 0.0001
        let span = max(hi - lo, 0.0001)
        // Projeksiyon varsa gerçek seri kadar x, kalan pay kuyruğa ayrılır.
        // Sağdan yarım nokta payı bırakılır ki uçtaki nokta kenardan kırpılmasın.
        let lastIndex = max(1, all.count - 1)
        let plotW = max(1, w - 4)
        func x(_ i: Int) -> CGFloat { plotW * CGFloat(i) / CGFloat(lastIndex) }
        func y(_ v: Double) -> CGFloat {
            flat ? plotBottom - plotH / 2 : plotBottom - CGFloat((v - lo) / span) * plotH
        }

        // Tek noktalı seri düz bir çizgiye açılır (boş kutu göstermek yerine).
        let mainPts: [CGPoint] = values.count == 1
            ? [CGPoint(x: 0, y: y(values[0])), CGPoint(x: plotW, y: y(values[0]))]
            : values.indices.map { CGPoint(x: x($0), y: y(values[$0])) }
        // Kuyruk uç noktadan başlar ki iki çizgi kopuk görünmesin.
        let tailPts: [CGPoint] = projection.isEmpty
            ? []
            : [mainPts.last].compactMap { $0 } + projection.indices.map {
                CGPoint(x: x(values.count + $0), y: y(projection[$0]))
            }
        let dot = mainPts.last ?? .zero

        return ZStack(alignment: .topLeading) {
            if mainPts.count >= 2 {
                if tailPts.count >= 2 {
                    PolylineShape(pts: tailPts)
                        .stroke(
                            Palette.textQuaternary.opacity(0.55),
                            style: StrokeStyle(lineWidth: lineWidth * 0.75, lineCap: .round, lineJoin: .round)
                        )
                        .opacity(tail ? 1 : 0)
                }

                if showDropLine {
                    Path { p in
                        p.move(to: CGPoint(x: dot.x, y: dot.y + 7))
                        p.addLine(to: CGPoint(x: dot.x, y: plotBottom + axisGap * 0.6))
                    }
                    .stroke(Palette.textQuaternary.opacity(0.6), lineWidth: 1)
                    .opacity(tail ? 1 : 0)
                }

                PolylineShape(pts: mainPts)
                    .trim(from: 0, to: drawn)
                    .stroke(
                        LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )

                Circle()
                    .fill(tint)
                    .frame(width: dotSize, height: dotSize)
                    .position(dot)
                    .opacity(tail ? 1 : 0)
                    .scaleEffect(tail ? 1 : 0.4)

                if let calloutValue {
                    Text(calloutValue)
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .frame(width: max(0, dot.x - 7), alignment: .trailing)
                        .offset(y: dot.y + 3)
                        .opacity(tail ? 1 : 0)
                }

                if let calloutTitle {
                    Text(calloutTitle)
                        .font(Typography.captionBold)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .frame(width: max(0, w - dot.x - 8), alignment: .leading)
                        .offset(x: dot.x + 8, y: max(0, dot.y - 18))
                        .opacity(tail ? 1 : 0)
                }
            }

            if showAxisDots {
                DottedAxisRail(count: axisDotCount)
                    .frame(width: w)
                    .offset(y: size.height - axisH)
                    .opacity(tail ? 1 : 0)
            }
        }
        .frame(width: w, height: size.height, alignment: .topLeading)
    }
}
