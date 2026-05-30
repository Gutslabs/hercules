import Foundation

final class NutritionDataProvider {
    static let shared = NutritionDataProvider()

    struct CachePayload: Codable {
        var version: Int
        var savedAt: Date
        var entries: [String: NutritionCacheEntry]
    }

    struct NutritionCacheEntry: Codable {
        var profile: NutritionLookupProfile
        var updatedAt: Date
    }

    struct NutritionLookupProfile: Codable {
        var displayName: String
        var sourceName: String
        var sourceURL: String?
        var nutrientsPer100g: [String: Double]
        var caloriesPer100g: Double?
    }

    struct NutrientSpec: Hashable {
        let key: String
        let label: String
        let unit: String
        let displayDigits: Int
        let targetMale: Double
        let targetFemale: Double
        let foods: [String]

        func target(for profile: AgentUserProfileSnapshot?) -> Double {
            profile?.sex == .female ? targetFemale : targetMale
        }
    }

    struct NutrientCoverage {
        let spec: NutrientSpec
        let averageDaily: Double
        let target: Double

        var ratio: Double {
            guard target > 0 else { return 0 }
            return min(2.0, averageDaily / target)
        }
    }

    struct NutritionAnalysis {
        let periodDays: Int
        let loggedDays: Int
        let uniqueFoodCount: Int
        let matchedFoodCount: Int
        let unmatchedFoods: [String]
        let coverage: [NutrientCoverage]
        let foodSuggestions: [String]
        let sourceSummary: String
        let sources: [String]
    }

    private let cacheURL: URL
    private var cache: [String: NutritionCacheEntry] = [:]
    private let session: URLSession
    private let usdaAPIKey: String
    private let cacheMaxAge: TimeInterval = 45 * 24 * 60 * 60

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let nutrientSpecs: [NutrientSpec] = [
        NutrientSpec(key: "fiber", label: "Lif", unit: "g", displayDigits: 1, targetMale: 30, targetFemale: 25, foods: ["yulaf", "baklagil", "sebze", "meyve", "chia/keten"]),
        NutrientSpec(key: "calcium", label: "Kalsiyum", unit: "mg", displayDigits: 0, targetMale: 1000, targetFemale: 1000, foods: ["yoğurt/kefir", "süt", "lor", "peynir", "kalsiyumlu maden suyu"]),
        NutrientSpec(key: "iron", label: "Demir", unit: "mg", displayDigits: 1, targetMale: 8, targetFemale: 18, foods: ["kırmızı et", "yumurta", "mercimek", "ıspanak + C vitamini"]),
        NutrientSpec(key: "magnesium", label: "Magnezyum", unit: "mg", displayDigits: 0, targetMale: 420, targetFemale: 320, foods: ["yulaf", "badem", "kabak çekirdeği", "baklagil", "kakao"]),
        NutrientSpec(key: "potassium", label: "Potasyum", unit: "mg", displayDigits: 0, targetMale: 3400, targetFemale: 2600, foods: ["patates", "muz", "yoğurt", "baklagil", "yeşillik"]),
        NutrientSpec(key: "zinc", label: "Çinko", unit: "mg", displayDigits: 1, targetMale: 11, targetFemale: 8, foods: ["kırmızı et", "yumurta", "kabak çekirdeği", "deniz ürünü"]),
        NutrientSpec(key: "vitamin_c", label: "C vitamini", unit: "mg", displayDigits: 0, targetMale: 90, targetFemale: 75, foods: ["kivi", "portakal", "çilek", "biber", "brokoli"]),
        NutrientSpec(key: "vitamin_a", label: "A vitamini", unit: "mcg", displayDigits: 0, targetMale: 900, targetFemale: 700, foods: ["havuç", "yumurta", "ıspanak", "tatlı patates"]),
        NutrientSpec(key: "vitamin_d", label: "D vitamini", unit: "mcg", displayDigits: 1, targetMale: 15, targetFemale: 15, foods: ["somon/sardalya", "yumurta", "D vitaminli süt/yoğurt"]),
        NutrientSpec(key: "vitamin_e", label: "E vitamini", unit: "mg", displayDigits: 1, targetMale: 15, targetFemale: 15, foods: ["badem", "fındık", "zeytinyağı", "avokado"]),
        NutrientSpec(key: "folate", label: "Folat", unit: "mcg", displayDigits: 0, targetMale: 400, targetFemale: 400, foods: ["ıspanak", "mercimek", "nohut", "avokado", "yeşillik"]),
        NutrientSpec(key: "b12", label: "B12", unit: "mcg", displayDigits: 1, targetMale: 2.4, targetFemale: 2.4, foods: ["yumurta", "süt/yoğurt", "et", "balık"]),
        NutrientSpec(key: "omega3", label: "Omega-3", unit: "g", displayDigits: 1, targetMale: 1.6, targetFemale: 1.1, foods: ["somon", "sardalya", "ceviz", "chia/keten"])
    ]

