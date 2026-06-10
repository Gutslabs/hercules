import Foundation

@MainActor
final class LocalMemoryProvider {
    static let shared = LocalMemoryProvider()

    private struct MemoryPayload: Codable, Sendable {
        var version: Int
        var savedAt: Date
        var memories: [AgentMemory]
    }

    private struct DiskFingerprint: Equatable {
        var exists: Bool
        var modificationDate: Date?
        var fileSize: Int?
    }

    private enum PersistMode {
        case immediate
        case deferredTouch
    }

    /// Disk yazımlarını serialize eder ve encode'u main thread'den çıkarır.
    /// sequence sırasına göre yazar; eski (stale) yazımları atlar.
    private actor MemoryFileWriter {
        private var latest = 0
        private let encoder: JSONEncoder = {
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            return e
        }()

        /// Bu sequence'e kadar olan uçuştaki yazımları geçersiz kıl (restore sonrası stale write'ı diske vurmadan engeller).
        func invalidate(upTo sequence: Int) { latest = max(latest, sequence) }

        @discardableResult
        func write(payload: MemoryPayload?, to url: URL, sequence: Int) -> Bool {
            guard sequence >= latest else { return false }
            latest = sequence
            guard let payload else {
                try? FileManager.default.removeItem(at: url)
                return true
            }
            guard let data = try? encoder.encode(payload) else { return false }
            try? data.write(to: url, options: [.atomic])
            return true
        }
    }

