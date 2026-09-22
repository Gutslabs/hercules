import SwiftUI
import LucideKit

// MARK: - Analiz · "Sade"
//
// Tasarım: "Hercules Mac Tasarımı" tuvali ▸ Analiz · V3 Sade. Üstte tek Yakım panosu (gerçek
// yakım + ince gösterge: alım + açık), altta üç kart (Hız · Protein · Mikro). Her kart: bir
// büyük sayı + tek kelimelik durum + tek görsel + bir küçük gerçek. Yargı cümleleri hover'da (.help).
//
// `AnalizFlowView` SAF görünümdür: sorgu sonuçları + mikro besin durumu dışarıdan gelir.
// `MicroNutrientStore` gerçek `micronutrients.json`'u okur ve tur (ağ/AI) tetikleyebildiği için
// ona yalnız sayfa kabuğu (`AnalysisView`) dokunur; önizleme/test sahte durum verir.

/// Mikro besin kartının durumu (sayfa `MicroNutrientStore`'dan doldurur).
struct AnalizMicroState {
    /// Raporun TÜM besinleri (şiddete göre sıralı gelir; kart kendi sırasını kurar).
    var findings: [MicroFinding] = []
    /// Önbellekte en az bir tahmin var mı (düğme "Analizi çalıştır" / "Güncelle").
    var hasProfiles = false
    var isRunning = false
    var progress: (done: Int, total: Int)? = nil
    var lastError: String? = nil
    /// Henüz tahmin edilmemiş farklı yemek adı sayısı.
    var missing = 0
    /// "23 gün kaldı" gibi sıradaki tur metni.
    var cycleText: String? = nil
}

/// Sayfanın türetilmiş değerleri — gövde başına BİR kez hesaplanır.
struct AnalizModel {
    struct Nutrition {
        let kcal: Double, p: Double, c: Double, f: Double
        let days: Int
    }

    let goal: Goal
    let energy: ScienceEngine.AdaptiveEnergy?
    let staticTDEE: Double?
    let verdict: ScienceEngine.RateVerdict?
    let projection: ScienceEngine.GoalProjection?
    /// Protein g/kg için gövde ağırlığı: trend kilo, yoksa son tartı.
    let bodyWeight: Double?
    /// Son 14 günün (bugün 00:00 − 14 gün → şimdi) kayıtlı günlerinin ortalaması.
    let nutrition: Nutrition?
    /// Protein hedefi: kalori açığında ~2,0 g/kg, korumada ~1,6 (Morton 2018 bandı).
    let proteinTarget: Double

    init(measurements: [Measurement], foods: [FoodEntry], profile: UserProfile?,
         now: Date, calendar: Calendar = .current) {
        let goal = profile?.goal ?? .maintain
        self.goal = goal
        let energy = ScienceEngine.bestAdaptiveEnergy(measurements: measurements, foods: foods,
                                                      now: now, calendar: calendar)
        self.energy = energy
        let latestWeight = measurements.last(where: { $0.weight != nil })?.weight
        let latestBodyFat = measurements.last(where: { $0.bodyFat != nil })?.bodyFat
        bodyWeight = energy?.trendWeightNow ?? latestWeight
        if let p = profile, let w = latestWeight {
            staticTDEE = CalorieCalculator.compute(
                weight: w, height: p.height, age: p.age, sex: p.sex,
                bodyFat: latestBodyFat ?? p.manualBodyFat,
                activity: p.activity, goal: p.goal
            ).tdee
        } else {
            staticTDEE = nil
        }
        verdict = energy.map { ScienceEngine.rateVerdict(percentPerWeek: $0.ratePercentPerWeek, goal: goal) }
        projection = energy.flatMap {
            ScienceEngine.goalProjection(energy: $0, targetWeight: profile?.targetWeight, now: now, calendar: calendar)
        }

        // Beslenme penceresi eski kartla aynı: bugün 00:00 − 14 gün → (üst sınır yok).
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -14, to: today) ?? today
        var days: [Date: (kcal: Double, p: Double, c: Double, f: Double)] = [:]
        for entry in foods where entry.date >= from {
            let key = calendar.startOfDay(for: entry.date)
            var t = days[key] ?? (0, 0, 0, 0)
            t.kcal += entry.calories
            t.p += entry.protein ?? 0
            t.c += entry.carbs ?? 0
            t.f += entry.fat ?? 0
            days[key] = t
        }
        if days.isEmpty {
            nutrition = nil
        } else {
            let n = Double(days.count)
            nutrition = Nutrition(
                kcal: days.values.reduce(0) { $0 + $1.kcal } / n,
                p: days.values.reduce(0) { $0 + $1.p } / n,
                c: days.values.reduce(0) { $0 + $1.c } / n,
                f: days.values.reduce(0) { $0 + $1.f } / n,
                days: days.count
            )
        }
        proteinTarget = goal.calorieAdjustment < 0 ? 2.0 : 1.6
    }

    /// Eski TDEE kartının yargı cümlesi — artık yakım göstergesinin tooltip'i.
    var tdeeAnswer: String? {
        guard let energy, let s = staticTDEE else { return energy?.confidence.detail }
        let diff = energy.adaptiveTDEE - s
        if abs(diff) < 25 { return "Formül tahminiyle örtüşüyor." }
        return "Formülün dediğinden \(Fmt.int(abs(diff))) kalori daha \(diff < 0 ? "az" : "fazla")."
    }
}

