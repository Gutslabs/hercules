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
    var confidence: Double
    var type: MemoryType
    var createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date
    var expiresAt: Date?
    var pinned: Bool
    /// Soft-delete / supersede (Zep tarzı): doluysa kayıt AI'a sunulmaz ama diskte
    /// kalır — geçmiş kaybolmaz, gerekirse geri alınabilir.
    var invalidatedAt: Date?
    /// Bu kaydı geçersiz kılan yeni kaydın id'si (biliniyorsa).
    var supersededBy: UUID?
    /// Semantic retrieval için on-device embedding (Qwen3). JSON'a base64 olarak yazılır.
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
        type: MemoryType = .other,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastSeenAt: Date = .now,
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
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
        self.expiresAt = expiresAt
        self.pinned = pinned
        self.invalidatedAt = invalidatedAt
        self.supersededBy = supersededBy
        self.embedding = embedding
        self.embeddingModel = embeddingModel
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, tags, source, confidence, type
        case createdAt, updatedAt, lastSeenAt, expiresAt, pinned
        case invalidatedAt, supersededBy
        case embedding, embeddingModel
    }

    // Eski agent-memory.json (type/invalidatedAt/supersededBy alanları olmayan)
    // dosyaları sorunsuz okunabilsin diye lossy/defaulting decoder.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        content = (try? c.decode(String.self, forKey: .content)) ?? ""
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "unknown"
        confidence = (try? c.decodeIfPresent(Double.self, forKey: .confidence)) ?? 0.7
        type = (try? c.decodeIfPresent(MemoryType.self, forKey: .type)) ?? .other
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .now
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .now
        lastSeenAt = (try? c.decodeIfPresent(Date.self, forKey: .lastSeenAt)) ?? .now
        expiresAt = try? c.decodeIfPresent(Date.self, forKey: .expiresAt)
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        invalidatedAt = try? c.decodeIfPresent(Date.self, forKey: .invalidatedAt)
        supersededBy = try? c.decodeIfPresent(UUID.self, forKey: .supersededBy)
        if let base64 = try? c.decodeIfPresent(String.self, forKey: .embedding) {
            embedding = AgentMemory.decodeEmbedding(base64)
        } else {
            embedding = nil
        }
        embeddingModel = try? c.decodeIfPresent(String.self, forKey: .embeddingModel)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(tags, forKey: .tags)
        try c.encode(source, forKey: .source)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(type, forKey: .type)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(lastSeenAt, forKey: .lastSeenAt)
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
        let count = data.count / MemoryLayout<Float>.stride
        guard count > 0 else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
    }
}

/// Mem0 tarzı memory operasyonu — LLM memory-manager üretir, LocalMemoryProvider uygular.
struct LLMMemoryOperation: Sendable {
    enum Kind: Sendable { case add, update, delete }
    var kind: Kind
    var targetID: UUID?        // update / delete hedefi
    var content: String?       // add / update içeriği (atomik cümle)
    var type: MemoryType?
    var tags: [String] = []
    var importance: Double?    // 0...1 → confidence
    var supersedes: UUID?      // add bir eski kaydı supersede ediyorsa
}
