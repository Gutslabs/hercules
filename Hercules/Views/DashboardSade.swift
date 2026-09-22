import SwiftUI
import LucideKit

// MARK: - Genel Bakış · V3 "Sade"
//
// Tasarım: "Hercules Mac Tasarımı" tuvali ▸ Genel Bakış · V3 · Bugün B Halka (artboard
// 1829×1147; kart koordinatları tasarım betiği mac_genel_v3_bugun.py ile birebir). 2×2 eşit
// kart, her kartta tek soru ve tek görsel: Bugün (kalan kalori halkası) · Makrolar (üç hizalı
// çubuk) · Öğünler (saat · ad · kalori + günün payı) · Kilo (başlangıç → hedef göstergesi).
// Kabuk ve yerleşim DashboardRings.swift'ten: RingsPanel (18pt köşe, başlık (24, 20)) ve
// `ringsPin`. Tasarım ölçüsü 734×523; başka ölçüde konumlar kart boyundan türetilir.
// Tasarımdaki rgba(255,255,255,a) → `Palette.textPrimary.opacity(a)`.

// MARK: - İnce gösterge parçaları

/// Yuvarlak uçlu yatay çubuk; (x0, y) sol üst köşe. Genişlik en az boy kadar — çok küçük
/// değer de nokta olarak görünür.
private struct SadeBar: View {
    let x0: CGFloat
    let x1: CGFloat
    let y: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        let width = max(height, x1 - x0)
        Capsule()
            .fill(color)
            .frame(width: width, height: height)
            .position(x: x0 + width / 2, y: y + height / 2)
    }
}

/// Hedef çentiği: çubuğun 6pt üstünden 6pt altına dikey çizgi.
private struct SadeTick: View {
    let x: CGFloat
    let y: CGFloat
    let height: CGFloat

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: x, y: y - 6))
            p.addLine(to: CGPoint(x: x, y: y + height + 6))
        }
        .stroke(Palette.textPrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }
}

/// Kartın ortasında tek satırlık soluk not (veri yokken).
private struct SadeEmptyNote: View {
    let text: String
    let size: CGSize

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: max(0, size.width - 48))
            .position(x: size.width / 2, y: size.height / 2)
    }
}

// MARK: - 1 · Bugün (kalan kalori halkası)

struct DashboardTodayCard: View {
    struct Plan {
        let goal: Double
        let consumed: Double
    }

    /// "22 Eylül Salı"
    let dateLabel: String
    /// nil → hedef hesaplanamadı (profil / kilo eksik); halkanın yerine kısa açıklama.
    let plan: Plan?
    /// Bugünün adımı (HealthKit öncelikli); nil → kayıt yok.
    let steps: Int?
    var stepGoal: Int = 10_000
    var setupTitle: String = ""
    var setupDetail: String = ""

