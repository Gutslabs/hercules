import Foundation
import Security
import Observation

enum AIConfig {
    static let defaultAPIKey = ""
    static let defaultModel = "openai/gpt-5.4-mini"
    // :online suffix = OpenRouter'ın web arama eklentisi (her modelde çalışır).
    static let searchModel = "openai/gpt-5.4-mini:online"
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
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

    static func normalizedPromptKey(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased(with: Locale(identifier: "tr_TR"))
    }

    /// System prompt — her mesajda yeniden hesaplanır, bugünün tarihi gömülür.
    static var systemPrompt: String {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "tr_TR")
        dateFmt.dateFormat = "d MMMM yyyy EEEE"
        let today = dateFmt.string(from: .now)
        let datePrefix = "Bugünün tarihi: \(today). Zaman bağlamlı tüm yorumları buna göre yap."
        return datePrefix + "\n\n" + PromptStore.shared.text(.chatSystem)
    }

    /// `.chatSystem` varsayılan gövdesi (tarih öneki hariç). PromptStore override tutar →
    /// Admin ▸ System ekranından düzenlenebilir. Düzenlenmemişse bu metin kullanılır.
    static let chatSystemBody = """
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
           {"name": "yemek adı", "grams": <gram>, "calories": <kcal>, "protein_g": <p>, "carbs_g": <c>, "fat_g": <y>, "message": "kısa Türkçe açıklama"}

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

    /// `.webSearchSub` varsayılanı — :online alt-modeline giden araştırmacı system prompt'u.
    static let webSearchSubDefault = "Sen kısa ve doğru bilgi veren bir araştırmacısın. Tarif/yemek tarifi sorgusu ise ASLA tarif uydurma: web'de bulunan 2-4 gerçek tarif kaynağı ver; başlık, kaynak adı, tam URL, kısa malzeme/yapılış özeti, porsiyon/süre ve varsa kcal/P/K/Y bilgisini dön. Kaynak yoksa 'güvenilir tarif kaynağı bulunamadı' de. Yemek makro sorgusu ise porsiyon, kcal, protein, karb, yağ özetini dön. Fitness/sağlık/genel sorgu ise en güncel ve doğru bilgiyi 3-5 cümlede özetle. Maksimum 8 satır."
}

final class OpenRouterClient: AIClient {
    private let session: URLSession

    static let defaultSession: URLSession = {
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
    static let webSearchTool: [String: Any] = [
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
                : "auto"
            let body: [String: Any] = [
                "model": AIKeyStore.shared.openRouterModel,
                "messages": messages,
                "temperature": 0.2,
                "tools": [Self.webSearchTool],
                "tool_choice": toolChoice
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

    /// Lean, tek-atışlık completion — araç/streaming yok. Memory extraction için.
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

    /// Performs a web search by hitting the :online variant of the model.
    /// Returns concise text to feed back as tool result.
    private func performWebSearch(query: String, key: String) async throws -> String {
        let body: [String: Any] = [
            "model": AIConfig.searchModel,
            "messages": [
                ["role": "system", "content": PromptStore.shared.text(.webSearchSub)],
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
        #if os(macOS)
        switch provider {
        case .openRouter: return OpenRouterClient()
        case .codex: return CodexFirstFallbackClient()
        }
        #else
        // iOS'ta Codex/Terminal yok — provider ne olursa olsun DOĞRUDAN OpenRouter.
        // Böylece telefonda "Codex hata verdi… OpenRouter'a yönlendirdim" bildirimi hiç çıkmaz.
        return OpenRouterClient()
        #endif
    }

    @discardableResult
    static func writeKeychainPassword(_ password: String, service: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // AfterFirstUnlock: cihaz yeniden başlatılıp ilk kez açıldıktan sonra (kilitliyken
        // bile) okunabilir ve kalıcı kalır — "bir kere gir, sonsuza dek dursun". update'e de
        // koyuyoruz ki eski WhenUnlocked kayıtlar da bu eriişme seviyesine taşınsın.
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound { return false }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func readKeychainPassword(service: String, account: String) -> String? {
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

    static func deleteKeychainPassword(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Editable system prompts (Admin ▸ System)

/// Uygulamadaki düzenlenebilir LLM prompt'larının kataloğu. Her case bir prompt'a karşılık
/// gelir; varsayılan metni `defaultText`'tir, kullanıcı override'ı `PromptStore`'da tutulur.
/// Mac-only prompt'ların (hafıza/koç) varsayılanları kendi dosyalarında tanımlı.
enum PromptKey: String, CaseIterable, Identifiable {
    case chatSystem
    case webSearchSub
    case memoryExtraction
    case memoryConsolidation
    case coachReport
    case coachRecipe

    var id: String { rawValue }

    /// UI başlığı.
    var title: String {
        switch self {
        case .chatSystem:         return "Ana Koç (Sohbet)"
        case .webSearchSub:       return "Web Araması Alt-Modeli"
        case .memoryExtraction:   return "Hafıza Çıkarımı"
        case .memoryConsolidation:return "Hafıza Konsolidasyonu"
        case .coachReport:        return "Koç Günlük Analiz"
        case .coachRecipe:        return "Koç Günlük Tarif"
        }
    }

    /// Sidebar/kart gruplaması.
    var group: String {
        switch self {
        case .chatSystem, .webSearchSub:                return "Sohbet & Arama"
        case .memoryExtraction, .memoryConsolidation:   return "Hafıza"
        case .coachReport, .coachRecipe:                return "Koç"
        }
    }

    /// Nerede ve ne zaman kullanıldığı.
    var locationNote: String {
        switch self {
        case .chatSystem:         return "OpenRouterClient · her sohbet mesajında system prompt"
        case .webSearchSub:       return "OpenRouterClient · :online web araması alt-modeli"
        case .memoryExtraction:   return "MemoryManager · konuşmadan kalıcı hafıza çıkarımı"
        case .memoryConsolidation:return "MemoryManager · hafıza tekrar/çelişki temizliği"
        case .coachReport:        return "CoachEngine · her sabahki günlük analiz"
        case .coachRecipe:        return "CoachEngine · her sabahki günlük tarif"
        }
    }

    /// Otomatik enjekte edilen dinamik parçalar (kullanıcının bilmesi için).
    var dynamicNote: String? {
        switch self {
        case .chatSystem:
            return "Başına bugünün tarihi otomatik eklenir. Kullanıcı verisi + skill context mesajla gelir."
        case .webSearchSub:
            return nil
        case .memoryExtraction:
            return "Son konuşma + mevcut hafıza kayıtları ayrı bir kullanıcı mesajı olarak eklenir."
        case .memoryConsolidation:
            return "Mevcut hafıza kayıt listesi ayrı bir kullanıcı mesajı olarak eklenir."
        case .coachReport:
            return "Başına bugünün tarihi; sonuna bilimsel-dayanak direktifi + açık takip maddeleri + önceki rapor + makine-okunur takip formatı otomatik eklenir."
        case .coachRecipe:
            return "Başına bugünün tarihi otomatik eklenir. Yemek günlüğü + kayıtlı tarifler bağlam olarak gelir."
        }
    }

    /// Varsayılan (düzenlenmemiş) metin. Mac-only prompt'lar kendi dosyalarındaki sabitlerden gelir.
    var defaultText: String {
        switch self {
        case .chatSystem:   return AIConfig.chatSystemBody
        case .webSearchSub: return AIConfig.webSearchSubDefault
        case .memoryExtraction:
            #if os(macOS)
            return MemoryManager.memoryExtractionDefault
            #else
            return ""
            #endif
        case .memoryConsolidation:
            #if os(macOS)
            return MemoryManager.memoryConsolidationDefault
            #else
            return ""
            #endif
        case .coachReport:
            #if os(macOS)
            return CoachEngine.reportInstructionsDefault
            #else
            return ""
            #endif
        case .coachRecipe:
            #if os(macOS)
            return CoachEngine.recipeInstructionsDefault
            #else
            return ""
            #endif
        }
    }
}

/// Düzenlenebilir prompt override'larını saklar (UserDefaults JSON). `text(_:)` override
/// varsa onu, yoksa `defaultText`'i döner. Tüm prompt çağrı yerleri buradan okur.
@Observable
final class PromptStore {
    static let shared = PromptStore()

    private static let storageKey = "hercules.prompts.overrides.v1"
    private var overrides: [String: String]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            overrides = dict
        } else {
            overrides = [:]
        }
    }

    /// Etkin metin: geçerli override varsa o, yoksa varsayılan.
    func text(_ key: PromptKey) -> String {
        if let override = overrides[key.rawValue],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return key.defaultText
    }

    func isOverridden(_ key: PromptKey) -> Bool {
        overrides[key.rawValue] != nil
    }

    func override(for key: PromptKey) -> String? {
        overrides[key.rawValue]
    }

    /// Override yaz. Boşsa veya varsayılana eşitse override kaldırılır (temiz tutar).
    func setOverride(_ key: PromptKey, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == key.defaultText.trimmingCharacters(in: .whitespacesAndNewlines) {
            overrides[key.rawValue] = nil
        } else {
            overrides[key.rawValue] = value
        }
        persist()
    }

    func resetToDefault(_ key: PromptKey) {
        overrides[key.rawValue] = nil
        persist()
    }

    func resetAll() {
        overrides = [:]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
