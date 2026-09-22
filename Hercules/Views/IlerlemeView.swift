import SwiftUI
import LucideKit
import SwiftData

/// İlerleme — tasarım: "Hercules Mac Tasarımı" tuvali ▸ İlerleme · V1 Rota (sade).
/// Tek büyük görsel (başlangıç → hedef rotası) + üç sayı (% tamamlandı · kalan kg · varış)
/// + ince Dönemler şeridi. Haftalık ritim, günlük açık ve sıradaki ara hedef ekranda değil,
/// "şimdi" düğmesinin ve sıradaki durağın tooltip'inde.
///
/// Veri gerçek: Measurement (kilo) + UserProfile.targetWeight; ritim TrendAnalysis
/// regresyonundan (app'in geri kalanıyla tutarlı). Kilo verme VE alma yönünü destekler.
/// Her şey AKTİF DÖNEME göre ölçülür (bkz. `DietEpoch`): başlangıç kilosu, gün sayacı ve
/// ritim dönemin başından sayılır. Yeni dönem açılınca rota sıfırdan başlar; eski dönemler
/// ve aralar alttaki Dönemler şeridinde kalır.
struct IlerlemeView: View {
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    /// @Observable: `body` içinde okunan `epochs` değişince sayfa yeniden hesaplanır.
    private let epochStore = DietEpochStore.shared
    @State private var startingEpoch = false
    @State private var editingEpoch: DietEpoch?

    /// Dönem şeridinin sabit boyu; kalan yükseklik Rota paneline gider.
    private static let stripHeight: CGFloat = 180
    /// Rota panelinin tabanı — rakam bloğu + rota bundan kısa pencerede sığmaz, sayfa kayar.
    private static let rotaMinHeight: CGFloat = 520

