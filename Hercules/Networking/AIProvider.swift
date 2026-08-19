import Foundation

/// AI sağlayıcı seçimi. Şu anda sadece Codex aktif (OpenRouter kodu duruyor ama UI'da yok).
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openRouter
    case codex
    /// Kendi OpenAI-uyumlu proxy'n (CLIProxyAPI tarzı) — abonelik havuzu:
    /// Gemini / Grok / Codex / Claude tek endpoint'te, "bare" model id'leriyle.
    case gateway

    var id: String { rawValue }

    /// UI'da seçilebilir sağlayıcılar. Codex (ChatGPT hesabı) varsayılan; OpenRouter
    /// API-key ile alternatif; Gateway kendi CLIProxy'ne bağlanır (abonelik havuzu).
    static var selectable: [AIProvider] { [.codex, .openRouter, .gateway] }

    var label: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .codex: return "Codex (ChatGPT)"
        case .gateway: return "Gateway"
        }
    }

    var detail: String {
        switch self {
        case .openRouter: return "API key ile · web araması destekli"
        case .codex: return "ChatGPT hesabıyla · ~/.codex/auth.json"
        case .gateway: return "Kendi OpenAI-uyumlu proxy'n · abonelik havuzu"
        }
    }

    var systemImage: String {
        switch self {
        case .openRouter: return "globe.americas"
        case .codex: return "person.badge.key"
        case .gateway: return "server.rack"
        }
    }

    /// Bu sağlayıcı için varsayılan model.
    var defaultModel: String {
        switch self {
        case .openRouter: return "openai/gpt-5.4-mini"
        case .codex: return "gpt-5.6-terra"
        case .gateway: return "gemini-3-flash"
        }
    }

    /// Seçilebilir modeller (UI dropdown). Gateway'de bunlar sadece ÖNERİ —
    /// havuz değişebildiği için kullanıcı serbest metin de girebilir.
    var availableModels: [String] {
        switch self {
        case .openRouter:
            // Hepsi tool/function-calling destekli (web arama akışı için şart).
            return ["openai/gpt-5.4-mini", "openai/gpt-5.4", "openai/gpt-5.4-nano"]
        case .codex:
            // GPT-5.6 ailesi (~/.codex/models_cache.json'daki gerçek slug'lar):
            // sol=frontier, terra=dengeli (varsayılan), luna=hızlı/ekonomik.
            // Eski gpt-5.x id'leri listede değil → saklanan model otomatik `defaultModel`e düşer.
            return ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
        case .gateway:
            // "bare" id'ler → CLIProxy abonelik havuzuna gider (proxy'nin sunduğuna göre değişir).
            return ["gemini-3-flash", "gemini-3-pro", "grok-4.3", "gpt-5.5", "gpt-5.4", "claude-sonnet-4.5"]
        }
    }

    /// Gateway serbest-metin model kabul eder (havuz id'leri whitelist'e sığmaz).
    var allowsCustomModel: Bool { self == .gateway }

    /// Intelligence (reasoning) bu sağlayıcıda anlamlı mı?
    var supportsIntelligence: Bool {
        self == .codex
    }
}

/// Gateway model id'lerini markaya göre gruplar (uzun listeyi menüde taranabilir yapmak için).
enum GatewayModelGrouping {
    static func family(of id: String) -> String {
        let l = id.lowercased()
        // Hem CLIProxy bare id'leri (grok-4.5) hem OpenRouter vendor id'leri (x-ai/grok-4.5).
        if l.contains("gemini") || l.hasPrefix("google/") || l.hasPrefix("antigravity") { return "Gemini" }
        if l.contains("claude") || l.hasPrefix("anthropic/") { return "Claude" }
        if l.contains("grok") || l.hasPrefix("x-ai/") { return "Grok" }
        if l.hasPrefix("gpt") || l.hasPrefix("openai/") || l.contains("codex") || l.hasPrefix("o1") || l.hasPrefix("o3") || l.hasPrefix("o4") { return "GPT / Codex" }
        return "Diğer"
    }

