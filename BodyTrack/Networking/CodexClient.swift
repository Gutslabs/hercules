import Foundation

/// Codex (chatgpt.com/backend-api/codex) için Responses API üzerinden konuşan istemci.
final class CodexClient: AIClient {
    private let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
    private let session: URLSession

    /// Dedicated session — default URLSession sonsuz timeout'a yakın değerlerle
    /// gelir; biz açık 60s request / 600s resource (streaming uzun cevaplar) belirliyoruz.
    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    init(session: URLSession? = nil) {
        self.session = session ?? Self.defaultSession
    }

    /// OpenAI Responses API'nın server-side web search tool'u.
    /// Model ihtiyaç duyduğunda OpenAI tarafında otomatik aratma yapar,
    /// sonuçları context'e ekler ve nihai cevabı döner — bizim execute etmemiz gerekmez.
    private static let webSearchTool: [String: Any] = [
        "type": "web_search"
    ]

    func send(
        history: [ChatTurn],
        newUserText: String,
        userContext: String?,
        onSearchStart: @MainActor @escaping (String) -> Void,
        onMessageUpdate: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, String?) {
        let tokens = try await CodexAuth.shared.ensureFreshToken()
        guard let accountId = tokens.chatGPTAccountId else {
            throw CodexAuthError.noAccountId
        }

        let model = AIKeyStore.shared.model
        let recent = Array(history.suffix(10))
        var input: [[String: Any]] = []
        for t in recent {
            input.append(["role": t.role.rawValue, "content": t.text])
        }
        // Inject app data + agent skill context inline before the user's actual question.
        // Codex/Responses API uses a single `instructions` field for the system
        // prompt, so per-turn extra context goes here as a developer/user role.
        let finalUserText: String = {
            guard let userContext, !userContext.isEmpty else { return newUserText }
            return """
            Aşağıda Hercules'in canlı kullanıcı verisi, kişisel hafızası ve agent skill sonuçları olabilir.
            Sorumu cevaplarken sadece alakalı kısımları kullan; kaynaklı araştırma varsa tarih/kaynak hassasiyetini koru.

            \(userContext)

            ---
            \(newUserText)
            """
        }()
        input.append(["role": "user", "content": finalUserText])

        let requiresRecipeSearch = AIConfig.requiresRecipeWebSearch(newUserText)
        var body: [String: Any] = [
            "model": model,
            "instructions": AIConfig.systemPrompt,
            "input": input,
            "tools": [Self.webSearchTool],
            "tool_choice": requiresRecipeSearch ? "required" : "auto",
            "store": false,
            "stream": true
        ]
        let effort = AIKeyStore.shared.intelligence.apiValue
        body["reasoning"] = ["effort": effort, "summary": "auto"]
        body["include"] = ["reasoning.encrypted_content"]

        let stream = try await streamResponse(
            body: body,
            token: tokens.access_token,
            accountId: accountId,
            onSearchStart: onSearchStart,
            onMessageUpdate: onMessageUpdate
        )

        // Output'ta web_search_call varsa search query'sini al
        var searchQuery: String? = nil
        var assistantText: String? = nil
        for item in stream.output {
            let type = (item["type"] as? String) ?? ""
            if type == "web_search_call" || type.hasPrefix("web_search") {
                if let action = item["action"] as? [String: Any],
                   let query = action["query"] as? String {
                    searchQuery = query
                } else if let query = item["query"] as? String {
                    searchQuery = query
                }
            } else if type == "message" {
                if let content = item["content"] as? [[String: Any]] {
                    for part in content {
                        if let text = part["text"] as? String {
                            assistantText = (assistantText ?? "") + text
                        } else if let text = part["output_text"] as? String {
                            assistantText = (assistantText ?? "") + text
                        }
                    }
                } else if let directText = item["text"] as? String {
                    assistantText = (assistantText ?? "") + directText
                }
            }
        }

        let finalText = (assistantText?.isEmpty == false ? assistantText : nil) ?? stream.accumulatedText
        guard !finalText.isEmpty else {
            throw OpenRouterError.decoding("Empty response — başka model dene.")
        }
        return (parseFood(finalText), searchQuery ?? stream.searchQuery)
    }

