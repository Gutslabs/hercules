import Foundation

/// AI sağlayıcı seçimi. Şu anda sadece Codex aktif (OpenRouter kodu duruyor ama UI'da yok).
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openRouter
    case codex

    var id: String { rawValue }

    /// UI'da seçilebilir sağlayıcılar (OpenRouter şu an gizli).
    static var selectable: [AIProvider] { [.codex] }

    var label: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .codex: return "Codex (ChatGPT)"
        }
    }

    var detail: String {
        switch self {
        case .openRouter: return "API key ile · web araması destekli"
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
        case .openRouter: return "x-ai/grok-4.1-fast"
        case .codex: return "gpt-5.4"
        }
    }

    /// Seçilebilir modeller (UI dropdown).
    var availableModels: [String] {
        switch self {
        case .openRouter:
            return ["x-ai/grok-4.1-fast"]
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
        onSearchStart: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, String?)
}
