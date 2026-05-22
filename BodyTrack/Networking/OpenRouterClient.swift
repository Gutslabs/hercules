import Foundation

enum AIConfig {
    static let defaultAPIKey = ""
    static let defaultModel = "x-ai/grok-4.1-fast"
    static let searchModel = "x-ai/grok-4.1-fast:online"
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    static let appReferer = "https://hercules.local"
    static let appTitle = "Hercules"

    /// System prompt — her mesajda yeniden hesaplanır, bugünün tarihi gömülür.
    static var systemPrompt: String {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "tr_TR")
        dateFmt.dateFormat = "d MMMM yyyy EEEE"
        let today = dateFmt.string(from: .now)

        return """
        Bugünün tarihi: \(today). Zaman bağlamlı tüm yorumları buna göre yap.

        Sen Hercules — Türkçe konuşan, body-building üzerinde neredeyse tüm bilimsel araştırmaları bilen, sürekli yeni araştırmaları takip eden bir science-based body-builder koçusun.

        CEVAP FORMATI — her zaman SADECE tek bir JSON objesi dön:

        Üç mod var:

        1) YEMEK MODU — kullanıcı bir yemek + miktar yazarsa (örn. "200g tavuk göğsü", "1 dilim ekmek", "Burger King double whopper"):
           {"name": "yemek adı", "grams": <gram>, "calories": <kcal>, "protein_g": <p>, "carbs_g": <c>, "fat_g": <y>, "message": "kısa Türkçe açıklama"}

        2) SOHBET MODU — diğer her şey (selamlama, soru-cevap, fitness/diyet teorisi, antrenman önerisi, plato sorusu, motivasyon, genel sohbet):
           {"message": "Türkçe cevap"}

        3) APP TOOL MODU — kullanıcı açıkça app içinde bir şeyi KAYDET / EKLE / DEĞİŞTİR / DÜZENLE derse, normal message yanında `actions` dizisi ekle:
           {"message": "kısa Türkçe açıklama veya onay sorusu", "actions": [ ... ]}

        APP TOOL ŞEMASI:
        - `tool`: "log_food", "add_recipe", "update_workout_plan", "update_meal_plan"
        - `summary`: Kullanıcıya gösterilecek kısa Türkçe işlem özeti.
        - Yemek kaydı için: {"tool":"log_food","summary":"Bugüne 520 kcal tavuk pilav ekle","name":"Tavuk pilav","grams":300,"calories":520,"protein_g":42,"carbs_g":55,"fat_g":12}
        - Tarif ekleme için: {"tool":"add_recipe","summary":"Tariflere protein pankek ekle","title":"Protein pankek","category":"breakfast","recipe_summary":"Ucuz, yüksek proteinli kahvaltı.","ingredients":"- 60g yulaf\\n- 2 yumurta\\n- 150g yoğurt","instructions":"1. Malzemeleri karıştır.\\n2. Tavada iki yüzünü pişir.","servings":1,"prep_minutes":12,"calories":520,"protein_g":38,"carbs_g":58,"fat_g":16,"url":"https://..."}; category sadece "breakfast", "dinner", "dessert". URL opsiyonel, ama tarif metni dolu olmalı.
        - Antrenman planı ad/kcal için: {"tool":"update_workout_plan","summary":"Salı antrenmanını Sırt + Göğüs yap","workout_operation":"set_session","weekday":3,"name":"Sırt + Göğüs","estimated_calories":380}
        - Antrenman planına hareket ekleme için: {"tool":"update_workout_plan","summary":"Salı planına Lat Pulldown ekle","workout_operation":"add_exercise","weekday":3,"exercise_name":"Lat Pulldown","sets":3,"reps":10,"weight":55}
        - Yemek planı gün tipi için: {"tool":"update_meal_plan","summary":"Salı gününü tavuk göğsü günü yap","meal_operation":"set_day_type","weekday":3,"day_type":"gogus"}
        - Yemek planına öğe ekleme için: {"tool":"update_meal_plan","summary":"Salı öğlene 200g tavuk göğsü ekle","meal_operation":"add_item","weekday":3,"meal_slot":"ogle","item_name":"Tavuk göğsü","amount":200,"unit":"g","calories":330,"protein_g":62,"carbs_g":0,"fat_g":7}
        - weekday Apple Calendar formatındadır: 1=Pazar, 2=Pazartesi, 3=Salı, 4=Çarşamba, 5=Perşembe, 6=Cuma, 7=Cumartesi.
        - meal_slot sadece "sabah", "ogle", "ara", "aksam". day_type sadece "gogus", "but", "pirzola", "free".

        KURALLAR:
        - JSON dışında HİÇBİR ŞEY yazma. Markdown, kod bloğu, açıklama, başlık YOK.
        - message daima dolu olsun. Yemek modunda kısa (1-2 cümle). Onun dışında kafana göre, gerektiği kadar açıkla.
        - JSON içindeki newline'ları \\n olarak escape et — message uzunsa paragraf için \\n\\n kullan.
        - Top-level calories, protein_g, carbs_g, fat_g sadece YEMEK MODU'nda doldur. `actions` içindeki log_food / update_meal_plan.add_item alanlarında bu makro/kcal değerleri ayrıca kullanılabilir.
        - `actions` sadece kullanıcı app datasını değiştirmeyi açıkça istediğinde eklenir. Sadece öneri veya sohbet istiyorsa action üretme.
        - `update_workout_plan` ve `update_meal_plan` ASLA yapılmış gibi konuşma. Bunlar app içinde önce onay bekler. Message içinde doğal şekilde "Bunu şöyle değiştirmeyi öneriyorum, onaylıyor musun?" diye sor.
        - `log_food` ve `add_recipe` action'ları app tarafından otomatik uygulanır. Bu action'ları üretirken "onaylıyor musun?" diye sorma; işlem gerçekleşmiş gibi kısa ve net konuş.
        - Kullanıcı "şu hareketi ekle" derse `update_workout_plan` içinde `workout_operation:"add_exercise"` kullan; tüm antrenman adını hareket listesine çevirmeye çalışma.
        - `log_food` ve `add_recipe` kullanıcı açıkça "ekle/kaydet" dediyse action olarak yazılabilir.
        - `add_recipe` üretirken sadece link bırakma; recipe_summary, ingredients ve instructions alanlarını mutlaka doldur. URL sadece kaynak/fikir linki varsa ek alan.

        web_search NE ZAMAN:
        - Bilmediğin/emin olmadığın yemek/marka/ürün (ör. lokal restoranlar, yöresel yemekler, yeni çıkmış ürünler).
        - Güncel veri gereken fitness sorusu (yeni supplement çalışmaları, yeni egzersiz teknikleri).
        - Yaygın bilgiler için aratma — temel yemekler, klasik egzersizler, bilinen makro bilgileri kendi bilginle hızlı cevapla.
        - Tek aramayla yetin, döngüye girme.

        KULLANICI HAKKINDA + VERİSİ + AGENT SKILL CONTEXT:
        - Eğer kullanıcı mesajının başında `[KULLANICI HAKKINDA ...]` bloku varsa, bu kullanıcının kendi yazdığı geçmişi/kişiliği — onu TANI, ona göre cevapla. Bu blok HER mesajda gelir. Ama kullanıcı normal yazıyorsa, bunu kullanıcıya her dakika aktarmamalısın. Kullanıcı sadece öneri isterken/body-building konuşurken bunu göz önünde bulundurarak cevap ver. Örneğin: kullanıcı "selam" yazdığında normal cevap ver; ama body-building ile alakalı bir şey sorarsa verileri ve mevcut durumu göz önüne al.
        - Eğer `HERCULES AGENT SKILL CONTEXT` bloku varsa, bu kişisel memory, PubMed research adayları veya food lookup sonuçları içerebilir. Sadece alakalı olanları kullan; PubMed sonuçlarını "kanıt yönü" gibi ele al, tek başına kesin hüküm yapma.
        - Veri geldiyse bu verilere göre yorum yaparsın. Current date'yi de göz önünde bulundur (yukarıda verildi).
        - Hakkında metnindeki bilgiyi sürekli tekrar etme; sadece relevant olduğunda referans ver.

        KİŞİLİĞİN:
        - Coach gibisin ama aynı zamanda friend-like. Plain text yazmayı seviyorsun; gereksiz büyük harf vs kullanmak yerine doğal yazmayı seviyorsun.
        - Bilgiyi verirken yeterli miktarda açıklıyorsun. Hepsi bilimsel destekli ve mantık çerçevesi içinde gerçekten bilinen şeyler veya yeni güçlü makaleleri olan şeyler.
        - "Bilmiyorum" deme — bilmiyorsan ya araştır, ya makul aralık ver ve "tahmini" diye belirt.
        - Kullanıcı miktar belirtmediyse makul porsiyon varsay (1 porsiyon ≈ 200g, 1 dilim ≈ 30g).
        - Vücut analizi (kilo trendi, yağ %, plato) sorularında literatüre uygun mantıklı önerilerde bulun. Örneğin kullanıcı kilo vermek istiyorsa X süresi boyunca aynı kilodaysa: ya kaloriyi düzgün takip edemiyor, ya çok hareketsiz, ya su tutuyor, ya da maintenance'a girmiş. Bilimsel mantığa göre cevapla her zaman.
        - Çiğ vs pişmiş tartım farkını biliyorsun (çiğ pirinç 360 kcal/100g, pişmiş 130; çiğ bulgur 340, pişmiş 120 vs).
        """
    }
}

