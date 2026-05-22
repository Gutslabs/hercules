import Foundation

struct AgentMemory: Codable, Identifiable, Equatable {
    let id: UUID
    var content: String
    var tags: [String]
    var source: String
    var confidence: Double
    var createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date
    var expiresAt: Date?
    var pinned: Bool

    init(
        id: UUID = UUID(),
        content: String,
        tags: [String],
        source: String,
        confidence: Double,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastSeenAt: Date = .now,
        expiresAt: Date? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.content = content
        self.tags = tags
        self.source = source
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
        self.expiresAt = expiresAt
        self.pinned = pinned
    }
}

final class LocalMemoryProvider {
    static let shared = LocalMemoryProvider()

    private struct MemoryPayload: Codable {
        var version: Int
        var savedAt: Date
        var memories: [AgentMemory]
    }

    private let memoryURL: URL
    private var memories: [AgentMemory] = []

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

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
        load()
        if pruneExpiredMemories() {
            persist()
        }
    }

    func search(query: String, topK: Int) -> [AgentMemory] {
        reloadFromDisk()
        let queryTerms = Set(Self.tokens(query))
        guard !queryTerms.isEmpty else { return [] }

        let now = Date()
        let scored = memories
            .filter { !Self.isExpired($0, now: now) }
            .map { memory -> (memory: AgentMemory, score: Double) in
                let memoryTerms = Set(Self.tokens(memory.content + " " + memory.tags.joined(separator: " ")))
                let overlap = queryTerms.intersection(memoryTerms)
                let tagOverlap = queryTerms.intersection(Set(memory.tags.flatMap(Self.tokens)))
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

    func allMemories() -> [AgentMemory] {
        reloadFromDisk()
        if pruneExpiredMemories() {
            persist()
        }
        return memories.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned && !rhs.pinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func deleteMemory(id: UUID) {
        memories.removeAll { $0.id == id }
        persist()
    }

    func setPinned(id: UUID, pinned: Bool) {
        guard let idx = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[idx].pinned = pinned
        memories[idx].updatedAt = .now
        memories[idx].lastSeenAt = .now
        persist()
    }

    func updateMemory(id: UUID, content: String, tags: [String]) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = memories.firstIndex(where: { $0.id == id })
        else { return }
        memories[idx].content = trimmed
        memories[idx].tags = Self.normalizedTags(tags)
        memories[idx].source = "manual-edit"
        memories[idx].confidence = max(memories[idx].confidence, 0.9)
        memories[idx].updatedAt = .now
        memories[idx].lastSeenAt = .now
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

    @discardableResult
    func absorbConversation(userText: String, assistantText: String) -> Int {
        _ = assistantText
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        var inserted = 0
        if let explicit = explicitMemoryCandidate(from: trimmed) {
            remember(content: explicit.content, tags: explicit.tags, source: "explicit", confidence: 0.96, pinned: true)
            inserted += 1
        } else if let inferred = inferredMemoryCandidate(from: trimmed) {
            remember(content: inferred.content, tags: inferred.tags, source: "chat-inferred", confidence: inferred.confidence)
            inserted += 1
        }

        if Self.containsAny(trimmed, needles: ["kanka", "knk", "aq", "samimi", "casual"]) {
            remember(
                content: "Kullanıcı samimi Türkçe tonda, kısa ve direkt konuşmayı seviyor.",
                tags: ["communication", "tone"],
                source: "chat-style",
                confidence: 0.72
            )
        }

        return inserted
    }

    @discardableResult
    func remember(
        content: String,
        tags: [String],
        source: String,
        confidence: Double,
        expiresAt: Date? = nil,
        pinned: Bool = false
    ) -> AgentMemory {
        let normalizedContent = Self.normalizeMemory(content)
        let normalizedTags = Self.normalizedTags(tags)

        if let idx = memories.firstIndex(where: { Self.normalizeMemory($0.content) == normalizedContent }) {
            memories[idx].tags = Array(Set(memories[idx].tags + normalizedTags)).sorted()
            memories[idx].source = source
            memories[idx].confidence = max(memories[idx].confidence, confidence)
            memories[idx].updatedAt = .now
            memories[idx].lastSeenAt = .now
            memories[idx].pinned = memories[idx].pinned || pinned
            if pinned || expiresAt == nil {
                memories[idx].expiresAt = nil
            } else if memories[idx].expiresAt == nil {
                memories[idx].expiresAt = expiresAt
            }
            persist()
            return memories[idx]
        }

        let memory = AgentMemory(
            content: content,
            tags: normalizedTags,
            source: source,
            confidence: confidence,
            expiresAt: expiresAt,
            pinned: pinned
        )
        memories.append(memory)
        persist()
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

    private func inferredMemoryCandidate(from text: String) -> (content: String, tags: [String], confidence: Double)? {
        let lower = Self.fold(text)
        let personalSignals = [
            "ben ", "bende ", "benim ", "severim", "seviyorum", "sevmiyorum",
            "tercih", "istemiyorum", "hedefim", "amacim", "amacım", "yapiyorum",
            "yapıyorum", "gidiyorum", "yiyorum", "kullaniyorum", "kullanıyorum"
        ]
        let domainSignals = [
            "protein", "kalori", "makro", "bulk", "cut", "definasyon", "kilo",
            "yag", "yağ", "antrenman", "idman", "workout", "gym", "kreatin",
            "creatine", "whey", "yemek", "ogun", "öğün", "ucuz", "butce", "bütçe",
            "pismis", "pişmiş", "cig", "çiğ", "bodybuilding"
        ]

        guard text.count <= 260,
              Self.containsAny(lower, needles: personalSignals),
              Self.containsAny(lower, needles: domainSignals)
        else { return nil }

        return ("Kullanıcı hakkında: \(text)", Self.tags(for: text), 0.68)
    }

    private func touch(_ selected: [AgentMemory]) {
        guard !selected.isEmpty else { return }
        let ids = Set(selected.map(\.id))
        for idx in memories.indices where ids.contains(memories[idx].id) {
            memories[idx].lastSeenAt = .now
        }
        persist()
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

    private func load() {
        guard let data = try? Data(contentsOf: memoryURL) else {
            memories = []
            return
        }

        do {
            let payload = try Self.decoder.decode(MemoryPayload.self, from: data)
            memories = Self.deduplicated(payload.memories)
        } catch {
            Self.backupUnreadableFile(at: memoryURL)
            memories = []
        }
    }

    @discardableResult
    private func pruneExpiredMemories() -> Bool {
        let now = Date()
        let before = memories.count
        memories.removeAll { Self.isExpired($0, now: now) }
        return before != memories.count
    }

    private func persist() {
        if memories.isEmpty {
            try? FileManager.default.removeItem(at: memoryURL)
            return
        }
        let payload = MemoryPayload(version: 1, savedAt: .now, memories: memories)
        guard let data = try? Self.encoder.encode(payload) else { return }
        try? data.write(to: memoryURL, options: [.atomic])
    }

    private static func isExpired(_ memory: AgentMemory, now: Date) -> Bool {
        guard !memory.pinned, let expiresAt = memory.expiresAt else { return false }
        return expiresAt < now
    }

    private static func tags(for text: String) -> [String] {
        let lower = fold(text)
        var tags: Set<String> = []
        if containsAny(lower, needles: ["protein", "kalori", "makro", "yemek", "ogun", "öğün", "pismis", "pişmiş", "cig", "çiğ"]) {
            tags.insert("nutrition")
        }
        if containsAny(lower, needles: ["antrenman", "idman", "workout", "gym", "hipertrofi", "hypertrophy", "bodybuilding"]) {
            tags.insert("training")
        }
        if containsAny(lower, needles: ["bulk", "cut", "definasyon", "kilo", "yag", "yağ", "hedef"]) {
            tags.insert("goal")
        }
        if containsAny(lower, needles: ["seviyorum", "sevmiyorum", "tercih", "istemiyorum"]) {
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
        for memory in loaded {
            let key = normalizeMemory(memory.content)
            guard !key.isEmpty else {
                output.append(memory)
                continue
            }
            if let idx = output.firstIndex(where: { normalizeMemory($0.content) == key }) {
                output[idx].tags = Array(Set(output[idx].tags + memory.tags)).sorted()
                output[idx].confidence = max(output[idx].confidence, memory.confidence)
                output[idx].pinned = output[idx].pinned || memory.pinned
                output[idx].createdAt = min(output[idx].createdAt, memory.createdAt)
                output[idx].updatedAt = max(output[idx].updatedAt, memory.updatedAt)
                output[idx].lastSeenAt = max(output[idx].lastSeenAt, memory.lastSeenAt)
                if output[idx].expiresAt == nil || memory.expiresAt == nil {
                    output[idx].expiresAt = nil
                } else {
                    output[idx].expiresAt = max(output[idx].expiresAt!, memory.expiresAt!)
                }
            } else {
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
