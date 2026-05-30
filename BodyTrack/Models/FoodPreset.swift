import Foundation
import SwiftData

@Model
final class FoodPreset {
    var presetID: String
    var name: String
    var brand: String
    var category: String
    var servingLabel: String
    var servingGrams: Double
    var defaultServings: Double
    var calories: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var note: String
    var searchText: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        presetID: String,
        name: String,
        brand: String,
        category: String = "Supplement",
        servingLabel: String = "ölçek",
        servingGrams: Double,
        defaultServings: Double = 1,
        calories: Double,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        note: String = "",
        searchText: String = "",
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.presetID = presetID
        self.name = name
        self.brand = brand
        self.category = category
        self.servingLabel = servingLabel
        self.servingGrams = servingGrams
        self.defaultServings = defaultServings
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.note = note
        self.searchText = searchText
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func calories(for servings: Double) -> Double {
        calories * servings
    }

    func protein(for servings: Double) -> Double? {
        protein.map { $0 * servings }
    }

    func carbs(for servings: Double) -> Double? {
        carbs.map { $0 * servings }
    }

    func fat(for servings: Double) -> Double? {
        fat.map { $0 * servings }
    }

    func grams(for servings: Double) -> Double {
        servingGrams * servings
    }

    func entryName(for servings: Double) -> String {
        "\(brand) \(name) (\(servingCountText(servings)))"
    }

    func servingCountText(_ servings: Double) -> String {
        let count = servings == floor(servings) ? "\(Int(servings))" : Fmt.num(servings, digits: 1)
        return "\(count) \(servingLabel)"
    }

    func makeFoodEntry(servings: Double) -> FoodEntry {
        FoodEntry(
            date: .now,
            name: entryName(for: servings),
            grams: grams(for: servings),
            calories: calories(for: servings),
            protein: protein(for: servings),
            carbs: carbs(for: servings),
            fat: fat(for: servings)
        )
    }
}

struct FoodPresetSeed {
    private struct Spec {
        let presetID: String
        let name: String
        let brand: String
        let servingGrams: Double
        let defaultServings: Double
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let note: String
        let searchText: String
        let sortOrder: Int
    }

    private static let defaults: [Spec] = [
        Spec(
            presetID: "ssn-command-quadro-whey-creme-caramel",
            name: "Command Quadro Whey Creme Caramel",
            brand: "SSN",
            servingGrams: 30,
            defaultServings: 2,
            calories: 115,
            protein: 22.1,
            carbs: 4.8,
            fat: 0.8,
            note: "Etiket: 30g servis, 70 servis. 2 ölçek: 230 kcal, P44.2g, K9.6g, Y1.6g.",
            searchText: "ssn command quadro whey creme caramel karamel vanilya protein tozu whey",
            sortOrder: 10
        ),
        Spec(
            presetID: "gentopure-wpc80-chocolate-milk",
            name: "WPC80 Chocolate Milk",
            brand: "Gentopure",
            servingGrams: 30,
            defaultServings: 2,
            calories: 121,
            protein: 24,
            carbs: 3,
            fat: 1.7,
            note: "Görselde 30g servis ve 24g protein net. Kcal/karb/yağ WPC80 standardına yakın yaklaşık girildi.",
            searchText: "gentopure wpc80 whey protein chocolate milk sutlu cikolata protein tozu",
            sortOrder: 20
        ),
        Spec(
            presetID: "protein-ocean-whey-protein",
            name: "Whey Protein",
            brand: "Protein Ocean",
            servingGrams: 25,
            defaultServings: 2,
            calories: 86,
            protein: 18.8,
            carbs: 1.5,
            fat: 0.3,
            note: "Etiket: 25g servis. 2 servis: 172 kcal, P37.6g, K3g, Y0.6g.",
            searchText: "protein ocean whey protein protein tozu digezyme wpc",
            sortOrder: 30
        )
    ]

    static var defaultPresetIDs: Set<String> {
        Set(defaults.map(\.presetID))
    }

    @MainActor
    static func upsertDefaults(_ ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<FoodPreset>())) ?? []
        var byID: [String: FoodPreset] = [:]
        for preset in existing where byID[preset.presetID] == nil {
            byID[preset.presetID] = preset
        }

        for spec in defaults {
            let preset = byID[spec.presetID] ?? FoodPreset(
                presetID: spec.presetID,
                name: spec.name,
                brand: spec.brand,
                servingGrams: spec.servingGrams,
                defaultServings: spec.defaultServings,
                calories: spec.calories,
                protein: spec.protein,
                carbs: spec.carbs,
                fat: spec.fat,
                note: spec.note,
                searchText: spec.searchText,
                sortOrder: spec.sortOrder
            )

            preset.name = spec.name
            preset.brand = spec.brand
            preset.category = "Supplement"
            preset.servingLabel = "ölçek"
            preset.servingGrams = spec.servingGrams
            preset.defaultServings = spec.defaultServings
            preset.calories = spec.calories
            preset.protein = spec.protein
            preset.carbs = spec.carbs
            preset.fat = spec.fat
            preset.note = spec.note
            preset.searchText = spec.searchText
            preset.sortOrder = spec.sortOrder
            preset.updatedAt = .now

            if byID[spec.presetID] == nil {
                ctx.insert(preset)
                byID[spec.presetID] = preset
            }
        }

        ctx.saveOrReport()
    }
}