// MARK: - Sayfa

/// Analiz sayfasının saf görünümü. Genişte Yakım üstte, üç kart altta yan yana; dar pencerede
/// kartlar alt alta dizilir ve sayfa kayar.
struct AnalizFlowView: View {
    let measurements: [Measurement]
    let foods: [FoodEntry]
    let profile: UserProfile?
    var micro = AnalizMicroState()
    var onMicroRefresh: () -> Void = {}
    var now: Date = .now

    var body: some View {
        let model = AnalizModel(measurements: measurements, foods: foods, profile: profile, now: now)
        GeometryReader { proxy in
            ScrollView {
                AnalizFlowLayout(model: model, micro: micro, onMicroRefresh: onMicroRefresh, size: proxy.size)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct AnalizFlowLayout: View {
    let model: AnalizModel
    let micro: AnalizMicroState
    let onMicroRefresh: () -> Void
    let size: CGSize

    var body: some View {
        let innerW = max(320, size.width - 48)
        if size.width >= 960 {
            // Tasarım oranları (1.493 × 1.070 iç alan): Yakım 360 · kartlar 686, aralık 24.
            // Kısa pencerede taban 900 → sayfa kayar.
            let flex = max(size.height - 36, 900) - 24
            let h1 = (flex * 360 / 1046).rounded()
            VStack(spacing: 24) {
                AnalizYakimPanel(model: model)
                    .frame(height: h1)
                HStack(spacing: 24) {
                    AnalizHizCard(model: model)
                    AnalizProteinCard(model: model)
                    AnalizMikroCard(micro: micro, onRefresh: onMicroRefresh)
                }
                .frame(height: flex - h1)
            }
            .frame(width: innerW)
        } else {
            VStack(spacing: 18) {
                AnalizYakimPanel(model: model).frame(height: 340)
                AnalizHizCard(model: model).frame(height: 540)
                AnalizProteinCard(model: model).frame(height: 540)
                AnalizMikroCard(micro: micro, onRefresh: onMicroRefresh).frame(height: 540)
            }
            .frame(width: innerW)
        }
    }
}

// MARK: - Ortak parçalar

private extension View {
    /// Tasarımın mutlak yerleşimi: (x, y) görünümün ÜST kenarı; yatay hiza `alignment` ile
    /// (.top = x'te ortalı, .topTrailing = sağ kenar x'te, .leading = dikeyde y'de ortalı).
    func analizPin(_ x: CGFloat, _ y: CGFloat, _ alignment: Alignment = .topLeading) -> some View {
        fixedSize()
            .frame(width: 0, height: 0, alignment: alignment)
            .position(x: x, y: y)
    }
}

/// Panel kabuğu: 18pt köşe, yarı saydam yüzey, kırpılmış; başlık (24, 20)'de.
private struct AnalizPanel<Content: View>: View {
    let title: String
    var sub: String? = nil
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                content(geo.size)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                AnalizTitle(title: title, sub: sub)
                    .analizPin(24, 20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.surface.opacity(0.55))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AnalizTitle: View {
    let title: String
    let sub: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            if let sub {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .lineLimit(1)
    }
}

/// Büyük sayı + taban çizgisine hizalı küçük birim.
private struct AnalizBig: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 56
    var tracking: CGFloat = -1.4
    var color: Color = Palette.textPrimary
    var unitSize: CGFloat = 14

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .tracking(tracking)
                .foregroundStyle(color)
            if let unit {
                Text(unit)
                    .font(.system(size: unitSize))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .lineLimit(1)
    }
}

private struct AnalizChip<Label: View>: View {
    let tint: Color
    @ViewBuilder var label: () -> Label

    var body: some View {
        HStack(spacing: 3) { label() }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.13))
            )
    }
}

private struct AnalizEmptyNote: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.warning)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Kartın alt bloğu: soluk etiket + büyük değer (+ isteğe bağlı ek) + soluk alt satır.
private struct AnalizFootnote<Value: View>: View {
    let label: String
    var sub: String? = nil
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
            value()
            if let sub {
                Text(sub)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .lineLimit(1)
    }
}

