import Foundation

struct AgentContext {
    let appContext: String?
    let history: [ChatTurn]
    let dataSnapshot: AgentDataSnapshot?
    let now: Date
}

struct SkillResult {
    let skillID: String
    let title: String
    let content: String
    let sources: [String]

    var formatted: String {
        var output = ["### \(title)", content]
        if !sources.isEmpty {
            output.append("Kaynaklar: \(sources.joined(separator: " | "))")
        }
        return output.joined(separator: "\n")
    }
}

protocol AgentSkill {
    var id: String { get }
    var name: String { get }
    var description: String { get }

    func canHandle(_ query: String) -> Bool
    func run(query: String, context: AgentContext) async throws -> SkillResult?
}

enum AgentQueryClassifier {
    static let bodySignals = [
        "bodybuilding", "fitness", "coach", "koc", "vucut", "kas", "hipertrofi", "hypertrophy",
        "protein", "whey", "kreatin", "creatine", "supplement", "antrenman", "idman",
        "training", "resistance", "volume", "set", "tekrar", "rir", "rpe", "failure",
        "bulk", "cut", "definasyon", "yag", "lean", "kilo", "kalori", "makro",
        "sleep", "uyku", "recovery", "toparlanma", "adim", "step"
    ]

    static let trainingSignals = [
        "antrenman", "idman", "program", "split", "hareket", "set", "tekrar", "rir", "rpe",
        "failure", "progressive", "overload", "bench", "squat", "deadlift", "pulldown",
        "row", "press", "volume", "frekans", "frequency", "deload"
    ]

    static let nutritionSignals = [
        "protein", "whey", "kalori", "makro", "karb", "carb", "yag", "definasyon",
        "cut", "bulk", "diyet", "beslenme", "acik", "açık", "maintenance",
        "tdee", "bmr", "tokluk", "ogun", "öğün", "tarif", "meal"
    ]

    static let researchTriggers = [
        "pubmed", "makale", "calisma", "arastirma", "paper", "evidence", "kanit",
        "meta", "systematic", "literatur", "guncel", "son", "yeni", "2026",
        "bilim", "science", "study", "review", "nippard", "jeff"
    ]

    static let coachIntentTriggers = [
        "nasil", "neden", "mantikli", "oner", "oneri", "ne dusunuyorsun",
        "iyi mi", "dogru mu", "yanlis mi", "optimal", "optimum", "gelistir",
        "duzelt", "arttir", "azalt", "hedef", "plato", "ulasir miyim", "deger mi"
    ]

    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    static func containsAny(_ lowercasedText: String, _ needles: [String]) -> Bool {
        needles.map { normalized($0) }.contains { needle in
            guard !needle.isEmpty else { return false }
            if needle.count <= 3 || needle.contains(" ") {
                let escaped = NSRegularExpression.escapedPattern(for: needle)
                let pattern = "(^|[^a-z0-9])\(escaped)($|[^a-z0-9])"
                return lowercasedText.range(of: pattern, options: .regularExpression) != nil
            }
            return lowercasedText.contains(needle)
        }
    }

    static func isCoachQuery(_ query: String) -> Bool {
        let lower = normalized(query)
        return containsAny(lower, bodySignals)
            || containsAny(lower, trainingSignals)
            || containsAny(lower, nutritionSignals)
    }

    static func isLikelyFoodLog(_ query: String) -> Bool {
        let lower = normalized(query)
        let hasAmount = lower.range(of: #"(\d+([,.]\d+)?)\s*(g|gr|gram|kg|ml|lt|l|olcek|ölcek|ölçek|adet|dilim|porsiyon)"#, options: .regularExpression) != nil
        let hasWriteIntent = containsAny(lower, ["yedim", "ictim", "içtim", "pisirdim", "pişirdim", "hasladim", "haşladım", "ekle", "kaydet"])
        let asksForReasoning = lower.contains("?") || containsAny(lower, researchTriggers + coachIntentTriggers)
        return hasAmount && hasWriteIntent && !asksForReasoning
    }

    static func shouldUseResearchCache(_ query: String) -> Bool {
        let lower = normalized(query)
        guard isCoachQuery(query), !isLikelyFoodLog(query) else { return false }
        return containsAny(lower, researchTriggers)
            || containsAny(lower, coachIntentTriggers)
            || containsAny(lower, trainingSignals)
            || containsAny(lower, nutritionSignals)
    }

    static func shouldUseLivePubMed(_ query: String) -> Bool {
        let lower = normalized(query)
        guard isCoachQuery(query), !isLikelyFoodLog(query) else { return false }
        return containsAny(lower, researchTriggers)
            || (containsAny(lower, ["optimal", "optimum", "kanıt", "kanit", "bilimsel", "science"]) && containsAny(lower, bodySignals))
    }
}

struct CoachBrainSkill: AgentSkill {
    let id = "coach.brain.v4"
    let name = "Hercules Coach Brain V4"
    let description = "Fitness/nutrition/body-comp sorularında uzman cevap protokolünü aktif eder."

    func canHandle(_ query: String) -> Bool {
        AgentQueryClassifier.isCoachQuery(query) && !AgentQueryClassifier.isLikelyFoodLog(query)
    }

