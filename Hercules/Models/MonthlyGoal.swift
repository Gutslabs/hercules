import Foundation
import SwiftData

@Model
final class MonthlyGoal {
    /// Hedefin ulaşılması gereken tarih (ay/gün referans noktası).
    var anchorDate: Date = Date.now
    /// O tarihte ulaşılmak istenen kilo (kg).
    var targetWeight: Double = 0
    var note: String?
    /// Kaydın son değişiklik zamanı.
    var updatedAt: Date = Date.now

    init(anchorDate: Date, targetWeight: Double, note: String? = nil) {
        self.anchorDate = anchorDate
        self.targetWeight = targetWeight
        self.note = note
    }
}
