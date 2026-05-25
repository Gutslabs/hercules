import Foundation

struct CalorieResult {
    let bmr: Double
    let tdee: Double
    let goalCalories: Double
    let protein: Macro
    let carbs: Macro
    let fat: Macro
    let water: Double
    let fiber: Double
    let leanMass: Double
    let formula: String
}

struct Macro {
    let grams: Double
    let calories: Double
    let percent: Double
}

enum CalorieCalculator {
    static func compute(
        weight: Double,
        height: Double,
        age: Int,
        sex: Sex,
        bodyFat: Double?,
        activity: ActivityLevel,
        goal: Goal,
        manualOffset: Double = 0,
        workoutCalories: Double = 0,
        stepCalories: Double = 0
    ) -> CalorieResult {
        let bmr: Double
        let lbm: Double
        let formula: String

        if let bf = bodyFat, bf > 0 {
            lbm = weight * (1.0 - bf / 100.0)
            bmr = 370.0 + (21.6 * lbm)
            formula = "Katch-McArdle"
        } else {
            let s: Double = (sex == .male) ? 5 : -161
            bmr = (10.0 * weight) + (6.25 * height) - (5.0 * Double(age)) + s
            lbm = weight * (sex == .male ? 0.85 : 0.75)
            formula = "Mifflin-St Jeor"
        }

        let tdee = bmr * activity.multiplier
        // Antrenman kalorileri hedefe eklenmez; günlük plan sabit kalır.
        // Adım kalorisi düşük yoğunluklu günlük hareket bütçesi olarak ayrı tutulur.
        let goalCalories = max(1200, tdee + goal.calorieAdjustment + manualOffset + stepCalories)

        let proteinGrams = lbm * 2.2
        let proteinCals = proteinGrams * 4.0

        let fatCals = goalCalories * 0.25
        let fatGrams = fatCals / 9.0

        let carbsCals = max(0, goalCalories - proteinCals - fatCals)
        let carbsGrams = carbsCals / 4.0

        let total = goalCalories
        let protein = Macro(
            grams: proteinGrams,
            calories: proteinCals,
            percent: proteinCals / total * 100
        )
        let fat = Macro(
            grams: fatGrams,
            calories: fatCals,
            percent: fatCals / total * 100
        )
        let carbs = Macro(
            grams: carbsGrams,
            calories: carbsCals,
            percent: carbsCals / total * 100
        )

        let water = weight * 0.035
        let fiber = (goalCalories / 1000.0) * 14.0

        return CalorieResult(
            bmr: bmr,
            tdee: tdee,
            goalCalories: goalCalories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            water: water,
            fiber: fiber,
            leanMass: lbm,
            formula: formula
        )
    }
}
