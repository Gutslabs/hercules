import Foundation

/// Kazınmış bir Instagram gönderisini yapılandırılmış tarife çevirir.
///
/// Caption metni + gönderi görselleri birlikte modele gider. Görsel şart: Instagram'daki
/// yemek postlarının büyük kısmı tarifi caption'a değil GÖRSELİN İÇİNE yazıyor (carousel
/// slaytları, üstüne bindirilmiş metin) — sadece caption'a bakan bir ayıklayıcı orada eli
/// boş döner. `AIClient.complete(systemPrompt:userPrompt:images:)` zaten multimodal.
struct AIRecipeResult: Codable, Sendable {
    /// Model "bu bir tarif değil" diyebilsin. Kaydedilen her gönderi tarif olmak zorunda
    /// değil; olmayanı kütüphaneye çöp olarak eklemek yerine atlıyoruz.
    var isRecipe: Bool?
    var title: String?
    var summary: String?
    var ingredientsText: String?
    var instructionsText: String?
    /// "breakfast" | "dinner" | "dessert" — `RecipeCategory` ile eşlenir.
    var category: String?
    var servings: Int?
    var prepMinutes: Int?
    var calories: Double?
    var protein_g: Double?
    var carbs_g: Double?
    var fat_g: Double?
    /// Makrolar caption'da yazmıyorduysa model tahmin etti — kullanıcı bilsin.
    var macrosEstimated: Bool?
    /// Modelin kısa notu (eksik bilgi, belirsizlik). İnceleme adımında gösterilir.
    var note: String?

    var looksUsable: Bool {
        guard isRecipe != false else { return false }
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !t.isEmpty
    }
}

enum RecipeExtractionError: LocalizedError {
    case notARecipe(String)
    case unparsable(String)

    var errorDescription: String? {
        switch self {
        case .notARecipe(let note):
            return note.isEmpty ? "Gönderi tarif değil." : "Gönderi tarif değil: \(note)"
        case .unparsable(let raw):
            let head = raw.prefix(160)
            return "Model yanıtı tarife çevrilemedi: \(head)"
        }
    }
}

#if os(macOS)
struct RecipeExtractor {
    /// `PromptKey.recipeExtraction` bunun üzerinden düzenlenebilir; burası varsayılan.
    static let recipeExtractionDefault = """
    Sana bir Instagram gönderisinin caption metni ve görselleri verilecek. Görevin bunu \
    yapılandırılmış bir yemek tarifine çevirmek.

    ÖNEMLİ: Tarif bilgisi caption'da OLMAYABİLİR — çoğu zaman görselin içine yazılmıştır \
    (carousel slaytları, üstüne bindirilmiş metin). Görselleri mutlaka oku.

    Gönderi bir yemek tarifi değilse (spor, alıntı, reklam, sadece yemek fotoğrafı vb.) \
    isRecipe=false dön ve note alanına tek cümleyle nedenini yaz. Tarif uydurma.

    Malzeme ve yapılış metinlerini Türkçe yaz. Malzemeleri satır başına bir tane, ölçüsüyle \
    birlikte ver. Yapılışı numaralı adımlar hâlinde ver.

    Makrolar caption'da veya görselde yazıyorsa onları kullan ve macrosEstimated=false yap. \
    Yazmıyorsa malzemelerden PORSİYON BAŞINA tahmin et ve macrosEstimated=true yap. \
    Tahmin edemiyorsan alanları boş bırak — sıfır yazma.

    SADECE şu şemada geçerli JSON dön, başka hiçbir metin ekleme:
    {
      "isRecipe": true,
      "title": "kısa tarif adı",
      "summary": "1-2 cümle",
      "ingredientsText": "satır başına bir malzeme",
      "instructionsText": "1. ...\\n2. ...",
      "category": "breakfast" | "dinner" | "dessert",
      "servings": 2,
      "prepMinutes": 25,
      "calories": 520,
      "protein_g": 32,
      "carbs_g": 45,
      "fat_g": 18,
      "macrosEstimated": true,
      "note": "varsa kısa not"
    }
    """

    /// Kazınmış gönderiyi modele verip tarife çevirir.
    ///
    /// `AIKeyStore.makeClient()` DEĞİL: o, ayarlardaki seçili sağlayıcıyı döner ve seçim
    /// OpenRouter'daysa her tarif için API kredisi yakar. Bu iş toplu koşuyor (günde 5-10
    /// gönderi), yani maliyet birikir. `CodexFirstFallbackClient` önce abonelikteki Codex'i
    /// deniyor ve OpenRouter'a yalnızca Codex hata verir VE elde bir OpenRouter anahtarı
    /// varsa düşüyor — istediğimiz sıra tam bu.
    func extract(from post: ScrapedPost) async throws -> AIRecipeResult {
        let client: AIClient = CodexFirstFallbackClient()
        let caption = post.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var userPrompt = "Instagram gönderisi: \(InstagramPostScraper.postURL(for: post.shortcode))\n\n"
        if caption.isEmpty {
            userPrompt += "Caption boş veya okunamadı. Tarif bilgisi yalnızca görsellerde.\n"
        } else {
            userPrompt += "Caption:\n\(caption)\n"
        }
        if post.images.isEmpty {
            userPrompt += "\n(Görsel indirilemedi — sadece caption'a göre değerlendir.)"
        } else {
            userPrompt += "\n(\(post.images.count) görsel ekli.)"
        }

        let raw = try await client.complete(
            systemPrompt: PromptStore.shared.text(.recipeExtraction),
            userPrompt: userPrompt,
            images: post.images
        )

        guard let result = Self.parse(raw) else {
            throw RecipeExtractionError.unparsable(raw)
        }
        if result.isRecipe == false || !result.looksUsable {
            throw RecipeExtractionError.notARecipe(result.note ?? "")
        }
        return result
    }

    static func parse(_ raw: String) -> AIRecipeResult? {
        let stripped = stripCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = stripped.data(using: .utf8),
           let result = try? JSONDecoder().decode(AIRecipeResult.self, from: data) {
            return result
        }
        // Model JSON'un etrafına metin koyduysa ilk gövdeyi kes.
        guard let start = stripped.firstIndex(of: "{"),
              let end = stripped.lastIndex(of: "}"),
              start < end
        else { return nil }
        let slice = String(stripped[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIRecipeResult.self, from: data)
    }

    private static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) }
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t
    }
}

extension AIRecipeResult {
    /// Tarif nesnesine çevirir. Kaynak URL gönderi linki olur — dedup anahtarı da bu.
    func makeRecipe(shortcode: String) -> Recipe {
        var summaryText = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if macrosEstimated == true {
            let marker = "Makrolar malzemelerden tahmin edildi."
            summaryText = [summaryText, marker].compactMap { $0 }.filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
        return Recipe(
            title: (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            urlString: InstagramPostScraper.postURL(for: shortcode),
            category: AIRecipeResult.mapCategory(category),
            summary: summaryText?.isEmpty == false ? summaryText : nil,
            ingredientsText: ingredientsText,
            instructionsText: instructionsText,
            servings: servings,
            prepMinutes: prepMinutes,
            calories: calories,
            protein: protein_g,
            carbs: carbs_g,
            fat: fat_g
        )
    }

    static func mapCategory(_ raw: String?) -> RecipeCategory {
        switch raw?.lowercased() {
        case "breakfast": return .breakfast
        case "dessert":   return .dessert
        default:          return .dinner
        }
    }
}
#endif
