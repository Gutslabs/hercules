import Foundation

@MainActor
final class MemoryManager {
    static let shared = MemoryManager()
    private init() {}

    private let provider = LocalMemoryProvider.shared

    func ingest(userText: String, assistantText: String) async {
        let user = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return }
        // Onay/gürültü turlarında LLM çağrısı israf olur — atla.
        if Self.isTrivial(user) { return }

        let candidates = provider.candidatesForUpdate(userText: user, assistantText: assistantText)
        let prompt = Self.buildUserPrompt(userText: user, assistantText: assistantText, candidates: candidates)
        let client = AIKeyStore.shared.makeClient()

        do {
            let raw = try await client.complete(systemPrompt: Self.systemPrompt, userPrompt: prompt)
            if let ops = Self.parseOperations(raw, candidates: candidates) {
                // ops boş olabilir: LLM "tutulacak kalıcı bilgi yok" dedi → saygı duy.
                provider.applyLLMOperations(ops)
            } else {
                // Yanıt çözümlenemedi → heuristik fallback.
                provider.absorbConversation(userText: user, assistantText: assistantText)
            }
        } catch {
            // Offline / API hatası → heuristik fallback (regresyon yok).
            provider.absorbConversation(userText: user, assistantText: assistantText)
        }

        // Arka plan bakımı: lokal decay + (eşik/interval uygunsa) LLM konsolidasyonu.
        await consolidateIfNeeded()
        // Model zaten yüklüyse eksik embedding'leri tamamla (sohbet sırasında indirme tetiklemez).
        await embedPendingMemories()
    }

    // MARK: - Konsolidasyon + decay

    private static let consolidationKey = "hercules.memory.lastConsolidation"
    private static let consolidationMinInterval: TimeInterval = 6 * 3600
    private static let consolidationCountThreshold = 40
    private static let consolidationMaxCandidates = 120

    /// Lokal decay her zaman çalışır; aktif kayıt sayısı eşiği aşar VE son
    /// konsolidasyondan yeterince zaman geçtiyse LLM ile near-dupe/çelişki temizliği
    /// yapılır (offline/hata → atlanır, decay yine de uygulanmış olur).
    func consolidateIfNeeded() async {
        provider.applyDecay()

        let active = provider.allMemories()
        guard active.count >= Self.consolidationCountThreshold else { return }
        let defaults = UserDefaults.standard
        let last = (defaults.object(forKey: Self.consolidationKey) as? Date) ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.consolidationMinInterval else { return }
        defaults.set(Date(), forKey: Self.consolidationKey)   // tekrar tetiklenmeyi önle

        let candidates = Array(active.prefix(Self.consolidationMaxCandidates))
        let prompt = Self.buildConsolidationPrompt(candidates)
        let client = AIKeyStore.shared.makeClient()
        do {
            let raw = try await client.complete(systemPrompt: Self.consolidationSystemPrompt, userPrompt: prompt)
            if let ops = Self.parseOperations(raw, candidates: candidates) {
                provider.applyLLMOperations(ops)
            }
        } catch {
            // offline / hata → decay zaten yapıldı, sorun değil.
        }
    }

    // MARK: - Embedding (semantic retrieval backfill)

    /// Model HAZIRSA eksik embedding'leri tamamla. Model yüklü değilse no-op (indirme TETİKLEMEZ).
    func embedPendingMemories() async {
        let pending = provider.memoriesNeedingEmbedding(model: EmbeddingService.modelID, limit: 64)
        guard !pending.isEmpty else { return }
        var results: [UUID: [Float]] = [:]
        for item in pending {
            guard let vector = await EmbeddingService.shared.embedDocumentIfAvailable(item.content) else {
                break   // model hazır değil → sonra (Memory ekranı warmUp tetikler)
            }
            results[item.id] = vector
        }
        if !results.isEmpty {
            provider.applyEmbeddings(results, model: EmbeddingService.modelID)
        }
    }

    /// Embedding modelini indir/yükle (gerekiyorsa) ve tüm eksik kayıtları backfill et.
    /// Memory ekranı açıldığında çağrılır — sürpriz indirmeyi sohbet akışının dışına alır.
    func warmUpEmbeddingsAndBackfill() async {
        let model = EmbeddingService.modelID
        let alreadyLoaded = await EmbeddingService.shared.isLoaded
        let pendingBefore = provider.pendingEmbeddingCount(model: model)

        if alreadyLoaded && pendingBefore == 0 {
            EmbeddingStatus.shared.set(.ready)
            return
        }

        EmbeddingStatus.shared.set(alreadyLoaded ? .backfilling(done: 0, total: pendingBefore) : .downloading(fraction: 0))

        guard await EmbeddingService.shared.warmUp() else {
            EmbeddingStatus.shared.set(.unavailable)
            return
        }

        let total = max(provider.pendingEmbeddingCount(model: model), 1)
        var safety = 0
        while safety < 200 {
            let remaining = provider.pendingEmbeddingCount(model: model)
            if remaining == 0 { break }
            EmbeddingStatus.shared.set(.backfilling(done: max(0, total - remaining), total: total))
            await embedPendingMemories()
            safety += 1
            // İlerleme yoksa (embedding üretilemiyorsa) sonsuz döngüyü önle.
            if provider.pendingEmbeddingCount(model: model) >= remaining { break }
        }

        EmbeddingStatus.shared.set(provider.pendingEmbeddingCount(model: model) == 0 ? .ready : .unavailable)
    }

    // MARK: - Prompt

    private static let systemPrompt = """
    Sen Hercules adlı Türkçe, bilim temelli bodybuilding koçu uygulamasının HAFIZA YÖNETİCİSİSİN.
    Görevin: kullanıcı ile koç arasındaki SON konuşmadan, uzun vadeli hafızada tutulmaya değer
    KALICI ve KULLANICIYA ÖZEL bilgileri çıkarmak ve mevcut hafızayla karşılaştırıp operasyon üretmek.

    KALICI sayılan bilgiler:
    - profile: yaş, boy, kilo, cinsiyet, vücut yağ oranı gibi kişisel ölçümler.
    - goal: hedef kilo/yağ oranı, bulk/cut/definasyon hedefi, hedef tarihi.
    - preference: sevdiği/sevmediği yemek-egzersiz, çalışma saati, iletişim tonu tercihi.
    - constraint: sakatlık, alerji, ekipman/zaman/bütçe kısıtı, kaçındığı şeyler.
    - supplement: kullandığı takviyeler, dozları, markaları.
    - training: programı, antrenman frekansı, favori/öncelikli hareketler, split.
    - nutrition: diyet tarzı, makro alışkanlıkları, kullandığı protein tozu/öğün düzeni.
    - app: uygulamayla ilgili kalıcı tercih/ayar istekleri.
    - episodic: önemli tek seferlik olay veya kararlar.

    YOK SAY (operasyon üretme):
    - Geçici sorular, tek seferlik yemek kaydı, koçun genel bilgi/tavsiye/bilim açıklamaları.
    - Selamlaşma, "tamam/evet/olur" gibi onaylar, küfür/dolgu kelimeler.

    OPERASYONLAR (mevcut hafızaya göre karar ver):
    - update: Mevcut kayıt (Mx) aynı konuda ama DEĞİŞMİŞ/DÜZELTİLMİŞ ya da daha fazla detay içeriyorsa.
      Örn. hedef kilo 80'den 85'e çıktıysa: {"op":"update","id":"M2","content":"Hedefi 85 kg'a çıkmak.","type":"goal","importance":0.9}
    - delete: Mevcut kayıt (Mx) artık AÇIKÇA geçersiz/yanlışsa ve yerine yenisi yoksa: {"op":"delete","id":"M3"}
    - add: Gerçekten yeni, mevcut kayıtlarda olmayan kalıcı bilgi: {"op":"add","content":"...","type":"preference","tags":["preference"],"importance":0.8}
      Yeni bilgi mevcut bir Mx ile çelişiyorsa add yerine o Mx'i UPDATE etmeyi tercih et.

    content KURALLARI:
    - Tek cümle, atomik, Türkçe, kendi başına anlamlı; küfür/dolgu temizlenmiş.
    - "kullanıcı şöyle dedi" gibi sarmalama yapma; doğrudan bilgiyi yaz (örn. "Hedefi 85 kg'a çıkmak.").
    - Sayıları/birimleri koru.

    type değerleri: profile, goal, preference, constraint, supplement, training, nutrition, app, episodic, other.
    importance: 0 ile 1 arası (stabil/önemli bilgi yüksek olsun).

    ÇIKTI: SADECE tek bir JSON objesi. Markdown, açıklama, kod bloğu YOK.
    Format: {"operations":[ ... ]}
    Tutulacak kalıcı bilgi yoksa: {"operations":[]}
    """

    private static func buildUserPrompt(userText: String, assistantText: String, candidates: [AgentMemory]) -> String {
        let user = String(userText.prefix(1500))
        let assistant = String(assistantText.prefix(1500))
        let memoryBlock: String
        if candidates.isEmpty {
            memoryBlock = "(yok)"
        } else {
            memoryBlock = candidates.enumerated()
                .map { idx, memory in "M\(idx + 1) | \(memory.type.rawValue) | \(memory.content)" }
                .joined(separator: "\n")
        }
        return """
        SON KONUŞMA:
        Kullanıcı: \(user)
        Koç: \(assistant)

        MEVCUT İLGİLİ HAFIZA (id | tip | içerik):
        \(memoryBlock)

        Bu konuşmadan çıkarılacak kalıcı hafıza operasyonlarını SADECE JSON olarak ver.
        """
    }

    private static let consolidationSystemPrompt = """
    Sen Hercules hafıza yöneticisinin KONSOLİDASYON modusun. Sana kullanıcının uzun
    vadeli hafıza kayıtları (M1..Mn) veriliyor. Görevin: gereksiz tekrarları, çelişkileri
    ve parçalanmış bilgileri temizleyerek hafızayı derli toplu tutmak.

    KURALLAR:
    - Aynı/çok benzer bilgiyi anlatan kayıtları TEK kanonik kayıtta birleştir: birini
      "update" ile en net/güncel haline getir, kalan kopyaları "delete" et.
    - Açıkça çelişen kayıtlardan güncel/doğru olanı koru, eskisini "delete" et.
    - Emin değilsen DOKUNMA. Bilgiyi kaybetme; sadece gerçekten gereksiz/yinelenen olanı sil.
    - Yeni bilgi UYDURMA; sadece mevcut içerikleri sadeleştir/birleştir.

    ÇIKTI: SADECE {"operations":[ ... ]} JSON. Markdown/açıklama YOK.
    op değerleri: "update" (id + content [+ type]) veya "delete" (id).
    Yapılacak bir şey yoksa: {"operations":[]}
    """

    private static func buildConsolidationPrompt(_ candidates: [AgentMemory]) -> String {
        let block = candidates.enumerated()
            .map { idx, memory in "M\(idx + 1) | \(memory.type.rawValue) | \(memory.content)" }
            .joined(separator: "\n")
        return """
        HAFIZA KAYITLARI (id | tip | içerik):
        \(block)

        Gereksiz tekrar ve çelişkileri temizleyecek operasyonları SADECE JSON olarak ver.
        """
    }

    // MARK: - Parsing

    /// nil = hiç çözümlenemedi (fallback gerek). Boş dizi = geçerli ama operasyon yok (NOOP).
    private static func parseOperations(_ raw: String, candidates: [AgentMemory]) -> [LLMMemoryOperation]? {
        let cleaned = stripCodeFences(raw)
        let root = (cleaned.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
            ?? salvageJSONObject(from: cleaned)
        guard let root else { return nil }
        guard let opsAny = root["operations"] as? [[String: Any]] else { return [] }
        return mapOperations(opsAny, candidates: candidates)
    }

    private static func mapOperations(_ opsAny: [[String: Any]], candidates: [AgentMemory]) -> [LLMMemoryOperation] {
        var idMap: [String: UUID] = [:]
        for (idx, memory) in candidates.enumerated() {
            idMap["M\(idx + 1)"] = memory.id
        }
        func resolve(_ any: Any?) -> UUID? {
            guard let raw = (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { return nil }
            return idMap[raw.uppercased()]
        }

        var result: [LLMMemoryOperation] = []
        for dict in opsAny {
            let opStr = ((dict["op"] as? String) ?? (dict["operation"] as? String) ?? "").lowercased()
            let content = (dict["content"] as? String) ?? (dict["text"] as? String)
            let type = (dict["type"] as? String).flatMap { MemoryType(rawValue: $0.lowercased()) }
            let tags = parseTags(dict["tags"])
            let importance = number(dict["importance"]) ?? number(dict["confidence"])

            switch opStr {
            case "add", "create":
                guard let content, content.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { continue }
                result.append(LLMMemoryOperation(
                    kind: .add, targetID: nil, content: content, type: type,
                    tags: tags, importance: importance,
                    supersedes: resolve(dict["supersedes"] ?? dict["supersedes_id"])
                ))
            case "update", "edit":
                guard let id = resolve(dict["id"]),
                      let content, content.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
                else { continue }
                result.append(LLMMemoryOperation(
                    kind: .update, targetID: id, content: content, type: type,
                    tags: tags, importance: importance, supersedes: nil
                ))
            case "delete", "remove":
                guard let id = resolve(dict["id"]) else { continue }
                result.append(LLMMemoryOperation(
                    kind: .delete, targetID: id, content: nil, type: nil,
                    tags: [], importance: nil, supersedes: nil
                ))
            default:
                continue // noop / bilinmeyen
            }
        }
        return result
    }

    private static func parseTags(_ any: Any?) -> [String] {
        if let arr = any as? [String] { return arr }
        if let s = any as? String {
            return s.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }).map(String.init)
        }
        return []
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    private static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) }
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Model JSON'u düz metne gömdüyse ilk { ... } bloğunu kurtarmayı dene.
    private static func salvageJSONObject(from text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else { return nil }
        let slice = String(text[start...end])
        return slice.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private static func isTrivial(_ text: String) -> Bool {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        if folded.count < 6 { return true }
        let approvals: Set<String> = [
            "tamam", "tmm", "evet", "okay", "olur", "yap", "uygula", "ekle", "kaydet",
            "onayliyorum", "onay", "aynen", "tamamdir", "devam", "hadi", "hayir", "yok", "peki"
        ]
        return approvals.contains(folded)
    }
}

/// On-device embedding sağlayıcısı (Qwen3-Embedding-0.6B, swift-embeddings / MLTensor).
/// Model ilk `warmUp()` çağrısında HuggingFace'ten inip cache'lenir (F32, ~2.4GB).
/// "IfAvailable" metotları model henüz yüklü değilse indirmeyi TETİKLEMEZ; nil döner →
/// retrieval lexical'e graceful fallback yapar (sohbet sırasında sürpriz indirme olmaz).
/// Actor: model yükleme + encode serialize edilir.
