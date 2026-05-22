import Foundation
import SwiftData

/// Günlük adım kaydı — manuel girilebilir veya iPhone Shortcuts sync ile dolabilir.
@Model
final class StepEntry {
    var date: Date
    var steps: Int
    var source: String  // "manual" veya "shortcuts"
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    var syncedAt: Date?

    init(
        date: Date = .now,
        steps: Int = 0,
        source: String = "manual",
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
        entry.activeEnergyKcal ?? calorieBurn(steps: entry.steps, weightKg: weightKg)
    }
}
