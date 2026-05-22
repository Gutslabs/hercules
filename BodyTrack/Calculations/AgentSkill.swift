import Foundation

struct AgentContext {
    let appContext: String?
    let history: [ChatTurn]
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

final class AgentRouter {
    static let shared = AgentRouter(
        skills: [
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
        history: [ChatTurn]
    ) async -> String? {
        let context = AgentContext(appContext: appContext, history: history, now: .now)
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

    func absorbConversation(userText: String, assistantText: String) {
        memoryProvider.absorbConversation(userText: userText, assistantText: assistantText)
    }
}

struct MemoryRecallSkill: AgentSkill {
    let id = "memory.recall"
    let name = "Local Memory Recall"
    let description = "Kullanıcıya ait kalıcı, düzeltilebilir local hafızayı getirir."

    func canHandle(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run(query: String, context: AgentContext) async throws -> SkillResult? {
        let memories = LocalMemoryProvider.shared.search(query: query, topK: 6)
        guard !memories.isEmpty else { return nil }

        let lines = memories.map { memory in
            let tags = memory.tags.isEmpty ? "" : " [\(memory.tags.joined(separator: ", "))]"
            return "- \(memory.content)\(tags)"
        }

        return SkillResult(
            skillID: id,
            title: "Kişisel Hafıza",
            content: lines.joined(separator: "\n"),
            sources: []
        )
    }
}