    var body: some View {
        let weights = TrendAnalysis.points(measurements, for: .weight)
        let m = IlerlemeMetrics.make(weights: weights, goal: profile?.targetWeight, epochs: epochStore.epochs)
        let segments = DietTimeline.segments(epochs: epochStore.epochs, weights: weights)
        GeometryReader { geo in
            ScrollView {
                let rota = max(Self.rotaMinHeight, geo.size.height - 36 - 24 - Self.stripHeight)
                VStack(spacing: 24) {
                    IlerlemeRotaPanel(metrics: m, counter: counterText, empty: emptyCopy)
                        .frame(height: rota)
                    EpochTimelineStrip(
                        segments: segments,
                        isLoss: m?.isLoss ?? true,
                        eta: m?.eta,
                        onStartNew: { startingEpoch = true },
                        onEdit: { id in editingEpoch = epochStore.epochs.first { $0.id == id } }
                    )
                    .frame(height: Self.stripHeight)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
        .sheet(isPresented: $startingEpoch) {
            EpochStartSheet(store: epochStore, weights: weights) { startingEpoch = false }
        }
        .sheet(item: $editingEpoch) { epoch in
            EpochEditorSheet(store: epochStore, epoch: epoch) { editingEpoch = nil }
        }
    }

    /// Başlık eki: süren dönemde "Dönem 2 · 5. gün" (başlangıç günü 1. gün); aradaysa aranın süresi.
    private var counterText: String? {
        guard let (epoch, number) = DietTimeline.current(in: epochStore.epochs) else { return nil }
        let now = Date()
        if let lastDay = epoch.lastDay {
            let restFirst = Calendar.current.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return "Ara · \(DietTimeline.inclusiveDays(from: restFirst, to: now)) gün"
        }
        return "Dönem \(number) · \(DietTimeline.inclusiveDays(from: epoch.start, to: now)). gün"
    }

    /// Hedef ya da kilo verisi eksikken Rota panelinin yerini tutan kısa açıklama.
    private var emptyCopy: (title: String, detail: String) {
        profile?.targetWeight == nil
            ? ("Hedef kilonu belirle", "Profil'den hedef kilonu gir; ilerlemen burada tek bakışta görünür.")
            : ("Henüz kilo verisi yok", "Ölçümler'den kilonu gir; birkaç tartıdan sonra varış tahmini de gelir.")
    }
}

// MARK: - Metrik hesabı

extension IlerlemeMetrics {
    /// Ritim için dönemin tartıları en az bu kadar güne yayılmalı. Taze bir dönemde
    /// 2-3 günlük tartı farkı sudan ibarettir; ondan haftalık hız / bitiş tarihi
    /// türetmek "18 günde hedeftesin" gibi saçma tahminler üretir.
    private static let minimumRhythmSpanDays: Double = 7

    /// Aktif dönemin yolculuğu — İlerleme sayfası ve Genel Bakış'ın Kilo kartı aynı sayıları
    /// okusun diye tek yerde. Hedef, tartı ya da dönem başlangıç kilosu yoksa nil.
    static func make(weights pts: [TrendPoint], goal: Double?, epochs: [DietEpoch],
                     now: Date = Date(), calendar cal: Calendar = .current) -> IlerlemeMetrics? {
        guard let goal,
              let last = pts.last,
              let (epoch, _) = DietTimeline.current(in: epochs),
              let start = DietTimeline.startWeight(of: epoch, weights: pts),
              abs(start - goal) > 0.05 else { return nil }

        // Haftalık ritim YALNIZ bu dönemin tartılarından: son ~8 hafta penceresinden
        // regresyon (yetersizse dönemin tümü). Önceki dönemin / aranın eğimi yeni döneme
        // taşınmaz — "sıfırdan başladım" diyen birine aradaki kilo alışının hızı gösterilmez.
        let epochPts = DietTimeline.weights(in: epoch, from: pts)
        let windowStart = cal.date(byAdding: .day, value: -56, to: now) ?? epoch.start
        let recent = epochPts.filter { $0.date >= windowStart }
        let fitPts = recent.count >= 3 ? recent : epochPts
        let span = (epochPts.last?.date.timeIntervalSince(epochPts.first?.date ?? now) ?? 0) / 86_400
        // "Şimdi" ise GERÇEK son ölçüm — Dashboard/Ölçümler son ölçümü gösteriyor, İlerleme
        // de onunla tutarlı olsun (geçilen duraklar geçilmiş sayılır).
        let slopePerDay: Double
        if span >= Self.minimumRhythmSpanDays, let fit = TrendAnalysis.linearFit(fitPts) {
            slopePerDay = fit.slope
        } else {
            slopePerDay = 0
        }
        let current = last.value
        let weeklyRate = slopePerDay * 7
        let rateAbs = abs(weeklyRate)

        let isLoss = goal < start
        let total = max(0.1, abs(start - goal))
        let progressed = max(0, isLoss ? (start - current) : (current - start))
        let remaining = max(0, isLoss ? (current - goal) : (goal - current))
        let pct = min(1, max(0, progressed / total))
        let movingTowardGoal = isLoss ? (weeklyRate < 0) : (weeklyRate > 0)

        var daysLeft: Int? = nil
        var eta: Date? = nil
        if rateAbs >= 0.01, movingTowardGoal, remaining > 0.05 {
            let d = Int((remaining / rateAbs * 7).rounded())
            daysLeft = d
            eta = cal.date(byAdding: .day, value: d, to: now)
        }

        // Rota durakları — start→goal arası 6 eşit adım.
        let segs = 6
        let nodes: [IlerlemeMetrics.Node] = (0...segs).map { i in
            let w = start + (goal - start) * Double(i) / Double(segs)
            let frac = min(1, max(0, (start - w) / (start - goal)))
            let passed = isLoss ? (w >= current - 0.001) : (w <= current + 0.001)
            return IlerlemeMetrics.Node(w: w, frac: frac, passed: passed)
        }

        var next: (w: Double, toNext: Double, weeks: Int?)? = nil
        if let nx = nodes.first(where: { isLoss ? ($0.w < current - 0.05) : ($0.w > current + 0.05) }) {
            let toNext = abs(current - nx.w)
            let weeks = rateAbs >= 0.01 && movingTowardGoal ? max(1, Int((toNext / rateAbs).rounded())) : nil
            next = (nx.w, toNext, weeks)
        }

        let deficit = Int((rateAbs * ScienceEngine.kcalPerKg / 7).rounded())

        return IlerlemeMetrics(start: start, current: current, goal: goal, weeklyRate: weeklyRate,
                               isLoss: isLoss, pct: pct, remaining: remaining, nodes: nodes,
                               daysLeft: daysLeft, eta: eta, next: next, deficitPerDay: deficit)
    }
}

/// Aktif dönemin hedef yolculuğu.
struct IlerlemeMetrics {
    struct Node {
        let w: Double
        /// Yol üzerindeki konum (0 başlangıç … 1 hedef).
        let frac: Double
        let passed: Bool
    }

    let start: Double, current: Double, goal: Double
    let weeklyRate: Double          // işaretli kg/hafta (negatif = kaybediyor)
    let isLoss: Bool
    let pct: Double                 // 0...1
    let remaining: Double
    let nodes: [Node]
    let daysLeft: Int?
    let eta: Date?
    /// `weeks` nil → dönemin ritmi henüz oturmadı; süre tahmini uydurulmaz.
    let next: (w: Double, toNext: Double, weeks: Int?)?
    let deficitPerDay: Int

    var pctInt: Int { Int((pct * 100).rounded()) }

    /// "şimdi" düğmesinin tooltip'i: haftalık ritim + günlük açık/fazla.
    var rateHelp: String {
        guard abs(weeklyRate) >= 0.01 else { return "Ritim için dönemde en az 1 haftalık tartı gerekiyor." }
        let rate = "\(weeklyRate < 0 ? "−" : "+")\(Fmt.num(abs(weeklyRate), digits: 2)) kg/hafta"
        guard deficitPerDay > 0 else { return rate }
        return "\(rate) · günlük \(isLoss ? "−" : "+")\(Fmt.int(Double(deficitPerDay))) kalori \(isLoss ? "açık" : "fazla")"
    }

    /// Sıradaki durağın tooltip'i.
    var nextHelp: String? {
        guard let next else { return nil }
        let weeks = next.weeks.map { " · ~\($0) hafta" } ?? ""
        return "Sıradaki ara hedef \(Fmt.num(next.w, digits: 1)) kg · \(Fmt.num(next.toNext, digits: 1)) kg kaldı\(weeks)"
    }
}

// MARK: - Rota paneli

/// Dev yüzde + kalan kg / varış; altında başlangıç → hedef şeridi (ara duraklar yalnız nokta,
/// etiket yalnız başlangıç · şimdi · hedef).
private struct IlerlemeRotaPanel: View {
    let metrics: IlerlemeMetrics?
    let counter: String?
    let empty: (title: String, detail: String)

    var body: some View {
        RingsPanel(title: "Rota", sub: counter) { size in
            if let metrics {
                IlerlemeRotaDrawing(m: metrics, size: size)
            } else {
                VStack(spacing: 8) {
                    Text(empty.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(empty.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }
}

private struct IlerlemeRotaDrawing: View {
    let m: IlerlemeMetrics
    let size: CGSize

    /// Rakam bloğunun üstünden durak etiketlerinin altına kadar (tasarımda 236 → 663).
    private static let blockHeight: CGFloat = 427

    var body: some View {
        let tx0: CGFloat = 96
        let tx1 = size.width - 96
        // Blok panelde dikeyde ortalanır (tasarımda 866 pt panelde üst 236); başlığa taşmaz.
        let top = max(56, (size.height - Self.blockHeight) / 2 + 16)
        let ty = top + 380
        let x: (Double) -> CGFloat = { tx0 + (tx1 - tx0) * CGFloat(min(1, max(0, $0))) }
        let xNow = x(m.pct)
        let nextIndex = m.nodes.firstIndex { !$0.passed }
        let done = xNow - tx0
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Palette.textPrimary.opacity(0.07))
                .frame(width: max(0, tx1 - tx0), height: 14)
                .position(x: (tx0 + tx1) / 2, y: ty)
            if done >= 14 {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.chart.opacity(0.35))
                    .frame(width: done, height: 14)
                    .blur(radius: 10)
                    .position(x: tx0 + done / 2, y: ty)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.chart)
                    .frame(width: done, height: 14)
                    .position(x: tx0 + done / 2, y: ty)
            }
            ForEach(Array(m.nodes.enumerated()), id: \.offset) { i, node in
                if i > 0, i < m.nodes.count - 1, abs(x(node.frac) - xNow) >= 20 {
                    let isNext = i == nextIndex
                    Circle()
                        .fill(node.passed ? Palette.background.opacity(0.55)
                              : (isNext ? Palette.warning : Palette.textPrimary.opacity(0.3)))
                        .frame(width: isNext ? 9 : 7, height: isNext ? 9 : 7)
                        .position(x: x(node.frac), y: ty)
                    if isNext, let help = m.nextHelp {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: 28, height: 28)
                            .position(x: x(node.frac), y: ty)
                            .help(help)
                    }
                }
            }
            Circle()
                .fill(Palette.chart)
                .frame(width: 20, height: 20)
                .position(x: tx0, y: ty)
            ZStack {
                Circle()
                    .fill(Palette.background)
                    .overlay(Circle().stroke(Palette.warning, lineWidth: 2.5))
                    .frame(width: 30, height: 30)
                Lucide("target", size: 17)
                    .foregroundStyle(Palette.warning)
            }
            .position(x: tx1, y: ty)
            ZStack {
                Circle()
                    .fill(Palette.chart.opacity(0.22))
                    .frame(width: 48, height: 48)
                    .blur(radius: 8)
                Circle()
                    .fill(Palette.background)
                    .overlay(Circle().stroke(Palette.chart, lineWidth: 2.5))
                    .frame(width: 32, height: 32)
                Circle()
                    .fill(Palette.chart)
                    .frame(width: 11, height: 11)
            }
            .contentShape(Circle())
            .help(m.rateHelp)
            .position(x: xNow, y: ty)

            // Tasarımdaki 150 pt yüzdenin satır kutusu 85 pt'ye oturtulmuş: taban çizgisi
            // bloğun üstünden 95,8 pt aşağıda. SwiftUI metni kendi doğal boyunda (≈179 pt,
            // taban 142,8 pt) çizdiği için kutunun üstü 47 pt yukarıda başlar.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("%\(m.pctInt)")
                    .font(.system(size: 150, weight: .semibold).monospacedDigit())
                    .tracking(-5)
                    .foregroundStyle(Palette.textPrimary)
                Text("tamamlandı")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.textTertiary)
            }
            .lineLimit(1)
            .ringsPin(tx0 - 8, top - 47)
            VStack(alignment: .trailing, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.num(m.remaining, digits: 1))
                        .font(.system(size: 72, weight: .semibold).monospacedDigit())
                        .tracking(-2)
                        .foregroundStyle(Palette.textPrimary)
                    Text("kg kaldı")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.textTertiary)
                }
                if let eta = m.eta, let days = m.daysLeft {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.dateLong.string(from: eta))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Palette.warning)
                        Text("\(days) gün")
                            .font(.system(size: 14).monospacedDigit())
                            .foregroundStyle(Palette.textTertiary)
                    }
                } else {
                    Text(m.remaining <= 0.05 ? "hedeftesin" : "varış tahmini bekleniyor")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textTertiary)
                        .help(m.rateHelp)
                }
            }
            .lineLimit(1)
            .ringsPin(tx1 + 8, top + 16, .topTrailing)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.num(m.current, digits: 1))
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .tracking(-0.6)
                    .foregroundStyle(Palette.textPrimary)
                Text("kg")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
            .ringsPin(xNow, ty - 86, .top)
            Text(Fmt.num(m.start, digits: 1))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
                .ringsPin(tx0, ty + 30, .top)
            Text(abs(m.goal - m.goal.rounded()) < 0.05 ? Fmt.int(m.goal) : Fmt.num(m.goal, digits: 1))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.warning)
                .ringsPin(tx1, ty + 30, .top)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
