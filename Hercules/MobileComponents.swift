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
    var previous: Double? { values.count >= 2 ? values[values.count - 2] : nil }
    var delta: Double? { guard let c = current, let p = previous else { return nil }; return c - p }
    var lastDate: Date? { dates.last }
    var average: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    var minValue: Double? { values.min() }
    var maxValue: Double? { values.max() }
    var weeklyChange: Double? {
        guard values.count >= 2, let f = dates.first, let l = dates.last else { return nil }
        let days = max(1, l.timeIntervalSince(f) / 86_400)
        return ((values[values.count - 1] - values[0]) / days) * 7
    }
    var hasData: Bool { current != nil }

    var grup: String { kind.category == .composition ? "Kompozisyon" : "Çevre" }
    var deltaAbs: Double? { delta.map(abs) }
    var isDown: Bool { (delta ?? 0) < 0 }

    /// nil = nötr (≈0), true = iyi yön (hedefe uygun), false = kötü yön.
    var improving: Bool? {
        guard let d = delta, abs(d) > 0.0001 else { return nil }
        return kind.lowerIsBetter ? d < 0 : d > 0
    }
    var weeklyImproving: Bool? {
        guard let wk = weeklyChange, abs(wk) > 0.0001 else { return nil }
        return kind.lowerIsBetter ? wk < 0 : wk > 0
    }
}

/// İyi/kötü/nötr → semantik renk (bordo YOK: iyi=positive, kötü=negative, nötr=soluk).
func measurementTrendColor(_ improving: Bool?) -> Color {
    guard let improving else { return Palette.textTertiary }
    return improving ? Palette.positive : Palette.negative
}

/// Hafif çizgi grafik — yalnız min/max ızgara çizgisi + sağda mono etiket + uç nokta.
/// Çizgi rengi `Palette.chart` (Ayarlar'daki grafik tonu — bordo yalnız BURADA olabilir).
struct MeasurementLineChart: View {
    let values: [Double]
    var lineColor: Color = Palette.chart
    var height: CGFloat = 88

    var body: some View {
        GeometryReader { geo in
            chart(in: geo.size)
        }
        .frame(height: height)
    }

    // Düz fonksiyon (ViewBuilder değil) — let/iç fonksiyon serbest; tek bir view döner.
    private func chart(in size: CGSize) -> some View {
        let gutter: CGFloat = 42
        let plotRight = max(size.width - gutter, 1)
        let padX: CGFloat = 2
        let padY: CGFloat = 10
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let n = values.count
        func y(_ v: Double) -> CGFloat { size.height - padY - CGFloat((v - lo) / span) * (size.height - padY * 2) }
        let xs: [CGFloat] = values.indices.map { i in
            n <= 1 ? padX : padX + CGFloat(i) / CGFloat(n - 1) * (plotRight - padX * 2)
        }
        let ys: [CGFloat] = values.map { y($0) }

        return ZStack(alignment: .topLeading) {
            ForEach([hi, lo], id: \.self) { v in
                Path { p in
                    p.move(to: CGPoint(x: padX, y: y(v)))
                    p.addLine(to: CGPoint(x: plotRight, y: y(v)))
                }
                .stroke(Palette.border, lineWidth: 1)
                Text(Fmt.num(v, digits: 1))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                    .position(x: plotRight + gutter / 2, y: y(v))
            }
            if n >= 2 {
                Path { p in
                    for i in xs.indices {
                        let pt = CGPoint(x: xs[i], y: ys[i])
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            Circle()
                .fill(lineColor)
                .frame(width: 5.6, height: 5.6)
                .position(x: xs.last ?? padX, y: ys.last ?? y(lo))
        }
    }
}

/// V1 "Tek Akış" satırlarında etiket ile değer arasını dolduran noktalı lider çizgisi
/// (yemek/egzersiz satırları). Esnek genişlik — kalan boşluğu kaplar.
struct DottedLeader: View {
    var color: Color = Palette.track

    var body: some View {
        GeometryReader { geo in
            Path { p in
                let y = geo.size.height / 2
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: geo.size.width, y: y))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3]))
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity)
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
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.negative)
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
