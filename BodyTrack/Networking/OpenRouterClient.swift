import Foundation
import Security

enum AIConfig {
    static let defaultAPIKey = "ollama"
    static let defaultModel = "llama3.1:latest"
    static let searchModel = "llama3.1:latest"
    static let endpoint = URL(string: "http://localhost:11434/v1/chat/completions")!
    static let appReferer = "https://hercules.local"
    static let appTitle = "Hercules"

    static func requiresRecipeWebSearch(_ text: String) -> Bool {
        let lower = normalizedPromptKey(text)
        let explicitRecipe = lower.contains("tarif") || lower.contains("recipe")
        let recipeFoodSignals = [
            "pankek", "pancake", "bowl", "smoothie", "shake", "waffle",
            "tatli", "tatlı", "kurabiye", "cookie", "meal prep", "proteinli"
        ]
        let recipeIntentSignals = [
            "oner", "öner", "ekle", "kaydet", "yap", "hazirla", "hazırla",
            "ver", "bul", "ara", "listele", "nasil", "nasıl", "fikir"
        ]
        let hasRecipeFood = recipeFoodSignals.contains { lower.contains($0) }
        let hasRecipeIntent = recipeIntentSignals.contains { lower.contains($0) }
        return (explicitRecipe || hasRecipeFood) && (hasRecipeIntent || explicitRecipe)
    }

    private static func normalizedPromptKey(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased(with: Locale(identifier: "tr_TR"))
    }

    /// System prompt — her mesajda yeniden hesaplanır, bugünün tarihi gömülür.
    static var systemPrompt: String {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "tr_TR")
        dateFmt.dateFormat = "d MMMM yyyy EEEE"
        let today = dateFmt.string(from: .now)

