import Foundation
import SwiftData

@Model
final class FoodPreset {
    var presetID: String = ""
    var name: String = ""
    var brand: String = ""
    var category: String = "Supplement"
    var servingLabel: String = "ölçek"
    var servingGrams: Double = 0
    var defaultServings: Double = 1
    var calories: Double = 0
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var note: String = ""
    var searchText: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

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
        var changed = false

        for group in Dictionary(grouping: existing, by: \FoodPreset.presetID).values {
            guard let keeper = group.sorted(by: {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
            }).first else { continue }
            byID[keeper.presetID] = keeper
            for duplicate in group where duplicate.persistentModelID != keeper.persistentModelID {
                ctx.delete(duplicate)
                changed = true
            }
        }

        for spec in defaults {
            let preset: FoodPreset
            if let existingPreset = byID[spec.presetID] {
                preset = existingPreset
            } else {
                preset = FoodPreset(
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
                ctx.insert(preset)
                byID[spec.presetID] = preset
                changed = true
            }

            if apply(spec, to: preset) {
                preset.updatedAt = .now
                changed = true
            }
        }

        if changed {
            ctx.saveOrReport("varsayılan yemekleri hazırlama")
        }
    }

    /// Seed her açılışta çalışabilir; aynı değerleri tekrar yazarak `updatedAt` ve
    /// CloudKit export üretmez. Yalnız gerçek bir spec değişikliği varsa `true` döner.
    private static func apply(_ spec: Spec, to preset: FoodPreset) -> Bool {
        var changed = false

        func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<FoodPreset, Value>, _ value: Value) {
            guard preset[keyPath: keyPath] != value else { return }
            preset[keyPath: keyPath] = value
            changed = true
        }

        set(\.name, spec.name)
        set(\.brand, spec.brand)
        set(\.category, "Supplement")
        set(\.servingLabel, "ölçek")
        set(\.servingGrams, spec.servingGrams)
        set(\.defaultServings, spec.defaultServings)
        set(\.calories, spec.calories)
        set(\.protein, Optional(spec.protein))
        set(\.carbs, Optional(spec.carbs))
        set(\.fat, Optional(spec.fat))
        set(\.note, spec.note)
        set(\.searchText, spec.searchText)
        set(\.sortOrder, spec.sortOrder)
        return changed
    }
}

// MARK: - Sık girilen yemekler (otomatik preset)

/// Kullanıcının son N günde 3+ kez girdiği yemeklerden türetilen hızlı-ekle önerisi.
/// FoodEntry günlüğünden deterministik (AI'sız, cihazda) hesaplanır; kalıcı değildir —
/// her açılışta canlı türetilir, böylece daima gerçek alışkanlığı yansıtır.
struct FrequentFood: Identifiable, Hashable {
    let key: String            // normalize edilmiş anahtar (grup kimliği)
    let displayName: String    // en sık ham yazım → input'a yazılacak metin
    let count: Int             // toplam giriş sayısı (son pencerede)
    let dayCount: Int          // kaç farklı günde girildi
    let lastUsed: Date
    let calories: Double       // grup medyanı (kombolara karşı dayanıklı)
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let grams: Double?

    var id: String { key }
}

enum FrequentFoodDetector {
    /// Türkçe-duyarlı normalize (büyük/küçük + diakritik + boşluk sadeleştirme).
    /// FoodPresetWidget'ın arama normalize'i ile aynı davranış (tutarlılık için).
    static func normalizedKey(_ text: String) -> String {
        let locale = Locale(identifier: "tr_TR")
        return text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .lowercased(with: locale)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Son `windowDays` günde `minCount`+ kez girilen yemekleri sıklık sırasıyla döner.
    /// Sıralama: sıklık azalan, eşitlikte en son kullanılan üstte. `limit` ile kırpılır.
    static func detect(
        from entries: [FoodEntry],
        now: Date = .now,
        windowDays: Int = 60,
        minCount: Int = 3,
        limit: Int = 16
    ) -> [FrequentFood] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let recent = entries.filter {
            $0.date >= cutoff &&
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !recent.isEmpty else { return [] }

        var groups: [String: [FoodEntry]] = [:]
        for e in recent {
            let key = normalizedKey(e.name)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(e)
        }

        var result: [FrequentFood] = []
        for (key, items) in groups where items.count >= minCount {
            let days = Set(items.map { cal.startOfDay(for: $0.date) }).count
            let last = items.map(\.date).max() ?? now
            result.append(FrequentFood(
                key: key,
                displayName: mostCommonName(items),
                count: items.count,
                dayCount: days,
                lastUsed: last,
                calories: median(items.map(\.calories)) ?? 0,
                protein: median(items.compactMap(\.protein)),
                carbs: median(items.compactMap(\.carbs)),
                fat: median(items.compactMap(\.fat)),
                grams: median(items.compactMap(\.grams))
            ))
        }

        result.sort {
            $0.count != $1.count ? $0.count > $1.count : $0.lastUsed > $1.lastUsed
        }
        return Array(result.prefix(limit))
    }

    /// Grubun en sık ham yazımı (eşitlikte en yeni girilen kazanır).
    private static func mostCommonName(_ items: [FoodEntry]) -> String {
        var counts: [String: (n: Int, last: Date)] = [:]
        for e in items {
            let name = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let prev = counts[name]
            counts[name] = (n: (prev?.n ?? 0) + 1, last: max(prev?.last ?? .distantPast, e.date))
        }
        let best = counts.max {
            $0.value.n != $1.value.n ? $0.value.n < $1.value.n : $0.value.last < $1.value.last
        }
        return best?.key ?? (items.first?.name ?? "")
    }

    private static func median(_ values: [Double]) -> Double? {
        let v = values.filter { $0.isFinite }.sorted()
        guard !v.isEmpty else { return nil }
        let mid = v.count / 2
        return v.count.isMultiple(of: 2) ? (v[mid - 1] + v[mid]) / 2 : v[mid]
    }
}
