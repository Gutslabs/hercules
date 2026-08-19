import Foundation

struct FoodLookupSkill: AgentSkill {
    let id = "food.openfoodfacts"
    let name = "Food Lookup"
    let description = "Protein, kalori, makro ve ürün sorularında Open Food Facts'ten besin adayı getirir."

    private let session: URLSession

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init(session: URLSession? = nil) {
        self.session = session ?? Self.defaultSession
    }

    func canHandle(_ query: String) -> Bool {
        let lower = fold(query)
        let foodIntent = [
            "yemek", "ogun", "öğün", "kalori", "makro", "protein",
            "market", "urun", "ürün", "marka", "ne yiy", "ucuz",
            "ulasılabilir", "ulaşılabilir", "besin", "barcode"
        ]
        let researchIntent = ["pubmed", "makale", "calisma", "çalışma", "arastirma", "araştırma", "paper"]
        return containsAny(lower, foodIntent) && !containsAny(lower, researchIntent)
    }

    func run(query: String, context: AgentContext) async throws -> SkillResult? {
        let products = try await searchProducts(query: query)
        let productLines = products.prefix(4).map { product in
            "- \(product.name)\(product.brand.map { " · \($0)" } ?? ""): \(product.macroLine)"
        }
        let baselineLines = baselineFoods(for: query).map { "- \($0)" }

        guard !productLines.isEmpty || !baselineLines.isEmpty else { return nil }

        var sections: [String] = []
        if !baselineLines.isEmpty {
            sections.append("""
            Ulaşılabilir yüksek-protein referansları:
            \(baselineLines.joined(separator: "\n"))
            """)
        }
        if !productLines.isEmpty {
            sections.append("""
            Open Food Facts ürün/veri adayları:
            \(productLines.joined(separator: "\n"))
            """)
        }

        return SkillResult(
            skillID: id,
            title: "Food Lookup Adayları",
            content: """
            Bunları porsiyon, pişmiş/çiğ farkı ve kullanıcının bütçe/erişilebilirlik durumuna göre yorumla.
            \(sections.joined(separator: "\n\n"))
            """,
            sources: productLines.isEmpty ? [] : ["https://world.openfoodfacts.org"]
        )
    }

    private func searchProducts(query: String) async throws -> [FoodProductCandidate] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "4"),
            URLQueryItem(name: "fields", value: "product_name,brands,nutriments")
        ]
        let url = components.url!
        let (data, _) = try await session.data(from: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let products = root?["products"] as? [[String: Any]] ?? []

        return products.compactMap { item in
            guard let name = (item["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { return nil }
            let brand = (item["brands"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let nutriments = item["nutriments"] as? [String: Any] ?? [:]

            return FoodProductCandidate(
                name: name,
                brand: brand?.isEmpty == false ? brand : nil,
                kcal100g: number(from: nutriments["energy-kcal_100g"]),
                protein100g: number(from: nutriments["proteins_100g"]),
                carbs100g: number(from: nutriments["carbohydrates_100g"]),
                fat100g: number(from: nutriments["fat_100g"])
            )
        }
    }

    private func number(from value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func baselineFoods(for query: String) -> [String] {
        let lower = fold(query)
        guard containsAny(lower, ["protein", "ucuz", "ulasılabilir", "ulaşılabilir", "ne yiy", "ogun", "öğün", "yemek"]) else {
            return []
        }

        return [
            "Tavuk göğsü, pişmiş: yaklaşık 31g protein / 100g; sade ve ucuz ana kaynak.",
            "Hindi göğüs veya yağsız dana kıyma: yaklaşık 26-30g protein / 100g; fiyat/erişim durumuna göre.",
            "Ton balığı: yaklaşık 23-25g protein / 100g; pratik ama sodyum ve bütçe değişebilir.",
            "Yumurta: yaklaşık 6g protein / adet; yanına yoğurt/lor eklenirse öğün daha proteinli olur.",
            "Süzme yoğurt veya Greek yogurt: yaklaşık 8-10g protein / 100g; kolay ara öğün.",
            "Lor/cottage cheese: yaklaşık 15-18g protein / 100g; uygun fiyatlıysa çok iyi.",
            "Mercimek/nohut, pişmiş: yaklaşık 8-9g protein / 100g; protein var ama karb da yüksek, ana protein değil destek gibi düşün."
        ]
    }

    private func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.map { fold($0) }.contains { text.contains($0) }
    }
}

private struct FoodProductCandidate {
    let name: String
    let brand: String?
    let kcal100g: Double?
    let protein100g: Double?
    let carbs100g: Double?
    let fat100g: Double?

    var macroLine: String {
        let kcal = kcal100g.map { "\(Fmt.int($0)) kcal" } ?? "? kcal"
        let protein = protein100g.map { "P \(Fmt.num($0, digits: 1))g" } ?? "P ?"
        let carbs = carbs100g.map { "K \(Fmt.num($0, digits: 1))g" } ?? "K ?"
        let fat = fat100g.map { "Y \(Fmt.num($0, digits: 1))g" } ?? "Y ?"
        return "\(kcal) / 100g, \(protein), \(carbs), \(fat)"
    }
}
