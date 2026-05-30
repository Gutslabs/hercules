import Foundation

struct MemoryRecallSkill: AgentSkill {
    let id = "memory.recall"
    let name = "Local Memory Recall"
    let description = "Kullanıcıya ait kalıcı, düzeltilebilir local hafızayı getirir."

    func canHandle(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run(query: String, context: AgentContext) async throws -> SkillResult? {
        // Model yüklüyse semantic (cosine) skoru da harmanlanır; değilse saf lexical (graceful).
        let queryEmbedding = await EmbeddingService.shared.embedQueryIfAvailable(query)
        let memories = LocalMemoryProvider.shared.contextMemories(query: query, queryEmbedding: queryEmbedding, limit: 24)
        guard !memories.isEmpty else { return nil }

        // Tipe göre grupla — koç yapılandırılmış, tiplenmiş bir hafıza bloğu görsün.
        let grouped = Dictionary(grouping: memories, by: { $0.type })
        let order: [MemoryType] = [
            .profile, .goal, .constraint, .preference,
            .training, .nutrition, .supplement, .app, .episodic, .other
        ]
        var lines: [String] = []
        for type in order {
            guard let items = grouped[type], !items.isEmpty else { continue }
            lines.append("[\(type.label.uppercased())]")
            for memory in items {
                let pin = memory.pinned ? "📌 " : ""
                lines.append("- \(pin)\(memory.content)")
            }
        }

        return SkillResult(
            skillID: id,
            title: "Kişisel Hafıza",
            content: lines.joined(separator: "\n"),
            sources: []
        )
    }
}

struct MicronutrientCoverageSkill: AgentSkill {
    let id = "nutrition.micronutrient.coverage.v2"
    let name = "Micronutrient Coverage V2"
    let description = "USDA/Open Food Facts cache ile son yemeklerden vitamin-mineral ve cesitlilik aciklarini cikarir."

    func canHandle(_ query: String) -> Bool {
        let lower = AgentQueryClassifier.normalized(query)
        guard !AgentQueryClassifier.isLikelyFoodLog(query) else { return false }
        return AgentQueryClassifier.containsAny(lower, AgentQueryClassifier.nutritionSignals)
            || AgentQueryClassifier.containsAny(lower, [
                "vitamin", "mineral", "mikro", "micronutrient", "lif", "fiber",
                "cesit", "çeşit", "sebze", "meyve", "ne yiy", "ogun", "öğün",
                "meal", "diyet", "beslenme", "bowl", "smoothie", "tarif"
            ])
    }

    func run(query: String, context: AgentContext) async throws -> SkillResult? {
        guard let dataSnapshot = context.dataSnapshot,
              let analysis = await NutritionDataProvider.shared.analyze(
                data: dataSnapshot,
                days: 14,
                maxUniqueFoods: 12,
                networkLookupLimit: 6
              )
        else { return nil }

        let low = analysis.coverage
            .filter { $0.ratio < 0.72 }
            .prefix(7)
            .map { "\($0.spec.label) \(Fmt.int($0.ratio * 100))% (\(Fmt.num($0.averageDaily, digits: $0.spec.displayDigits))\( $0.spec.unit)/gün)" }

        let okay = analysis.coverage
            .filter { $0.ratio >= 0.9 }
            .prefix(4)
            .map { "\($0.spec.label) \(Fmt.int($0.ratio * 100))%" }

        var lines: [String] = [
            "[MICRONUTRIENT COVERAGE V2 — son \(analysis.periodDays) gün, USDA/Open Food Facts + local cache]",
            "- Kapsam: \(analysis.loggedDays)/\(analysis.periodDays) gün log · \(analysis.matchedFoodCount)/\(analysis.uniqueFoodCount) yiyecek nutrient match · \(analysis.sourceSummary)",
            "- Güven: Bu tıbbi teşhis değil; yemek adı/gram ve dış veri eşleşmesine göre yaklaşık coverage. Eksik veri varsa kesin konuşma, çeşitlilik öner."
        ]

        if !low.isEmpty {
            lines.append("- Düşük/öncelikli görünenler: \(low.joined(separator: " · "))")
        }
        if !okay.isEmpty {
            lines.append("- Fena görünmeyenler: \(okay.joined(separator: " · "))")
        }
        if !analysis.unmatchedFoods.isEmpty {
            lines.append("- Eşleşemeyen sık yiyecekler: \(analysis.unmatchedFoods.prefix(5).joined(separator: ", "))")
        }
        if !analysis.foodSuggestions.isEmpty {
            lines.append("- Çeşitlilik/meal öneri havuzu: \(analysis.foodSuggestions.joined(separator: " · "))")
        }
        lines.append("- Koç notu: Kullanıcı meal/tarif isterse düşük mikro hedefleri makro hedefini bozmadan tarife ekle; supplement yerine önce gerçek yiyecek öner.")

        return SkillResult(
            skillID: id,
            title: "Micronutrient Coverage V2",
            content: lines.joined(separator: "\n"),
            sources: analysis.sources
        )
    }
}

struct ProteinRecipeTrendSkill: AgentSkill {
    let id = "nutrition.protein.recipe.trends.v3"
    let name = "Protein Recipe Trend Skill V3"
    let description = "Protein tozu, bowl, smoothie ve yuksek protein tarifleri icin makro boslugu + canli web arama talimati uretir."

