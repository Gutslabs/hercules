import Foundation
import SwiftData

@Model
final class WorkoutSession {
    /// Calendar.weekday convention: 1=Pazar, 2=Pazartesi, …, 7=Cumartesi
    var weekday: Int
    var name: String
    var estimatedCalories: Double

    init(weekday: Int, name: String, estimatedCalories: Double = 300) {
        self.weekday = weekday
        self.name = name
        self.estimatedCalories = estimatedCalories
    }

    static let weekdayNames: [String] = [
        "", "Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"
    ]

    static let weekdayShort: [String] = [
        "", "Pa", "Pt", "Sa", "Ça", "Pe", "Cu", "Ct"
    ]

    var weekdayName: String {
        guard weekday >= 1 && weekday <= 7 else { return "?" }
        return Self.weekdayNames[weekday]
    }
}