    private init() {
        cacheURL = Self.makeCacheURL()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "HerculesNutritionSkill/1.0 (local macOS app; contact: hercules.local)"
        ]
        session = URLSession(configuration: config)
        usdaAPIKey = UserDefaults.standard.string(forKey: "hercules.usda.api_key") ?? "DEMO_KEY"
        load()
    }

    func analyze(
        data: AgentDataSnapshot,
        days: Int,
        maxUniqueFoods: Int,
        networkLookupLimit: Int
    ) async -> NutritionAnalysis? {
        let periodDays = max(1, min(days, 30))
        let cal = Calendar.current
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(periodDays - 1), to: .now) ?? .now)
        let periodFoods = data.foods.filter { $0.date >= start }
        guard !periodFoods.isEmpty else { return nil }

        let loggedDays = Set(periodFoods.map { cal.startOfDay(for: $0.date) }).count
        let grouped = Dictionary(grouping: periodFoods) { Self.normalizedFoodKey($0.name) }
        let candidates = grouped
            .map { key, entries -> (key: String, display: String, score: Double, entries: [AgentFoodSnapshot]) in
                let display = entries.max(by: { $0.calories < $1.calories })?.name ?? key
                let score = entries.reduce(0) { $0 + $1.calories } + Double(entries.count) * 80
                return (key, display, score, entries)
            }
            .sorted { $0.score > $1.score }
            .prefix(maxUniqueFoods)

        var profileByKey: [String: NutritionLookupProfile] = [:]
        var unmatched: [String] = []
        var networkRemaining = max(0, networkLookupLimit)

        for item in candidates {
            let result = await lookupProfile(for: item.display, key: item.key, allowNetwork: networkRemaining > 0)
            if result.usedNetwork {
                networkRemaining -= 1
            }
            if let profile = result.profile {
                profileByKey[item.key] = profile
            } else {
                unmatched.append(Self.cleanDisplayName(item.display))
            }
        }

        guard !profileByKey.isEmpty else { return nil }

        var totals: [String: Double] = [:]
        var sourceNames: Set<String> = []
        var sourceURLs: Set<String> = []

        for item in candidates {
            guard let profile = profileByKey[item.key] else { continue }
            sourceNames.insert(profile.sourceName)
            if let sourceURL = profile.sourceURL {
                sourceURLs.insert(sourceURL)
            }
            for entry in item.entries {
                guard let grams = grams(for: entry, profile: profile), grams > 0 else { continue }
                let factor = grams / 100.0
                for (key, value) in profile.nutrientsPer100g {
                    totals[key, default: 0] += value * factor
                }
            }
        }

        let profile = data.profile
        let denominator = Double(max(1, loggedDays))
        let coverage = Self.nutrientSpecs.map { spec in
            NutrientCoverage(
                spec: spec,
                averageDaily: (totals[spec.key] ?? 0) / denominator,
                target: spec.target(for: profile)
            )
        }
        .sorted { lhs, rhs in
            if lhs.ratio == rhs.ratio {
                return lhs.spec.label < rhs.spec.label
            }
            return lhs.ratio < rhs.ratio
        }

        let suggestions = Self.suggestions(from: coverage)
        let sourceSummary = sourceNames.sorted().joined(separator: " + ")
        return NutritionAnalysis(
            periodDays: periodDays,
            loggedDays: loggedDays,
            uniqueFoodCount: candidates.count,
            matchedFoodCount: profileByKey.count,
            unmatchedFoods: unmatched,
            coverage: coverage,
            foodSuggestions: suggestions,
            sourceSummary: sourceSummary.isEmpty ? "cache/dış veri yok" : sourceSummary,
            sources: Array(sourceURLs).sorted()
        )
    }

    func todayMacroContext(data: AgentDataSnapshot) -> String? {
        guard let profile = data.profile,
              let latestWeight = data.measurements.first?.weight
        else { return nil }

        let bodyFat = data.measurements.first?.bodyFat ?? profile.manualBodyFat
        let target = CalorieCalculator.compute(
            weight: latestWeight,
            height: profile.height,
            age: profile.age,
            sex: profile.sex,
            bodyFat: bodyFat,
            activity: profile.activity,
            goal: profile.goal,
            manualOffset: profile.manualCalorieOffset,
            manualOffsetMacro: profile.manualCalorieOffsetMacro,
            manualProteinGrams: profile.manualProteinGrams,
            manualCarbsGrams: profile.manualCarbsGrams,
            manualFatGrams: profile.manualFatGrams
        )

        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        let todays = data.foods.filter { $0.date >= todayStart && cal.isDateInToday($0.date) }
        let kcal = todays.reduce(0) { $0 + $1.calories }
        let protein = todays.compactMap(\.protein).reduce(0, +)
        let carbs = todays.compactMap(\.carbs).reduce(0, +)
        let fat = todays.compactMap(\.fat).reduce(0, +)

        let remainingKcal = target.goalCalories - kcal
        let remainingProtein = target.protein.grams - protein
        let remainingCarbs = target.carbs.grams - carbs
        let remainingFat = target.fat.grams - fat

        return "\(Fmt.int(kcal))/\(Fmt.int(target.goalCalories)) kcal · P \(Fmt.int(protein))/\(Fmt.int(target.protein.grams))g (kalan \(Fmt.signed(remainingProtein, digits: 0))g) · K \(Fmt.int(carbs))/\(Fmt.int(target.carbs.grams))g (kalan \(Fmt.signed(remainingCarbs, digits: 0))g) · Y \(Fmt.int(fat))/\(Fmt.int(target.fat.grams))g (kalan \(Fmt.signed(remainingFat, digits: 0))g) · kalan kcal \(Fmt.signed(remainingKcal, digits: 0))"
    }

    func proteinPresets(data: AgentDataSnapshot, limit: Int) -> [String] {
        data.foodPresets
            .filter { preset in
                let text = Self.fold("\(preset.name) \(preset.brand) \(preset.category) \(preset.searchText)")
                return Self.containsAny(text, ["protein", "whey", "casein", "tozu", "supplement"])
            }
            .prefix(limit)
            .map { preset in
                let p = preset.protein.map { "P\(Fmt.num($0, digits: 1))g" } ?? "P?"
                return "\(preset.brand) \(preset.name): \(Fmt.int(preset.calories)) kcal/\(preset.servingLabel), \(p)"
            }
    }

    func savedProteinRecipes(data: AgentDataSnapshot, limit: Int) -> [String] {
        data.recipes
            .filter { recipe in
                let text = Self.fold("\(recipe.title) \(recipe.summary ?? "") \(recipe.ingredientsText ?? "")")
                return Self.containsAny(text, ["protein", "whey", "bowl", "yulaf", "yoğurt", "yogurt", "pankek", "smoothie"])
            }
            .prefix(limit)
            .map { recipe in
                let macro = recipe.protein.map { " · P\(Fmt.int($0))g" } ?? ""
                return "\(recipe.title)\(macro)"
            }
    }

    private func lookupProfile(
        for foodName: String,
        key: String,
        allowNetwork: Bool
    ) async -> (profile: NutritionLookupProfile?, usedNetwork: Bool) {
        let now = Date()
        if let cached = cache[key],
           now.timeIntervalSince(cached.updatedAt) < cacheMaxAge {
            return (cached.profile, false)
        }
        guard allowNetwork else { return (cache[key]?.profile, false) }

        let query = Self.searchQuery(for: foodName)
        let productFirst = Self.looksLikePackagedProduct(foodName)
        let profile: NutritionLookupProfile?
        if productFirst {
            if let offProfile = await fetchOpenFoodFactsProfile(query: query) {
                profile = offProfile
            } else {
                profile = await fetchUSDAProfile(query: query)
            }
        } else {
            if let usdaProfile = await fetchUSDAProfile(query: query) {
                profile = usdaProfile
            } else {
                profile = await fetchOpenFoodFactsProfile(query: query)
            }
        }

        if let profile {
            cache[key] = NutritionCacheEntry(profile: profile, updatedAt: now)
            persist()
        }
        return (profile, true)
    }

    private func fetchUSDAProfile(query: String) async -> NutritionLookupProfile? {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: usdaAPIKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "5"),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey (FNDDS),Branded")
        ]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = root["foods"] as? [[String: Any]]
        else { return nil }

        let sorted = foods.sorted { lhs, rhs in
            Self.usdaDataTypePriority(lhs["dataType"] as? String) < Self.usdaDataTypePriority(rhs["dataType"] as? String)
        }

        for food in sorted {
            if let profile = Self.profileFromUSDAFood(food) {
                return profile
            }
        }
        return nil
    }

    private func fetchOpenFoodFactsProfile(query: String) async -> NutritionLookupProfile? {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "4"),
            URLQueryItem(name: "fields", value: "product_name,brands,nutriments,url")
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let products = root["products"] as? [[String: Any]]
            else { return nil }

            for product in products {
                if let profile = Self.profileFromOpenFoodFactsProduct(product) {
                    return profile
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func grams(for entry: AgentFoodSnapshot, profile: NutritionLookupProfile) -> Double? {
        if let grams = entry.grams, grams > 0 {
            return grams
        }
        guard let kcal100 = profile.caloriesPer100g, kcal100 > 20 else { return nil }
        return (entry.calories / kcal100) * 100.0
    }

    static func profileFromUSDAFood(_ food: [String: Any]) -> NutritionLookupProfile? {
        guard let nutrients = food["foodNutrients"] as? [[String: Any]], !nutrients.isEmpty else {
            return nil
        }

        var values: [String: Double] = [:]
        var calories: Double?

        for item in nutrients {
            let name = ((item["nutrientName"] as? String)
                        ?? (item["name"] as? String)
                        ?? ((item["nutrient"] as? [String: Any])?["name"] as? String)
                        ?? "")
            let unit = ((item["unitName"] as? String)
                        ?? (item["unit"] as? String)
                        ?? ((item["nutrient"] as? [String: Any])?["unitName"] as? String)
                        ?? "")
            let amount = Self.number(from: item["value"])
                ?? Self.number(from: item["amount"])
                ?? Self.number(from: item["nutrientAmount"])
            guard let amount else { continue }

            let folded = Self.fold(name)
            if folded == "energy" || folded.contains("energy") {
                if unit.uppercased().contains("KCAL") {
                    calories = amount
                }
                continue
            }
            guard let key = Self.nutrientKey(forUSDAName: folded) else { continue }
            let baseUnit = Self.spec(for: key)?.unit ?? "mg"
            let converted = Self.convert(amount: amount, from: unit, to: baseUnit)
            values[key, default: 0] += converted
        }

        guard !values.isEmpty else { return nil }
        let fdcID = Self.intString(food["fdcId"])
        let sourceURL = fdcID.map { "https://fdc.nal.usda.gov/fdc-app.html#/food-details/\($0)/nutrients" }
        let description = (food["description"] as? String) ?? "USDA food"
        return NutritionLookupProfile(
            displayName: description,
            sourceName: "USDA FoodData Central",
            sourceURL: sourceURL,
            nutrientsPer100g: values,
            caloriesPer100g: calories
        )
    }

    static func profileFromOpenFoodFactsProduct(_ product: [String: Any]) -> NutritionLookupProfile? {
        guard let nutriments = product["nutriments"] as? [String: Any] else { return nil }

        let fieldMap: [(key: String, field: String)] = [
            ("fiber", "fiber_100g"),
            ("calcium", "calcium_100g"),
            ("iron", "iron_100g"),
            ("magnesium", "magnesium_100g"),
            ("potassium", "potassium_100g"),
            ("zinc", "zinc_100g"),
            ("vitamin_c", "vitamin-c_100g"),
            ("vitamin_a", "vitamin-a_100g"),
            ("vitamin_d", "vitamin-d_100g"),
            ("vitamin_e", "vitamin-e_100g"),
            ("folate", "folates_100g"),
            ("folate", "vitamin-b9_100g"),
            ("b12", "vitamin-b12_100g"),
            ("omega3", "omega-3-fat_100g")
        ]

        var values: [String: Double] = [:]
        for item in fieldMap {
            guard let amount = Self.number(from: nutriments[item.field]) else { continue }
            let unit = (nutriments[item.field.replacingOccurrences(of: "_100g", with: "_unit")] as? String) ?? "g"
            let baseUnit = Self.spec(for: item.key)?.unit ?? "mg"
            values[item.key, default: 0] += Self.convert(amount: amount, from: unit, to: baseUnit)
        }

        guard !values.isEmpty else { return nil }
        let productName = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let brands = (product["brands"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = [brands, productName].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " ")

        return NutritionLookupProfile(
            displayName: display.isEmpty ? "Open Food Facts product" : display,
            sourceName: "Open Food Facts",
            sourceURL: product["url"] as? String,
            nutrientsPer100g: values,
            caloriesPer100g: Self.number(from: nutriments["energy-kcal_100g"])
        )
    }

    static func nutrientKey(forUSDAName folded: String) -> String? {
        if folded.contains("fiber") { return "fiber" }
        if folded.contains("calcium") { return "calcium" }
        if folded.contains("iron") { return "iron" }
        if folded.contains("magnesium") { return "magnesium" }
        if folded.contains("potassium") { return "potassium" }
        if folded.contains("zinc") { return "zinc" }
        if folded.contains("vitamin c") || folded.contains("ascorbic") { return "vitamin_c" }
        if folded.contains("vitamin a") && (folded.contains("rae") || !folded.contains("iu")) { return "vitamin_a" }
        if folded.contains("vitamin d") { return "vitamin_d" }
        if folded.contains("vitamin e") || folded.contains("alpha-tocopherol") { return "vitamin_e" }
        if folded.contains("folate") && (folded.contains("dfe") || folded == "folate") { return "folate" }
        if folded.contains("vitamin b-12") || folded.contains("vitamin b12") || folded.contains("cobalamin") { return "b12" }
        if folded.contains("omega-3") || folded.contains("n-3") || folded.contains("epa") || folded.contains("dha") { return "omega3" }
        return nil
    }

    static func suggestions(from coverage: [NutrientCoverage]) -> [String] {
        var output: [String] = []
        for item in coverage where item.ratio < 0.72 {
            for food in item.spec.foods where !output.contains(food) {
                output.append(food)
                if output.count >= 9 { return output }
            }
        }
        return output
    }

    static func convert(amount: Double, from rawUnit: String, to targetUnit: String) -> Double {
        let unit = rawUnit
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: "µ", with: "u")
        let grams: Double
        if unit.contains("kcal") {
            return amount
        } else if unit == "g" || unit.contains("gram") {
            grams = amount
        } else if unit == "mg" || unit.contains("milligram") {
            grams = amount / 1_000.0
        } else if unit == "ug" || unit == "mcg" || unit.contains("microgram") {
            grams = amount / 1_000_000.0
        } else {
            grams = amount
        }

        switch targetUnit {
        case "g": return grams
        case "mg": return grams * 1_000.0
        case "mcg": return grams * 1_000_000.0
        default: return amount
        }
    }

    static func spec(for key: String) -> NutrientSpec? {
        nutrientSpecs.first { $0.key == key }
    }

    static func searchQuery(for foodName: String) -> String {
        let folded = fold(foodName)
        let mappings: [(needles: [String], query: String)] = [
            (["protein tozu", "whey", "casein"], "whey protein powder"),
            (["tavuk", "gogus", "göğüs"], "cooked chicken breast"),
            (["yumurta"], "whole egg"),
            (["pirinc", "pirinç", "pilav"], "cooked white rice"),
            (["bulgur"], "cooked bulgur"),
            (["yulaf", "oat"], "oats"),
            (["suzme yogurt", "süzme yoğurt", "greek"], "plain greek yogurt"),
            (["yogurt", "yoğurt"], "plain yogurt"),
            (["lor", "cottage"], "cottage cheese"),
            (["ton baligi", "ton balığı", "tuna"], "canned tuna"),
            (["somon", "salmon"], "salmon"),
            (["dana", "kirmizi et", "kırmızı et", "beef"], "beef cooked"),
            (["mercimek"], "cooked lentils"),
            (["nohut"], "cooked chickpeas"),
            (["fasulye"], "cooked beans"),
            (["brokoli"], "broccoli cooked"),
            (["ispanak", "ıspanak"], "spinach cooked"),
            (["muz"], "banana"),
            (["elma"], "apple"),
            (["cilek", "çilek"], "strawberries"),
            (["fistik ezmesi", "fıstık ezmesi"], "peanut butter"),
            (["badem"], "almonds"),
            (["patates"], "potato baked"),
            (["makarna"], "pasta cooked")
        ]
        if let mapped = mappings.first(where: { containsAny(folded, $0.needles) }) {
            return mapped.query
        }

        return cleanDisplayName(foodName)
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+([,.]\d+)?\s*(g|gr|gram|kg|ml|lt|l|adet|dilim|porsiyon|ölçek|olcek)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func looksLikePackagedProduct(_ foodName: String) -> Bool {
        containsAny(fold(foodName), ["whey", "protein tozu", "ssn", "gentopure", "protein ocean", "bar", "marka"])
    }

    static func cleanDisplayName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedFoodKey(_ name: String) -> String {
        fold(cleanDisplayName(name))
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+([,.]\d+)?\b"#, with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
            .prefix(8)
            .joined(separator: " ")
    }

    static func usdaDataTypePriority(_ value: String?) -> Int {
        let value = fold(value ?? "")
        if value.contains("foundation") { return 0 }
        if value.contains("sr legacy") { return 1 }
        if value.contains("survey") { return 2 }
        return 3
    }

    static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.map(fold).contains { text.contains($0) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    static func number(from value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String {
            return Double(value.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    static func intString(_ value: Any?) -> String? {
        if let value = value as? Int { return "\(value)" }
        if let value = value as? Double { return "\(Int(value))" }
        if let value = value as? String, !value.isEmpty { return value }
        return nil
    }

    static func makeCacheURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("nutrition-cache.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? Self.decoder.decode(CachePayload.self, from: data)
        else {
            cache = [:]
            return
        }
        cache = payload.entries
    }

    private func persist() {
        let payload = CachePayload(version: 1, savedAt: .now, entries: cache)
        guard let data = try? Self.encoder.encode(payload) else { return }
        try? data.write(to: cacheURL, options: [.atomic])
    }

}