struct AIFoodResult: Codable, Equatable {
    var name: String?
    var grams: Double?
    var calories: Double?
    var protein_g: Double?
    var carbs_g: Double?
    var fat_g: Double?
    var message: String
    var actions: [AIAppAction]?

    var isFood: Bool {
        calories != nil && (name?.isEmpty == false)
    }

    var actionList: [AIAppAction] {
        actions ?? []
    }

    init(
        name: String? = nil,
        grams: Double? = nil,
        calories: Double? = nil,
        protein_g: Double? = nil,
        carbs_g: Double? = nil,
        fat_g: Double? = nil,
        message: String,
        actions: [AIAppAction]? = nil
    ) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.protein_g = protein_g
        self.carbs_g = carbs_g
        self.fat_g = fat_g
        self.message = message
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case name, grams, calories, protein_g, carbs_g, fat_g, message, actions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        grams = try? c.decodeIfPresent(Double.self, forKey: .grams)
        calories = try? c.decodeIfPresent(Double.self, forKey: .calories)
        protein_g = try? c.decodeIfPresent(Double.self, forKey: .protein_g)
        carbs_g = try? c.decodeIfPresent(Double.self, forKey: .carbs_g)
        fat_g = try? c.decodeIfPresent(Double.self, forKey: .fat_g)
        message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? ""
        let decodedActions = ((try? c.decodeIfPresent(LossyAIActionList.self, forKey: .actions))?.values) ?? []
        actions = decodedActions.isEmpty ? nil : decodedActions
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(grams, forKey: .grams)
        try c.encodeIfPresent(calories, forKey: .calories)
        try c.encodeIfPresent(protein_g, forKey: .protein_g)
        try c.encodeIfPresent(carbs_g, forKey: .carbs_g)
        try c.encodeIfPresent(fat_g, forKey: .fat_g)
        try c.encode(message, forKey: .message)
        try c.encodeIfPresent(actions, forKey: .actions)
    }
}

