import Foundation
import SwiftData

@Model
final class MonthlyGoal {
    /// Hedefin ulaşılması gereken tarih (ay/gün referans noktası).
    var anchorDate: Date
    /// O tarihte ulaşılmak istenen kilo (kg).
    var targetWeight: Double
    /// O tarihte ulaşılmak istenen yağ oranı (%). Opsiyonel.
    var targetBodyFat: Double?
    var note: String?

    init(anchorDate: Date, targetWeight: Double, targetBodyFat: Double? = nil, note: String? = nil) {
        self.anchorDate = anchorDate
        self.targetWeight = targetWeight
        self.targetBodyFat = targetBodyFat
        self.note = note
    }
}
