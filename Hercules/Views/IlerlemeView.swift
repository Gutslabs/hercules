import SwiftUI
import SwiftData

/// İlerleme (Progress) — hedefe doğru tek sakin odak: halka + rota + özet.
/// Tasarım: kullanıcının React mockup'ı; renkler Hercules Palette'i (light/dark uyumlu).
/// Yeşil accent rolü = `Palette.chart` (grafik/halka token'ı; kullanıcının seçtiği tint).
/// Veri gerçek: Measurement (kilo) + UserProfile.targetWeight; haftalık ritim TrendAnalysis
/// regresyonundan (app'in geri kalanıyla tutarlı). Kilo verme VE alma yönünü destekler.
struct IlerlemeView: View {
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .padding(.horizontal, 52)
                    .padding(.top, 34)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
        .background(Palette.background.ignoresSafeArea())
    }

    @ViewBuilder private var content: some View {
        let m = metrics
        VStack(alignment: .leading, spacing: 0) {
            header(m)
            if let m {
                Spacer(minLength: 28)
                hero(m).frame(maxWidth: .infinity)
                Spacer(minLength: 28)
                route(m).padding(.top, 4)
                summary(m).padding(.top, 18)
            } else {
                Spacer(minLength: 0)
                emptyState.frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder private func header(_ m: Metrics?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                eyebrow("Takip")
                Text("İlerleme")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            if let m {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(Palette.chart).frame(width: 6, height: 6)
                        eyebrow("Hedef")
                        Text("\(Fmt.num(m.goal, digits: 1)) kg")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .monospacedDigit()
                    }
                    Text("\(m.isLoss ? "Kilo verme" : "Kilo alma")\(m.planMonths.map { " · ~\($0) aylık plan" } ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    // MARK: - Hero (halka + istatistikler)

    private func hero(_ m: Metrics) -> some View {
        VStack(spacing: 34) {
            ZStack {
                Circle().stroke(Palette.track, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: m.pct)
                    .stroke(Palette.chart, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    eyebrow("Hedefe kalan", tracking: 1.3)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.num(m.remaining, digits: 1))
                            .font(.system(size: 64, weight: .semibold))
                            .tracking(-1.6)
                            .foregroundStyle(Palette.textPrimary)
                            .monospacedDigit()
                        Text("kg")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.top, 12)
                    Text("%\(m.pctInt) tamamlandı")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.chart)
                        .padding(.top, 14)
                }
            }
            .frame(width: 228, height: 228)

            HStack(spacing: 0) {
                stat("\(daysSinceStart) gün", startLabel)
                statDivider
                stat(m.daysLeft.map { "\($0)" } ?? "—", "gün kaldı")
                statDivider
                stat(m.etaStr ?? "—", "tahmini bitiş")
                statDivider
                stat(m.rateStr, "haftalık ritim")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 36)
    }

    private var statDivider: some View {
        Rectangle().fill(Palette.border).frame(width: 1, height: 30)
    }

    // MARK: - Rota (hedef yolu)

    private func route(_ m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Divider().overlay(Palette.border)
                eyebrow("Hedef rotası").padding(.top, 20)
            }
            GeometryReader { g in
                let w = g.size.width
                let lineY: CGFloat = 39
                let nowX = min(max(34, w * m.pct), w - 34)
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Palette.track)
                        .frame(width: w, height: 2).position(x: w / 2, y: lineY)
                    Capsule().fill(Palette.chart)
                        .frame(width: max(0, w * m.pct), height: 2)
                        .position(x: (w * m.pct) / 2, y: lineY)

                    ForEach(m.nodes) { n in
                        Circle()
                            .fill(n.passed ? Palette.chart : Palette.background)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(n.passed ? Color.clear : Palette.borderStrong, lineWidth: 1.5))
                            .position(x: w * n.frac, y: lineY)
                        if n.isEnd {
                            Text(Fmt.num(n.w, digits: 1))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                                .monospacedDigit()
                                .fixedSize()
                                .position(x: w * n.frac, y: lineY + 24)
                        }
                    }

                    Text("ŞİMDİ")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(Palette.chart)
                        .fixedSize()
                        .position(x: nowX, y: 10)
                    // Mevcut kilo — uçlardaki (93,0 / 78,0) etiketlerle aynı satırda, accent vurgulu.
                    Text("\(Fmt.num(m.current, digits: 1)) kg")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.chart)
                        .monospacedDigit()
                        .fixedSize()
                        .position(x: nowX, y: lineY + 24)

                    Circle()
                        .fill(Palette.chart)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Palette.background, lineWidth: 3))
                        .shadow(color: Palette.chart.opacity(0.55), radius: 7)
                        .position(x: w * m.pct, y: lineY)
                }
                .frame(width: w, height: 84)
            }
            .frame(height: 84)
            .padding(.horizontal, 30)
            .padding(.top, 2)
        }
    }

    // MARK: - Özet

    private func summary(_ m: Metrics) -> some View {
        HStack(alignment: .center) {
            if let next = m.next {
                HStack(spacing: 0) {
                    Text("Sıradaki ")
                        .foregroundStyle(Palette.textSecondary)
                    Text("\(Fmt.num(next.w, digits: 1)) kg")
                        .foregroundStyle(Palette.textPrimary).fontWeight(.semibold)
                    Text(" · \(Fmt.num(next.toNext, digits: 1)) kg, ~\(next.weeks) hafta")
                        .foregroundStyle(Palette.textSecondary)
                }
                .font(.system(size: 13))
                .monospacedDigit()
            } else {
                Text("Hedefe ulaştın 🎯")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if m.deficitPerDay > 0 {
                HStack(spacing: 0) {
                    Text("\(m.isLoss ? "−" : "+")\(Fmt.int(Double(m.deficitPerDay))) kcal/gün")
                        .foregroundStyle(Palette.chart)
                    Text(m.isLoss ? " açık" : " fazla")
                        .foregroundStyle(Palette.textTertiary)
                }
                .font(.system(size: 13))
                .monospacedDigit()
            }
        }
        .padding(.top, 18)
        .overlay(alignment: .top) { Divider().overlay(Palette.border) }
    }

    // MARK: - Boş durum

    private var emptyState: some View {
        VStack(spacing: 12) {
            eyebrow(profile?.targetWeight == nil ? "Hedef gerekli" : "Veri gerekli", tracking: 1.3)
            Text(profile?.targetWeight == nil
                 ? "Hedef kilonu belirle"
                 : "Henüz kilo verisi yok")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(profile?.targetWeight == nil
                 ? "Profil'den hedef kilonu gir; ilerlemeni buradan tek bakışta izle."
                 : "Ölçümler'den kilonu gir. Birkaç ölçüm sonrası ritim oturunca tahmini bitiş de gelir.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 40)
    }

    private func eyebrow(_ text: String, tracking: CGFloat = 1.1) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(tracking)
            .foregroundStyle(Palette.textTertiary)
    }

    // MARK: - Başlangıç (sabit: 18 Mayıs)

    /// Programın sabit başlangıç tarihi — kullanıcının cut başlangıcı: 18 Mayıs 2026.
    /// Geçen gün buradan sayılır (yeni bir döneme geçilirse burayı güncelle).
    private var startDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 18)) ?? Date()
    }

    /// 18 Mayıs'tan bugüne geçen tam takvim günü.
    private var daysSinceStart: Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: startDate)
        let to = cal.startOfDay(for: Date())
        return max(0, cal.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// İstatistik etiketi: "18 Mayıs'tan beri" (gün sayısı value olarak gösterilir).
    private var startLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM"
        return "\(f.string(from: startDate))'tan beri"
    }

    // MARK: - Metrik hesabı

    private struct RouteNode: Identifiable {
        let id = UUID()
        let w: Double
        let frac: Double
        let passed: Bool
        let isEnd: Bool
    }

    private struct Metrics {
        let start: Double, current: Double, goal: Double
        let weeklyRate: Double          // işaretli kg/hafta (negatif = kaybediyor)
        let isLoss: Bool
        let pct: Double                 // 0...1
        let remaining: Double
        let nodes: [RouteNode]
        let daysLeft: Int?
        let eta: Date?
        let next: (w: Double, toNext: Double, weeks: Int)?
        let deficitPerDay: Int

        var pctInt: Int { Int((pct * 100).rounded()) }
        var rateStr: String {
            guard abs(weeklyRate) >= 0.01 else { return "—" }
            return "\(weeklyRate < 0 ? "−" : "+")\(Fmt.num(abs(weeklyRate), digits: 2)) kg"
        }
        var etaStr: String? { eta.map { Self.etaFormatter.string(from: $0) } }
        var planMonths: Int? {
            guard let daysLeft else { return nil }
            return max(1, Int((Double(daysLeft) / 30.44).rounded()))
        }
        static let etaFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "tr_TR")
            f.dateFormat = "d MMM yyyy"
            return f
        }()
    }

    private var metrics: Metrics? {
        let pts = TrendAnalysis.points(measurements, for: .weight)
        guard let goal = profile?.targetWeight,
              let first = pts.first, let last = pts.last,
              abs(first.value - goal) > 0.05 else { return nil }

        let start = first.value
        let now = Date()
        let cal = Calendar.current

        // Haftalık ritim: son ~8 hafta penceresinden regresyon (yetersizse tümü, sonra basit).
        let windowStart = cal.date(byAdding: .day, value: -56, to: now) ?? first.date
        let recent = pts.filter { $0.date >= windowStart }
        let fitPts = recent.count >= 3 ? recent : pts
        // Haftalık ritim trend regresyonundan; "şimdi" ise GERÇEK son ölçüm — Dashboard/Ölçümler
        // son ölçümü gösteriyor, İlerleme de onunla tutarlı olsun (geçilen milestone'lar passed olur).
        let slopePerDay: Double
        if let fit = TrendAnalysis.linearFit(fitPts) {
            slopePerDay = fit.slope
        } else {
            let days = max(1, last.date.timeIntervalSince(first.date) / 86_400)
            slopePerDay = (last.value - first.value) / days
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

        // Rota düğümleri — start→goal arası 6 eşit adım.
        let segs = 6
        let nodes: [RouteNode] = (0...segs).map { i in
            let w = start + (goal - start) * Double(i) / Double(segs)
            let frac = min(1, max(0, (start - w) / (start - goal)))
            let passed = isLoss ? (w >= current - 0.001) : (w <= current + 0.001)
            return RouteNode(w: w, frac: frac, passed: passed, isEnd: i == 0 || i == segs)
        }

        var next: (w: Double, toNext: Double, weeks: Int)? = nil
        if let nx = nodes.first(where: { isLoss ? ($0.w < current - 0.05) : ($0.w > current + 0.05) }) {
            let toNext = abs(current - nx.w)
            let weeks = rateAbs >= 0.01 ? max(1, Int((toNext / rateAbs).rounded())) : 1
            next = (nx.w, toNext, weeks)
        }

        let deficit = Int((rateAbs * ScienceEngine.kcalPerKg / 7).rounded())

        return Metrics(start: start, current: current, goal: goal, weeklyRate: weeklyRate,
                       isLoss: isLoss, pct: pct, remaining: remaining, nodes: nodes,
                       daysLeft: daysLeft, eta: eta, next: next, deficitPerDay: deficit)
    }
}
