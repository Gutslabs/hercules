import Foundation
import SwiftData

/// iPhone HealthKit'ten alınan günlük aktivite özeti. SwiftData/CloudKit bu kaydı
/// diğer cihazlara taşır; HealthKit yalnız iPhone'da okunur.
@Model
final class StepEntry {
    static let healthKitSource = "healthkit"

    var date: Date = Date.now
    var steps: Int = 0
    var source: String = StepEntry.healthKitSource
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    var syncedAt: Date?
    /// HealthKit özetinin son değişiklik zamanı.
    var updatedAt: Date = Date.now

    init(
        date: Date = .now,
        steps: Int = 0,
        source: String = StepEntry.healthKitSource,
        distanceMeters: Double? = nil,
        activeEnergyKcal: Double? = nil,
        syncedAt: Date? = nil
    ) {
        self.date = date
        self.steps = steps
        self.source = source
        self.distanceMeters = distanceMeters
        self.activeEnergyKcal = activeEnergyKcal
        self.syncedAt = syncedAt
    }

    /// kcal hesabı — kullanıcı kilosuna göre. ~0.0004 kcal/adım/kg.
    static func calorieBurn(steps: Int, weightKg: Double) -> Double {
        Double(steps) * 0.0004 * weightKg
    }

    static func calorieBurn(for entry: StepEntry, weightKg: Double) -> Double {
        calorieBurn(steps: entry.steps, weightKg: weightKg)
    }

    /// Aynı güne iki cihazdan kayıt gelirse HealthKit her zaman eski taşıma
    /// kaynaklarından üstündür; aynı kaynakta en güncel özet kazanır.
    static func isPreferred(_ candidate: StepEntry, over current: StepEntry) -> Bool {
        let candidateIsHealth = candidate.source == healthKitSource
        let currentIsHealth = current.source == healthKitSource
        if candidateIsHealth != currentIsHealth { return candidateIsHealth }
        if candidate.updatedAt != current.updatedAt { return candidate.updatedAt > current.updatedAt }
        if (candidate.syncedAt ?? .distantPast) != (current.syncedAt ?? .distantPast) {
            return (candidate.syncedAt ?? .distantPast) > (current.syncedAt ?? .distantPast)
        }
        return candidate.steps > current.steps
    }

    static func preferredEntries(
        from entries: [StepEntry],
        calendar: Calendar = .current
    ) -> [StepEntry] {
        var byDay: [Date: StepEntry] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if let current = byDay[day] {
                if isPreferred(entry, over: current) { byDay[day] = entry }
            } else {
                byDay[day] = entry
            }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    static func preferredToday(
        from entries: [StepEntry],
        calendar: Calendar = .current
    ) -> StepEntry? {
        preferredEntries(
            from: entries.filter { calendar.isDateInToday($0.date) },
            calendar: calendar
        ).first
    }
}
