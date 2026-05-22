import Foundation
import SwiftUI
import SwiftData

// MARK: - AI/user overrides

enum MealPlanOverrideOperation: String, Codable, CaseIterable, Hashable {
    case setDayType = "set_day_type"
    case addItem = "add_item"
}

@Model
final class MealPlanOverride {
    /// Calendar.weekday convention: 1=Pazar, 2=Pazartesi, ... 7=Cumartesi
    var weekday: Int
    var operationRaw: String
    var dayTypeRaw: String?
    var slotRaw: String?
    var itemName: String?
    var amount: Double?
    var unit: String?
    /// Totals for this custom line, not per-unit values.
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var note: String?
    var source: String
    var createdAt: Date

    init(
        weekday: Int,
        operation: MealPlanOverrideOperation,
        dayType: MealDayType? = nil,
        slot: MealSlot? = nil,
        itemName: String? = nil,
        amount: Double? = nil,
        unit: String? = nil,
        calories: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        note: String? = nil,
        source: String = "manual",
        createdAt: Date = .now
    ) {
        self.weekday = weekday
        self.operationRaw = operation.rawValue
        self.dayTypeRaw = dayType?.rawValue
        self.slotRaw = slot?.rawValue
        self.itemName = itemName
        self.amount = amount
        self.unit = unit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.note = note
        self.source = source
        self.createdAt = createdAt
    }

    var operation: MealPlanOverrideOperation {
        MealPlanOverrideOperation(rawValue: operationRaw) ?? .addItem
    }

    var dayType: MealDayType? {
        guard let dayTypeRaw else { return nil }
        return MealDayType(rawValue: dayTypeRaw)
    }

    var slot: MealSlot? {
        guard let slotRaw else { return nil }
        return MealSlot(rawValue: slotRaw)
    }

    var macros: Macros {
        Macros(kcal: calories ?? 0, p: protein ?? 0, c: carbs ?? 0, f: fat ?? 0)
    }

    var amountText: String {
        guard let amount, let unit, !unit.isEmpty else { return "" }
        if unit == "adet" || unit == "tabak" {
            return "\(Int(amount.rounded())) \(unit)"
        }
        return "\(Int(amount.rounded())) \(unit)"
    }

    var displayName: String {
        let name = itemName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "AI eklemesi" : name
    }

    static func dayTypeOverride(for weekday: Int, in overrides: [MealPlanOverride]) -> MealDayType? {
        overrides
            .filter { $0.weekday == weekday && $0.operation == .setDayType }
            .sorted { $0.createdAt > $1.createdAt }
            .first?
            .dayType
    }
}

// MARK: - Day type

enum MealDayType: String, CaseIterable, Identifiable, Hashable {
    case gogus, but, pirzola, free

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gogus: return "Tavuk Göğsü"
        case .but: return "Derisiz But"
        case .pirzola: return "Pirzola"
        case .free: return "Serbest"
        }
    }

    var short: String {
        switch self {
        case .gogus: return "Göğüs"
        case .but: return "But"
        case .pirzola: return "Pirzola"
        case .free: return "Serbest"
        }
    }

    var accent: Color {
        switch self {
        case .gogus: return Palette.macroProtein
        case .but: return Palette.warning
        case .pirzola: return Palette.macroFat
        case .free: return Color(red: 0.62, green: 0.78, blue: 0.95)
        }
    }

    var headline: String {
        switch self {
        case .gogus: return "Temiz protein günü. Yağ kontrollü, zeytinyağı serbest."
        case .but: return "Yağ doğal olarak yükselir. Zeytinyağı yok, yumurta dengeli."
        case .pirzola: return "Yağ en oynak gün. Zeytinyağı yok, karb biraz düşük."
        case .free: return "Aynı kalori bandında serbest gün. Hafta sonu için."
        }
    }
}

// MARK: - Meal slots

enum MealSlot: String, CaseIterable, Identifiable, Hashable {
    case sabah, ogle, ara, aksam
    var id: String { rawValue }

    var label: String {
        switch self {
        case .sabah: return "Sabah"
        case .ogle: return "Öğle"
        case .ara: return "Ara"
        case .aksam: return "Akşam"
        }
    }