    var body: some View {
        RingsPanel(title: "Bugün", sub: dateLabel) { size in
            if let plan {
                DashboardTodayRing(size: size, plan: plan, steps: steps, stepGoal: stepGoal)
            } else {
                RingsSetupMessage(title: setupTitle, detail: setupDetail)
                    .frame(maxWidth: min(380, max(0, size.width - 48)))
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
    }
}

/// Tek halka: tepeden saat yönünde yenen (grafik rengi), hedefe kalan yay pirinç; ortada
/// kalan kalori, solda yenen, sağda hedef, altta adım. Hedef aşılınca halka dolar, aşım
/// kırmızı ikinci tur olur (Apple halka dili) ve ortadaki sayı kırmızı "fazla" okunur.
private struct DashboardTodayRing: View {
    let size: CGSize
    let plan: DashboardTodayCard.Plan
    let steps: Int?
    let stepGoal: Int

    private static let lineWidth: CGFloat = 14

    var body: some View {
        let lw = Self.lineWidth
        let c = CGPoint(x: size.width / 2, y: (size.height - 7) / 2)
        // Tasarım ölçüsünde 116; kısa/dar kartta başlığa, adım satırına ve yan sayılara çarpmaz.
        let r = max(40, min(116, c.y - 55, size.height - 95 - c.y, c.x - 142))
        let scale = r / 116
        let ratio = plan.goal > 0 ? plan.consumed / plan.goal : 0
        let remaining = plan.goal - plan.consumed
        // Yan sayıların merkezi: kart kenarıyla halkanın dış kenarı arasının ortası (+6).
        let side = (24 + c.x - r - lw) / 2 + 6
        ZStack(alignment: .topLeading) {
            ring(center: c, radius: r, ratio: ratio)
            VStack(spacing: 0) {
                Text(Fmt.int(abs(remaining)))
                    .font(.system(size: max(40, 64 * scale), weight: .semibold).monospacedDigit())
                    .tracking(-1.8 * scale)
                    .foregroundStyle(remaining < 0 ? Palette.negative : Palette.warning)
                    .contentTransition(.numericText())
                Text(remaining < 0 ? "fazla" : "kaldı")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textTertiary)
            }
            .ringsPin(c.x, c.y - 3.5, .center)
            stat(Fmt.int(plan.consumed), "yenen")
                .ringsPin(side, c.y + 0.5, .center)
            stat(Fmt.int(plan.goal), "hedef")
                .ringsPin(size.width - side, c.y + 0.5, .center)
            stepsLine
                .ringsPin(c.x, size.height - 76, .top)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(remaining))
    }

    @ViewBuilder
    private func ring(center c: CGPoint, radius r: CGFloat, ratio: Double) -> some View {
        let lw = Self.lineWidth
        RingsArc(center: c, radius: r, from: 0, to: 360)
            .stroke(Palette.textPrimary.opacity(0.08), lineWidth: lw)
        if ratio <= 1 {
            let a = 360 * max(0, ratio)
            // Kalan yay, yenen yayın ucunun 4° altından başlar: iki yuvarlak uç arasında boşluk kalmaz.
            RingsArc(center: c, radius: r, from: max(0, a - 4), to: 359.9)
                .stroke(Palette.warning.opacity(0.55), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            RingsArc(center: c, radius: r, from: 0, to: a)
                .stroke(Palette.chart.opacity(0.85), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        } else {
            let end = 360 * min(ratio - 1, 0.995)
            RingsArc(center: c, radius: r, from: 0, to: 360)
                .stroke(Palette.chart.opacity(0.85), lineWidth: lw)
            RingsTipShadow(point: ringsPoint(c, r, end), lineWidth: lw)
            RingsArc(center: c, radius: r, from: 0, to: end)
                .stroke(Palette.negative, style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .semibold).monospacedDigit())
                .tracking(-0.6)
                .foregroundStyle(Palette.textPrimary)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
        }
        .lineLimit(1)
    }

    private var stepsLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("adım")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
            Text(steps.map { Fmt.int(Double($0)) } ?? "—")
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(steps == nil ? Palette.textQuaternary : Palette.textPrimary)
            Text("/ \(Fmt.int(Double(stepGoal)))")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
        }
        .lineLimit(1)
    }

