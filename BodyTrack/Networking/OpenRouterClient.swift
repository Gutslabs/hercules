import Foundation

enum AIConfig {
    static let defaultAPIKey = ""
    static let defaultModel = "x-ai/grok-4.1-fast"
    static let searchModel = "x-ai/grok-4.1-fast:online"
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    static let appReferer = "https://hercules.local"
    static let appTitle = "Hercules"

    static let systemPrompt = """
    Sen Türkçe konuşan, samimi bir kalori uzmanısın. Kullanıcı bir yemek/miktar yazınca SADECE şu JSON formatında dön:

    {"name": "yemek adı", "grams": <gram>, "calories": <kalori>, "protein_g": <protein>, "carbs_g": <karbonhidrat>, "fat_g": <yağ>, "message": "kısa Türkçe açıklama"}

    EN ÖNEMLİ KURAL: Asla "bilmiyorum" veya boş cevap verme. Bilmiyorsan ÖNCE web_search aracını kullan, sonra sonuca göre JSON dön.

    web_search ne zaman:
    - Bilmediğin/EMİN OLMADIĞIN her yemek/marka/ürün için (ör. "eti şekli", "popeyes wicked", "mado künefe", lokal yöresel yemekler).
    - Yeni çıkan veya bölgesel ürünler için.
    - Eminsen aratma — yaygın yemekler (tavuk göğsü, pirinç, yumurta, makarna, ekmek, vb) için kendi bilgini kullan, hızlı cevap ver.
    - Aratınca tek aramayla yetin, defalarca arama yapma.

    Diğer kurallar:
    - calories, protein_g, carbs_g, fat_g sayı (g cinsinden) olmalı.
    - Kullanıcı miktar belirtmediyse makul porsiyon varsay (1 porsiyon ≈ 200g, 1 dilim ≈ 30g).
    - Yemek değilse (selamlama, soru, sohbet) sadece: {"message": "Türkçe cevap"}
    - JSON dışında HİÇBİR ŞEY yazma. Markdown, kod bloğu, açıklama yok.
    - message kısa ve net olsun (1-2 cümle).
    - Aratıp da bulamazsan: makul bir tahmin yap, message'da "kesin değer bulunamadı, tahmini" diye belirt.
    """
}

struct AIFoodResult: Codable, Equatable {
    var name: String?
    var grams: Double?
    var calories: Double?
    var protein_g: Double?
    var carbs_g: Double?
    var fat_g: Double?
    var message: String

    var isFood: Bool {
        calories != nil && (name?.isEmpty == false)
    }
}

enum OpenRouterError: LocalizedError {
    case badResponse(Int, String)
    case decoding(String)
    case missingKey
    case toolLoop

    var errorDescription: String? {
        switch self {
        case .badResponse(let code, let msg): return "HTTP \(code): \(msg)"
        case .decoding(let s): return "Yanıt çözümlenemedi: \(s)"
        case .missingKey: return "OpenRouter API key tanımlı değil."
        case .toolLoop: return "Tool çağrı limiti aşıldı."
        }
    }
}

struct ChatTurn: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var food: AIFoodResult? = nil
    var saved: Bool = false
    var searchedFor: String? = nil  // populated if AI did a web search
}