    func canHandle(_ query: String) -> Bool {
        let lower = AgentQueryClassifier.normalized(query)
        guard !AgentQueryClassifier.isLikelyFoodLog(query) else { return false }
        let recipeSignals = [
            "bowl", "smoothie", "shake", "pankek", "pancake", "waffle",
            "protein tozu", "whey", "casein", "tarif", "tatli", "tatlı",
            "yogurt", "yoğurt", "yulaf", "oats", "meal prep"
        ]
        return AgentQueryClassifier.containsAny(lower, recipeSignals)
            && AgentQueryClassifier.containsAny(lower, ["protein", "whey", "bowl", "tarif", "meal", "ogun", "öğün"])
    }

    func run(query: String, context: AgentContext) async throws -> SkillResult? {
        guard let dataSnapshot = context.dataSnapshot else { return nil }

        let macro = NutritionDataProvider.shared.todayMacroContext(data: dataSnapshot)
        let presets = NutritionDataProvider.shared.proteinPresets(data: dataSnapshot, limit: 5)
        let savedRecipes = NutritionDataProvider.shared.savedProteinRecipes(data: dataSnapshot, limit: 5)
        let micro = await NutritionDataProvider.shared.analyze(
            data: dataSnapshot,
            days: 14,
            maxUniqueFoods: 10,
            networkLookupLimit: 2
        )

        var lines: [String] = [
            "[PROTEIN RECIPE / BOWL TRENDS V3]",
            "- Amaç: Kullanıcının protein tozu/presetleri, bugünkü makro boşluğu ve mikro çeşitlilik açıklarına göre bowl/smoothie/pancake/tatlı tarifini kişiselleştir."
        ]

        if let macro {
            lines.append("- Bugünkü makro durumu: \(macro)")
        }
        if !presets.isEmpty {
            lines.append("- Kullanılabilir protein presetleri: \(presets.joined(separator: " · "))")
        }
        if !savedRecipes.isEmpty {
            lines.append("- Kayıtlı benzer tarifler: \(savedRecipes.joined(separator: " · "))")
        }
        if let micro {
            let low = micro.coverage
                .filter { $0.ratio < 0.72 }
                .prefix(4)
                .map(\.spec.label)
            if !low.isEmpty {
                lines.append("- Tarife eklenebilecek mikro hedefler: \(low.joined(separator: ", ")). Örnek eklemeler: \(micro.foodSuggestions.prefix(5).joined(separator: " · "))")
            }
        }

        lines.append("""
        - CANLI WEB TALİMATI: Kullanıcı protein bowl/protein tozu/tatlı/pankek gibi tarif istiyorsa web_search ZORUNLU. Tek aramada denenmiş/yorumlu/bilinen kaynak tarif bul, kaynak URL'sini koru, sonra Hercules makro/mikro bağlamına uyarla. Önerilen sorgular: "yorumlu yüksek protein pankek tarifi", "denenmiş whey protein bowl tarifi", "high protein whey yogurt bowl recipe reviews".
        - Tarif dönerken kcal/P/K/Y yaklaşık ver; kaydet/ekle derse sadece kaynak URL + malzeme + yapılış doluysa `add_recipe` action üret. Sadece öneri istiyorsa action üretme.
        """)

        return SkillResult(
            skillID: id,
            title: "Protein Recipe Trends V3",
            content: lines.joined(separator: "\n"),
            sources: ["https://fdc.nal.usda.gov/api-guide/", "https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/"]
        )
    }
}