    var icon: String {
        switch self {
        case .sabah: return "sunrise.fill"
        case .ogle: return "sun.max.fill"
        case .ara: return "leaf.fill"
        case .aksam: return "moon.fill"
        }
    }
}

// MARK: - Items

enum MealItemKind: Hashable {
    case protein, carb, fat, dairy, fruit, veg

    var tint: Color {
        switch self {
        case .protein: return Palette.macroProtein
        case .carb: return Palette.macroCarbs
        case .fat: return Palette.macroFat
        case .dairy: return Color(red: 0.62, green: 0.78, blue: 0.95)
        case .fruit: return Color(red: 0.90, green: 0.62, blue: 0.78)
        case .veg: return Palette.positive
        }
    }
}

/// A single food item in a meal. Values are per "unit" (gram or piece),
/// so totals scale with `baseAmount`. `trimFactor` controls how aggressively
/// the item shrinks when a calorie deficit is applied (0 = never, 1 = first).
struct PlannedItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseAmount: Double
    let unit: String       // "g" or "adet"
    let kind: MealItemKind
    let kcal: Double       // per unit
    let p: Double          // per unit
    let c: Double          // per unit
    let f: Double          // per unit
    let trimFactor: Double // 0...1

    /// Scaled amount after applying a deficit factor (0...~0.35).
    func amount(deficit: Double) -> Double {
        let safe = max(0, min(1, deficit))
        let reduction = safe * trimFactor
        return max(0, baseAmount * (1.0 - reduction))
    }

    func macros(deficit: Double) -> Macros {
        let a = amount(deficit: deficit)
        return Macros(kcal: a * kcal, p: a * p, c: a * c, f: a * f)
    }

    var hasMacros: Bool { kcal > 0 || p > 0 || c > 0 || f > 0 }
}

struct Macros: Hashable {
    var kcal: Double = 0
    var p: Double = 0
    var c: Double = 0
    var f: Double = 0

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, p: a.p + b.p, c: a.c + b.c, f: a.f + b.f)
    }

    static var zero: Macros { Macros() }
}

struct PlannedMeal: Identifiable, Hashable {
    let id = UUID()
    let slot: MealSlot
    let items: [PlannedItem]

    func totals(deficit: Double) -> Macros {
        items.reduce(.zero) { $0 + $1.macros(deficit: deficit) }
    }
}

struct DayTemplate: Identifiable, Hashable {
    let id = UUID()
    let type: MealDayType
    let meals: [PlannedMeal]

    func totals(deficit: Double) -> Macros {
        meals.reduce(.zero) { $0 + $1.totals(deficit: deficit) }
    }
}

// MARK: - Deficit levels

enum DeficitLevel: String, CaseIterable, Identifiable, Hashable {
    case maintain, light, medium, hard
    var id: String { rawValue }

    var label: String {
        switch self {
        case .maintain: return "Maintenance"
        case .light:    return "Hafif"
        case .medium:   return "Orta"
        case .hard:     return "Sert"
        }
    }

    /// Approximate kcal delta vs maintenance baseline (~2100 kcal).
    var deltaKcal: Int {
        switch self {
        case .maintain: return 0
        case .light:    return -300
        case .medium:   return -500
        case .hard:     return -700
        }
    }

    /// Trim factor applied to scalable items. Empirically these line up
    /// with the deltaKcal targets given the template above.
    var factor: Double {
        switch self {
        case .maintain: return 0.0
        case .light:    return 0.12
        case .medium:   return 0.22
        case .hard:     return 0.32
        }
    }

    var subtitle: String {
        switch self {
        case .maintain: return "Bakım — günlük plan tam"
        case .light:    return "Hafif kesinti, plato kırmak için"
        case .medium:   return "Sürdürülebilir cut hızı"
        case .hard:     return "Kısa süreli agresif kesinti"
        }
    }
}

// MARK: - Library

enum MealLibrary {

    // Calendar weekday: Sunday=1, Monday=2, ... Saturday=7
    static let weeklyRotation: [Int: MealDayType] = [
        2: .gogus,
        3: .but,
        4: .pirzola,
        5: .gogus,
        6: .but,
        7: .gogus,
        1: .free,
    ]