/// Aşağı bakan üçgen işaretçi.
private struct AnalizTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// Tasarımdaki tipografik eksi: "−0,25" / "+0,25" / "0,00".
private func analizSigned(_ v: Double, digits: Int) -> String {
    let body = Fmt.num(abs(v), digits: digits)
    if body == Fmt.num(0, digits: digits) { return body }
    return (v < 0 ? "−" : "+") + body
}

private func analizTone(_ t: ScienceEngine.RateTone) -> Color {
    switch t {
    case .good:    return Palette.positive
    case .warn:    return Palette.warning
    case .bad:     return Palette.negative
    case .neutral: return Palette.textTertiary
    }
}

/// Hız yargısının çipteki tek kelimelik hâli (tam cümle çipin tooltip'inde).
private func analizRateWord(_ label: String) -> String {
    switch label {
    case "Çok hızlı kayıp":   return "çok hızlı"
    case "Sağlıklı kayıp":    return "ideal"
    case "Yavaş kayıp":       return "yavaş"
    case "Stabil (bakım)":    return "stabil"
    case "Plato / ters yön":  return "plato"
    case "Lean bulk aralığı": return "lean bulk"
    case "Hafif kilo alımı":  return "hafif alım"
    case "Hızlı kilo alımı":  return "hızlı alım"
    default:                  return label.lowercased(with: Locale(identifier: "tr_TR"))
    }
}

// MARK: - 1 · Yakım (gerçek TDEE)

private struct AnalizYakimPanel: View {
    let model: AnalizModel

    var body: some View {
        AnalizPanel(title: "Yakım", sub: model.energy.map { "son \($0.windowDays) gün" }) { size in
            if let energy = model.energy {
                AnalizYakimContent(model: model, energy: energy, size: size)
            } else {
                AnalizEmptyNote(title: "Henüz hesaplanamıyor",
                                detail: "≥10 günü kapsayan 2+ tartı ve 7+ kayıtlı yemek günü gerekiyor.")
            }
        }
    }
}

private struct AnalizYakimContent: View {
    let model: AnalizModel
    let energy: ScienceEngine.AdaptiveEnergy
    let size: CGSize

    var body: some View {
        let balance = energy.dailyBalanceVsMaintenance        // negatif = açık
        let tint = balance <= 0 ? Palette.positive : Palette.negative
        ZStack(alignment: .topLeading) {
            AnalizConfidenceBadge(confidence: energy.confidence)
                .analizPin(size.width - 24, 21, .topTrailing)
            AnalizBig(value: Fmt.int(energy.adaptiveTDEE), unit: "kalori/gün", size: 72, tracking: -2, unitSize: 15)
                .analizPin(24, 48)
            AnalizChip(tint: tint) {
                Lucide(balance <= 0 ? "trending-down" : "trending-up", size: 13)
                Text("\(analizSigned(balance, digits: 0)) kalori/gün")
            }
            .help(balance <= 0 ? "Yaktığından az yiyorsun: günlük açık." : "Yaktığından fazla yiyorsun: günlük fazla.")
            .analizPin(24, 146)
            AnalizEnergyGauge(intake: energy.avgIntake, burn: energy.adaptiveTDEE, formula: model.staticTDEE,
                              formulaHelp: model.tdeeAnswer, loggedDays: energy.loggedDays,
                              windowDays: energy.windowDays, width: size.width,
                              y: max(190, size.height - 110))
        }
    }
}