private struct LossyAIActionList: Decodable {
    let values: [AIAppAction]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var output: [AIAppAction] = []
        while !container.isAtEnd {
            let elementDecoder = try container.superDecoder()
            if let action = try? AIAppAction(from: elementDecoder) {
                output.append(action)
            }
        }
        values = output
    }
}

enum AIAppToolName: String, Codable, Equatable {
    case logFood = "log_food"
    case addRecipe = "add_recipe"
    case updateWorkoutPlan = "update_workout_plan"
    case updateMealPlan = "update_meal_plan"
}

enum AIAppActionStatus: String, Codable, Equatable {
    case pending
    case applied
    case rejected
    case failed
}

struct AIAppAction: Identifiable, Equatable, Codable {
    var id: UUID
    var tool: AIAppToolName
    var summary: String?
    var status: AIAppActionStatus
    var resultMessage: String?

    var name: String?
    var title: String?
    var url: String?
    var category: String?
    var recipeSummary: String?
    var ingredients: String?
    var instructions: String?
    var servings: Int?
    var prepMinutes: Int?

    var weekday: Int?
    var estimatedCalories: Double?
    var workoutOperation: String?
    var exerciseName: String?
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var mealOperation: String?
    var dayType: String?
    var mealSlot: String?
    var itemName: String?
    var amount: Double?
    var unit: String?

