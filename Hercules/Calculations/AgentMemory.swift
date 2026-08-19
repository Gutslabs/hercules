import Foundation

/// Hafıza kaydının türü. Profil/hedef/kısıt gibi stabil "çekirdek" bilgiler her
/// zaman bağlama enjekte edilmeye değer; gerisi alaka skoruna göre çekilir.
enum MemoryType: String, Codable, CaseIterable, Sendable {
    case profile, goal, preference, constraint, supplement, training, nutrition, app, episodic, other

    var label: String {
        switch self {
        case .profile: return "profil"
        case .goal: return "hedef"
        case .preference: return "tercih"
        case .constraint: return "kısıt"
        case .supplement: return "takviye"
        case .training: return "antrenman"
        case .nutrition: return "beslenme"
        case .app: return "uygulama"
        case .episodic: return "olay"
        case .other: return "genel"
        }
    }

    /// Stabil, neredeyse her zaman geçerli olan çekirdek bilgi tipleri.
    var isCore: Bool {
        switch self {
        case .profile, .goal, .constraint: return true
        default: return false
        }
    }
}

struct AgentMemory: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var content: String
    var tags: [String]
    var source: String
    /// Kaydın doğru olma olasılığı (epistemik güven). Retrieval önceliği değildir.
    var confidence: Double
    /// Kullanıcı için ne kadar kalıcı/önemli olduğu. Confidence'tan ayrı tutulur.
    var importance: Double
    var type: MemoryType
    var createdAt: Date
    var updatedAt: Date
    /// Bilginin son kez kullanıcı/kanıt tarafından desteklendiği zaman.
    var lastSeenAt: Date
    /// Retrieval'ın bu kaydı son kez bağlama aldığı zaman. Truth/recency skorunu değiştirmez.
    var lastAccessedAt: Date?
    /// Decay'in en son hangi zaman dilimine kadar uygulandığı; decay'i idempotent yapar.
    var lastDecayedAt: Date?
    var expiresAt: Date?
    var pinned: Bool
    /// Soft-delete / supersede (Zep tarzı): doluysa kayıt AI'a sunulmaz ama diskte
    /// kalır — geçmiş kaybolmaz, gerekirse geri alınabilir.
    var invalidatedAt: Date?
    /// Bu kaydı geçersiz kılan yeni kaydın id'si (biliniyorsa).
    var supersededBy: UUID?
    /// Semantic retrieval için on-device embedding (Multilingual E5). JSON'a base64 yazılır.
    var embedding: [Float]?
    /// embedding'i üreten model id'si — model değişince yeniden hesaplanır.
    var embeddingModel: String?

    var isActive: Bool { invalidatedAt == nil }

    init(
        id: UUID = UUID(),
        content: String,
        tags: [String],
        source: String,
        confidence: Double,
        importance: Double? = nil,
        type: MemoryType = .other,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastSeenAt: Date = .now,
        lastAccessedAt: Date? = nil,
        lastDecayedAt: Date? = nil,
        expiresAt: Date? = nil,
        pinned: Bool = false,
        invalidatedAt: Date? = nil,
        supersededBy: UUID? = nil,
        embedding: [Float]? = nil,
        embeddingModel: String? = nil
    ) {
        self.id = id
        self.content = content
        self.tags = tags
        self.source = source
        self.confidence = confidence
        self.importance = importance ?? Self.defaultImportance(for: type)
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
        self.lastAccessedAt = lastAccessedAt
        self.lastDecayedAt = lastDecayedAt
        self.expiresAt = expiresAt
        self.pinned = pinned
        self.invalidatedAt = invalidatedAt
        self.supersededBy = supersededBy
        self.embedding = embedding
        self.embeddingModel = embeddingModel
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, tags, source, confidence, importance, type
        case createdAt, updatedAt, lastSeenAt, lastAccessedAt, lastDecayedAt, expiresAt, pinned
        case invalidatedAt, supersededBy
        case embedding, embeddingModel
    }

    // Eski agent-memory.json (type/invalidatedAt/supersededBy alanları olmayan)
    // dosyaları okunur; ama mevcut bir alan yanlış tipteyse corruption sessizce
    // yeni UUID/.now gibi geçerli görünen değerlere dönüştürülmez.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        let decodedConfidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.7
        confidence = decodedConfidence.isFinite ? min(1, max(0, decodedConfidence)) : 0.7
        type = try c.decodeIfPresent(MemoryType.self, forKey: .type) ?? .other
        let decodedImportance = try c.decodeIfPresent(Double.self, forKey: .importance)
            ?? Self.defaultImportance(for: type)
        importance = decodedImportance.isFinite
            ? min(1, max(0, decodedImportance))
            : Self.defaultImportance(for: type)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt) ?? updatedAt
        lastAccessedAt = try c.decodeIfPresent(Date.self, forKey: .lastAccessedAt)
        lastDecayedAt = try c.decodeIfPresent(Date.self, forKey: .lastDecayedAt)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        invalidatedAt = try c.decodeIfPresent(Date.self, forKey: .invalidatedAt)
        supersededBy = try c.decodeIfPresent(UUID.self, forKey: .supersededBy)
        if let base64 = try c.decodeIfPresent(String.self, forKey: .embedding) {
            embedding = AgentMemory.decodeEmbedding(base64)
        } else {
            embedding = nil
        }
        embeddingModel = try c.decodeIfPresent(String.self, forKey: .embeddingModel)
        if let embedding, embedding.count != EmbeddingService.dimension {
            self.embedding = nil
        }
        if embedding == nil { embeddingModel = nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(tags, forKey: .tags)
        try c.encode(source, forKey: .source)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(importance, forKey: .importance)
        try c.encode(type, forKey: .type)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(lastSeenAt, forKey: .lastSeenAt)
        try c.encodeIfPresent(lastAccessedAt, forKey: .lastAccessedAt)
        try c.encodeIfPresent(lastDecayedAt, forKey: .lastDecayedAt)
        try c.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try c.encode(pinned, forKey: .pinned)
        try c.encodeIfPresent(invalidatedAt, forKey: .invalidatedAt)
        try c.encodeIfPresent(supersededBy, forKey: .supersededBy)
        if let embedding, !embedding.isEmpty {
            try c.encode(AgentMemory.encodeEmbedding(embedding), forKey: .embedding)
        }
        try c.encodeIfPresent(embeddingModel, forKey: .embeddingModel)
    }

    /// [Float] embedding'i kompakt base64 string'e çevir (prettyPrinted JSON'u 1024
    /// satırlık dizilerle şişirmemek için).
    static func encodeEmbedding(_ vector: [Float]) -> String {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
    }

    static func decodeEmbedding(_ base64: String) -> [Float]? {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return nil }
        guard data.count.isMultiple(of: MemoryLayout<Float>.stride) else { return nil }
        let count = data.count / MemoryLayout<Float>.stride
        guard count > 0, count <= 16_384 else { return nil }
        let vector: [Float] = data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
        return vector.allSatisfy(\.isFinite) ? vector : nil
    }

    static func defaultImportance(for type: MemoryType) -> Double {
        switch type {
        case .constraint: return 0.95
        case .profile, .goal: return 0.9
        case .preference, .supplement: return 0.8
        case .training, .nutrition: return 0.72
        case .app: return 0.65
        case .episodic: return 0.58
        case .other: return 0.5
        }
    }
}