    static func dayType(for weekday: Int) -> MealDayType {
        weeklyRotation[weekday] ?? .gogus
    }

    static func template(for type: MealDayType) -> DayTemplate {
        switch type {
        case .gogus:   return gogusDay
        case .but:     return butDay
        case .pirzola: return pirzolaDay
        case .free:    return freeDay
        }
    }

    // MARK: - Item factories (per-unit macro values)

    private static func yumurtaTam(_ count: Int) -> PlannedItem {
        PlannedItem(
            name: "Tam yumurta", baseAmount: Double(count), unit: "adet",
            kind: .protein,
            kcal: 70, p: 6, c: 0.5, f: 5,
            trimFactor: 0.0
        )
    }

    private static func yumurtaBeyaz(_ count: Int) -> PlannedItem {
        PlannedItem(
            name: "Yumurta beyazı", baseAmount: Double(count), unit: "adet",
            kind: .protein,
            kcal: 17, p: 3.6, c: 0.2, f: 0.06,
            trimFactor: 0.0
        )
    }

    private static func lor(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Lor peyniri", baseAmount: g, unit: "g",
            kind: .dairy,
            kcal: 1.0, p: 0.14, c: 0.04, f: 0.04,
            trimFactor: 0.0
        )
    }

    private static func yulaf(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Yulaf (kuru)", baseAmount: g, unit: "g",
            kind: .carb,
            kcal: 3.8, p: 0.13, c: 0.67, f: 0.07,
            trimFactor: 0.5
        )
    }

    private static func elma(_ count: Int = 1) -> PlannedItem {
        PlannedItem(
            name: "Elma", baseAmount: Double(count), unit: "adet",
            kind: .fruit,
            kcal: 95, p: 0.5, c: 25, f: 0.3,
            trimFactor: 0.4
        )
    }

    private static func muz(_ count: Int = 1) -> PlannedItem {
        PlannedItem(
            name: "Muz", baseAmount: Double(count), unit: "adet",
            kind: .fruit,
            kcal: 105, p: 1.3, c: 27, f: 0.3,
            trimFactor: 0.4
        )
    }

    private static func gogusEt(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Tavuk göğsü (çiğ)", baseAmount: g, unit: "g",
            kind: .protein,
            kcal: 1.65, p: 0.31, c: 0, f: 0.036,
            trimFactor: 0.0
        )
    }

    private static func butEt(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Tavuk but, derisiz (çiğ)", baseAmount: g, unit: "g",
            kind: .protein,
            kcal: 1.20, p: 0.20, c: 0, f: 0.043,
            trimFactor: 0.0
        )
    }

    private static func pirzolaEt(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Tavuk pirzola, derisiz (çiğ)", baseAmount: g, unit: "g",
            kind: .protein,
            kcal: 1.45, p: 0.22, c: 0, f: 0.06,
            trimFactor: 0.0
        )
    }

    private static func bulgur(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Bulgur (çiğ)", baseAmount: g, unit: "g",
            kind: .carb,
            kcal: 3.42, p: 0.123, c: 0.76, f: 0.013,
            trimFactor: 1.0
        )
    }

    private static func pirinc(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Pirinç (çiğ)", baseAmount: g, unit: "g",
            kind: .carb,
            kcal: 3.60, p: 0.07, c: 0.80, f: 0.007,
            trimFactor: 1.0
        )
    }

    private static func patates(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Patates (çiğ)", baseAmount: g, unit: "g",
            kind: .carb,
            kcal: 0.77, p: 0.02, c: 0.17, f: 0.001,
            trimFactor: 1.0
        )
    }

    private static func yogurt(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Yoğurt", baseAmount: g, unit: "g",
            kind: .dairy,
            kcal: 0.60, p: 0.04, c: 0.05, f: 0.03,
            trimFactor: 0.0
        )
    }

    private static func zeytinyagi(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Zeytinyağı", baseAmount: g, unit: "g",
            kind: .fat,
            kcal: 9.0, p: 0, c: 0, f: 1.0,
            trimFactor: 1.0
        )
    }

    private static func salata() -> PlannedItem {
        PlannedItem(
            name: "Yeşil salata (serbest)", baseAmount: 1, unit: "tabak",
            kind: .veg,
            kcal: 0, p: 0, c: 0, f: 0,
            trimFactor: 0.0
        )
    }

    private static func tonBalik(_ g: Double) -> PlannedItem {
        PlannedItem(
            name: "Ton balığı (suda)", baseAmount: g, unit: "g",
            kind: .protein,
            kcal: 1.16, p: 0.26, c: 0, f: 0.008,
            trimFactor: 0.0
        )
    }

    // MARK: - Day templates

    static let gogusDay = DayTemplate(
        type: .gogus,
        meals: [
            PlannedMeal(slot: .sabah, items: [
                yumurtaTam(3), lor(100), yulaf(50), elma()
            ]),
            PlannedMeal(slot: .ogle, items: [
                gogusEt(220), bulgur(55), yogurt(200), salata()
            ]),
            PlannedMeal(slot: .ara, items: [
                yogurt(250), muz()
            ]),
            PlannedMeal(slot: .aksam, items: [
                gogusEt(180), patates(300), salata(), zeytinyagi(10)
            ]),
        ]
    )

    static let butDay = DayTemplate(
        type: .but,
        meals: [
            PlannedMeal(slot: .sabah, items: [
                yumurtaTam(2), yumurtaBeyaz(2), lor(100), yulaf(50), elma()
            ]),
            PlannedMeal(slot: .ogle, items: [
                butEt(270), pirinc(50), yogurt(200), salata()
            ]),
            PlannedMeal(slot: .ara, items: [
                yogurt(250), muz()
            ]),
            PlannedMeal(slot: .aksam, items: [
                butEt(240), patates(300), salata()
            ]),
        ]
    )

    static let pirzolaDay = DayTemplate(
        type: .pirzola,
        meals: [
            PlannedMeal(slot: .sabah, items: [
                yumurtaTam(2), yumurtaBeyaz(3), lor(100), yulaf(40), elma()
            ]),
            PlannedMeal(slot: .ogle, items: [
                pirzolaEt(260), bulgur(45), yogurt(200), salata()
            ]),
            PlannedMeal(slot: .ara, items: [
                yogurt(250), muz()
            ]),
            PlannedMeal(slot: .aksam, items: [
                pirzolaEt(230), patates(250), salata()
            ]),
        ]
    )

    static let freeDay = DayTemplate(
        type: .free,
        meals: [
            PlannedMeal(slot: .sabah, items: [
                yumurtaTam(3), lor(100), yulaf(50), elma()
            ]),
            PlannedMeal(slot: .ogle, items: [
                tonBalik(150), bulgur(55), yogurt(200), salata()
            ]),
            PlannedMeal(slot: .ara, items: [
                yogurt(250), muz()
            ]),
            PlannedMeal(slot: .aksam, items: [
                gogusEt(200), patates(300), salata(), zeytinyagi(10)
            ]),
        ]
    )
}

// MARK: - Weekly helpers

enum Weekday: Int, CaseIterable, Identifiable, Hashable {
    case pzt = 2, sal = 3, car = 4, per = 5, cum = 6, cmt = 7, paz = 1
    var id: Int { rawValue }

    var short: String {
        switch self {
        case .pzt: return "Pzt"
        case .sal: return "Sal"
        case .car: return "Çar"
        case .per: return "Per"
        case .cum: return "Cum"
        case .cmt: return "Cmt"
        case .paz: return "Paz"
        }
    }

    var long: String {
        switch self {
        case .pzt: return "Pazartesi"
        case .sal: return "Salı"
        case .car: return "Çarşamba"
        case .per: return "Perşembe"
        case .cum: return "Cuma"
        case .cmt: return "Cumartesi"
        case .paz: return "Pazar"
        }
    }

    static var orderedTrWeek: [Weekday] { [.pzt, .sal, .car, .per, .cum, .cmt, .paz] }

    static var today: Weekday {
        let wd = Calendar.current.component(.weekday, from: Date())
        return Weekday(rawValue: wd) ?? .pzt
    }
}