    /// Lean completion — araç/yemek-parse yok, minimal reasoning. Streaming yolunu
    /// no-op callback'lerle yeniden kullanır, asistanın ham metnini döner.
    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        let tokens = try await CodexAuth.shared.ensureFreshToken()
        guard let accountId = tokens.chatGPTAccountId else {
            throw CodexAuthError.noAccountId
        }

        var body: [String: Any] = [
            "model": AIKeyStore.shared.model,
            "instructions": systemPrompt,
            "input": [["role": "user", "content": userPrompt]],
            "store": false,
            "stream": true
        ]
        body["reasoning"] = ["effort": "minimal", "summary": "auto"]
        body["include"] = ["reasoning.encrypted_content"]

        let stream = try await streamResponse(
            body: body,
            token: tokens.access_token,
            accountId: accountId
        )

        var assistantText = ""
        for item in stream.output where (item["type"] as? String) == "message" {
            if let content = item["content"] as? [[String: Any]] {
                for part in content {
                    if let text = part["text"] as? String {
                        assistantText += text
                    } else if let text = part["output_text"] as? String {
                        assistantText += text
                    }
                }
            } else if let directText = item["text"] as? String {
                assistantText += directText
            }
        }

        let finalText = assistantText.isEmpty ? stream.accumulatedText : assistantText
        guard !finalText.isEmpty else {
            throw OpenRouterError.decoding("Boş yanıt")
        }
        return finalText
    }

    struct StreamResult {
        var output: [[String: Any]]
        var accumulatedText: String  // text delta'larından toplanmış
        var searchQuery: String?     // web_search çağrıldıysa query
    }

    /// Codex'ten gelen SSE stream'ini parse et. Hem text delta'ları biriktir hem de
    /// `response.completed` event'inden final output dizisini al. Web search call'larını
    /// onSearchStart callback'i ile UI'a bildirir.
    private func streamResponse(
        body: [String: Any],
        token: String,
        accountId: String,
        onSearchStart: @MainActor @escaping (String) -> Void = { _ in },
        onMessageUpdate: @MainActor @escaping (String) -> Void = { _ in }
    ) async throws -> StreamResult {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("codex_cli_rs/0.0.0 (Hercules)", forHTTPHeaderField: "User-Agent")
        req.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OpenRouterError.badResponse(-1, "Invalid response")
        }
        if !(200..<300).contains(http.statusCode) {
            var bodyText = ""
            for try await line in bytes.lines {
                bodyText += line + "\n"
                if bodyText.count > 500 { break }
            }
            throw OpenRouterError.badResponse(http.statusCode, bodyText)
        }

        var collectedOutput: [[String: Any]] = []
        var accumulatedText = ""
        var searchQuery: String? = nil
        // Incremental extractor — accumulatedText'i her seferinde baştan
        // taramak yerine son scan offset'ten devam eder. Stream uzadıkça
        // performans sabit kalır (O(n²) → O(n)).
        var extractor = MessageStreamExtractor()
        var lastPartialSent = ""
        var lastPartialSentAt = Date.distantPast
        let partialUpdateInterval: TimeInterval = 0.12
        let partialUpdateCharacterBudget = 96

        func publishPartial(_ partial: String, force: Bool = false) async {
            guard partial != lastPartialSent else { return }
            let now = Date()
            let currentLength = partial.count
            let characterBudget: Int
            let interval: TimeInterval
            if currentLength > 3_000 {
                characterBudget = 240
                interval = 0.22
            } else if currentLength > 1_200 {
                characterBudget = 160
                interval = 0.16
            } else {
                characterBudget = partialUpdateCharacterBudget
                interval = partialUpdateInterval
            }
            let grewEnough = currentLength - lastPartialSent.count >= characterBudget
            let waitedEnough = now.timeIntervalSince(lastPartialSentAt) >= interval
            guard force || grewEnough || waitedEnough else { return }
            lastPartialSent = partial
            lastPartialSentAt = now
            await onMessageUpdate(partial)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }

            switch type {
            case "response.output_text.delta":
                if let delta = obj["delta"] as? String {
                    accumulatedText += delta
                    // Typewriter: çıkartılan partial message'ı UI'a yolla
                    if let partial = extractor.feed(accumulated: accumulatedText) {
                        await publishPartial(partial)
                    }
                }
            case "response.output_item.added":
                // Web search aramasının başladığı moment
                if let item = obj["item"] as? [String: Any],
                   let itemType = item["type"] as? String,
                   itemType == "web_search_call" {
                    let q = (item["action"] as? [String: Any])?["query"] as? String
                          ?? (item["query"] as? String)
                          ?? "..."
                    searchQuery = q
                    await onSearchStart(q)
                }
            case "response.web_search_call.in_progress",
                 "response.web_search_call.searching":
                if let item = obj["item"] as? [String: Any],
                   let q = (item["action"] as? [String: Any])?["query"] as? String {
                    searchQuery = q
                    await onSearchStart(q)
                }
            case "response.completed":
                if let response = obj["response"] as? [String: Any] {
                    if let output = response["output"] as? [[String: Any]] {
                        collectedOutput = output
                    }
	                    if accumulatedText.isEmpty,
	                       let outputText = response["output_text"] as? String {
	                        accumulatedText = outputText
	                    }
	                }
	                if let partial = extractor.feed(accumulated: accumulatedText) {
	                    await publishPartial(partial, force: true)
	                }
	                return StreamResult(output: collectedOutput, accumulatedText: accumulatedText, searchQuery: searchQuery)
            case "response.failed", "error":
                let msg = (obj["error"] as? [String: Any])?["message"] as? String
                    ?? (obj["message"] as? String)
                    ?? payload
                throw OpenRouterError.badResponse(500, msg)
            default:
                break
            }
        }
        if !accumulatedText.isEmpty || !collectedOutput.isEmpty {
            if let partial = extractor.feed(accumulated: accumulatedText) {
                await publishPartial(partial, force: true)
            }
            return StreamResult(output: collectedOutput, accumulatedText: accumulatedText, searchQuery: searchQuery)
        }
        throw OpenRouterError.decoding("Stream ended without response.completed")
    }

    /// Streaming sırasında biriken raw JSON'dan `"message"` alanının değerini
    /// canlı olarak çıkar. State tutar — accumulatedText'i her seferinde
    /// baştan değil, kalan kısımdan tarar.
    fileprivate struct MessageStreamExtractor {
        /// `"message":"` sonrasında value-start offset (raw içinde).
        private var valueStartOffset: Int?
        /// Bir sonraki tarama hangi offset'ten devam edecek (raw içinde).
        private var scanOffset: Int = 0
        /// Şimdiye kadar çıkartılan unescaped string.
        private var output: String = ""
        /// String içinde kapanış " görüldü mü.
        private var closed: Bool = false

        mutating func feed(accumulated raw: String) -> String? {
            // 1) Start offset'i bul (sadece bir kez)
            if valueStartOffset == nil {
                guard let r = raw.range(of: "\"message\"") else { return nil }
                var i = r.upperBound
                while i < raw.endIndex, raw[i] == ":" || raw[i].isWhitespace {
                    i = raw.index(after: i)
                }
                guard i < raw.endIndex, raw[i] == "\"" else { return nil }
                let start = raw.index(after: i)
                valueStartOffset = raw.distance(from: raw.startIndex, to: start)
                scanOffset = valueStartOffset!
            }
            if closed { return output }

            // 2) scanOffset'ten devam et
            var i = raw.index(raw.startIndex, offsetBy: scanOffset)
            while i < raw.endIndex {
                let c = raw[i]
                if c == "\\" {
                    let n = raw.index(after: i)
                    if n >= raw.endIndex {
                        // Escape sequence yarım kaldı, sonraki chunk'ı bekle
                        scanOffset = raw.distance(from: raw.startIndex, to: i)
                        return output
                    }
                    switch raw[n] {
                    case "n":  output.append("\n")
                    case "t":  output.append("\t")
                    case "r":  output.append("\r")
                    case "\"": output.append("\"")
                    case "\\": output.append("\\")
                    case "/":  output.append("/")
                    default:   output.append(raw[n])
                    }
                    i = raw.index(after: n)
                    continue
                }
                if c == "\"" {
                    closed = true
                    scanOffset = raw.distance(from: raw.startIndex, to: i)
                    return output
                }
                output.append(c)
                i = raw.index(after: i)
            }
            scanOffset = raw.distance(from: raw.startIndex, to: i)
            return output
        }
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
