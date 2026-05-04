import Foundation
import SwiftData

/// Günlük adım kaydı — manuel girilebilir, ileride HealthKit auto-fill yapabilir.
@Model
final class StepEntry {
    var date: Date
    var steps: Int
    var source: String  // "manual" veya "healthkit"

    init(date: Date = .now, steps: Int = 0, source: String = "manual") {
        self.date = date
        self.steps = steps
        self.source = source
    }

    /// kcal hesabı — kullanıcı kilosuna göre. ~0.0004 kcal/adım/kg.
    static func calorieBurn(steps: Int, weightKg: Double) -> Double {
        Double(steps) * 0.0004 * weightKg
    }
}