    var grams: Double?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?

    var requiresConfirmation: Bool {
        tool == .updateWorkoutPlan || tool == .updateMealPlan
    }

    var displayTitle: String {
        switch tool {
        case .logFood: return "Kalori ekle"
        case .addRecipe: return "Tarif ekle"
        case .updateWorkoutPlan: return "Antrenman planı"
        case .updateMealPlan: return "Yemek planı"
        }
    }

    var displaySummary: String {
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        switch tool {
        case .logFood:
            return "\(name ?? "Yemek") → \(Int((calories ?? 0).rounded())) kcal"
        case .addRecipe:
            return title ?? "Yeni tarif"
        case .updateWorkoutPlan:
            if let exerciseName, !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(weekdayLabel) → + \(exerciseName)"
            }
            return "\(weekdayLabel) → \(name ?? "Antrenman")"
        case .updateMealPlan:
            if mealOperation == "set_day_type" {
                return "\(weekdayLabel) → \(dayType ?? "gün tipi")"
            }
            return "\(weekdayLabel) \(mealSlot ?? "öğün") → \(itemName ?? "öğe")"
        }
    }

    var weekdayLabel: String {
        guard let weekday, weekday >= 1, weekday < WorkoutSession.weekdayNames.count else { return "Gün" }
        return WorkoutSession.weekdayNames[weekday]
    }

    init(
        id: UUID = UUID(),
        tool: AIAppToolName,
        summary: String? = nil,
        status: AIAppActionStatus = .pending,
        resultMessage: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.summary = summary
        self.status = status
        self.resultMessage = resultMessage
    }

    private enum CodingKeys: String, CodingKey {
        case id, tool, summary, status, resultMessage
        case name, title, url, category, weekday, grams, calories, amount, unit
        case recipeSummary, recipe_summary
        case ingredients, instructions, servings
        case prepMinutes, prep_minutes
        case estimatedCalories, estimated_calories
        case workoutOperation, workout_operation
        case exerciseName, exercise_name
        case sets, reps, weight
        case mealOperation, meal_operation
        case dayType, day_type
        case mealSlot, meal_slot
        case itemName, item_name
        case proteinG, protein_g
        case carbsG, carbs_g
        case fatG, fat_g
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        tool = try c.decode(AIAppToolName.self, forKey: .tool)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        status = (try? c.decodeIfPresent(AIAppActionStatus.self, forKey: .status)) ?? .pending
        resultMessage = try? c.decodeIfPresent(String.self, forKey: .resultMessage)

        name = try? c.decodeIfPresent(String.self, forKey: .name)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        recipeSummary = (try? c.decodeIfPresent(String.self, forKey: .recipeSummary))
            ?? (try? c.decodeIfPresent(String.self, forKey: .recipe_summary))
        ingredients = try? c.decodeIfPresent(String.self, forKey: .ingredients)
        instructions = try? c.decodeIfPresent(String.self, forKey: .instructions)
        servings = try? c.decodeIfPresent(Int.self, forKey: .servings)
        prepMinutes = (try? c.decodeIfPresent(Int.self, forKey: .prepMinutes))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .prep_minutes))
        weekday = try? c.decodeIfPresent(Int.self, forKey: .weekday)
        grams = try? c.decodeIfPresent(Double.self, forKey: .grams)
        calories = try? c.decodeIfPresent(Double.self, forKey: .calories)
        amount = try? c.decodeIfPresent(Double.self, forKey: .amount)
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        estimatedCalories = (try? c.decodeIfPresent(Double.self, forKey: .estimatedCalories))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .estimated_calories))
        workoutOperation = (try? c.decodeIfPresent(String.self, forKey: .workoutOperation))
            ?? (try? c.decodeIfPresent(String.self, forKey: .workout_operation))
        exerciseName = (try? c.decodeIfPresent(String.self, forKey: .exerciseName))
            ?? (try? c.decodeIfPresent(String.self, forKey: .exercise_name))
        sets = try? c.decodeIfPresent(Int.self, forKey: .sets)
        reps = try? c.decodeIfPresent(Int.self, forKey: .reps)
        weight = try? c.decodeIfPresent(Double.self, forKey: .weight)
        mealOperation = (try? c.decodeIfPresent(String.self, forKey: .mealOperation))
            ?? (try? c.decodeIfPresent(String.self, forKey: .meal_operation))
        dayType = (try? c.decodeIfPresent(String.self, forKey: .dayType))
            ?? (try? c.decodeIfPresent(String.self, forKey: .day_type))
        mealSlot = (try? c.decodeIfPresent(String.self, forKey: .mealSlot))
            ?? (try? c.decodeIfPresent(String.self, forKey: .meal_slot))
        itemName = (try? c.decodeIfPresent(String.self, forKey: .itemName))
            ?? (try? c.decodeIfPresent(String.self, forKey: .item_name))
        proteinG = (try? c.decodeIfPresent(Double.self, forKey: .proteinG))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .protein_g))
        carbsG = (try? c.decodeIfPresent(Double.self, forKey: .carbsG))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .carbs_g))
        fatG = (try? c.decodeIfPresent(Double.self, forKey: .fatG))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .fat_g))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tool, forKey: .tool)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(resultMessage, forKey: .resultMessage)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(recipeSummary, forKey: .recipeSummary)
        try c.encodeIfPresent(ingredients, forKey: .ingredients)
        try c.encodeIfPresent(instructions, forKey: .instructions)
        try c.encodeIfPresent(servings, forKey: .servings)
        try c.encodeIfPresent(prepMinutes, forKey: .prepMinutes)
        try c.encodeIfPresent(weekday, forKey: .weekday)
        try c.encodeIfPresent(estimatedCalories, forKey: .estimatedCalories)
        try c.encodeIfPresent(workoutOperation, forKey: .workoutOperation)
        try c.encodeIfPresent(exerciseName, forKey: .exerciseName)
        try c.encodeIfPresent(sets, forKey: .sets)
        try c.encodeIfPresent(reps, forKey: .reps)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(mealOperation, forKey: .mealOperation)
        try c.encodeIfPresent(dayType, forKey: .dayType)
        try c.encodeIfPresent(mealSlot, forKey: .mealSlot)
        try c.encodeIfPresent(itemName, forKey: .itemName)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(grams, forKey: .grams)
        try c.encodeIfPresent(calories, forKey: .calories)
        try c.encodeIfPresent(proteinG, forKey: .proteinG)
        try c.encodeIfPresent(carbsG, forKey: .carbsG)
        try c.encodeIfPresent(fatG, forKey: .fatG)
    }
}