    func run(query: String, context: AgentContext) async throws -> SkillResult? {
        let lower = AgentQueryClassifier.normalized(query)
        let domains = [
            AgentQueryClassifier.containsAny(lower, AgentQueryClassifier.trainingSignals) ? "antrenman" : nil,
            AgentQueryClassifier.containsAny(lower, AgentQueryClassifier.nutritionSignals) ? "beslenme/makro" : nil,
            AgentQueryClassifier.containsAny(lower, ["kilo", "yag", "definasyon", "cut", "bulk", "adim", "step"]) ? "vücut kompozisyonu" : nil
        ].compactMap { $0 }.joined(separator: " + ")

        return SkillResult(
            skillID: id,
            title: "Coach Brain V4",
            content: """
            Sorgu alanı: \(domains.isEmpty ? "genel koçluk" : domains)

            Cevap protokolü:
            - Kullanıcıyı beginner kabul etme; genel "protein al, düzenli uyu" klişesi yerine mevcut kilosu, yağ oranı, kalori/adım/antrenman verisi ve hafızasına göre karar ver.
            - Önce net hüküm ver, sonra kısa gerekçe, sonra uygulanabilir eşik/plan ver. Gerekiyorsa güven seviyesini belirt.
            - Evidence hiyerarşisi: meta-analiz / sistematik review / position stand > RCT > mekanizma > anekdot. Research context geldiyse paper/PMID adını abartmadan kullan.
            - Antrenman sorularında volume, frekans, RIR/failure, progresyon, egzersiz seçimi, yorgunluk yönetimi ve adherence dengesini birlikte düşün.
            - Definasyon sorularında kilo trendi, kalori log tutarlılığı, protein, adım, su/glikojen ve kayıp hızı ayrımını yap.
            - Context'te App hedef kalorisi/makro hedefi varsa tek kaynak odur; başka hedef sayı üretme.
            - Spor günlerine otomatik ekstra kalori ekleme; kullanıcının hedef kalorisi sabit kabul edilir, sadece özel olarak isterse farklılaştır.
            - App verisi değiştirme sadece kullanıcı açıkça isterse action üretir. Antrenman/yemek planı değişikliklerinde önce onay sorulur.
            - Tarif/yemek tarifi isteklerinde kaynak zorunludur: web_search yapmadan tarif önerme, tarif uydurma veya `add_recipe` action üretme. Kaynak URL yoksa tarif ekleme.
            - Basit yemek kaydı gibi mesajlarda uzun bilim dersi verme; hızlı makro/kcal hesapla.
            """,
            sources: []
        )
    }
}

struct CoachIntelligenceSkill: AgentSkill {
    let id = "coach.intelligence.pack"
    let name = "Coach Intelligence Pack"
    let description = "Uygulama verisinden kişisel model, karar flagleri ve evidence claim graph üretir."

    func canHandle(_ query: String) -> Bool {
        AgentQueryClassifier.isCoachQuery(query) && !AgentQueryClassifier.isLikelyFoodLog(query)
    }

    func run(query: String, context: AgentContext) async throws -> SkillResult? {
        guard let dataSnapshot = context.dataSnapshot,
              let content = CoachIntelligence.buildContext(query: query, data: dataSnapshot)
        else { return nil }

        return SkillResult(
            skillID: id,
            title: "Coach Intelligence Pack",
            content: content,
            sources: []
        )
    }
}

final class AgentRouter {
    static let shared = AgentRouter(
        skills: [
            CoachBrainSkill(),
            CoachIntelligenceSkill(),
            MicronutrientCoverageSkill(),
            ProteinRecipeTrendSkill(),
            MemoryRecallSkill(),
            ResearchLibrarySkill(),
            PubMedResearchSkill(),
            FoodLookupSkill()
        ]
    )

    private let skills: [AgentSkill]
    private let memoryProvider: LocalMemoryProvider

    init(skills: [AgentSkill], memoryProvider: LocalMemoryProvider = .shared) {
        self.skills = skills
        self.memoryProvider = memoryProvider
    }

    func buildSkillContext(
        query: String,
        appContext: String?,
        history: [ChatTurn],
        dataSnapshot: AgentDataSnapshot? = nil
    ) async -> String? {
        let context = AgentContext(appContext: appContext, history: history, dataSnapshot: dataSnapshot, now: .now)
        var results: [SkillResult] = []

        for skill in skills where skill.canHandle(query) {
            do {
                if let result = try await skill.run(query: query, context: context) {
                    results.append(result)
                }
            } catch {
                continue
            }
        }

        guard !results.isEmpty else { return nil }
        return """
        === HERCULES AGENT SKILL CONTEXT ===
        Bu bölüm kullanıcıya ham olarak anlatılmak zorunda değil. Sadece alakalı olduğunda kullan.
        Kaynaklı research varsa tarih/kaynak hassasiyetini koru; emin olmadığın yerde kesin konuşma.

        \(results.map(\.formatted).joined(separator: "\n\n"))
        === AGENT SKILL CONTEXT SONU ===
        """
    }

    /// Konuşmayı arka planda LLM memory-manager'a verir (Mem0 tarzı extraction +
    /// update). Fire-and-forget — chat akışını bloklamaz. LLM ulaşılamazsa
    /// MemoryManager içinde keyword-heuristik fallback'e düşer.
    func absorbConversation(userText: String, assistantText: String) {
        Task { @MainActor in
            await MemoryManager.shared.ingest(userText: userText, assistantText: assistantText)
        }
    }
}