    /// Sıralı (family, [id]) grupları — sabit aile sırasıyla, her grup alfabetik.
    static func grouped(_ ids: [String]) -> [(family: String, models: [String])] {
        let order = ["Gemini", "Claude", "Grok", "GPT / Codex", "Diğer"]
        var buckets: [String: [String]] = [:]
        for id in ids { buckets[family(of: id), default: []].append(id) }
        return order.compactMap { fam in
            guard let list = buckets[fam], !list.isEmpty else { return nil }
            return (fam, list.sorted())
        }
    }
}

/// Intelligence (reasoning effort) seviyesi.
/// API'deki effort değerleriyle eşleşir: low/medium/high/xhigh
/// (GPT-5.6 ailesi "minimal" desteklemiyor — models_cache.json'daki supported_reasoning_levels)
enum IntelligenceLevel: String, CaseIterable, Codable, Identifiable {
    case low, medium, high, extraHigh
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .extraHigh: return "Extra High"
        }
    }

    /// API'ye gidecek effort değeri.
    var apiValue: String {
        switch self {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        case .extraHigh: return "xhigh"
        }
    }
}

#if os(macOS)
final class CodexFirstFallbackClient: AIClient {
    private let codex: AIClient
    private let openRouter: AIClient

    init(codex: AIClient = CodexClient(), openRouter: AIClient = OpenRouterClient()) {
        self.codex = codex
        self.openRouter = openRouter
    }

    func send(
        history: [ChatTurn],
        newUserText: String,
        userContext: String?,
        images: [Data],
        onSearchStart: @MainActor @escaping (String) -> Void,
        onMessageUpdate: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, AIWebSearchEvidence?) {
        do {
            return try await codex.send(
                history: history,
                newUserText: newUserText,
                userContext: userContext,
                images: images,
                onSearchStart: onSearchStart,
                onMessageUpdate: onMessageUpdate
            )
        } catch {
            // Kullanıcı 'Dur'a bastıysa bu bir Codex hatası değil — kısmi metni koru,
            // sahte OpenRouter yönlendirmesi başlatma. İptali olduğu gibi yukarı fırlat.
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw error
            }
            let openRouterKey = AIKeyStore.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !openRouterKey.isEmpty else {
                throw error
            }

            let notice = Self.routingNotice(for: error)
            await onMessageUpdate(notice)

            do {
                var (result, searchEvidence) = try await openRouter.send(
                    history: history,
                    newUserText: newUserText,
                    userContext: userContext,
                    images: images,
                    onSearchStart: onSearchStart,
                    onMessageUpdate: { partial in
                        let routedPartial = [notice, partial]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n\n")
                        onMessageUpdate(routedPartial)
                    }
                )
                result.message = [notice, result.message]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                return (result, searchEvidence)
            } catch {
                throw AIFallbackError(codexError: notice, openRouterError: error.localizedDescription)
            }
        }
    }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        do {
            return try await codex.complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
        } catch {
            // İptali olduğu gibi fırlat — fallback başlatma.
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw error
            }
            let openRouterKey = AIKeyStore.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !openRouterKey.isEmpty else { throw error }
            return try await openRouter.complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
    }

    func completeJSON(
        systemPrompt: String,
        userPrompt: String,
        schemaName: String,
        schemaJSON: String
    ) async throws -> String {
        do {
            return try await codex.completeJSON(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                schemaName: schemaName,
                schemaJSON: schemaJSON
            )
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw error
            }
            let openRouterKey = AIKeyStore.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !openRouterKey.isEmpty else { throw error }
            return try await openRouter.completeJSON(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                schemaName: schemaName,
                schemaJSON: schemaJSON
            )
        }
    }

    func complete(systemPrompt: String, userPrompt: String, images: [Data]) async throws -> String {
        do {
            return try await codex.complete(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: images
            )
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw error
            }
            let openRouterKey = AIKeyStore.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !openRouterKey.isEmpty else { throw error }
            return try await openRouter.complete(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: images
            )
        }
    }

    private static func routingNotice(for error: Error) -> String {
        let message = error.localizedDescription
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(message.prefix(180))
        return "Codex hata verdi: \(clipped). OpenRouter'a yönlendirdim."
    }
}
#endif

struct AIFallbackError: LocalizedError {
    var codexError: String
    var openRouterError: String

    var errorDescription: String? {
        "\(codexError) OpenRouter da hata verdi: \(openRouterError)"
    }
}
