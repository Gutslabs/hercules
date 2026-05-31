import Foundation

/// AI sağlayıcı seçimi. Şu anda sadece Codex aktif (OpenRouter kodu duruyor ama UI'da yok).
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openRouter
    case codex

    var id: String { rawValue }

    /// UI'da seçilebilir sağlayıcılar.
    static var selectable: [AIProvider] { [.openRouter, .codex] }

    var label: String {
        switch self {
        case .openRouter: return "Ollama (Yerel)"
        case .codex: return "Codex (ChatGPT)"
        }
    }

    var detail: String {
        switch self {
        case .openRouter: return "Yerel Ollama · internet gerekmez"
        case .codex: return "ChatGPT hesabıyla · ~/.codex/auth.json"
        }
    }

    var systemImage: String {
        switch self {
        case .openRouter: return "globe.americas"
        case .codex: return "person.badge.key"
        }
    }

    /// Bu sağlayıcı için varsayılan model.
    var defaultModel: String {
        switch self {
        case .openRouter: return "qwen2.5:14b"
        case .codex: return "gpt-5.4"
        }
    }

    /// Seçilebilir modeller (UI dropdown).
    var availableModels: [String] {
        switch self {
        case .openRouter:
            return ["qwen2.5:14b"]
        case .codex:
            return ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2"]
        }
    }

    /// Intelligence (reasoning) bu sağlayıcıda anlamlı mı?
    var supportsIntelligence: Bool {
        self == .codex
    }
}

/// Intelligence (reasoning effort) seviyesi.
/// API'deki effort değerleriyle eşleşir: minimal/low/medium/high
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
        case .low: return "minimal"
        case .medium: return "low"
        case .high: return "medium"
        case .extraHigh: return "high"
        }
    }
}

/// Tüm AI istemcileri bu protokolü uygular.
protocol AIClient {
    func send(
        history: [ChatTurn],
        newUserText: String,
        userContext: String?,
        onSearchStart: @MainActor @escaping (String) -> Void,
        onMessageUpdate: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, String?)

    /// Lean, tek-atışlık completion: streaming/araç/yemek-parse yok. Hafıza çıkarımı
    /// gibi arka plan işleri için kullanılır. Modelin ham metin çıktısını (genelde JSON) döner.
    func complete(systemPrompt: String, userPrompt: String) async throws -> String
}

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
        onSearchStart: @MainActor @escaping (String) -> Void,
        onMessageUpdate: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, String?) {
        do {
            return try await codex.send(
                history: history,
                newUserText: newUserText,
                userContext: userContext,
                onSearchStart: onSearchStart,
                onMessageUpdate: onMessageUpdate
            )
        } catch {
            let notice = Self.routingNotice(for: error)
            await onMessageUpdate(notice)

            do {
                var (result, searchQuery) = try await openRouter.send(
                    history: history,
                    newUserText: newUserText,
                    userContext: userContext,
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
                return (result, searchQuery)
            } catch {
                throw AIFallbackError(codexError: notice, openRouterError: error.localizedDescription)
            }
        }
    }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        do {
            return try await codex.complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
        } catch {
            return try await openRouter.complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
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

struct AIFallbackError: LocalizedError {
    var codexError: String
    var openRouterError: String

    var errorDescription: String? {
        "\(codexError) OpenRouter da hata verdi: \(openRouterError)"
    }
}