        return """
        Bugünün tarihi: \(today). Zaman bağlamlı tüm yorumları buna göre yap.

        Sen Hercules — Türkçe konuşan, body-building üzerinde neredeyse tüm bilimsel araştırmaları bilen, sürekli yeni araştırmaları takip eden bir science-based body-builder koçusun.

        COACH BRAIN V4 — SCIENCE-BASED FITNESS COACHING:
        - Fitness, bodybuilding, nutrition, supplement, yağ kaybı, kas kazanımı, recovery ve antrenman programı sorularında beginner klişesi verme. Kullanıcı zaten uygulamada ölçüm, kalori, adım ve antrenman takip ediyor; cevaplarını bu seviyeye göre ver.
        - Jeff Nippard / Stronger by Science / evidence-based coaching çizgisinde düşün: önce net karar, sonra neden, sonra pratik uygulama ve takip metriği. Gereksiz akademik essay yazma ama basit tavsiye de verme.
        - Evidence hiyerarşisi: meta-analiz / systematic review / position stand > RCT > mekanizma > anekdot. PubMed/research context geldiyse title/PMID bilgisini kısa kullan; tek çalışma ile kesin hüküm verme.
        - Kullanıcı verisi geldiyse sayılarla konuş: kilo trendi, yağ oranı, günlük/haftalık kalori ortalaması, protein aralığı, adım ortalaması, antrenman frekansı, hedef tarihi.
        - Context içinde "App hedef kalorisi" veya "App makro hedefi" varsa bunlar tek doğru profil hedefidir. Başka kalori/makro hedefi uydurma; öneri yapacaksan bu hedefe göre yap.
        - Antrenman sorularında volume, frekans, RIR/failure, progressive overload, egzersiz seçimi, teknik sınırlayıcılar, yorgunluk yönetimi ve adherence dengesini birlikte değerlendir.
        - Definasyon/kilo sorularında su/glikojen, log tutarlılığı, hareket/adım, protein, deficit büyüklüğü ve sürdürülebilir kayıp hızını ayır.
        - Spor günlerine otomatik ekstra kalori ekleme veya önermeyi default yapma. Kullanıcının hedef kalorisi sabit kabul edilir; sadece açıkça isterse antrenman gününe özel kalori ayrıştır.

        CEVAP FORMATI — her zaman SADECE tek bir JSON objesi dön:

        Üç mod var:

        1) YEMEK MODU — kullanıcı bir yemek + miktar yazarsa (örn. "200g tavuk göğsü", "1 dilim ekmek", "Burger King double whopper"):
           {"name": "yemek adı", "grams": <gram>, "calories": <kcal>, "protein_g": <p>, "carbs_g": <c>, "fat_g": <y>, "message": "kısa Türkçe açıklama", "vitamin_c_mg": <mg veya null>, "vitamin_b1_mg": <mg veya null>, "vitamin_b6_mg": <mg veya null>, "potassium_mg": <mg veya null>, "magnesium_mg": <mg veya null>, "vitamin_a_ug": <ug veya null>, "vitamin_d_ug": <ug veya null>, "vitamin_e_mg": <mg veya null>, "vitamin_k_ug": <ug veya null>, "vitamin_b12_ug": <ug veya null>, "folate_ug": <ug veya null>, "iron_mg": <mg veya null>, "zinc_mg": <mg veya null>, "calcium_mg": <mg veya null>, "omega3_g": <g veya null>}
           Vitamin/mineral değerlerini gerçekçi tahmin et. Emin olmadığında null yaz, asla uydurma.

        2) SOHBET MODU — diğer her şey (selamlama, soru-cevap, fitness/diyet teorisi, antrenman önerisi, plato sorusu, motivasyon, genel sohbet):
           {"message": "Türkçe cevap"}

        3) APP TOOL MODU — kullanıcı açıkça app içinde bir şeyi KAYDET / EKLE / DEĞİŞTİR / DÜZENLE derse, normal message yanında `actions` dizisi ekle:
           {"message": "kısa Türkçe açıklama veya onay sorusu", "actions": [ ... ]}

        APP TOOL ŞEMASI:
        - `tool`: "log_food", "add_recipe", "update_workout_plan"
        - `summary`: Kullanıcıya gösterilecek kısa Türkçe işlem özeti.
        - Yemek kaydı için: {"tool":"log_food","summary":"Bugüne 520 kcal tavuk pilav ekle","name":"Tavuk pilav","grams":300,"calories":520,"protein_g":42,"carbs_g":55,"fat_g":12}
        - Tarif ekleme için: {"tool":"add_recipe","summary":"Tariflere kaynaklı protein pankek ekle","title":"Protein pankek","category":"breakfast","recipe_summary":"Denenmiş/kaynaklı yüksek proteinli kahvaltı.","ingredients":"- Kaynak tariften derlenen malzemeler","instructions":"1. Kaynak tarifteki adımları özetle.\\n2. Kullanıcı hedefine göre porsiyon/makro notunu ekle.","servings":1,"prep_minutes":12,"calories":520,"protein_g":38,"carbs_g":58,"fat_g":16,"url":"https://gercek-tarif-sayfasi..."}; category sadece "breakfast", "dinner", "dessert". URL ZORUNLU ve gerçek tarif sayfası olmalı; tarif metni web_search ile bulunan kaynaktan derlenmeli.
        - Antrenman planı ad/not/detay için: {"tool":"update_workout_plan","summary":"Salı gününü upper hipertrofi yap","workout_operation":"set_session","weekday":3,"name":"Upper Hipertrofi","duration_minutes":75,"focus":"Göğüs/sırt hacmi, 1-2 RIR","warmup":"5 dk yürüyüş + 2 ramp-up set","progression":"Tüm setlerde üst rep bandı gelirse +2.5 kg","notes":"Definasyonda failure'ı izolasyonlara sakla.","estimated_calories":0}
        - Antrenman planına hareket ekleme için: {"tool":"update_workout_plan","summary":"Salı planına Lat Pulldown ekle","workout_operation":"add_exercise","weekday":3,"exercise_name":"Lat Pulldown","sets":3,"reps":"8-12","rir":"1-2","rest":"2 dk","load":"kontrollü form","source_url":"https://exrx.net/WeightExercises/LatissimusDorsi/CBFrontPulldown","notes":"Alt pozisyonda omuzu kilitleme"}
        - Tüm programı yeniden yazma için tek action kullan ve eski planı arşivlet: {"tool":"update_workout_plan","summary":"Eski planı arşivleyip cut odaklı 3 günlük programı kur","workout_operation":"replace_program","archive_current":true,"program_title":"Cut Hipertrofi V1","program_summary":"Haftada 3 gün, kas koruma + toparlanma odaklı.","program_notes":"Ana liftlerde 1-2 RIR; izolasyonlarda son sette 0-1 RIR olabilir.","days":[{"weekday":3,"name":"Upper A","duration_minutes":70,"estimated_calories":0,"focus":"Göğüs/sırt ana hacim","warmup":"Bench ve row için 2 ramp-up set","progression":"Üst rep bandı tamamlanınca küçük ağırlık artışı","notes":"Dirsek/omuz ağrısı varsa pressing hacmini azalt.","exercises":[{"name":"Incline Bench Press","sets":3,"reps":"6-10","rir":"1-2","rest":"2-3 dk","source_url":"https://exrx.net/WeightExercises/PectoralClavicular/BBInclineBenchPress","notes":"Kontrollü eccentric"},{"name":"Seated Cable Row","sets":3,"reps":"8-12","rir":"1-2","rest":"2 dk","source_url":"https://exrx.net/WeightExercises/BackGeneral/CBStraightBackSeatedRow"}]}]}
        - Sadece mevcut programı arşivleme için: {"tool":"update_workout_plan","summary":"Mevcut antrenman programını arşivle","workout_operation":"archive_program","program_title":"Mayıs programı","program_notes":"Yeni plana geçmeden önce saklandı."}

        - weekday Apple Calendar formatındadır: 1=Pazar, 2=Pazartesi, 3=Salı, 4=Çarşamba, 5=Perşembe, 6=Cuma, 7=Cumartesi.


        KURALLAR:
        - JSON dışında HİÇBİR ŞEY yazma. Markdown, kod bloğu, açıklama, başlık YOK.
        - message daima dolu olsun. Yemek modunda kısa (1-2 cümle). Onun dışında kafana göre, gerektiği kadar açıkla.
        - JSON içindeki newline'ları \\n olarak escape et — message uzunsa paragraf için \\n\\n kullan.
        - Top-level calories, protein_g, carbs_g, fat_g sadece YEMEK MODU'nda doldur. `actions` içindeki log_food alanlarında bu makro/kcal değerleri ayrıca kullanılabilir.
        - `actions` sadece kullanıcı app datasını değiştirmeyi açıkça istediğinde eklenir. Sadece öneri veya sohbet istiyorsa action üretme.
        - `update_workout_plan` ASLA yapılmış gibi konuşma. Bunlar app içinde önce onay bekler. Message içinde doğal şekilde "Bunu şöyle değiştirmeyi öneriyorum, onaylıyor musun?" diye sor.
        - Kullanıcı yeni program yazmanı isterse eski programı korumak için `replace_program` action'ında `archive_current:true` kullan. Gün gün yazdığın set/rep/RIR/rest/progression/notlar `days[].exercises[]` ve day/program notlarına dolu gelsin; sadece chat mesajında bırakma.
        - Antrenman hareketlerinde biliyorsan `source_url` ekle. Öncelik: ExRx / güvenilir egzersiz kütüphanesi / iyi teknik anlatımı. Emin değilsen URL uydurma; boş bırak.
        - `log_food` ve `add_recipe` action'ları app tarafından otomatik uygulanır. Bu action'ları üretirken "onaylıyor musun?" diye sorma; işlem gerçekleşmiş gibi kısa ve net konuş.
        - Kullanıcı "şu hareketi ekle" derse `update_workout_plan` içinde `workout_operation:"add_exercise"` kullan; tüm antrenman adını hareket listesine çevirmeye çalışma.
        - `log_food` ve `add_recipe` kullanıcı açıkça "ekle/kaydet" dediyse action olarak yazılabilir.
        - TARİF KURALI SERT: Kullanıcı tarif/yemek tarifi/protein pankek/bowl/yüksek protein tatlı gibi bir tarif isterse web_search ZORUNLU. Asla hafızadan veya tahminle tarif uydurma.
        - Tarif önerirken ve özellikle `add_recipe` üretirken sadece insanların denediği/bilinen kaynaklardan gelen tarifleri kullan. Öncelik: Nefis Yemek Tarifleri, Yemek.com, güvenilir tarif blogları, ürün markalarının tarif sayfaları, yorumlu/denenmiş tarif sayfaları.
        - `add_recipe` için `url` zorunludur. Kaynak URL yoksa veya sadece arama motoru linki varsa action üretme; "kaynaklı iyi tarif bulamadım, web'de daha net kaynak lazım" diye söyle.
        - `add_recipe` üretirken sadece link bırakma; recipe_summary, ingredients ve instructions alanlarını mutlaka web'de bulduğun kaynak tariften derle. Makroları kullanıcı hedefine göre tahmini uyarlayabilirsin ama tarifin malzeme/yapılışını icat etme.

        web_search NE ZAMAN:
        - Bilmediğin/emin olmadığın yemek/marka/ürün (ör. lokal restoranlar, yöresel yemekler, yeni çıkmış ürünler).
        - Tarif/yemek tarifi isteklerinde HER ZAMAN web_search kullan; tek aramayla kaynaklı, denenmiş/yorumlu tarif bul, sonra kullanıcının makro/mikro context'ine uyarla.
        - Protein tozu, whey bowl, smoothie bowl, yüksek protein tatlı/pankek/yoğurt bowl gibi tarif trendlerinde web_search ZORUNLU; kaynak URL'siz tarif verme.
        - Güncel veri gereken fitness sorusu (yeni supplement çalışmaları, yeni egzersiz teknikleri).
        - Yaygın yemek makroları için aratma — temel yemekler, klasik egzersizler, bilinen makro bilgileri kendi bilginle hızlı cevapla. Ama tarif önerisi/eklemesi bu istisnaya girmez; tarifte arama zorunlu.
        - Tek aramayla yetin, döngüye girme.

        KULLANICI HAKKINDA + VERİSİ + AGENT SKILL CONTEXT:
        - Eğer kullanıcı mesajının başında `[KULLANICI HAKKINDA ...]` bloku varsa, bu kullanıcının kendi yazdığı geçmişi/kişiliği — onu TANI, ona göre cevapla. Bu blok HER mesajda gelir. Ama kullanıcı normal yazıyorsa, bunu kullanıcıya her dakika aktarmamalısın. Kullanıcı sadece öneri isterken/body-building konuşurken bunu göz önünde bulundurarak cevap ver. Örneğin: kullanıcı "selam" yazdığında normal cevap ver; ama body-building ile alakalı bir şey sorarsa verileri ve mevcut durumu göz önüne al.
        - Eğer `HERCULES AGENT SKILL CONTEXT` bloku varsa, bu kişisel memory, Coach Intelligence Pack, evidence claim graph, PubMed research adayları veya food lookup sonuçları içerebilir. Coach Intelligence Pack içindeki sayısal trend/decision flag'leri öncelikli karar desteği olarak kullan. PubMed sonuçlarını "kanıt yönü" gibi ele al, tek başına kesin hüküm yapma.
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

struct AIFoodResult: Codable, Equatable, Sendable {
    var name: String?
    var grams: Double?
    var calories: Double?
    var protein_g: Double?
    var carbs_g: Double?
    var fat_g: Double?
    var message: String
    var actions: [AIAppAction]?

    // Günlük vitaminler
    var vitamin_c_mg: Double?
    var vitamin_b1_mg: Double?
    var vitamin_b6_mg: Double?
    var potassium_mg: Double?
    var magnesium_mg: Double?

    // Haftalık vitaminler & mineraller
    var vitamin_a_ug: Double?
    var vitamin_d_ug: Double?
    var vitamin_e_mg: Double?
    var vitamin_k_ug: Double?
    var vitamin_b12_ug: Double?
    var folate_ug: Double?
    var iron_mg: Double?
    var zinc_mg: Double?
    var calcium_mg: Double?
    var omega3_g: Double?

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
        actions: [AIAppAction]? = nil,
        vitamin_c_mg: Double? = nil,
        vitamin_b1_mg: Double? = nil,
        vitamin_b6_mg: Double? = nil,
        potassium_mg: Double? = nil,
        magnesium_mg: Double? = nil,
        vitamin_a_ug: Double? = nil,
        vitamin_d_ug: Double? = nil,
        vitamin_e_mg: Double? = nil,
        vitamin_k_ug: Double? = nil,
        vitamin_b12_ug: Double? = nil,
        folate_ug: Double? = nil,
        iron_mg: Double? = nil,
        zinc_mg: Double? = nil,
        calcium_mg: Double? = nil,
        omega3_g: Double? = nil
    ) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.protein_g = protein_g
        self.carbs_g = carbs_g
        self.fat_g = fat_g
        self.message = message
        self.actions = actions
        self.vitamin_c_mg = vitamin_c_mg
        self.vitamin_b1_mg = vitamin_b1_mg
        self.vitamin_b6_mg = vitamin_b6_mg
        self.potassium_mg = potassium_mg
        self.magnesium_mg = magnesium_mg
        self.vitamin_a_ug = vitamin_a_ug
        self.vitamin_d_ug = vitamin_d_ug
        self.vitamin_e_mg = vitamin_e_mg
        self.vitamin_k_ug = vitamin_k_ug
        self.vitamin_b12_ug = vitamin_b12_ug
        self.folate_ug = folate_ug
        self.iron_mg = iron_mg
        self.zinc_mg = zinc_mg
        self.calcium_mg = calcium_mg
        self.omega3_g = omega3_g
    }

    private enum CodingKeys: String, CodingKey {
        case name, grams, calories, protein_g, carbs_g, fat_g, message, actions
        case vitamin_c_mg, vitamin_b1_mg, vitamin_b6_mg, potassium_mg, magnesium_mg
        case vitamin_a_ug, vitamin_d_ug, vitamin_e_mg, vitamin_k_ug, vitamin_b12_ug
        case folate_ug, iron_mg, zinc_mg, calcium_mg, omega3_g
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
        vitamin_c_mg = try? c.decodeIfPresent(Double.self, forKey: .vitamin_c_mg)
        vitamin_b1_mg = try? c.decodeIfPresent(Double.self, forKey: .vitamin_b1_mg)
        vitamin_b6_mg = try? c.decodeIfPresent(Double.self, forKey: .vitamin_b6_mg)
        potassium_mg = try? c.decodeIfPresent(Double.self, forKey: .potassium_mg)
        magnesium_mg = try? c.decodeIfPresent(Double.self, forKey: .magnesium_mg)
        vitamin_a_ug = try? c.decodeIfPresent(Double.self, forKey: .vitamin_a_ug)
        vitamin_d_ug = try? c.decodeIfPresent(Double.self, forKey: .vitamin_d_ug)
        vitamin_e_mg = try? c.decodeIfPresent(Double.self, forKey: .vitamin_e_mg)
        vitamin_k_ug = try? c.decodeIfPresent(Double.self, forKey: .vitamin_k_ug)
        vitamin_b12_ug = try? c.decodeIfPresent(Double.self, forKey: .vitamin_b12_ug)
        folate_ug = try? c.decodeIfPresent(Double.self, forKey: .folate_ug)
        iron_mg = try? c.decodeIfPresent(Double.self, forKey: .iron_mg)
        zinc_mg = try? c.decodeIfPresent(Double.self, forKey: .zinc_mg)
        calcium_mg = try? c.decodeIfPresent(Double.self, forKey: .calcium_mg)
        omega3_g = try? c.decodeIfPresent(Double.self, forKey: .omega3_g)
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
        try c.encodeIfPresent(vitamin_c_mg, forKey: .vitamin_c_mg)
        try c.encodeIfPresent(vitamin_b1_mg, forKey: .vitamin_b1_mg)
        try c.encodeIfPresent(vitamin_b6_mg, forKey: .vitamin_b6_mg)
        try c.encodeIfPresent(potassium_mg, forKey: .potassium_mg)
        try c.encodeIfPresent(magnesium_mg, forKey: .magnesium_mg)
        try c.encodeIfPresent(vitamin_a_ug, forKey: .vitamin_a_ug)
        try c.encodeIfPresent(vitamin_d_ug, forKey: .vitamin_d_ug)
        try c.encodeIfPresent(vitamin_e_mg, forKey: .vitamin_e_mg)
        try c.encodeIfPresent(vitamin_k_ug, forKey: .vitamin_k_ug)
        try c.encodeIfPresent(vitamin_b12_ug, forKey: .vitamin_b12_ug)
        try c.encodeIfPresent(folate_ug, forKey: .folate_ug)
        try c.encodeIfPresent(iron_mg, forKey: .iron_mg)
        try c.encodeIfPresent(zinc_mg, forKey: .zinc_mg)
        try c.encodeIfPresent(calcium_mg, forKey: .calcium_mg)
        try c.encodeIfPresent(omega3_g, forKey: .omega3_g)
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

enum AIAppToolName: String, Codable, Equatable, Sendable {
    case logFood = "log_food"
    case addRecipe = "add_recipe"
    case updateWorkoutPlan = "update_workout_plan"

}

enum AIAppActionStatus: String, Codable, Equatable, Sendable {
    case pending
    case applied
    case rejected
    case failed
}

struct AIWorkoutExercisePlan: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var sets: Int?
    var reps: String?
    var load: String?
    var rir: String?
    var rest: String?
    var sourceURL: String?
    var notes: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, sets, reps, load, rir, rest, notes
        case sourceURL, source_url, url
    }

    init(
        id: UUID = UUID(),
        name: String,
        sets: Int? = nil,
        reps: String? = nil,
        load: String? = nil,
        rir: String? = nil,
        rest: String? = nil,
        sourceURL: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.load = load
        self.rir = rir
        self.rest = rest
        self.sourceURL = sourceURL
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        sets = try? c.decodeIfPresent(Int.self, forKey: .sets)
        if let value = try? c.decodeIfPresent(String.self, forKey: .reps) {
            reps = value
        } else if let value = try? c.decodeIfPresent(Int.self, forKey: .reps) {
            reps = "\(value)"
        } else {
            reps = nil
        }
        load = try? c.decodeIfPresent(String.self, forKey: .load)
        rir = try? c.decodeIfPresent(String.self, forKey: .rir)
        rest = try? c.decodeIfPresent(String.self, forKey: .rest)
        sourceURL = (try? c.decodeIfPresent(String.self, forKey: .sourceURL))
            ?? (try? c.decodeIfPresent(String.self, forKey: .source_url))
            ?? (try? c.decodeIfPresent(String.self, forKey: .url))
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(sets, forKey: .sets)
        try c.encodeIfPresent(reps, forKey: .reps)
        try c.encodeIfPresent(load, forKey: .load)
        try c.encodeIfPresent(rir, forKey: .rir)
        try c.encodeIfPresent(rest, forKey: .rest)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}

struct AIWorkoutDayPlan: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var weekday: Int
    var name: String
    var estimatedCalories: Double?
    var durationMinutes: Int?
    var focus: String?
    var warmup: String?
    var progression: String?
    var notes: String?
    var exercises: [AIWorkoutExercisePlan]

    private enum CodingKeys: String, CodingKey {
        case id, weekday, name, focus, warmup, progression, notes, exercises
        case estimatedCalories, estimated_calories
        case durationMinutes, duration_minutes
    }

    init(
        id: UUID = UUID(),
        weekday: Int,
        name: String,
        estimatedCalories: Double? = nil,
        durationMinutes: Int? = nil,
        focus: String? = nil,
        warmup: String? = nil,
        progression: String? = nil,
        notes: String? = nil,
        exercises: [AIWorkoutExercisePlan] = []
    ) {
        self.id = id
        self.weekday = weekday
        self.name = name
        self.estimatedCalories = estimatedCalories
        self.durationMinutes = durationMinutes
        self.focus = focus
        self.warmup = warmup
        self.progression = progression
        self.notes = notes
        self.exercises = exercises
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        weekday = (try? c.decode(Int.self, forKey: .weekday)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        estimatedCalories = (try? c.decodeIfPresent(Double.self, forKey: .estimatedCalories))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .estimated_calories))
        durationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .durationMinutes))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .duration_minutes))
        focus = try? c.decodeIfPresent(String.self, forKey: .focus)
        warmup = try? c.decodeIfPresent(String.self, forKey: .warmup)
        progression = try? c.decodeIfPresent(String.self, forKey: .progression)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        exercises = (try? c.decodeIfPresent([AIWorkoutExercisePlan].self, forKey: .exercises)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(weekday, forKey: .weekday)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(estimatedCalories, forKey: .estimatedCalories)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(focus, forKey: .focus)
        try c.encodeIfPresent(warmup, forKey: .warmup)
        try c.encodeIfPresent(progression, forKey: .progression)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(exercises, forKey: .exercises)
    }
}

struct AIAppAction: Identifiable, Equatable, Codable, Sendable {
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
    var durationMinutes: Int?
    var workoutOperation: String?
    var exerciseName: String?
    var sets: Int?
    var reps: String?
    var weight: Double?
    var load: String?
    var rir: String?
    var rest: String?
    var sourceURL: String?
    var workoutNotes: String?
    var focus: String?
    var warmup: String?
    var progression: String?
    var archiveCurrent: Bool?
    var programTitle: String?
    var programSummary: String?
    var programNotes: String?
    var days: [AIWorkoutDayPlan]?

    var itemName: String?
    var amount: Double?
    var unit: String?

    var grams: Double?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?

    // Vitaminler & mineraller
    var vitaminC_mg: Double?
    var vitaminB1_mg: Double?
    var vitaminB6_mg: Double?
    var potassium_mg: Double?
    var magnesium_mg: Double?
    var vitaminA_ug: Double?
    var vitaminD_ug: Double?
    var vitaminE_mg: Double?
    var vitaminK_ug: Double?
    var vitaminB12_ug: Double?
    var folate_ug: Double?
    var iron_mg: Double?
    var zinc_mg: Double?
    var calcium_mg: Double?
    var omega3_g: Double?

    var requiresConfirmation: Bool {
        tool == .updateWorkoutPlan
    }

    var displayTitle: String {
        switch tool {
        case .logFood: return "Kalori ekle"
        case .addRecipe: return "Tarif ekle"
        case .updateWorkoutPlan: return "Antrenman planı"
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
            if workoutOperation == "replace_program" {
                return programTitle ?? "Yeni program"
            }
            if workoutOperation == "archive_program" {
                return programTitle ?? "Mevcut programı arşivle"
            }
            return "\(weekdayLabel) → \(name ?? "Antrenman")"

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
        case durationMinutes, duration_minutes
        case workoutOperation, workout_operation
        case exerciseName, exercise_name
        case sets, reps, weight, load, rir, rest, focus, warmup, progression, days
        case sourceURL, source_url
        case workoutNotes, workout_notes
        case archiveCurrent, archive_current
        case programTitle, program_title
        case programSummary, program_summary
        case programNotes, program_notes

        case itemName, item_name
        case proteinG, protein_g
        case carbsG, carbs_g
        case fatG, fat_g
        case vitaminC_mg = "vitamin_c_mg"
        case vitaminB1_mg = "vitamin_b1_mg"
        case vitaminB6_mg = "vitamin_b6_mg"
        case potassium_mg
        case magnesium_mg
        case vitaminA_ug = "vitamin_a_ug"
        case vitaminD_ug = "vitamin_d_ug"
        case vitaminE_mg = "vitamin_e_mg"
        case vitaminK_ug = "vitamin_k_ug"
        case vitaminB12_ug = "vitamin_b12_ug"
        case folate_ug
        case iron_mg
        case zinc_mg
        case calcium_mg
        case omega3_g
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
        durationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .durationMinutes))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .duration_minutes))
        workoutOperation = (try? c.decodeIfPresent(String.self, forKey: .workoutOperation))
            ?? (try? c.decodeIfPresent(String.self, forKey: .workout_operation))
        exerciseName = (try? c.decodeIfPresent(String.self, forKey: .exerciseName))
            ?? (try? c.decodeIfPresent(String.self, forKey: .exercise_name))
        sets = try? c.decodeIfPresent(Int.self, forKey: .sets)
        if let value = try? c.decodeIfPresent(String.self, forKey: .reps) {
            reps = value
        } else if let value = try? c.decodeIfPresent(Int.self, forKey: .reps) {
            reps = "\(value)"
        } else {
            reps = nil
        }
        weight = try? c.decodeIfPresent(Double.self, forKey: .weight)
        load = try? c.decodeIfPresent(String.self, forKey: .load)
        rir = try? c.decodeIfPresent(String.self, forKey: .rir)
        rest = try? c.decodeIfPresent(String.self, forKey: .rest)
        sourceURL = (try? c.decodeIfPresent(String.self, forKey: .sourceURL))
            ?? (try? c.decodeIfPresent(String.self, forKey: .source_url))
        workoutNotes = (try? c.decodeIfPresent(String.self, forKey: .workoutNotes))
            ?? (try? c.decodeIfPresent(String.self, forKey: .workout_notes))
        focus = try? c.decodeIfPresent(String.self, forKey: .focus)
        warmup = try? c.decodeIfPresent(String.self, forKey: .warmup)
        progression = try? c.decodeIfPresent(String.self, forKey: .progression)
        archiveCurrent = (try? c.decodeIfPresent(Bool.self, forKey: .archiveCurrent))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: .archive_current))
        programTitle = (try? c.decodeIfPresent(String.self, forKey: .programTitle))
            ?? (try? c.decodeIfPresent(String.self, forKey: .program_title))
        programSummary = (try? c.decodeIfPresent(String.self, forKey: .programSummary))
            ?? (try? c.decodeIfPresent(String.self, forKey: .program_summary))
        programNotes = (try? c.decodeIfPresent(String.self, forKey: .programNotes))
            ?? (try? c.decodeIfPresent(String.self, forKey: .program_notes))
        days = try? c.decodeIfPresent([AIWorkoutDayPlan].self, forKey: .days)

        itemName = (try? c.decodeIfPresent(String.self, forKey: .itemName))
            ?? (try? c.decodeIfPresent(String.self, forKey: .item_name))
        proteinG = (try? c.decodeIfPresent(Double.self, forKey: .proteinG))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .protein_g))
        carbsG = (try? c.decodeIfPresent(Double.self, forKey: .carbsG))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .carbs_g))
        fatG = (try? c.decodeIfPresent(Double.self, forKey: .fatG))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .fat_g))
        vitaminC_mg = try? c.decodeIfPresent(Double.self, forKey: .vitaminC_mg)
        vitaminB1_mg = try? c.decodeIfPresent(Double.self, forKey: .vitaminB1_mg)
        vitaminB6_mg = try? c.decodeIfPresent(Double.self, forKey: .vitaminB6_mg)
        potassium_mg = try? c.decodeIfPresent(Double.self, forKey: .potassium_mg)
        magnesium_mg = try? c.decodeIfPresent(Double.self, forKey: .magnesium_mg)
        vitaminA_ug = try? c.decodeIfPresent(Double.self, forKey: .vitaminA_ug)
        vitaminD_ug = try? c.decodeIfPresent(Double.self, forKey: .vitaminD_ug)
        vitaminE_mg = try? c.decodeIfPresent(Double.self, forKey: .vitaminE_mg)
        vitaminK_ug = try? c.decodeIfPresent(Double.self, forKey: .vitaminK_ug)
        vitaminB12_ug = try? c.decodeIfPresent(Double.self, forKey: .vitaminB12_ug)
        folate_ug = try? c.decodeIfPresent(Double.self, forKey: .folate_ug)
        iron_mg = try? c.decodeIfPresent(Double.self, forKey: .iron_mg)
        zinc_mg = try? c.decodeIfPresent(Double.self, forKey: .zinc_mg)
        calcium_mg = try? c.decodeIfPresent(Double.self, forKey: .calcium_mg)
        omega3_g = try? c.decodeIfPresent(Double.self, forKey: .omega3_g)
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
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(workoutOperation, forKey: .workoutOperation)
        try c.encodeIfPresent(exerciseName, forKey: .exerciseName)
        try c.encodeIfPresent(sets, forKey: .sets)
        try c.encodeIfPresent(reps, forKey: .reps)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(load, forKey: .load)
        try c.encodeIfPresent(rir, forKey: .rir)
        try c.encodeIfPresent(rest, forKey: .rest)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try c.encodeIfPresent(workoutNotes, forKey: .workoutNotes)
        try c.encodeIfPresent(focus, forKey: .focus)
        try c.encodeIfPresent(warmup, forKey: .warmup)
        try c.encodeIfPresent(progression, forKey: .progression)
        try c.encodeIfPresent(archiveCurrent, forKey: .archiveCurrent)
        try c.encodeIfPresent(programTitle, forKey: .programTitle)
        try c.encodeIfPresent(programSummary, forKey: .programSummary)
        try c.encodeIfPresent(programNotes, forKey: .programNotes)
        try c.encodeIfPresent(days, forKey: .days)

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

struct ChatTurn: Identifiable, Equatable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
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
            "description": "Bir yemek/ürünün besin değeri, güncel bir fitness/diyet/supplement bilgisi veya emin olmadığın herhangi bir konu için web araması yap. Tarif/yemek tarifi isteklerinde ZORUNLU kullan; denenmiş/yorumlu/known kaynak tarif ve gerçek URL bul. Temel/yaygın makro bilgi için kullanma — ama tarif önerisi/eklemesi her zaman kaynaklı olmalı.",
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
        let requiresRecipeSearch = AIConfig.requiresRecipeWebSearch(newUserText)

        // Tool loop — max 2 iterations to avoid runaway
        for _ in 0..<2 {
            let toolChoice: Any = (requiresRecipeSearch && lastSearchQuery == nil)
                ? ["type": "function", "function": ["name": "web_search"]]
                : "none"
            let needsTools = requiresRecipeSearch
            var body: [String: Any] = [
                "model": AIKeyStore.shared.openRouterModel,
                "messages": messages,
                "temperature": 0.2,
                "stream": !needsTools  // tool loop'ta streaming kullanma
            ]
            if needsTools {
                body["tools"] = [Self.webSearchTool]
                body["tool_choice"] = toolChoice
            }

            // Streaming path (tool olmayan normal sohbet)
            if body["stream"] as? Bool == true {
                let content = try await streamJSON(body: body, key: key, onUpdate: onMessageUpdate)
                return (parseFood(content), lastSearchQuery)
            }

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
                ["role": "system", "content": "Sen kısa ve doğru bilgi veren bir araştırmacısın. Tarif/yemek tarifi sorgusu ise ASLA tarif uydurma: web'de bulunan 2-4 gerçek tarif kaynağı ver; başlık, kaynak adı, tam URL, kısa malzeme/yapılış özeti, porsiyon/süre ve varsa kcal/P/K/Y bilgisini dön. Kaynak yoksa 'güvenilir tarif kaynağı bulunamadı' de. Yemek makro sorgusu ise porsiyon, kcal, protein, karb, yağ özetini dön. Fitness/sağlık/genel sorgu ise en güncel ve doğru bilgiyi 3-5 cümlede özetle. Maksimum 8 satır."],
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

    private func streamJSON(
        body: [String: Any],
        key: String,
        onUpdate: @MainActor @escaping (String) -> Void
    ) async throws -> String {
        var req = URLRequest(url: AIConfig.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (stream, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OpenRouterError.badResponse(-1, "Stream response error")
        }

        var accumulated = ""
        for try await line in stream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]" else { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let token = delta["content"] as? String
            else { continue }
            accumulated += token
            await onUpdate(accumulated)
        }
        return accumulated
    }

    /// Lean, tek-atışlık completion — araç/streaming yok. Hafıza çıkarımı için.
    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        let key = AIKeyStore.shared.apiKey
        guard !key.isEmpty else { throw OpenRouterError.missingKey }
        let body: [String: Any] = [
            "model": AIKeyStore.shared.openRouterModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.1
        ]
        let (data, http) = try await postJSON(body: body, key: key)
        guard (200..<300).contains(http.statusCode) else {
            throw OpenRouterError.badResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "no body")
        }
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = outer["choices"] as? [[String: Any]],
              let first = choices.first,
              let messageDict = first["message"] as? [String: Any],
              let content = messageDict["content"] as? String
        else {
            throw OpenRouterError.decoding(String(data: data, encoding: .utf8) ?? "no body")
        }
        return content
    }

    private func postJSON(body: [String: Any], key: String) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: AIConfig.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

/// Stores provider/model in UserDefaults and OpenRouter key in Keychain.
final class AIKeyStore {
    static let shared = AIKeyStore()
    private let defaults = UserDefaults.standard
    private let keyAPI = "hercules.openrouter.api_key"
    private let keyProvider = "hercules.ai.provider"
    private let keyModelOpenRouter = "hercules.openrouter.model"
    private let keyModelCodex = "hercules.codex.model"
    private let keyReasoning = "hercules.codex.reasoning"
    private let keychainService = "hercules.openrouter"
    private let keychainAccount = "api_key"

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
            if let keychainValue = Self.readKeychainPassword(service: keychainService, account: keychainAccount),
               !keychainValue.isEmpty {
                return keychainValue
            }
            let stored = defaults.string(forKey: keyAPI) ?? ""
            if !stored.isEmpty {
                Self.writeKeychainPassword(stored, service: keychainService, account: keychainAccount)
                defaults.removeObject(forKey: keyAPI)
            }
            return stored.isEmpty ? AIConfig.defaultAPIKey : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Self.deleteKeychainPassword(service: keychainService, account: keychainAccount)
                defaults.removeObject(forKey: keyAPI)
            } else {
                Self.writeKeychainPassword(trimmed, service: keychainService, account: keychainAccount)
                defaults.removeObject(forKey: keyAPI)
            }
        }
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

    var openRouterModel: String {
        get {
            let stored = defaults.string(forKey: keyModelOpenRouter) ?? ""
            if !stored.isEmpty && AIProvider.openRouter.availableModels.contains(stored) {
                return stored
            }
            return AIProvider.openRouter.defaultModel
        }
        set { defaults.set(newValue, forKey: keyModelOpenRouter) }
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
        case .openRouter: return OllamaClient()
        case .codex: return CodexFirstFallbackClient()
        }
    }

    @discardableResult
    private static func writeKeychainPassword(_ password: String, service: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound { return false }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private static func readKeychainPassword(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainPassword(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
