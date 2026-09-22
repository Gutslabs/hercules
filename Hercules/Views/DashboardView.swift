import SwiftUI
import SwiftData

/// Genel Bakış · V3 "Sade": 2×2 eşit kart — Bugün (kalan kalori halkası) · Makrolar ·
/// Öğünler · Kilo. Kartlar DashboardSade.swift'te; burada veri toplama ve pencereyi
/// doldurma matematiği.
struct DashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]
    @Query private var todaysFoods: [FoodEntry]
    @Query private var todaysSteps: [StepEntry]
    @State private var revealContent = false

    /// Kilo kartının başlangıç kilosu, yüzdesi ve varışı İlerleme'yle aynı dönemden ölçülür.
    /// @Observable: dönem değişince kart yeniden hesaplanır.
    private let epochStore = DietEpochStore.shared
    /// Sayfanın gösterdiği gün (gün başı).
    private let day: Date

    /// Kart tabanı — iki satır bundan kısa pencerede sığmaz, sayfa kayar.
    private static let minCardHeight: CGFloat = 440

    init(today: Date = .now) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? today
        day = start
        _todaysFoods = Query(
            filter: #Predicate<FoodEntry> { entry in
                entry.date >= start && entry.date < end
            },
            sort: \FoodEntry.date,
            order: .reverse
        )
        _todaysSteps = Query(
            filter: #Predicate<StepEntry> { entry in
                entry.date >= start && entry.date < end
            },
            sort: \StepEntry.date,
            order: .reverse
        )
    }

    private var profile: UserProfile? { profiles.first }
    private var latest: Measurement? { measurements.first }

    private var consumedCalories: Double {
        todaysFoods.reduce(0) { $0 + $1.calories }
    }
    private var consumedProtein: Double { todaysFoods.compactMap(\.protein).reduce(0, +) }
    private var consumedCarbs: Double { todaysFoods.compactMap(\.carbs).reduce(0, +) }
    private var consumedFat: Double { todaysFoods.compactMap(\.fat).reduce(0, +) }

    private var calorieResult: CalorieResult? {
        guard let profile = profile,
              let latest = latest,
              let weight = latest.weight else { return nil }
        return CalorieCalculator.compute(
            weight: weight,
            height: profile.height,
            age: profile.age,
            sex: profile.sex,
            bodyFat: latest.bodyFat ?? profile.manualBodyFat,
            activity: profile.activity,
            goal: profile.goal,
            manualOffset: profile.manualCalorieOffset,
            manualOffsetMacro: profile.manualCalorieOffsetMacro,
            manualProteinGrams: profile.manualProteinGrams,
            manualCarbsGrams: profile.manualCarbsGrams,
            manualFatGrams: profile.manualFatGrams
        )
    }

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
        .onAppear { revealContent = true }
    }

    // MARK: - Sayfa gövdesi (pencereyi doldurma matematiği)

    /// Geniş pencere: 2×2 kart pencereyi doldurur (tasarım ölçüsünde 734/735 × 523); kısa
    /// pencerede kartlar `minCardHeight`'ın altına inmez, sayfa kayar. Dar pencere: alt alta.
    @ViewBuilder
    private func content(size: CGSize) -> some View {
        let innerW = max(0, size.width - 48)
        let result = calorieResult
        let meals = RingsMeal.group(todaysFoods)

        if innerW >= 880 {
            let innerH = max(size.height - 36, 2 * Self.minCardHeight + 24)
            let rows = Self.split(innerH - 24, into: 2)
            let columns = Self.split(innerW - 24, into: 2)
            VStack(spacing: 24) {
                HStack(spacing: 24) {
                    todayCard(result)
                        .frame(width: columns[0])
                        .dashboardReveal(revealContent, delay: 0.02)
                    macrosCard(result)
                        .frame(width: columns[1])
                        .dashboardReveal(revealContent, delay: 0.06)
                }
                .frame(height: rows[0])
                HStack(spacing: 24) {
                    mealsCard(meals, goal: result?.goalCalories)
                        .frame(width: columns[0])
                        .dashboardReveal(revealContent, delay: 0.10)
                    weightCard
                        .frame(width: columns[1])
                        .dashboardReveal(revealContent, delay: 0.14)
                }
                .frame(height: rows[1])
            }
            .frame(width: innerW, height: innerH, alignment: .topLeading)
        } else {
            VStack(spacing: 18) {
                todayCard(result)
                    .frame(height: 460)
                    .dashboardReveal(revealContent, delay: 0.02)
                macrosCard(result)
                    .frame(height: Self.minCardHeight)
                    .dashboardReveal(revealContent, delay: 0.06)
                mealsCard(meals, goal: result?.goalCalories)
                    .frame(height: 460)
                    .dashboardReveal(revealContent, delay: 0.10)
                weightCard
                    .frame(height: 460)
                    .dashboardReveal(revealContent, delay: 0.14)
            }
            .frame(width: innerW)
        }
    }

    /// `total`'ı `count` tam noktalık paya böler, artan noktalar sağdakilere
    /// (1469 → 734 · 735) — kart kenarları piksel ortasına düşüp bulanmasın.
    private static func split(_ total: CGFloat, into count: Int) -> [CGFloat] {
        var remaining = max(0, total)
        return (0..<count).map { index in
            let share = index == count - 1 ? remaining : floor(remaining / CGFloat(count - index))
            remaining -= share
            return share
        }
    }

    // MARK: - Kartlar

    private func todayCard(_ result: CalorieResult?) -> some View {
        DashboardTodayCard(
            dateLabel: Fmt.dayMonthWeekday.string(from: day),
            plan: result.map { DashboardTodayCard.Plan(goal: $0.goalCalories, consumed: consumedCalories) },
            steps: StepEntry.preferredEntries(from: todaysSteps).last?.steps,
            setupTitle: setupMissingTitle,
            setupDetail: setupMissingDetail
        )
    }

    private func macrosCard(_ result: CalorieResult?) -> some View {
        DashboardMacrosCard(macros: result.map { r in
            [
                DashboardMacro(name: "Protein", consumed: consumedProtein, target: r.protein.grams,
                               color: Palette.macroProtein),
                DashboardMacro(name: "Karb", consumed: consumedCarbs, target: r.carbs.grams,
                               color: Palette.macroCarbs),
                DashboardMacro(name: "Yağ", consumed: consumedFat, target: r.fat.grams,
                               color: Palette.macroFat),
            ]
        })
    }

    private func mealsCard(_ meals: [RingsMeal], goal: Double?) -> some View {
        DashboardMealsCard(meals: meals, goal: goal) { entry in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                ctx.delete(entry)
                ctx.saveOrReport()
            }
        }
    }

    private var weightCard: some View {
        DashboardWeightCard(model: weightModel)
    }

    // MARK: - Kilo verisi

    private var weightModel: DashboardWeightCard.Model {
        let points = TrendAnalysis.points(measurements, for: .weight)
        let calendar = Calendar.current
        // Son 30 günün değişimi; pencerede iki tartı yoksa serinin tümü (gün sayısı ona göre).
        let cutoff = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: .now)) ?? .distantPast
        let window = points.filter { $0.date >= cutoff }
        let span = window.count >= 2 ? window : points
        var delta: Double?
        var deltaDays = 30
        if span.count >= 2, let first = span.first, let last = span.last {
            delta = last.value - first.value
            if window.count < 2 {
                deltaDays = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: first.date),
                                                           to: calendar.startOfDay(for: last.date)).day ?? 1)
            }
        }
        // Kilo verme VE koruma modunda düşüş olumlu; yalnız kütle alma hedefinde artış olumlu.
        let lowerIsBetter = (profile?.goal.calorieAdjustment ?? 0) <= 0
        let journey = IlerlemeMetrics.make(weights: points, goal: profile?.targetWeight, epochs: epochStore.epochs)
        return DashboardWeightCard.Model(
            current: points.last?.value,
            goal: profile?.targetWeight,
            delta: delta,
            deltaDays: deltaDays,
            deltaIsGood: delta.map { lowerIsBetter ? $0 <= 0 : $0 >= 0 } ?? true,
            start: journey?.start,
            progress: journey?.pct,
            eta: journey?.eta
        )
    }

    // MARK: - Kurulum eksikken

    private var setupMissingTitle: String {
        if profile == nil { return "Profil tamamlanmalı" }
        if latest?.weight == nil { return "Kilo ölçümü bekleniyor" }
        return "Plan verisi eksik"
    }

    private var setupMissingDetail: String {
        if profile == nil {
            return "Kalori ve makro hedefleri için profil bilgilerini ekle."
        }
        if latest?.weight == nil {
            return "Kalori hesabı için en az bir kilo ölçümü gerekli."
        }
        return "Hedef planını hesaplamak için eksik alanları tamamla."
    }
}
