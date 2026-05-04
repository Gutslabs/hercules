import Foundation
import SwiftData

@Model
final class FoodEntry {
    var date: Date
    var name: String
    var grams: Double?
    var calories: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    init(
        date: Date = .now,
        name: String,
        grams: Double? = nil,
        calories: Double,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil
    ) {
        self.date = date
        self.name = name
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}