    private let memoryURL: URL
    private var memories: [AgentMemory] = []
    private var memoryTermsByID: [UUID: Set<String>] = [:]
    private var memoryTagTermsByID: [UUID: Set<String>] = [:]
    private var loadedFingerprint: DiskFingerprint?
    private var writeSequence = 0
    private var deferredWriteInFlight = false
    private let fileWriter = MemoryFileWriter()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        memoryURL = Self.makeMemoryURL()
        reloadFromDisk()
    }

    func reloadFromDisk() {
        cancelDeferredWrite()
        load()
        if pruneExpiredMemories() {
            persist()
        }
    }

    func search(query: String, topK: Int) -> [AgentMemory] {
        refreshFromDiskIfChanged()
        if pruneExpiredMemories() {
            persist()
        }
        let queryTerms = Set(Self.tokens(query))
        guard !queryTerms.isEmpty else { return [] }

        let now = Date()
        let scored = memories
            .filter { $0.isActive && !Self.isExpired($0, now: now) }
            .map { memory -> (memory: AgentMemory, score: Double) in
                let memoryTerms = memoryTermsByID[memory.id] ?? Set(Self.tokens(memory.content + " " + memory.tags.joined(separator: " ")))
                let tagTerms = memoryTagTermsByID[memory.id] ?? Set(memory.tags.flatMap(Self.tokens))
                let overlap = queryTerms.intersection(memoryTerms)
                let tagOverlap = queryTerms.intersection(tagTerms)
                let recencyDays = max(0, now.timeIntervalSince(memory.lastSeenAt) / 86_400)
                let recency = 1.0 / (1.0 + min(recencyDays, 60))
                let score = Double(overlap.count) * 2.0
                    + Double(tagOverlap.count) * 3.0
                    + memory.confidence
                    + recency
                    + (memory.pinned ? 2.0 : 0.0)
                return (memory, score)
            }
            .filter { $0.score >= 2.0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.memory.updatedAt > rhs.memory.updatedAt
                }
                return lhs.score > rhs.score
            }

        let selected = Array(scored.prefix(topK)).map(\.memory)
        touch(selected)
        return selected
    }

    func allMemories(includeInvalidated: Bool = false) -> [AgentMemory] {
        refreshFromDiskIfChanged()
        if pruneExpiredMemories() {
            persist()
        }
        return memories
            .filter { includeInvalidated || $0.isActive }
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned {
                    return lhs.pinned && !rhs.pinned
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    /// Coach context'ine enjekte edilecek memory seti. Çekirdek (profil/hedef/kısıt)
    /// + pinli kayıtlar HER ZAMAN dahil; gerisi blended skorla (lexical + importance +
    /// recency) seçilir ve limit'e göre kırpılır — çekirdek/pinli asla düşmez. Asıl
    /// "semantic" seçimi güçlü ana model yapar; biz ona temiz, tiplenmiş, sınırlı set veririz.
    func contextMemories(query: String, queryEmbedding: [Float]? = nil, limit: Int = 24) -> [AgentMemory] {
        refreshFromDiskIfChanged()
        if pruneExpiredMemories() { persist() }
        let now = Date()
        let active = memories.filter { $0.isActive && !Self.isExpired($0, now: now) }
        guard !active.isEmpty else { return [] }

        let queryTerms = Set(Self.tokens(query))
        func relevance(_ memory: AgentMemory) -> Double {
            let terms = memoryTermsByID[memory.id] ?? Set(Self.tokens(memory.content + " " + memory.tags.joined(separator: " ")))
            let overlap = Double(queryTerms.intersection(terms).count)
            let recencyDays = max(0, now.timeIntervalSince(memory.lastSeenAt) / 86_400)
            let recency = 1.0 / (1.0 + min(recencyDays, 90))
            // Semantic (cosine) varsa baskın sinyal; yoksa saf lexical davranışı korunur.
            var semantic = 0.0
            if let queryEmbedding, let emb = memory.embedding, !emb.isEmpty {
                semantic = Double(max(0, EmbeddingMath.cosine(queryEmbedding, emb)))
            }
            return semantic * 6.0 + overlap * 2.0 + memory.confidence + recency
        }

        let alwaysIn = active.filter { $0.type.isCore || $0.pinned }
        // Skoru karşılaştırma başına değil, kayıt başına BİR kez hesapla (1024-dim cosine pahalı).
        let rest = active.filter { !($0.type.isCore || $0.pinned) }
            .map { (memory: $0, score: relevance($0)) }
            .sorted { $0.score > $1.score }
            .map(\.memory)
        let remaining = max(0, limit - alwaysIn.count)
        let selected = alwaysIn + Array(rest.prefix(remaining))

        touch(selected)

        return selected.sorted { lhs, rhs in
            if lhs.type.isCore != rhs.type.isCore { return lhs.type.isCore && !rhs.type.isCore }
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// LLM memory-manager'a verilecek "ilgili mevcut kayıtlar" kümesi. Çekirdek
    /// (profil/hedef/kısıt) + pinli kayıtlar her zaman dahil; gerisi konuşmaya
    /// lexical alaka skoruyla seçilir. Yan etkisiz — lastSeenAt'e dokunmaz, persist etmez.
    func candidatesForUpdate(userText: String, assistantText: String, limit: Int = 12) -> [AgentMemory] {
        refreshFromDiskIfChanged()
        let now = Date()
        let active = memories.filter { $0.isActive && !Self.isExpired($0, now: now) }
        guard !active.isEmpty else { return [] }

        let queryTerms = Set(Self.tokens(userText + " " + assistantText))
        let scored = active.map { memory -> (memory: AgentMemory, score: Double) in
            let memoryTerms = memoryTermsByID[memory.id] ?? Set(Self.tokens(memory.content + " " + memory.tags.joined(separator: " ")))
            var score = Double(queryTerms.intersection(memoryTerms).count)
            if memory.type.isCore { score += 1.5 }
            if memory.pinned { score += 1.0 }
            return (memory, score)
        }

        return scored
            .filter { $0.score > 0 || $0.memory.type.isCore || $0.memory.pinned }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.memory.updatedAt > rhs.memory.updatedAt }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.memory)
    }

    /// Lokal decay (ağ yok): uzun süre görülmemiş, pinli/çekirdek olmayan otomatik
    /// kayıtların confidence'ını kademeli düşürür; çok düşük + çok eski olanları
    /// soft-invalidate eder. Manuel/explicit/pinli ve profil/hedef/kısıt kayıtlarına dokunmaz.
    @discardableResult
    func applyDecay(now: Date = Date()) -> Bool {
        var changed = false
        for idx in memories.indices {
            let memory = memories[idx]
            guard memory.isActive, !memory.pinned, !memory.type.isCore,
                  Self.isAutoSource(memory.source)
            else { continue }
            let unseenDays = now.timeIntervalSince(memory.lastSeenAt) / 86_400
            guard unseenDays > 30 else { continue }
            let decayed = max(0.3, memory.confidence - 0.1)
            if decayed != memory.confidence {
                memories[idx].confidence = decayed
                changed = true
            }
            if memories[idx].confidence <= 0.35, unseenDays > 90 {
                memories[idx].invalidatedAt = now
                changed = true
            }
        }
        if changed {
            rebuildSearchIndex()
            persist()
        }
        return changed
    }

    /// Mem0 tarzı operasyon listesini uygula. UPDATE içerikte yerinde düzeltme;
    /// DELETE soft-invalidate (Zep tarzı, diskte kalır); ADD yeni kayıt (gerekirse
    /// eski kaydı supersede eder). Pinli/manuel kayıtlar LLM tarafından değiştirilemez/silinemez.
    @discardableResult
    func applyLLMOperations(_ ops: [LLMMemoryOperation]) -> Int {
        guard !ops.isEmpty else { return 0 }
        refreshFromDiskIfChanged()
        var changed = 0
        for op in ops {
            switch op.kind {
            case .add:
                guard let content = Self.cleanedContent(op.content) else { continue }
                let memory = upsertMemory(
                    content: content,
                    tags: op.tags,
                    source: "llm-add",
                    confidence: Self.confidence(from: op.importance, default: 0.8),
                    type: op.type ?? .other
                )
                if let supersedes = op.supersedes,
                   let oldIdx = memories.firstIndex(where: { $0.id == supersedes }),
                   memories[oldIdx].id != memory.id,
                   !memories[oldIdx].pinned {
                    memories[oldIdx].invalidatedAt = .now
                    memories[oldIdx].supersededBy = memory.id
                }
                changed += 1
            case .update:
                guard let id = op.targetID,
                      let idx = memories.firstIndex(where: { $0.id == id }),
                      !memories[idx].pinned,                 // pinli/manuel kaydı koru
                      let content = Self.cleanedContent(op.content)
                else { continue }
                memories[idx].content = content
                if !op.tags.isEmpty {
                    memories[idx].tags = Array(Set(memories[idx].tags + Self.normalizedTags(op.tags))).sorted()
                }
                if let type = op.type, type != .other { memories[idx].type = type }
                if let importance = op.importance {
                    memories[idx].confidence = max(memories[idx].confidence, Self.confidence(from: importance, default: memories[idx].confidence))
                }
                memories[idx].source = "llm-update"
                memories[idx].updatedAt = .now
                memories[idx].lastSeenAt = .now
                memories[idx].invalidatedAt = nil
                memories[idx].supersededBy = nil
                memories[idx].embedding = nil          // içerik değişti → embedding bayat, yeniden hesaplanacak
                memories[idx].embeddingModel = nil
                changed += 1
            case .delete:
                guard let id = op.targetID,
                      let idx = memories.firstIndex(where: { $0.id == id }),
                      !memories[idx].pinned,                 // pinli/manuel kaydı LLM silemez
                      memories[idx].isActive
                else { continue }
                memories[idx].invalidatedAt = .now
                memories[idx].updatedAt = .now
                changed += 1
            }
        }
        if changed > 0 {
            rebuildSearchIndex()
            persist()
        }
        return changed
    }

    /// Embedding'i eksik veya güncel-model ile üretilmemiş aktif kayıtlar (backfill kaynağı).
    func memoriesNeedingEmbedding(model: String, limit: Int = 64) -> [(id: UUID, content: String)] {
        refreshFromDiskIfChanged()
        return memories
            .filter { $0.isActive && ($0.embedding == nil || $0.embeddingModel != model) }
            .prefix(limit)
            .map { ($0.id, $0.content) }
    }

    /// Embedding'i eksik/bayat aktif kayıt sayısı (backfill ilerlemesi için).
    func pendingEmbeddingCount(model: String) -> Int {
        refreshFromDiskIfChanged()
        return memories.filter { $0.isActive && ($0.embedding == nil || $0.embeddingModel != model) }.count
    }

    /// Hesaplanmış embedding'leri uygula (tek persist; arama indeksini etkilemez).
    func applyEmbeddings(_ embeddings: [UUID: [Float]], model: String) {
        guard !embeddings.isEmpty else { return }
        var changed = false
        for idx in memories.indices {
            if let vector = embeddings[memories[idx].id] {
                memories[idx].embedding = vector
                memories[idx].embeddingModel = model
                changed = true
            }
        }
        if changed { persist() }
    }

    func deleteMemory(id: UUID) {
        refreshFromDiskIfChanged()
        memories.removeAll { $0.id == id }
        rebuildSearchIndex()
        persist()
    }

    func setPinned(id: UUID, pinned: Bool) {
        refreshFromDiskIfChanged()
        guard let idx = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[idx].pinned = pinned
        memories[idx].updatedAt = .now
        memories[idx].lastSeenAt = .now
        persist()
    }

    func updateMemory(id: UUID, content: String, tags: [String]) {
        refreshFromDiskIfChanged()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = memories.firstIndex(where: { $0.id == id })
        else { return }
        let contentChanged = memories[idx].content != trimmed
        memories[idx].content = trimmed
        memories[idx].tags = Self.normalizedTags(tags)
        memories[idx].source = "manual-edit"
        memories[idx].confidence = max(memories[idx].confidence, 0.9)
        memories[idx].updatedAt = .now
        memories[idx].lastSeenAt = .now
        if contentChanged {
            memories[idx].embedding = nil          // içerik değişti → embedding bayat, yeniden hesaplanacak
            memories[idx].embeddingModel = nil
        }
        rebuildSearchIndex()
        persist()
    }

    @discardableResult
    func addManualMemory(content: String, tags: [String], pinned: Bool = true) -> AgentMemory? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return remember(
            content: trimmed,
            tags: Self.normalizedTags(tags),
            source: "manual",
            confidence: 0.98,
            pinned: pinned
        )
    }

    /// Heuristik fallback — yalnızca LLM memory-manager (MemoryManager) ulaşılamazsa
    /// devreye girer ve SADECE kullanıcının açıkça "bunu hatırla / unutma" dediği bilgiyi
    /// yakalar. Eski templated çıkarım (kalitesiz raw-text dökümü) kaldırıldı: LLM yoksa
    /// gürültü yazmaktansa hiç yazmamayı tercih eder.
    @discardableResult
    func absorbConversation(userText: String, assistantText: String) -> Int {
        refreshFromDiskIfChanged()
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let explicit = explicitMemoryCandidate(from: trimmed) else { return 0 }
        _ = upsertMemory(
            content: explicit.content,
            tags: explicit.tags,
            source: "explicit",
            confidence: 0.96,
            pinned: true
        )
        rebuildSearchIndex()
        persist()
        return 1
    }

    @discardableResult
    func remember(
        content: String,
        tags: [String],
        source: String,
        confidence: Double,
        type: MemoryType = .other,
        expiresAt: Date? = nil,
        pinned: Bool = false
    ) -> AgentMemory {
        refreshFromDiskIfChanged()
        let memory = upsertMemory(
            content: content,
            tags: tags,
            source: source,
            confidence: confidence,
            type: type,
            expiresAt: expiresAt,
            pinned: pinned
        )
        rebuildSearchIndex()
        persist()
        return memory
    }

    private func upsertMemory(
        content: String,
        tags: [String],
        source: String,
        confidence: Double,
        type: MemoryType = .other,
        expiresAt: Date? = nil,
        pinned: Bool = false
    ) -> AgentMemory {
        let normalizedContent = Self.normalizeMemory(content)
        let normalizedTags = Self.normalizedTags(tags)

        if let idx = memories.firstIndex(where: { Self.normalizeMemory($0.content) == normalizedContent }) {
            memories[idx].tags = Array(Set(memories[idx].tags + normalizedTags)).sorted()
            memories[idx].source = source
            memories[idx].confidence = max(memories[idx].confidence, confidence)
            if memories[idx].type == .other, type != .other {
                memories[idx].type = type
            }
            memories[idx].updatedAt = .now
            memories[idx].lastSeenAt = .now
            memories[idx].pinned = memories[idx].pinned || pinned
            // Aynı içerik tekrar doğrulandı — daha önce invalidate edildiyse geri getir.
            memories[idx].invalidatedAt = nil
            memories[idx].supersededBy = nil
            if pinned || expiresAt == nil {
                memories[idx].expiresAt = nil
            } else if memories[idx].expiresAt == nil {
                memories[idx].expiresAt = expiresAt
            }
            return memories[idx]
        }

        let memory = AgentMemory(
            content: content,
            tags: normalizedTags,
            source: source,
            confidence: confidence,
            type: type,
            expiresAt: expiresAt,
            pinned: pinned
        )
        memories.append(memory)
        return memory
    }

    private func explicitMemoryCandidate(from text: String) -> (content: String, tags: [String])? {
        let lower = Self.fold(text)
        let triggers = [
            "bunu hatirla", "beni hatirla", "unutma", "aklinda tut", "memoryye ekle",
            "memory'e ekle", "hafizaya ekle", "hafizana ekle", "remember this"
        ]
        guard triggers.contains(where: { lower.contains($0) }) else { return nil }

        let cleaned = text
            .replacingOccurrences(of: "bunu hatırla", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "beni hatırla", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "unutma", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "aklında tut", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "memoryye ekle", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "memory'e ekle", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "hafızaya ekle", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "hafızana ekle", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "remember this", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-\n\t"))

        let content = cleaned.isEmpty ? text : cleaned
        return ("Kullanıcı açıkça şunu hatırlatmak istedi: \(content)", Self.tags(for: content))
    }

    private func touch(_ selected: [AgentMemory]) {
        guard !selected.isEmpty else { return }
        let ids = Set(selected.map(\.id))
        let now = Date()
        for idx in memories.indices where ids.contains(memories[idx].id) {
            memories[idx].lastSeenAt = now
        }
        persist(.deferredTouch)
    }

    private static func makeMemoryURL() -> URL {
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
        return dir.appendingPathComponent("agent-memory.json")
    }

    private func refreshFromDiskIfChanged() {
        guard !deferredWriteInFlight else { return }
        let fingerprint = Self.diskFingerprint(for: memoryURL)
        guard fingerprint != loadedFingerprint else { return }
        load()
        if pruneExpiredMemories() {
            persist()
        }
    }

    private func load() {
        let fingerprint = Self.diskFingerprint(for: memoryURL)
        guard let data = try? Data(contentsOf: memoryURL) else {
            memories = []
            loadedFingerprint = fingerprint
            rebuildSearchIndex()
            return
        }

        do {
            let payload = try Self.decoder.decode(MemoryPayload.self, from: data)
            memories = Self.deduplicated(payload.memories)
            loadedFingerprint = fingerprint
        } catch {
            Self.backupUnreadableFile(at: memoryURL)
            memories = []
            loadedFingerprint = fingerprint
        }
        rebuildSearchIndex()
    }

    @discardableResult
    private func pruneExpiredMemories() -> Bool {
        let now = Date()
        let before = memories.count
        memories.removeAll { Self.isExpired($0, now: now) }
        let changed = before != memories.count
        if changed {
            rebuildSearchIndex()
        }
        return changed
    }

    /// Diske yazımı arka plana (writer actor) devreder — encode + I/O main thread'i bloklamaz.
    /// `mode` artık ayrım yaratmıyor; her iki durumda da debounced async yazım yapılır.
    private func persist(_ mode: PersistMode = .immediate) {
        let payload = memories.isEmpty ? nil : MemoryPayload(version: 1, savedAt: .now, memories: memories)
        writeSequence += 1
        let sequence = writeSequence
        let url = memoryURL
        let writer = fileWriter
        deferredWriteInFlight = true
        // Task @MainActor context'ini miras alır: actor write off-main, devamı tekrar main'de.
        Task { [weak self] in
            let wrote = await writer.write(payload: payload, to: url, sequence: sequence)
            guard let self, self.writeSequence == sequence else { return }
            if wrote { self.loadedFingerprint = Self.diskFingerprint(for: self.memoryURL) }
            self.deferredWriteInFlight = false
        }
        postLocalMemoryChanged()
    }

    private func postLocalMemoryChanged() {
        NotificationCenter.default.post(name: .localMemoryChanged, object: nil)
    }

    private func cancelDeferredWrite() {
        writeSequence += 1          // uçuştaki yazımların fingerprint güncellemesini geçersiz kıl
        deferredWriteInFlight = false
        // Writer actor'ı da yetkilendir: barrier'a kadar olan (stale) yazımlar diske vurmadan reddedilsin.
        // Sıradaki gerçek persist > barrier sequence kullanacağı için meşru yazımlar etkilenmez.
        let barrier = writeSequence
        let writer = fileWriter
        Task { await writer.invalidate(upTo: barrier) }
    }

    private func rebuildSearchIndex() {
        memoryTermsByID = Dictionary(uniqueKeysWithValues: memories.map { memory in
            (memory.id, Set(Self.tokens(memory.content + " " + memory.tags.joined(separator: " "))))
        })
        memoryTagTermsByID = Dictionary(uniqueKeysWithValues: memories.map { memory in
            (memory.id, Set(memory.tags.flatMap(Self.tokens)))
        })
    }

    private static func diskFingerprint(for url: URL) -> DiskFingerprint {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DiskFingerprint(exists: false, modificationDate: nil, fileSize: nil)
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return DiskFingerprint(
            exists: true,
            modificationDate: values?.contentModificationDate,
            fileSize: values?.fileSize
        )
    }

    private static func isExpired(_ memory: AgentMemory, now: Date) -> Bool {
        guard !memory.pinned, let expiresAt = memory.expiresAt else { return false }
        return expiresAt < now
    }

    private static func tags(for text: String) -> [String] {
        let lower = fold(text)
        var tags: Set<String> = []
        if containsAny(lower, needles: [
            "protein", "kalori", "makro", "yemek", "ogun", "öğün", "pismis",
            "pişmiş", "cig", "çiğ", "whey", "protein tozu", "pirinc", "pirinç",
            "tavuk", "yumurta", "karbonhidrat"
        ]) {
            tags.insert("nutrition")
        }
        if containsAny(lower, needles: [
            "antrenman", "idman", "workout", "gym", "hipertrofi", "hypertrophy",
            "bodybuilding", "program", "hareket", "rir", "set", "bench", "squat",
            "deadlift", "upper", "lower", "calf", "hamstring", "quad"
        ]) {
            tags.insert("training")
        }
        if containsAny(lower, needles: ["whey", "protein tozu", "kreatin", "creatine", "bcaa", "ssn", "gentopure", "protein ocean"]) {
            tags.insert("supplement")
        }
        if containsAny(lower, needles: ["chat", "memory", "hafiza", "hafıza", "sidebar", "layout", "preset", "takvim", "profil", "icloud", "shortcut"]) {
            tags.insert("app")
        }
        if containsAny(lower, needles: ["sidebar", "layout", "responsive", "tasarim", "tasarım", "renk", "popup", "pop-up", "buton", "arrow", "resize", "scroll"]) {
            tags.insert("ui")
        }
        if containsAny(lower, needles: ["bulk", "cut", "definasyon", "kilo", "yag", "yağ", "hedef"]) {
            tags.insert("goal")
        }
        if containsAny(lower, needles: ["seviyorum", "sevmiyorum", "tercih", "istemiyorum", "istemiyoruz", "olmasin", "olmasın"]) {
            tags.insert("preference")
        }
        if containsAny(lower, needles: ["ucuz", "butce", "bütçe", "ulasılabilir", "ulaşılabilir"]) {
            tags.insert("budget")
        }
        return Array(tags).sorted()
    }

    private static func tokens(_ text: String) -> [String] {
        fold(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    private static func normalizeMemory(_ text: String) -> String {
        tokens(text).joined(separator: " ")
    }

    private static func cleanedContent(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 ? trimmed : nil
    }

    /// Otomatik (LLM/chat/assistant) kaynaklı — decay'e tabi olanlar. Manuel/explicit hariç.
    private static func isAutoSource(_ source: String) -> Bool {
        source.hasPrefix("llm") || source.hasPrefix("chat") || source.hasPrefix("assistant")
    }

    /// LLM "importance" (0...1) → confidence. Aralığı makul tut: ne 0'a düşsün ne 1'i geçsin.
    private static func confidence(from importance: Double?, default fallback: Double) -> Double {
        guard let importance else { return fallback }
        return min(1.0, max(0.4, importance))
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.flatMap { tag in
            tag
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        })).sorted()
    }

    private static func containsAny(_ text: String, needles: [String]) -> Bool {
        let haystack = fold(text)
        return needles.map { fold($0) }.contains { haystack.contains($0) }
    }

    private static func deduplicated(_ loaded: [AgentMemory]) -> [AgentMemory] {
        var output: [AgentMemory] = []
        var indexByKey: [String: Int] = [:]   // normalize anahtarı → output indeksi (O(n) dedupe)
        for memory in loaded {
            let key = normalizeMemory(memory.content)
            guard !key.isEmpty else {
                output.append(memory)
                continue
            }
            if let idx = indexByKey[key] {
                output[idx].tags = Array(Set(output[idx].tags + memory.tags)).sorted()
                output[idx].confidence = max(output[idx].confidence, memory.confidence)
                output[idx].pinned = output[idx].pinned || memory.pinned
                if output[idx].type == .other, memory.type != .other {
                    output[idx].type = memory.type
                }
                output[idx].createdAt = min(output[idx].createdAt, memory.createdAt)
                output[idx].updatedAt = max(output[idx].updatedAt, memory.updatedAt)
                output[idx].lastSeenAt = max(output[idx].lastSeenAt, memory.lastSeenAt)
                // İkisinden biri aktifse aktif kabul et — aktif kayıt eskiyi supersede eder.
                if output[idx].invalidatedAt == nil || memory.invalidatedAt == nil {
                    output[idx].invalidatedAt = nil
                    output[idx].supersededBy = nil
                } else {
                    output[idx].invalidatedAt = max(output[idx].invalidatedAt!, memory.invalidatedAt!)
                }
                if output[idx].expiresAt == nil || memory.expiresAt == nil {
                    output[idx].expiresAt = nil
                } else {
                    output[idx].expiresAt = max(output[idx].expiresAt!, memory.expiresAt!)
                }
            } else {
                indexByKey[key] = output.count
                output.append(memory)
            }
        }
        return output
    }

    private static func backupUnreadableFile(at url: URL) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-unreadable-\(formatter.string(from: Date())).json")
        try? FileManager.default.copyItem(at: url, to: backupURL)
    }
}

extension Notification.Name {
    static let localMemoryChanged = Notification.Name("hercules.local-memory.changed")
    static let embeddingStatusChanged = Notification.Name("hercules.embedding-status.changed")
}

/// Embedding modelinin yükleme/backfill durumu — Memory ekranı bunu gösterir.