/// Mem0 tarzı memory operasyonu — LLM memory-manager üretir, LocalMemoryProvider uygular.
struct LLMMemoryOperation: Sendable {
    enum Kind: Sendable { case add, update, delete }
    var kind: Kind
    var targetID: UUID?        // update / delete hedefi
    /// Operasyon üretilirken modelin gördüğü revision. UI'da arada edit olduysa
    /// provider stale UPDATE/DELETE'i reddeder.
    var expectedUpdatedAt: Date?
    var content: String?       // add / update içeriği (atomik cümle)
    var type: MemoryType?
    var tags: [String]
    var importance: Double?    // 0...1 → retrieval/kalıcılık önemi
    var confidence: Double?    // 0...1 → bilgi doğruluğu
    var supersedes: UUID?      // add bir eski kaydı supersede ediyorsa

    init(
        kind: Kind,
        targetID: UUID? = nil,
        expectedUpdatedAt: Date? = nil,
        content: String? = nil,
        type: MemoryType? = nil,
        tags: [String] = [],
        importance: Double? = nil,
        confidence: Double? = nil,
        supersedes: UUID? = nil
    ) {
        self.kind = kind
        self.targetID = targetID
        self.expectedUpdatedAt = expectedUpdatedAt
        self.content = content
        self.type = type
        self.tags = tags
        self.importance = importance
        self.confidence = confidence
        self.supersedes = supersedes
    }
}
