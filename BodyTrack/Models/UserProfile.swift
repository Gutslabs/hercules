import Foundation
import SwiftData

enum Sex: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female
    var id: String { rawValue }
    var label: String {
        switch self {
        case .male: return "Erkek"
        case .female: return "Kadın"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case sedentary, light, moderate, active, veryActive, extreme

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.20
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.90
        case .extreme: return 2.10
        }
    }

    var label: String {
        switch self {
        case .sedentary: return "Hareketsiz"
        case .light: return "Az Hareketli"
        case .moderate: return "Orta Aktif"
        case .active: return "Aktif"
        case .veryActive: return "Çok Aktif"
        case .extreme: return "Profesyonel Sporcu"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: return "Masa başı, çok az veya hiç egzersiz yok"
        case .light: return "Haftada 1-3 gün hafif egzersiz"
        case .moderate: return "Haftada 3-5 gün orta yoğunlukta egzersiz"
        case .active: return "Haftada 6-7 gün yoğun egzersiz"
        case .veryActive: return "Günde 2 antrenman veya çok ağır iş"
        case .extreme: return "Profesyonel düzeyde antrenman"
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable, Sendable {
    case loseFast, lose, maintain, gain, gainFast

    var id: String { rawValue }

    var calorieAdjustment: Double {
        switch self {
        case .loseFast: return -500
        case .lose: return -250
        case .maintain: return 0
        case .gain: return 250
        case .gainFast: return 500
        }
    }

    var label: String {
        switch self {
        case .loseFast: return "Hızlı Kilo Verme"
        case .lose: return "Kilo Verme"
        case .maintain: return "Koruma"
        case .gain: return "Kilo Alma"
        case .gainFast: return "Hızlı Kilo Alma"
        }
    }

    var detail: String {
        switch self {
        case .loseFast: return "−500 kcal · ~0.5 kg/hafta"
        case .lose: return "−250 kcal · ~0.25 kg/hafta"
        case .maintain: return "Kilo değişimi yok"
        case .gain: return "+250 kcal · ~0.25 kg/hafta"
        case .gainFast: return "+500 kcal · ~0.5 kg/hafta"
        }
    }
}

enum CalorieOffsetMacro: String, Codable, CaseIterable, Identifiable, Sendable {
    case protein, carbs, fat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .carbs: return "Karbonhidrat"
        case .fat: return "Yağ"
        case .protein: return "Protein"
        }
    }

    var shortLabel: String {
        switch self {
        case .carbs: return "Karb"
        case .fat: return "Yağ"
        case .protein: return "Protein"
        }
    }

    var caloriesPerGram: Double {
        switch self {
        case .carbs, .protein: return 4
        case .fat: return 9
        }
    }
}

@Model
final class UserProfile {
    static let defaultSupplements = "Kreatin\nProtein tozu"

    var name: String
    var sex: Sex
    var birthDate: Date
    var height: Double
    var activity: ActivityLevel
    var goal: Goal
    var targetWeight: Double?
    var targetBodyFat: Double?
    var manualBodyFat: Double?
    var manualCalorieOffset: Double = 0
    var manualCalorieOffsetMacroRaw: String? = CalorieOffsetMacro.carbs.rawValue
    var manualProteinGrams: Double?
    var manualCarbsGrams: Double?
    var manualFatGrams: Double?
    /// Kullanıcının kendisi hakkında yazdığı kalıcı bilgi — her AI sohbetinde
    /// "kullanıcı kim" olarak system context'e enjekte edilir.
    var about: String = ""
    /// Kullanıcının düzenli kullandığı supplementler — AI context'e kalıcı
    /// profil bilgisi olarak enjekte edilir.
    var supplements: String = UserProfile.defaultSupplements

    init(
        name: String = "",
        sex: Sex = .male,
        birthDate: Date = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now,
        height: Double = 178,
        activity: ActivityLevel = .moderate,
        goal: Goal = .maintain,
        targetWeight: Double? = nil,
        targetBodyFat: Double? = nil,
        manualBodyFat: Double? = nil,
        manualCalorieOffset: Double = 0,
        manualCalorieOffsetMacro: CalorieOffsetMacro = .carbs,
        manualProteinGrams: Double? = nil,
        manualCarbsGrams: Double? = nil,
        manualFatGrams: Double? = nil,
        about: String = "",
        supplements: String = UserProfile.defaultSupplements
    ) {
        self.name = name
        self.sex = sex
        self.birthDate = birthDate
        self.height = height
        self.activity = activity
        self.goal = goal
        self.targetWeight = targetWeight
        self.targetBodyFat = targetBodyFat
        self.manualBodyFat = manualBodyFat
        self.manualCalorieOffset = manualCalorieOffset
        self.manualCalorieOffsetMacroRaw = manualCalorieOffsetMacro.rawValue
        self.manualProteinGrams = manualProteinGrams
        self.manualCarbsGrams = manualCarbsGrams
        self.manualFatGrams = manualFatGrams
        self.about = about
        self.supplements = supplements
    }

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
    }

    var manualCalorieOffsetMacro: CalorieOffsetMacro {
        get {
            CalorieOffsetMacro(rawValue: manualCalorieOffsetMacroRaw ?? "") ?? .carbs
        }
        set {
            manualCalorieOffsetMacroRaw = newValue.rawValue
        }
    }

    var effectiveSupplements: String {
        let trimmed = supplements.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultSupplements : supplements
    }
}