    private func accessibilityText(_ remaining: Double) -> String {
        var parts = ["\(Fmt.int(abs(remaining))) kalori \(remaining < 0 ? "fazla" : "kaldı")",
                     "\(Fmt.int(plan.consumed)) yenen", "hedef \(Fmt.int(plan.goal))"]
        if let steps { parts.append("\(Fmt.int(Double(steps))) adım") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - 2 · Makrolar (üç hizalı çubuk)

struct DashboardMacro: Identifiable {
    let name: String
    let consumed: Double
    let target: Double
    let color: Color

    var id: String { name }
    var progress: Double { target > 0 ? consumed / target : 0 }
}

struct DashboardMacrosCard: View {
    /// nil → plan hesaplanamadı, hedef yok.
    let macros: [DashboardMacro]?

    var body: some View {
        RingsPanel(title: "Makrolar", sub: "bugün") { size in
            if let macros {
                DashboardMacroRows(size: size, macros: macros)
            } else {
                SadeEmptyNote(text: "Hedefler plan hesaplanınca görünür", size: size)
            }
        }
    }
}

/// Satır: ad solda, "131 / 150 g" sağda, altında 10pt çubuk. Hedef çentikleri genişliğin
/// %80'inde (satırlar aynı hizada); hedefi aşan kısım kırmızı, en çok %125'e kadar çizilir.
private struct DashboardMacroRows: View {
    let size: CGSize
    let macros: [DashboardMacro]

    var body: some View {
        // Tasarım ölçüsünde satırlar 128 · 258 · 388; blok kartta dikeyde ortalı kalır.
        let step = min(130, max(64, (size.height - 133) / 3))
        let top = ((size.height - (2 * step + 36) + 29) / 2).rounded()
        ZStack(alignment: .topLeading) {
            ForEach(Array(macros.enumerated()), id: \.element.id) { index, macro in
                row(macro, y: top + CGFloat(index) * step)
            }
        }
    }

    @ViewBuilder
    private func row(_ macro: DashboardMacro, y: CGFloat) -> some View {
        let x0: CGFloat = 24
        let x1 = size.width - 24
        let h: CGFloat = 10
        let xt = x0 + (x1 - x0) * 0.8
        let barY = y + 26
        let fillEnd = x0 + (xt - x0) * CGFloat(min(macro.progress, 1.25))
        let over = macro.progress > 1
        Text(macro.name)
            .font(.system(size: 13))
            .foregroundStyle(Palette.textSecondary)
            .ringsPin(x0, y)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(Fmt.int(macro.consumed))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(over ? Palette.negative : Palette.textPrimary)
            Text("/ \(Fmt.int(macro.target)) g")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
        }
        .lineLimit(1)
        .ringsPin(x1, y - 1, .topTrailing)
        SadeBar(x0: x0, x1: x1, y: barY, height: h, color: Palette.textPrimary.opacity(0.08))
        if over {
            SadeBar(x0: xt - h, x1: fillEnd, y: barY, height: h, color: Palette.negative.opacity(0.85))
            SadeBar(x0: x0, x1: xt, y: barY, height: h, color: macro.color.opacity(0.9))
        } else if macro.consumed > 0 {
            SadeBar(x0: x0, x1: fillEnd, y: barY, height: h, color: macro.color.opacity(0.9))
        }
        SadeTick(x: xt, y: barY, height: h)
    }
}

// MARK: - 3 · Öğünler (saat · ad · kalori)

/// Ayrıntı hover'da (help), silme sağ tık menüsünde.
struct DashboardMealsCard: View {
    let meals: [RingsMeal]
    /// Günlük kalori hedefi — satır altındaki çizgi öğünün bu hedefteki payı.
    let goal: Double?
    var onDelete: (FoodEntry) -> Void = { _ in }

    var body: some View {
        RingsPanel(title: "Öğünler", sub: meals.isEmpty ? nil : "\(meals.count) öğün") { size in
            if meals.isEmpty {
                SadeEmptyNote(text: "Bugün kayıt yok", size: size)
            } else {
                DashboardMealList(size: size, meals: meals, goal: goal, onDelete: onDelete)
            }
        }
    }
}

/// Satırlar 78pt aralıkla; kart kısaysa aralık 52'ye kadar daralır, yine sığmazsa liste kayar.
private struct DashboardMealList: View {
    let size: CGSize
    let meals: [RingsMeal]
    let goal: Double?
    let onDelete: (FoodEntry) -> Void

    /// İlk satırın üst kenarı; satırın yazısı 12pt aşağıda (tasarımda 76).
    private static let top: CGFloat = 64

    var body: some View {
        let count = CGFloat(meals.count)
        // (count − 1) · aralık bu kadar yere sığmalı: son satırın çizgisi (48) + alt boşluk (12).
        let room = size.height - Self.top - 60
        let pitch = count > 1 ? min(78, max(52, room / (count - 1))) : 78
        let fits = (count - 1) * pitch <= room + 0.5
        let list = VStack(spacing: 0) {
            ForEach(meals) { meal in
                row(meal, pitch: pitch)
            }
        }
        Group {
            if fits {
                list
            } else {
                ScrollView(.vertical) { list.padding(.bottom, 12) }
            }
        }
        .frame(width: size.width, height: max(0, size.height - Self.top), alignment: .top)
        .padding(.top, Self.top)
    }

    private func row(_ meal: RingsMeal, pitch: CGFloat) -> some View {
        let w = size.width
        let denominator = max(1, goal ?? meals.reduce(0) { $0 + $1.calories })
        let share = CGFloat(min(1, max(0, meal.calories / denominator)))
        return ZStack(alignment: .topLeading) {
            Text(Fmt.timeShort.string(from: meal.date))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
                .ringsPin(24, 14)
            Text(meal.name)
                .font(.system(size: 14))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(0, w - 218), alignment: .leading)
                .ringsPin(84, 12)
            (Text("\(Fmt.int(meal.calories)) ")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
             + Text("kalori")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary))
                .lineLimit(1)
                .ringsPin(w - 24, 11, .topTrailing)
            SadeBar(x0: 84, x1: w - 24, y: 42, height: 6, color: Palette.textPrimary.opacity(0.08))
            SadeBar(x0: 84, x1: 84 + (w - 108) * share, y: 42, height: 6, color: Palette.chart.opacity(0.6))
        }
        .frame(width: w, height: pitch, alignment: .topLeading)
        .contentShape(Rectangle())
        .help(meal.helpText)
        .contextMenu { deleteMenu(meal) }
    }