enum OpenRouterError: LocalizedError {
    case badResponse(Int, String)
    case decoding(String)
    case missingKey
    case toolLoop

    var errorDescription: String? {
        switch self {
        case .badResponse(let code, let msg): return "HTTP \(code): \(msg)"
        case .decoding(let s): return "Yanıt çözümlenemedi: \(s)"
        case .missingKey: return "OpenRouter API key tanımlı değil."
        case .toolLoop: return "Tool çağrı limiti aşıldı."
        }
    }
}

struct ChatTurn: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    var food: AIFoodResult? = nil
    var actions: [AIAppAction] = []
    var saved: Bool = false
    var searchedFor: String? = nil  // populated if AI did a web search
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        food: AIFoodResult? = nil,
        actions: [AIAppAction] = [],
        saved: Bool = false,
        searchedFor: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.food = food
        self.actions = actions
        self.saved = saved
        self.searchedFor = searchedFor
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, text, food, actions, saved, searchedFor, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        role = try c.decode(Role.self, forKey: .role)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        food = try? c.decodeIfPresent(AIFoodResult.self, forKey: .food)
        actions = (try? c.decodeIfPresent([AIAppAction].self, forKey: .actions)) ?? []
        saved = (try? c.decodeIfPresent(Bool.self, forKey: .saved)) ?? false
        searchedFor = try? c.decodeIfPresent(String.self, forKey: .searchedFor)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(food, forKey: .food)
        if !actions.isEmpty {
            try c.encode(actions, forKey: .actions)
        }
        try c.encode(saved, forKey: .saved)
        try c.encodeIfPresent(searchedFor, forKey: .searchedFor)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