private struct AnalizConfidenceBadge: View {
    let confidence: ScienceEngine.AdaptiveEnergy.Confidence

    var body: some View {
        let color: Color = confidence == .high ? Palette.positive
            : (confidence == .medium ? Palette.warning : Palette.textTertiary)
        let level = confidence == .high ? 3 : (confidence == .medium ? 2 : 1)
        HStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(i < level ? color : Palette.textPrimary.opacity(0.14))
                        .frame(width: 3.6, height: 12 * CGFloat(i + 1) / 3)
                }
            }
            .frame(height: 12, alignment: .bottom)
            Text("güven")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(color)
        }
        .help("\(confidence.label) — \(confidence.detail)")
    }
}

/// Protein ölçeğiyle aynı dil: ince kapsül ray (0 → ölçek tavanı), dolum = alım, alımdan yakıma
/// yeşil "açık" parçası (alım yakımı aşarsa kırmızı "fazla"), yakımda çentik; etiketler altta.
/// Formül karşılaştırması tooltip'te.
private struct AnalizEnergyGauge: View {
    let intake: Double
    let burn: Double
    let formula: Double?
    let formulaHelp: String?
    let loggedDays: Int
    let windowDays: Int
    let width: CGFloat
    /// Rayın üst kenarı (tasarımda 360 pt panelde 250).
    let y: CGFloat

    private let height: CGFloat = 12

    var body: some View {
        let x0: CGFloat = 24
        let x1 = width - 24
        // Ölçek tavanı: büyük değerin %12 fazlası, 250'ye yuvarlı (tasarımda 3.000).
        let top = (max(burn, intake, 1) * 1.12 / 250).rounded(.up) * 250
        let x: (Double) -> CGFloat = { x0 + (x1 - x0) * CGFloat($0 / top) }
        let deficit = intake <= burn
        let tint = deficit ? Palette.positive : Palette.negative
        let lo = min(intake, burn), hi = max(intake, burn)
        let mid = y + height / 2
        let help = [formula.map { "Formül tahmini \(Fmt.int($0)) kalori" }, formulaHelp,
                    "Ortalama alım · son \(windowDays) günde \(loggedDays) kayıtlı gün",
                    "Günlük \(Fmt.int(abs(burn - intake))) kalori \(deficit ? "açık" : "fazla")"]
            .compactMap { $0 }.joined(separator: " · ")
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Palette.textPrimary.opacity(0.08))
                .frame(width: max(0, x1 - x0), height: height)
                .position(x: (x0 + x1) / 2, y: mid)
            Capsule()
                .fill(tint.opacity(0.55))
                .frame(width: max(height, x(hi) - x(lo) + height), height: height)
                .position(x: (x(lo) - height + x(hi)) / 2, y: mid)
            Capsule()
                .fill(Palette.chart.opacity(0.85))
                .frame(width: max(height, x(lo) - x0), height: height)
                .position(x: x0 + max(height, x(lo) - x0) / 2, y: mid)
            Capsule()
                .fill(Palette.textPrimary)
                .frame(width: 2.5, height: height + 12)
                .position(x: x(burn), y: mid)
            label("alım", intake).analizPin(x(intake), y + height + 12, .top)
            label("yakım", burn).analizPin(x(burn), y + height + 12, .top)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: max(0, x1 - x0), height: 44)
                .position(x: (x0 + x1) / 2, y: mid + 8)
                .help(help)
        }
    }

    private func label(_ name: String, _ value: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name)
                .foregroundStyle(Palette.textSecondary)
            Text(Fmt.int(value))
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textPrimary)
        }
        .font(.system(size: 11.5).monospacedDigit())
        .lineLimit(1)
    }
}

// MARK: - 2 · Hız

private struct AnalizHizCard: View {
    let model: AnalizModel