    @ViewBuilder
    private func deleteMenu(_ meal: RingsMeal) -> some View {
        if meal.entries.count == 1, let entry = meal.entries.first {
            Button("Öğünü sil", role: .destructive) { onDelete(entry.model) }
        } else {
            ForEach(meal.entries) { entry in
                Button("Sil: \(entry.name)", role: .destructive) { onDelete(entry.model) }
            }
        }
    }
}

// MARK: - 4 · Kilo (başlangıç → hedef göstergesi)

struct DashboardWeightCard: View {
    struct Model {
        var current: Double?
        var goal: Double?
        /// Değişim (son − ilk) ve kapsadığı gün sayısı (son 30 gün; tartı azsa tüm seri).
        var delta: Double?
        var deltaDays: Int = 30
        /// Değişim hedef yönünde mi (çip rengi).
        var deltaIsGood: Bool = true
        /// Aktif dönemin başlangıç kilosu, kat edilen pay (0…1) ve varış — İlerleme ile aynı hesap.
        var start: Double?
        var progress: Double?
        var eta: Date?
    }

    let model: Model

    var body: some View {
        RingsPanel(title: "Kilo", sub: model.goal.map { "hedef \(Self.kg($0)) kg" }) { size in
            DashboardWeightDrawing(size: size, model: model)
        }
    }

    /// "78,0" → "78", "89,14" → "89,1".
    static func kg(_ value: Double) -> String {
        let text = Fmt.num(value, digits: 1)
        return text.hasSuffix(",0") ? String(text.dropLast(2)) : text
    }
}

private struct DashboardWeightDrawing: View {
    let size: CGSize
    let model: DashboardWeightCard.Model

    var body: some View {
        let x0: CGFloat = 24
        let x1 = size.width - 24
        // Tasarım ölçüsünde gösterge 300'de, varış bloğu alttan 120'de.
        let gaugeY = max(190, size.height - 223)
        ZStack(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.current.map { Fmt.num($0, digits: 1) } ?? "—")
                    .font(.system(size: 72, weight: .semibold).monospacedDigit())
                    .tracking(-2)
                    .foregroundStyle(model.current == nil ? Palette.textQuaternary : Palette.textPrimary)
                Text("kg")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textTertiary)
            }
            .lineLimit(1)
            .ringsPin(24, 48)
            if let delta = model.delta {
                deltaChip(delta).ringsPin(24, 146)
            }
            if let start = model.start, let progress = model.progress, let goal = model.goal {
                gauge(x0: x0, x1: x1, y: gaugeY, start: start, progress: progress, goal: goal)
            }
            if let eta = model.eta {
                Text("varış")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                    .ringsPin(24, size.height - 120)
                Text(Fmt.dateLong.string(from: eta))
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.warning)
                    .lineLimit(1)
                    .ringsPin(24, size.height - 100)
            }
        }
    }

    /// Başlangıç → hedef: dolum kat edilen yol, ucunda düğme; altta uç kiloları ve yüzde.
    @ViewBuilder
    private func gauge(x0: CGFloat, x1: CGFloat, y: CGFloat, start: Double, progress: Double, goal: Double) -> some View {
        let h: CGFloat = 12
        let xn = x0 + (x1 - x0) * CGFloat(min(1, max(0, progress)))
        SadeBar(x0: x0, x1: x1, y: y, height: h, color: Palette.textPrimary.opacity(0.08))
        SadeBar(x0: x0, x1: xn, y: y, height: h, color: Palette.chart.opacity(0.85))
        Circle()
            .fill(Palette.background)
            .frame(width: 22.5, height: 22.5)
            .overlay(Circle().strokeBorder(Palette.chart, lineWidth: 2.5))
            .position(x: xn, y: y + h / 2)
        label(DashboardWeightCard.kg(start), weight: .semibold, color: Palette.textSecondary)
            .ringsPin(x0, y + 24)
        label(DashboardWeightCard.kg(goal), weight: .semibold, color: Palette.warning)
            .ringsPin(x1, y + 24, .topTrailing)
        // Yüzde, uç etiketlerinin üstüne binecekse gösterilmez.
        if xn - x0 > 64, x1 - xn > 56 {
            label("%\(Int((progress * 100).rounded()))", weight: .regular, color: Palette.textTertiary)
                .ringsPin(xn, y + 24, .top)
        }
    }

    private func label(_ text: String, weight: Font.Weight, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: weight).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func deltaChip(_ delta: Double) -> some View {
        let tint = model.deltaIsGood ? Palette.positive : Palette.negative
        return HStack(spacing: 3) {
            Lucide(delta <= 0 ? "trending-down" : "trending-up", size: 13)
            Text("\(Fmt.num(abs(delta), digits: 1)) kg · \(model.deltaDays) gün")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.13)))
    }
}