final class OpenRouterClient: AIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Web search tool exposed to the model. Model calls it only when uncertain.
    private static let webSearchTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "web_search",
            "description": "Bir yemek/ürünün kalori veya besin değeri hakkında EMİN olmadığında web'den aramak için kullan. Yaygın bilinen yiyecekler için kullanma.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Türkçe arama sorgusu (ör. 'Burger King double whopper kalori')"
                    ]
                ],
                "required": ["query"]
            ]
        ]
    ]

    /// Updates from the running request — set by closure so UI can react.
    /// Returns: (final JSON-parsed result, optional search query that was performed)
    func send(
        history: [ChatTurn],
        newUserText: String,
        onSearchStart: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, String?) {
        let key = AIKeyStore.shared.apiKey
        guard !key.isEmpty else { throw OpenRouterError.missingKey }

        // Build initial messages
        var messages: [[String: Any]] = [
            ["role": "system", "content": AIConfig.systemPrompt]
        ]
        let recent = Array(history.suffix(10))
        for t in recent {
            messages.append(["role": t.role.rawValue, "content": t.text])
        }
        messages.append(["role": "user", "content": newUserText])

        var lastSearchQuery: String? = nil

        // Tool loop — max 2 iterations to avoid runaway
        for _ in 0..<2 {
            let body: [String: Any] = [
                "model": AIKeyStore.shared.model,
                "messages": messages,
                "temperature": 0.2,
                "tools": [Self.webSearchTool],
                "tool_choice": "auto"
            ]

            let (data, http) = try await postJSON(body: body, key: key)
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? "no body"
                throw OpenRouterError.badResponse(http.statusCode, text)
            }

            guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = outer["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let messageDict = first["message"] as? [String: Any]
            else {
                throw OpenRouterError.decoding(String(data: data, encoding: .utf8) ?? "no body")
            }

            // Did the model emit tool_calls?
            if let toolCalls = messageDict["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                // Append assistant message with tool_calls (preserve as-is)
                var assistantMsg: [String: Any] = ["role": "assistant", "content": NSNull()]
                assistantMsg["tool_calls"] = toolCalls
                messages.append(assistantMsg)

                // Execute each tool call
                for tc in toolCalls {
                    guard let id = tc["id"] as? String,
                          let fn = tc["function"] as? [String: Any],
                          let name = fn["name"] as? String,
                          let argsStr = fn["arguments"] as? String,
                          let argsData = argsStr.data(using: .utf8),
                          let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]
                    else { continue }

                    if name == "web_search", let query = args["query"] as? String {
                        lastSearchQuery = query
                        await onSearchStart(query)
                        let result = try await performWebSearch(query: query, key: key)
                        messages.append([
                            "role": "tool",
                            "tool_call_id": id,
                            "content": result
                        ])
                    }
                }
                // Loop back to get final answer with tool result in context
                continue
            }

            // No tool calls — final content
            guard let content = messageDict["content"] as? String else {
                throw OpenRouterError.decoding("Empty content")
            }
            return (parseFood(content), lastSearchQuery)
        }

        throw OpenRouterError.toolLoop
    }

    /// Performs a web search by hitting the :online variant of the model.
    /// Returns concise text to feed back as tool result.
    private func performWebSearch(query: String, key: String) async throws -> String {
        let body: [String: Any] = [
            "model": AIConfig.searchModel,
            "messages": [
                ["role": "system", "content": "Sen kısa, doğru bilgi veren bir araştırmacısın. Sorulan yemeğin/ürünün kalori ve besin değerlerini web'den bulup özet halinde dön (porsiyon, kcal, protein, karbonhidrat, yağ). Maksimum 4 satır."],
                ["role": "user", "content": query]
            ],
            "temperature": 0.1
        ]

        let (data, http) = try await postJSON(body: body, key: key)
        guard (200..<300).contains(http.statusCode) else {
            return "Arama başarısız: HTTP \(http.statusCode)"
        }
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = outer["choices"] as? [[String: Any]],
              let first = choices.first,
              let messageDict = first["message"] as? [String: Any],
              let content = messageDict["content"] as? String
        else {
            return "Arama yanıtı çözümlenemedi."
        }
        return content
    }

    private func postJSON(body: [String: Any], key: String) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: AIConfig.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AIConfig.appReferer, forHTTPHeaderField: "HTTP-Referer")
        req.setValue(AIConfig.appTitle, forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OpenRouterError.badResponse(-1, "Invalid response")
        }
        return (data, http)
    }

    private func parseFood(_ content: String) -> AIFoodResult {
        let stripped = stripCodeFences(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let inner = stripped.data(using: .utf8) else {
            return AIFoodResult(message: stripped)
        }
        if let result = try? JSONDecoder().decode(AIFoodResult.self, from: inner) {
            return result
        }
        return AIFoodResult(message: stripped)
    }

    private func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) }
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t
    }
}

/// Stores provider/key/model in UserDefaults — UI'dan değiştirilebilir.
final class AIKeyStore {
    static let shared = AIKeyStore()
    private let defaults = UserDefaults.standard
    private let keyAPI = "hercules.openrouter.api_key"
    private let keyProvider = "hercules.ai.provider"
    private let keyModelOpenRouter = "hercules.openrouter.model"
    private let keyModelCodex = "hercules.codex.model"
    private let keyReasoning = "hercules.codex.reasoning"

    var provider: AIProvider {
        get {
            let stored = defaults.string(forKey: keyProvider) ?? ""
            let parsed = AIProvider(rawValue: stored) ?? .codex
            // OpenRouter UI'dan kaldırıldı — eski kullanıcılar otomatik Codex'e düşsün
            return AIProvider.selectable.contains(parsed) ? parsed : .codex
        }
        set { defaults.set(newValue.rawValue, forKey: keyProvider) }
    }

    var apiKey: String {
        get {
            let stored = defaults.string(forKey: keyAPI) ?? ""
            return stored.isEmpty ? AIConfig.defaultAPIKey : stored
        }
        set { defaults.set(newValue, forKey: keyAPI) }
    }

    /// Aktif sağlayıcının modeli — saklanan değer artık listede yoksa default'a düş.
    var model: String {
        get {
            let key = (provider == .codex) ? keyModelCodex : keyModelOpenRouter
            let stored = defaults.string(forKey: key) ?? ""
            if !stored.isEmpty && provider.availableModels.contains(stored) {
                return stored
            }
            return provider.defaultModel
        }
        set {
            let key = (provider == .codex) ? keyModelCodex : keyModelOpenRouter
            defaults.set(newValue, forKey: key)
        }
    }

    /// Codex intelligence (reasoning) seviyesi. Default: Low (en hızlı).
    var intelligence: IntelligenceLevel {
        get {
            let stored = defaults.string(forKey: keyReasoning) ?? ""
            return IntelligenceLevel(rawValue: stored) ?? .low
        }
        set { defaults.set(newValue.rawValue, forKey: keyReasoning) }
    }

    /// Yeni sağlayıcı seçilince doğru istemciyi kur.
    func makeClient() -> AIClient {
        switch provider {
        case .openRouter: return OpenRouterClient()
        case .codex: return CodexClient()
        }
    }
}