    var body: some View {
        AnalizPanel(title: "Hız", sub: "haftalık") { size in
            if let energy = model.energy, let verdict = model.verdict {
                let rate = energy.ratePercentPerWeek
                ZStack(alignment: .topLeading) {
                    AnalizBig(value: analizSigned(rate, digits: 2), unit: "%/hafta")
                        .analizPin(24, 48)
                    AnalizChip(tint: analizTone(verdict.tone)) {
                        Text(analizRateWord(verdict.label))
                    }
                    .help("\(verdict.label) — \(verdict.note)")
                    .analizPin(24, 128)
                    AnalizRateBand(goal: model.goal, rate: rate, left: 24, right: size.width - 24, y: 262)
                    eta(size)
                        .analizPin(24, size.height - 156)
                }
            } else {
                AnalizEmptyNote(title: "Henüz hesaplanamıyor",
                                detail: "Hız, gerçek yakım hesabıyla birlikte gelir.")
            }
        }
    }

    @ViewBuilder
    private func eta(_ size: CGSize) -> some View {
        if let p = model.projection, p.movingToward, let date = p.etaDate, let days = p.etaDays {
            AnalizFootnote(label: "varış", sub: "\(days) gün") {
                Text(Fmt.dateLong.string(from: date))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.warning)
            }
            .help("Hedef \(Fmt.num(p.targetWeight, digits: 1)) kg · \(Fmt.num(abs(p.kgToGo), digits: 1)) kg kaldı")
        } else if let p = model.projection {
            AnalizFootnote(label: "varış", sub: "trend hedefe gitmiyor") {
                Text("—")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .help("Hedef \(Fmt.num(p.targetWeight, digits: 1)) kg · \(Fmt.num(abs(p.kgToGo), digits: 1)) kg")
        } else {
            AnalizFootnote(label: "varış", sub: "Profil'de hedef kilo yok") {
                Text("—")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// Hedefe göre üç bölgeli hız bandı; eşikler `ScienceEngine.rateVerdict` ile aynı.
private struct AnalizRateBand: View {
    let goal: Goal
    let rate: Double
    let left: CGFloat
    let right: CGFloat
    let y: CGFloat

    private struct Zone {
        let from: Double
        let to: Double
        let color: Color
        let label: String
        let ideal: Bool
    }

    private var config: (zones: [Zone], lo: Double, hi: Double, value: Double) {
        let off = Palette.textPrimary.opacity(0.12)
        let ideal = Palette.positive.opacity(0.7)
        let hot = Palette.negative.opacity(0.5)
        switch goal {
        case .lose, .loseFast:
            // Kayıp pozitif okunur: 0…1,5 %/hafta — yavaş <0,35 · ideal 0,35–1 · hızlı >1.
            return ([Zone(from: 0, to: 0.35, color: off, label: "yavaş", ideal: false),
                     Zone(from: 0.35, to: 1.0, color: ideal, label: "ideal", ideal: true),
                     Zone(from: 1.0, to: 1.5, color: hot, label: "hızlı", ideal: false)], 0, 1.5, -rate)
        case .gain, .gainFast:
            return ([Zone(from: 0, to: 0.1, color: off, label: "yavaş", ideal: false),
                     Zone(from: 0.1, to: 0.5, color: ideal, label: "ideal", ideal: true),
                     Zone(from: 0.5, to: 0.75, color: hot, label: "hızlı", ideal: false)], 0, 0.75, rate)
        case .maintain:
            return ([Zone(from: -0.6, to: -0.1, color: hot, label: "veriyor", ideal: false),
                     Zone(from: -0.1, to: 0.1, color: ideal, label: "stabil", ideal: true),
                     Zone(from: 0.1, to: 0.6, color: hot, label: "alıyor", ideal: false)], -0.6, 0.6, rate)
        }
    }

    var body: some View {
        let c = config
        let x: (Double) -> CGFloat = { v in
            left + (right - left) * CGFloat((min(c.hi, max(c.lo, v)) - c.lo) / (c.hi - c.lo))
        }
        let marker = x(c.value)
        ZStack(alignment: .topLeading) {
            ForEach(Array(c.zones.enumerated()), id: \.offset) { i, zone in
                let x0 = x(zone.from) + (i == 0 ? 0 : 1)
                let x1 = x(zone.to) - (i == c.zones.count - 1 ? 0 : 1)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(zone.color)
                    .frame(width: max(0, x1 - x0), height: 12)
                    .position(x: (x0 + x1) / 2, y: y + 6)
                Text(zone.label)
                    .font(.system(size: 11.5, weight: zone.ideal ? .semibold : .regular))
                    .foregroundStyle(zone.ideal ? Palette.positive : Palette.textTertiary)
                    .analizPin((x(zone.from) + x(zone.to)) / 2, y + 20, .top)
            }
            AnalizTriangle()
                .fill(Palette.textPrimary)
                .frame(width: 14, height: 11)
                .position(x: marker, y: y - 6.5)
            Rectangle()
                .fill(Palette.textPrimary)
                .frame(width: 2, height: 14)
                .position(x: marker, y: y + 6)
        }
    }
}

// MARK: - 3 · Protein

private struct AnalizProteinCard: View {
    let model: AnalizModel

    var body: some View {
        AnalizPanel(title: "Protein", sub: "son 14 gün") { size in
            if let n = model.nutrition, let bw = model.bodyWeight, bw > 0 {
                let perKg = n.p / bw
                let target = model.proteinTarget
                let short = perKg < target
                let gap = (target - perKg) * bw
                let tint = short ? Palette.warning : Palette.positive
                let gl: CGFloat = 24
                let gr = size.width - 24
                let gx: (Double) -> CGFloat = { gl + (gr - gl) * CGFloat(min(2.4, max(0, $0)) / 2.4) }
                ZStack(alignment: .topLeading) {
                    AnalizBig(value: Fmt.num(perKg, digits: 2), unit: "g/kg")
                        .analizPin(24, 48)
                    AnalizChip(tint: tint) {
                        if short {
                            Lucide("trending-up", size: 13)
                            Text("+\(Fmt.int(gap)) g/gün")
                        } else {
                            Lucide(sf: "checkmark", size: 11)
                            Text("yeterli")
                        }
                    }
                    .help(short
                          ? "Protein hedefin altında: günde ~\(Fmt.int(gap)) g daha (\(Fmt.num(perKg, digits: 2)) / \(Fmt.num(target, digits: 1)) g/kg)."
                          : "Protein yeterli — kas koruması güvende.")
                    .analizPin(24, 128)
                    Capsule()
                        .fill(Palette.textPrimary.opacity(0.08))
                        .frame(width: max(0, gr - gl), height: 12)
                        .position(x: (gl + gr) / 2, y: 268)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(12, gx(perKg) - gl), height: 12)
                        .position(x: gl + max(12, gx(perKg) - gl) / 2, y: 268)
                    Capsule()
                        .fill(Palette.textPrimary)
                        .frame(width: 2.5, height: 24)
                        .position(x: gx(target), y: 268)
                    Text("hedef \(Fmt.num(target, digits: 1))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                        .analizPin(gx(target), 286, .top)
                    AnalizFootnote(label: "günlük") {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(Fmt.int(n.p)) g")
                                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.textPrimary)
                            Text("/ \(Fmt.int(target * bw)) g")
                                .font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .analizPin(24, size.height - 156)
                }
            } else {
                AnalizEmptyNote(title: "Kayıt yok", detail: "Son 14 günün yemek ve kilo kaydı gerekiyor.")
            }
        }
    }
}

// MARK: - 4 · Mikro (yalnız dikkat gerektirenler)

private struct AnalizMikroCard: View {
    let micro: AnalizMicroState
    let onRefresh: () -> Void

    var body: some View {
        AnalizPanel(title: "Mikro", sub: "son 30 gün") { size in
            ZStack(alignment: .topLeading) {
                let highs = micro.findings.filter { $0.status == .high }
                let lows = micro.findings.filter { $0.status == .low }.sorted { $0.percent < $1.percent }
                if micro.findings.isEmpty {
                    AnalizEmptyNote(title: micro.isRunning ? "Tahmin ediliyor" : "Henüz tahmin yok",
                                    detail: emptyDetail)
                } else if highs.isEmpty && lows.isEmpty {
                    AnalizBig(value: "0", unit: "dikkat")
                        .analizPin(24, 48)
                    Text("Belirgin eksik yok — 30 günlük ortalama hedeflerin üstünde.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.positive)
                        .analizPin(24, 130)
                } else {
                    AnalizBig(value: "\(highs.count + lows.count)", unit: "dikkat")
                        .analizPin(24, 48)
                    HStack(spacing: 8) {
                        if !lows.isEmpty {
                            AnalizChip(tint: Palette.warning) { Text("\(lows.count) düşük") }
                        }
                        if !highs.isEmpty {
                            AnalizChip(tint: Palette.negative) { Text("\(highs.count) yüksek") }
                        }
                    }
                    .analizPin(24, 128)
                    let rows = Array((highs + lows).prefix(4))
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, f in
                        row(f, y: 236 + CGFloat(i) * 62, width: size.width)
                    }
                }
                header.analizPin(size.width - 18, 14, .topTrailing)
            }
        }
    }

    private var emptyDetail: String {
        if micro.isRunning, let p = micro.progress { return "\(p.done)/\(p.total) isim" }
        if let err = micro.lastError { return "Son turda hata: \(err)" }
        if micro.hasProfiles { return "Son 30 günde gramı girilmiş yemek kaydı yok." }
        return "“Analizi çalıştır” ile yemek adların 100 g başına vitamin/mineral tahminine çevrilir."
    }

    private func row(_ f: MicroFinding, y: CGFloat, width: CGFloat) -> some View {
        let tint = f.status == .high ? Palette.negative : Palette.warning
        let x0: CGFloat = 24
        let x1 = width - 24
        let bx: (Double) -> CGFloat = { x0 + (x1 - x0) * CGFloat(min(200, max(0, $0)) / 200) }
        return ZStack(alignment: .topLeading) {
            Text(f.nutrient.label)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .analizPin(x0, y)
            Text("%\(Int(f.percent.rounded()))")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
                .analizPin(x1, y - 1, .topTrailing)
            Capsule()
                .fill(Palette.textPrimary.opacity(0.08))
                .frame(width: max(0, x1 - x0), height: 6)
                .position(x: (x0 + x1) / 2, y: y + 27)
            Capsule()
                .fill(tint.opacity(0.85))
                .frame(width: max(6, bx(f.percent) - x0), height: 6)
                .position(x: x0 + max(6, bx(f.percent) - x0) / 2, y: y + 27)
            Rectangle()
                .fill(Palette.textPrimary.opacity(0.6))
                .frame(width: 1.5, height: 16)
                .position(x: bx(100), y: y + 27)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: max(0, x1 - x0), height: 44)
                .position(x: (x0 + x1) / 2, y: y + 16)
                .help("\(f.nutrient.label): ort. \(Fmt.num(f.average, digits: 1)) \(f.nutrient.unit)/gün · hedef \(Fmt.num(f.target, digits: 1)) \(f.nutrient.unit)")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if micro.isRunning, !micro.findings.isEmpty {
                Text(micro.progress.map { "tahmin ediliyor · \($0.done)/\($0.total)" } ?? "tahmin ediliyor…")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
            } else if let err = micro.lastError, !micro.findings.isEmpty {
                Text("Hata: \(err)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.negative)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .trailing)
            }
            Button(action: onRefresh) {
                HStack(spacing: 5) {
                    Lucide(sf: micro.isRunning ? "hourglass" : "sparkles", size: 11)
                    Text(micro.isRunning ? "Çalışıyor…" : (micro.hasProfiles ? "Güncelle" : "Analizi çalıştır"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .flatButtonChrome(cornerRadius: 8)
            }
            .buttonStyle(.plain)
            .disabled(micro.isRunning)
            .help(helpText)
        }
    }

    private var helpText: String {
        var parts = [micro.missing > 0 ? "\(micro.missing) yeni yemek adı tahmin edilecek"
                                       : "Tüm isimler tahmin edildi — yeniden hesaplar"]
        if let cycle = micro.cycleText { parts.append("sıradaki tur: \(cycle)") }
        return parts.joined(separator: " · ")
    }
}