final class OpenRouterClient: AIClient {
    private let session: URLSession

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    init(session: URLSession? = nil) {
        self.session = session ?? Self.defaultSession
    }

    /// Web search tool exposed to the model. Model calls it only when uncertain.
    private static let webSearchTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "web_search",
            "description": "Bir yemek/ürünün besin değeri, güncel bir fitness/diyet/supplement bilgisi veya emin olmadığın herhangi bir konu için web araması yap. Temel/yaygın bilgi için kullanma — sadece bilmediğinde veya güncellik gerektiğinde.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Türkçe arama sorgusu (ör. 'Burger King double whopper kalori', 'kreatin yağ yakımı 2026 çalışma')"
                    ]
                ],
                "required": ["query"]
            ]
        ]
    ]

    /// Updates from the running request — set by closure so UI can react.
    /// Returns: (final JSON-parsed result, optional search query that was performed)
    func send(
        history: [ChatTurn],
        newUserText: String,
        userContext: String?,
        onSearchStart: @MainActor @escaping (String) -> Void,
        onMessageUpdate: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, String?) {
        // OpenRouter şu an streaming kullanmıyor — final cevap geldiğinde
        // tek seferlik update tetiklenir (final return içinde).
        _ = onMessageUpdate
        let key = AIKeyStore.shared.apiKey
        guard !key.isEmpty else { throw OpenRouterError.missingKey }

        // Build initial messages
        var messages: [[String: Any]] = [
            ["role": "system", "content": AIConfig.systemPrompt]
        ]
        let recent = Array(history.suffix(10))
        for t in recent {
            messages.append(["role": t.role.rawValue, "content": t.text])
        }
        // Inject app data + agent skill context inline with the question so it persists in
        // follow-up turns naturally.
        let finalUserText: String = {
            guard let userContext, !userContext.isEmpty else { return newUserText }
            return """
            Aşağıda Hercules'in canlı kullanıcı verisi, kişisel hafızası ve agent skill sonuçları olabilir.
            Sorumu cevaplarken sadece alakalı kısımları kullan; kaynaklı araştırma varsa tarih/kaynak hassasiyetini koru.

            \(userContext)

            ---
            \(newUserText)
            """
        }()
        messages.append(["role": "user", "content": finalUserText])

        var lastSearchQuery: String? = nil

        // Tool loop — max 2 iterations to avoid runaway
        for _ in 0..<2 {
            let body: [String: Any] = [
                "model": AIKeyStore.shared.model,
                "messages": messages,
                "temperature": 0.2,
                "tools": [Self.webSearchTool],
                "tool_choice": "auto"
            ]

            let (data, http) = try await postJSON(body: body, key: key)
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? "no body"
                throw OpenRouterError.badResponse(http.statusCode, text)
            }

            guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = outer["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let messageDict = first["message"] as? [String: Any]
            else {
                throw OpenRouterError.decoding(String(data: data, encoding: .utf8) ?? "no body")
            }

            // Did the model emit tool_calls?
            if let toolCalls = messageDict["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                // Append assistant message with tool_calls (preserve as-is)
                var assistantMsg: [String: Any] = ["role": "assistant", "content": NSNull()]
                assistantMsg["tool_calls"] = toolCalls
                messages.append(assistantMsg)

                // Execute each tool call
                for tc in toolCalls {
                    guard let id = tc["id"] as? String,
                          let fn = tc["function"] as? [String: Any],
                          let name = fn["name"] as? String,
                          let argsStr = fn["arguments"] as? String,
                          let argsData = argsStr.data(using: .utf8),
                          let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]
                    else { continue }

                    if name == "web_search", let query = args["query"] as? String {
                        lastSearchQuery = query
                        await onSearchStart(query)
                        let result = try await performWebSearch(query: query, key: key)
                        messages.append([
                            "role": "tool",
                            "tool_call_id": id,
                            "content": result
                        ])
                    }
                }
                // Loop back to get final answer with tool result in context
                continue
            }

            // No tool calls — final content
            guard let content = messageDict["content"] as? String else {
                throw OpenRouterError.decoding("Empty content")
            }
            return (parseFood(content), lastSearchQuery)
        }

        throw OpenRouterError.toolLoop
    }

    /// Performs a web search by hitting the :online variant of the model.
    /// Returns concise text to feed back as tool result.
    private func performWebSearch(query: String, key: String) async throws -> String {
        let body: [String: Any] = [
            "model": AIConfig.searchModel,
            "messages": [
                ["role": "system", "content": "Sen kısa ve doğru bilgi veren bir araştırmacısın. Yemek sorgusu ise: porsiyon, kcal, protein, karb, yağ özetini dön. Fitness/sağlık/genel sorgu ise: en güncel ve doğru bilgiyi 3-5 cümlede özetle. Maksimum 6 satır."],
                ["role": "user", "content": query]
            ],
            "temperature": 0.1
        ]

        let (data, http) = try await postJSON(body: body, key: key)
        guard (200..<300).contains(http.statusCode) else {
            return "Arama başarısız: HTTP \(http.statusCode)"
        }
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = outer["choices"] as? [[String: Any]],
              let first = choices.first,
              let messageDict = first["message"] as? [String: Any],
              let content = messageDict["content"] as? String
        else {
            return "Arama yanıtı çözümlenemedi."
        }
        return content
    }

    private func postJSON(body: [String: Any], key: String) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: AIConfig.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AIConfig.appReferer, forHTTPHeaderField: "HTTP-Referer")
        req.setValue(AIConfig.appTitle, forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OpenRouterError.badResponse(-1, "Invalid response")
        }
        return (data, http)
    }

    private func parseFood(_ content: String) -> AIFoodResult {
        let stripped = stripCodeFences(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let inner = stripped.data(using: .utf8) else {
            return AIFoodResult(message: stripped)
        }
        if let result = try? JSONDecoder().decode(AIFoodResult.self, from: inner) {
            return result
        }
        return AIFoodResult(message: stripped)
    }

    private func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) }
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t
    }
}

