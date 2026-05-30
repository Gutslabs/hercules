import Foundation
import SwiftData

@Model
final class MonthlyGoal {
    /// Hedefin ulaşılması gereken tarih (ay/gün referans noktası).
    var anchorDate: Date
    /// O tarihte ulaşılmak istenen kilo (kg).
    var targetWeight: Double
    var note: String?
    /// Sync merge: son değişiklik zamanı (çakışmada yenisi kazanır).
    var updatedAt: Date = Date.now

    init(anchorDate: Date, targetWeight: Double, note: String? = nil) {
        self.anchorDate = anchorDate
        self.targetWeight = targetWeight
        self.note = note
    }
}
