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

    // MARK: - Suda çözünür vitaminler (günlük takip)
    var vitaminC_mg: Double?   // C vitamini
    var vitaminB1_mg: Double?  // Tiamin
    var vitaminB6_mg: Double?  // B6
    var potassium_mg: Double?  // Potasyum
    var magnesium_mg: Double?  // Magnezyum

    // MARK: - Yağda çözünür vitaminler + mineraller (haftalık takip)
    var vitaminA_ug: Double?   // A vitamini (mikrogram)
    var vitaminD_ug: Double?   // D vitamini (mikrogram)
    var vitaminE_mg: Double?   // E vitamini
    var vitaminK_ug: Double?   // K vitamini (mikrogram)
    var vitaminB12_ug: Double? // B12 (mikrogram)
    var folate_ug: Double?     // Folat/B9 (mikrogram)
    var iron_mg: Double?       // Demir
    var zinc_mg: Double?       // Çinko
    var calcium_mg: Double?    // Kalsiyum
    var omega3_g: Double?      // Omega-3

    init(
        date: Date = .now,
        name: String,
        grams: Double? = nil,
        calories: Double,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        // Günlük
        vitaminC_mg: Double? = nil,
        vitaminB1_mg: Double? = nil,
        vitaminB6_mg: Double? = nil,
        potassium_mg: Double? = nil,
        magnesium_mg: Double? = nil,
        // Haftalık
        vitaminA_ug: Double? = nil,
        vitaminD_ug: Double? = nil,
        vitaminE_mg: Double? = nil,
        vitaminK_ug: Double? = nil,
        vitaminB12_ug: Double? = nil,
        folate_ug: Double? = nil,
        iron_mg: Double? = nil,
        zinc_mg: Double? = nil,
        calcium_mg: Double? = nil,
        omega3_g: Double? = nil
    ) {
        self.date = date
        self.name = name
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.vitaminC_mg = vitaminC_mg
        self.vitaminB1_mg = vitaminB1_mg
        self.vitaminB6_mg = vitaminB6_mg
        self.potassium_mg = potassium_mg
        self.magnesium_mg = magnesium_mg
        self.vitaminA_ug = vitaminA_ug
        self.vitaminD_ug = vitaminD_ug
        self.vitaminE_mg = vitaminE_mg
        self.vitaminK_ug = vitaminK_ug
        self.vitaminB12_ug = vitaminB12_ug
        self.folate_ug = folate_ug
        self.iron_mg = iron_mg
        self.zinc_mg = zinc_mg
        self.calcium_mg = calcium_mg
        self.omega3_g = omega3_g
    }
}