/// Stores provider/key/model in UserDefaults — UI'dan değiştirilebilir.
final class AIKeyStore {
    static let shared = AIKeyStore()
    private let defaults = UserDefaults.standard
    private let keyAPI = "hercules.openrouter.api_key"
    private let keyProvider = "hercules.ai.provider"
    private let keyModelOpenRouter = "hercules.openrouter.model"
    private let keyModelCodex = "hercules.codex.model"
    private let keyReasoning = "hercules.codex.reasoning"

    var provider: AIProvider {
        get {
            let stored = defaults.string(forKey: keyProvider) ?? ""
            let parsed = AIProvider(rawValue: stored) ?? .codex
            // OpenRouter UI'dan kaldırıldı — eski kullanıcılar otomatik Codex'e düşsün
            return AIProvider.selectable.contains(parsed) ? parsed : .codex
        }
        set { defaults.set(newValue.rawValue, forKey: keyProvider) }
    }

    var apiKey: String {
        get {
            let stored = defaults.string(forKey: keyAPI) ?? ""
            return stored.isEmpty ? AIConfig.defaultAPIKey : stored
        }
        set { defaults.set(newValue, forKey: keyAPI) }
    }

    /// Aktif sağlayıcının modeli — saklanan değer artık listede yoksa default'a düş.
    var model: String {
        get {
            let key = (provider == .codex) ? keyModelCodex : keyModelOpenRouter
            let stored = defaults.string(forKey: key) ?? ""
            if !stored.isEmpty && provider.availableModels.contains(stored) {
                return stored
            }
            return provider.defaultModel
        }
        set {
            let key = (provider == .codex) ? keyModelCodex : keyModelOpenRouter
            defaults.set(newValue, forKey: key)
        }
    }

    /// Codex intelligence (reasoning) seviyesi. Default: Low (en hızlı).
    var intelligence: IntelligenceLevel {
        get {
            let stored = defaults.string(forKey: keyReasoning) ?? ""
            return IntelligenceLevel(rawValue: stored) ?? .low
        }
        set { defaults.set(newValue.rawValue, forKey: keyReasoning) }
    }

    /// Yeni sağlayıcı seçilince doğru istemciyi kur.
    func makeClient() -> AIClient {
        switch provider {
        case .openRouter: return OpenRouterClient()
        case .codex: return CodexClient()
        }
    }
}
