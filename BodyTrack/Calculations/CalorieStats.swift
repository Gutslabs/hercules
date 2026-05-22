import Foundation

/// Tek bir periyodun tüketim özeti: kaç gün kayıtlı, toplam ve ortalama kcal,
/// hedef toplam ve net açık (negatif = açık, pozitif = fazla).
struct CaloriePeriodStats {
    /// İncelenen takvim aralığı.
    let range: DateInterval
    /// Aralıkta yemek girilmiş tekil gün sayısı.
    let loggedDays: Int
    /// Aralığın toplam takvim günü.
    let totalDays: Int
    /// Aralıkta toplam tüketilen kalori.
    let totalConsumed: Double
    /// Tek bir günlük hedef (CalorieCalculator çıktısı).
    let dailyTarget: Double
    /// Aralık için hedef toplam = totalDays * dailyTarget.
    var totalTargetForRange: Double { Double(totalDays) * dailyTarget }
    /// Aralık için hedef toplam, sadece KAYITLI günler üzerinden.
    var loggedTarget: Double { Double(loggedDays) * dailyTarget }
    /// Kayıtlı günlerin ortalama tüketimi.
    var averageDailyKcal: Double {
        guard loggedDays > 0 else { return 0 }
        return totalConsumed / Double(loggedDays)
    }
    /// Net açık (negatif) veya fazla (pozitif), sadece KAYITLI günler üzerinden.
    /// AI bu sayıyı "kalori açığı" olarak yorumlayacak.
    var netBalance: Double { totalConsumed - loggedTarget }
    /// Aralığın günlük ortalama açığı (kayıtlı günler).
    var averageDailyBalance: Double {
        guard loggedDays > 0 else { return 0 }
        return netBalance / Double(loggedDays)
    }
}

/// Aggregates over `FoodEntry` records for arbitrary date ranges.
/// `dailyTarget` ile beraber tüm period özetleri hesaplar.
enum CalorieStats {

    // MARK: - Range builders

    static func today(in cal: Calendar = .current) -> DateInterval {
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func thisWeek(in cal: Calendar = .current) -> DateInterval {
        var c = cal
        c.firstWeekday = 2 // Pazartesi
        let now = Date()
        let start = c.dateInterval(of: .weekOfYear, for: now)?.start ?? c.startOfDay(for: now)
        let end = c.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func thisMonth(in cal: Calendar = .current) -> DateInterval {
        cal.dateInterval(of: .month, for: .now)
            ?? DateInterval(start: cal.startOfDay(for: .now), duration: 86_400 * 30)
    }

    static func last(days: Int, in cal: Calendar = .current) -> DateInterval {
        let end = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let start = cal.date(byAdding: .day, value: -days, to: end) ?? end
        return DateInterval(start: start, end: end)
    }

    // MARK: - Computation

    /// Belirli bir aralıkta `foods` verisinden istatistik üret.
    /// `clipFutureDays = true` ise bugünün ötesindeki günleri totalDays'ten düşer
    /// (ay içindeyiz ama ay daha bitmedi).
    static func stats(
        for range: DateInterval,
        foods: [FoodEntry],
        dailyTarget: Double,
        clipFutureDays: Bool = true,
        cal: Calendar = .current
    ) -> CaloriePeriodStats {
        // Filter foods within range
        let inRange = foods.filter { range.contains($0.date) }
        let totalKcal = inRange.reduce(0) { $0 + $1.calories }

        // Distinct logged day count
        let dayKeys = Set(inRange.map { cal.startOfDay(for: $0.date) })
        let loggedDays = dayKeys.count

        // Total calendar days in range (clip to today if requested)
        let totalDays: Int = {
            let secs = range.end.timeIntervalSince(range.start)
            let raw = max(1, Int((secs / 86_400).rounded()))
            guard clipFutureDays else { return raw }
            let now = Date()
            if range.end <= now { return raw }
            // Days elapsed so far within the range
            let elapsedSecs = max(0, now.timeIntervalSince(range.start))
            let elapsed = max(1, Int(ceil(elapsedSecs / 86_400)))
            return min(raw, elapsed)
        }()

        return CaloriePeriodStats(
            range: range,
            loggedDays: loggedDays,
            totalDays: totalDays,
            totalConsumed: totalKcal,
            dailyTarget: dailyTarget
        )
    }

    /// Hafta günlerine göre toplam tüketim (Pzt..Paz). Eksik günler 0.
    static func weeklyDailyTotals(
        foods: [FoodEntry],
        week: DateInterval,
        cal: Calendar = .current
    ) -> [(date: Date, kcal: Double)] {
        var out: [(Date, Double)] = []
        for i in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: i, to: week.start) else { continue }
            let total = foods.filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.calories }
            out.append((day, total))
        }
        return out
    }
}
