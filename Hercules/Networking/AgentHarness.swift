import Foundation

// Buzz'ın "Agent runtimes / harness" sistemi — Swift portu.
//
// Buzz her CLI ajanını (Claude Code, Cursor, Grok…) TEK protokolle sürer:
// ACP (Agent Client Protocol) = JSON-RPC 2.0, satır-ayrımlı JSON (NDJSON),
// child process'in stdin/stdout'u üzerinden. Vendor-özel çıktı parse edilmez.
// Akış: initialize → session/new → session/prompt (session/update bildirimleri
// akar) → yanıt stopReason ile döner; iptal session/cancel bildirimi + kill.
// Kaynak: buzz/crates/buzz-acp/src/acp.rs + desktop/src-tauri/managed_agents.
//
// Hercules uyarlaması: her `send` turu kendi process'ini açar (havuz yok) —
// AIClient sözleşmesi stateless'tır ve her çağrıda tam geçmiş gelir; geçmiş
// prompt'a transkript olarak gömülür, kalıcı bağlam session/new'daki
// systemPrompt ile taşınır.

#if os(macOS)

// MARK: - Harness kataloğu (Buzz discovery.rs / presets.rs)

/// Harness durumu — Buzz `availability` + `auth_status`un sadeleşmiş hâli.
enum HarnessAvailability: Equatable {
    case ready(binary: String)
    /// Vendor CLI var ama ACP adapter'ı eksik (yalnız Claude Code).
    case adapterMissing(cli: String)
    case notInstalled

    var isReady: Bool { if case .ready = self { return true }; return false }
}

struct HarnessSpec {
    let provider: AIProvider
    /// ACP konuşan komut (adapter veya CLI'ın kendisi).
    let command: String
    let args: [String]
    /// Adapter kullanan harness'larda asıl vendor CLI (tespit kademesi için).
    let underlyingCLI: String?
    /// `claude`'un ACP adapter'ı systemPrompt'u `_meta.systemPrompt.append` ister.
    let systemPromptViaMeta: Bool
    let installHint: String
    let installURL: String

    /// Buzz KNOWN_ACP_RUNTIMES + PRESET_HARNESSES'tan birebir argv'ler.
    static func spec(for provider: AIProvider) -> HarnessSpec? {
        switch provider {
        case .claudeCode:
            return HarnessSpec(
                provider: .claudeCode,
                command: "claude-agent-acp", args: [],
                underlyingCLI: "claude",
                systemPromptViaMeta: true,
                installHint: "npm install -g @agentclientprotocol/claude-agent-acp",
                installURL: "https://claude.ai/install.sh"
            )
        case .cursor:
            return HarnessSpec(
                provider: .cursor,
                command: "cursor-agent", args: ["acp"],
                underlyingCLI: nil,
                systemPromptViaMeta: false,
                installHint: "cursor.com/downloads → cursor-agent CLI",
                installURL: "https://cursor.com/downloads"
            )
        case .codex:
            // Codex CLI'ın kendisi ACP konuşmuyor (yalnız deneysel `app-server`).
            // Zed'in adaptörü aradaki köprü: kuruluysa ACP yolu (streaming +
            // araç olayları) açılır, değilse yerleşik CodexClient devrede kalır.
            return HarnessSpec(
                provider: .codex,
                command: "codex-acp", args: [],
                underlyingCLI: "codex",
                systemPromptViaMeta: false,
                installHint: "npm install -g @agentclientprotocol/codex-acp",
                installURL: "https://github.com/agentclientprotocol/codex-acp"
            )
        case .grok:
            return HarnessSpec(
                provider: .grok,
                command: "grok", args: ["agent", "--always-approve", "stdio"],
                underlyingCLI: nil,
                systemPromptViaMeta: false,
                installHint: "build.x.ai/docs → grok CLI",
                installURL: "https://build.x.ai/docs"
            )
        default:
            return nil
        }
    }
}

// MARK: - Binary çözümleme (Buzz resolve_command)

/// GUI uygulamaların PATH'i minimaldir — Buzz gibi login shell'e sorup yaygın
/// dizinleri tarıyoruz. Sonuçlar (negatifler dahil) süreç ömrünce cache'lenir;
/// "Tekrar tara" cache'i boşaltır.
enum HarnessResolver {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    /// Buzz common_binary_paths — macOS tarafı.
    private static let commonDirs = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
        NSHomeDirectory() + "/.local/bin",
        NSHomeDirectory() + "/.volta/bin",
        NSHomeDirectory() + "/.asdf/shims",
        NSHomeDirectory() + "/.bun/bin",
        NSHomeDirectory() + "/.npm-global/bin",
    ]

    static func invalidateCache() {
        lock.lock(); cache = [:]; lock.unlock()
    }

    /// Binariyi mutlak yola çözer; bulunamazsa nil.
    static func resolve(_ name: String) -> String? {
        lock.lock()
        if let hit = cache[name] { lock.unlock(); return hit }
        lock.unlock()

        var found: String? = nil
        // 1) Yaygın dizinler (ucuz).
        for dir in commonDirs {
            let candidate = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { found = candidate; break }
        }
        // 2) Login shell — nvm/mise gibi yalnız interaktif kabukta gelen PATH'ler.
        if found == nil {
            found = loginShellWhich(name)
        }

        lock.lock(); cache[name] = found; lock.unlock()
        return found
    }

    private static func loginShellWhich(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-l", "-c", "command -v \(name)"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Buzz classify_runtime: adapter → Ready; adapter yok ama CLI var →
    /// AdapterMissing; ikisi de yok → NotInstalled.
    /// ACP yolu bu sağlayıcı için gerçekten açık mı (adaptör binary'si var mı)?
    /// Codex'te ACP opsiyoneldir: yoksa yerleşik istemciye düşülür.
    static func isAvailable(_ provider: AIProvider) -> Bool {
        if case .ready = availability(of: provider) { return true }
        return false
    }

    static func availability(of provider: AIProvider) -> HarnessAvailability {
        guard let spec = HarnessSpec.spec(for: provider) else { return .notInstalled }
        if let bin = resolve(spec.command) { return .ready(binary: bin) }
        if let cli = spec.underlyingCLI, resolve(cli) != nil { return .adapterMissing(cli: cli) }
        return .notInstalled
    }
}

// MARK: - Ajan aktivite merkezi (Buzz ComposerActivityAccessory + tool_call akışı)

/// ACP `session/update` olaylarının UI'a akan canlı özeti: düşünme durumu +
/// araç çağrıları. Protokol değişikliği gerektirmesin diye AIClient sözleşmesinin
/// DIŞINDA, gözlemlenebilir bir merkez olarak durur (Buzz'da Tauri event'leriyle
/// aynı rol). ChatPageView composer üstündeki aktivite rayında gösterir.
@MainActor
@Observable
final class AgentActivityCenter {
    static let shared = AgentActivityCenter()

    struct ToolEvent: Identifiable, Equatable {
        let id: String
        var title: String
        var status: String   // pending / in_progress / completed / failed
    }

    private(set) var thinking = false
    private(set) var toolEvents: [ToolEvent] = []

    func beginTurn() {
        thinking = false
        toolEvents = []
    }

    func endTurn() {
        thinking = false
        toolEvents = []
    }

    func reportThought() {
        thinking = true
    }

    func reportTool(id: String, title: String, status: String) {
        thinking = false
        if let idx = toolEvents.firstIndex(where: { $0.id == id }) {
            toolEvents[idx].status = status
            if !title.isEmpty { toolEvents[idx].title = title }
        } else {
            toolEvents.append(ToolEvent(id: id, title: title, status: status))
            // Ray kısa kalsın — Buzz da tek satır aktivite gösterir.
            if toolEvents.count > 4 { toolEvents.removeFirst(toolEvents.count - 4) }
        }
    }

    func updateTool(id: String, status: String) {
        if let idx = toolEvents.firstIndex(where: { $0.id == id }) {
            toolEvents[idx].status = status
        }
    }
}

// MARK: - ACP istemcisi

enum AcpError: LocalizedError {
    case harnessUnavailable(HarnessAvailability, HarnessSpec)
    case agentExited(code: Int32, stderr: String)
    case agentError(code: Int, message: String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .harnessUnavailable(let availability, let spec):
            switch availability {
            case .adapterMissing:
                return "\(spec.provider.label) CLI'ı bulundu ama ACP adapter'ı eksik. Kurulum: \(spec.installHint)"
            default:
                return "\(spec.provider.label) CLI'ı bulunamadı. Kurulum: \(spec.installURL)"
            }
        case .agentExited(let code, let stderr):
            let tail = stderr.split(separator: "\n").suffix(3).joined(separator: " · ")
            return "Ajan beklenmedik şekilde kapandı (kod \(code)). \(tail)"
        case .agentError(let code, let message):
            return "Ajan hatası (\(code)): \(message)"
        case .protocolError(let message):
            return "ACP protokol hatası: \(message)"
        }
    }
}

/// Tek ACP turunu süren aktör: process + NDJSON okuma döngüsü + tek uçuşta bir
/// JSON-RPC isteği. (initialize → session/new → session/prompt sıralı gider;
/// paralel istek yok, o yüzden tek continuation yeter.)
private actor AcpTurn {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var nextID = 1
    private var pending: CheckedContinuation<[String: Any], Error>? = nil
    private var pendingID: Int? = nil
    private var sessionID: String? = nil
    private var onChunk: ((String) -> Void)? = nil
    private var buffer = Data()
    private var finished = false

    init(binary: String, args: [String], extraEnv: [String: String]) {
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        // Adapter'ların node/npm zinciri için PATH'i zenginleştir.
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.local/bin"
        env["PATH"] = extraPath + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        for (k, v) in extraEnv { env[k] = v }
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    }

    func start(onChunk: @escaping (String) -> Void) throws {
        self.onChunk = onChunk
        try process.run()
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            Task { await self.consume(data) }
        }
    }

    private func consume(_ data: Data) {
        guard !finished else { return }
        if data.isEmpty {
            // EOF — process öldü; bekleyen istek varsa hatayla düşür.
            failPending(with: exitError())
            return
        }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
            else { continue }
            route(obj)
        }
    }

    private func route(_ obj: [String: Any]) {
        let hasID = obj["id"] != nil
        let method = obj["method"] as? String

        if let method, hasID {
            // Ajan → istemci İSTEĞİ. İzinleri Buzz gibi otomatik onayla (allow_once).
            if method == "session/request_permission" {
                respondToPermission(obj)
            } else {
                // Bilinmeyen ters istek — boş sonuçla geçiştir (fs/terminal istemiyoruz).
                reply(id: obj["id"], result: [:])
            }
            return
        }
        if let method {
            // Bildirim — akış güncellemeleri (Buzz handle_session_update kümesi).
            if method == "session/update",
               let params = obj["params"] as? [String: Any],
               let update = params["update"] as? [String: Any],
               let kind = update["sessionUpdate"] as? String {
                switch kind {
                case "agent_message_chunk":
                    if let content = update["content"] as? [String: Any],
                       let text = content["text"] as? String {
                        onChunk?(text)
                    }
                case "agent_thought_chunk":
                    Task { @MainActor in AgentActivityCenter.shared.reportThought() }
                case "tool_call":
                    let id = (update["toolCallId"] as? String) ?? UUID().uuidString
                    let title = (update["title"] as? String) ?? (update["kind"] as? String) ?? "araç"
                    let status = (update["status"] as? String) ?? "in_progress"
                    Task { @MainActor in AgentActivityCenter.shared.reportTool(id: id, title: title, status: status) }
                case "tool_call_update":
                    if let id = update["toolCallId"] as? String {
                        let status = (update["status"] as? String) ?? "completed"
                        Task { @MainActor in AgentActivityCenter.shared.updateTool(id: id, status: status) }
                    }
                default:
                    break
                }
            }
            return
        }
        if hasID {
            // Bizim isteğimizin yanıtı.
            guard let id = obj["id"] as? Int, id == pendingID else { return }
            let continuation = pending
            pending = nil; pendingID = nil
            if let errObj = obj["error"] as? [String: Any] {
                let code = errObj["code"] as? Int ?? -1
                let message = errObj["message"] as? String ?? "bilinmeyen"
                continuation?.resume(throwing: AcpError.agentError(code: code, message: message))
            } else {
                continuation?.resume(returning: (obj["result"] as? [String: Any]) ?? [:])
            }
        }
    }

    private func respondToPermission(_ obj: [String: Any]) {
        // options içinden kind == allow_once olanı seç; yoksa ilkini.
        var optionID: String? = nil
        if let params = obj["params"] as? [String: Any],
           let options = params["options"] as? [[String: Any]] {
            optionID = (options.first { ($0["kind"] as? String) == "allow_once" } ?? options.first)?["optionId"] as? String
        }
        let outcome: [String: Any] = optionID.map {
            ["outcome": ["outcome": "selected", "optionId": $0]]
        } ?? ["outcome": ["outcome": "cancelled"]]
        reply(id: obj["id"], result: outcome)
    }

    private func reply(id: Any?, result: [String: Any]) {
        guard let id else { return }
        writeLine(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func writeLine(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        var payload = data
        payload.append(0x0A)
        try? stdinPipe.fileHandleForWriting.write(contentsOf: payload)
    }

    /// Tek uçuşluk JSON-RPC isteği — yanıt gelene dek bekler.
    func request(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            pendingID = id
            writeLine(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        }
    }

    func notify(_ method: String, params: [String: Any]) {
        writeLine(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func failPending(with error: Error) {
        let continuation = pending
        pending = nil; pendingID = nil
        continuation?.resume(throwing: error)
    }

    private func exitError() -> AcpError {
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return .agentExited(code: process.isRunning ? -1 : process.terminationStatus, stderr: stderr)
    }

    // MARK: Tur akışı

    func handshake(systemPrompt: String, viaMeta: Bool) async throws {
        _ = try await request("initialize", params: [
            "protocolVersion": 2,
            "clientCapabilities": [:],
            "clientInfo": ["name": "Hercules", "version": "1.0"],
        ])
        var params: [String: Any] = [
            "cwd": NSHomeDirectory(),
            "mcpServers": [] as [Any],
        ]
        if viaMeta {
            params["_meta"] = ["systemPrompt": ["append": systemPrompt]]
        } else {
            params["systemPrompt"] = systemPrompt
        }
        let result = try await request("session/new", params: params)
        guard let sid = result["sessionId"] as? String else {
            throw AcpError.protocolError("session/new sessionId dönmedi")
        }
        sessionID = sid
    }

    /// Özel model seçildiyse dene; başarısızlık sessizce yutulur (CLI varsayılanında kalınır).
    func applyModelIfNeeded(_ model: String) async {
        guard let sessionID, model != "varsayılan", !model.isEmpty else { return }
        _ = try? await request("session/set_model", params: ["sessionId": sessionID, "modelId": model])
    }

    func prompt(_ text: String) async throws -> String {
        guard let sessionID else { throw AcpError.protocolError("session yok") }
        let result = try await request("session/prompt", params: [
            "sessionId": sessionID,
            "prompt": [["type": "text", "text": text]],
        ])
        let stop = (result["stopReason"] as? String)?.lowercased() ?? "end_turn"
        if stop == "refusal" { throw AcpError.protocolError("ajan yanıtı reddetti") }
        return stop
    }

    func cancelAndKill() {
        finished = true
        if let sessionID { notify("session/cancel", params: ["sessionId": sessionID]) }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        failPending(with: CancellationError())
    }

    func shutdown() {
        finished = true
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}

/// AIClient — ACP harness'ı üzerinden. Her `send`/`complete` turu taze process
/// açar: sözleşme stateless, geçmiş her çağrıda geliyor; transkript prompt'a
/// gömülür, kalıcı bağlam session/new'daki systemPrompt ile gider.
final class AcpAgentClient: AIClient {
    private let provider: AIProvider

    init(provider: AIProvider) {
        self.provider = provider
    }

    func send(
        history: [ChatTurn],
        newUserText: String,
        userContext: String?,
        images: [Data],
        onSearchStart: @MainActor @escaping (String) -> Void,
        onMessageUpdate: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, AIWebSearchEvidence?) {
        // Görseller ACP metin bloklarıyla taşınmıyor — capability farkını dürüstçe bildir.
        var prompt = Self.transcriptPrompt(history: history, userContext: userContext, newUserText: newUserText)
        if !images.isEmpty {
            prompt += "\n\n[Not: kullanıcı \(images.count) görsel ekledi ama bu sağlayıcı görsel almıyor; görselleri değerlendiremediğini belirt.]"
        }
        let text = try await runTurn(systemPrompt: AIConfig.systemPrompt, prompt: prompt, onChunk: onMessageUpdate)
        return (AIModelIngress.sanitized(Self.parseFood(text), searchEvidence: nil), nil)
    }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        try await runTurn(systemPrompt: systemPrompt, prompt: userPrompt, onChunk: { _ in })
    }

    func completeJSON(
        systemPrompt: String,
        userPrompt: String,
        schemaName: String,
        schemaJSON: String
    ) async throws -> String {
        // Harness'ta native structured output yok — şemayı prompt'a göm.
        let framed = systemPrompt + "\n\nYANIT ŞEMASI (yalnız bu şemaya uyan TEK bir JSON döndür, başka metin yazma):\n" + schemaJSON
        return try await complete(systemPrompt: framed, userPrompt: userPrompt)
    }

    // MARK: İç akış

    private func runTurn(
        systemPrompt: String,
        prompt: String,
        onChunk: @MainActor @escaping (String) -> Void
    ) async throws -> String {
        guard let spec = HarnessSpec.spec(for: provider) else {
            throw AcpError.protocolError("harness tanımı yok: \(provider.rawValue)")
        }
        let availability = HarnessResolver.availability(of: provider)
        guard case .ready(let binary) = availability else {
            throw AcpError.harnessUnavailable(availability, spec)
        }

        var extraEnv: [String: String] = [:]
        if spec.provider == .claudeCode, let cli = spec.underlyingCLI,
           let cliPath = HarnessResolver.resolve(cli) {
            // Adapter vendor CLI'ını bu env'den bulur (Buzz runtime.rs:376).
            extraEnv["CLAUDE_CODE_EXECUTABLE"] = cliPath
        }

        let turn = AcpTurn(binary: binary, args: spec.args, extraEnv: extraEnv)
        // Kümülatif metin — AIClient sözleşmesi delta değil TAM metin bekler.
        let accumulated = OSAllocatedUnfairLockedText()

        await AgentActivityCenter.shared.beginTurn()
        defer { Task { @MainActor in AgentActivityCenter.shared.endTurn() } }
        return try await withTaskCancellationHandler {
            try await turn.start { chunk in
                let full = accumulated.append(chunk)
                Task { @MainActor in onChunk(full) }
            }
            try await turn.handshake(systemPrompt: systemPrompt, viaMeta: spec.systemPromptViaMeta)
            await turn.applyModelIfNeeded(AIKeyStore.shared.model(for: provider))
            _ = try await turn.prompt(prompt)
            await turn.shutdown()
            return accumulated.value
        } onCancel: {
            Task { await turn.cancelAndKill() }
        }
    }

    private static func transcriptPrompt(history: [ChatTurn], userContext: String?, newUserText: String) -> String {
        var parts: [String] = []
        if let userContext, !userContext.isEmpty {
            parts.append("[Kullanıcı verisi]\n" + userContext)
        }
        let past = history.suffix(30)
        if !past.isEmpty {
            let coach = CoachIdentity.name
            let lines = past.map { turn in
                (turn.role == .user ? "Kullanıcı: " : "\(coach): ") + turn.text
            }
            parts.append("[Önceki konuşma]\n" + lines.joined(separator: "\n"))
        }
        parts.append("[Yeni mesaj]\n" + newUserText)
        return parts.joined(separator: "\n\n")
    }

    /// CodexClient.parseFood ile aynı sözleşme: çit temizle → AIFoodResult decode →
    /// olmadıysa düz mesaj.
    private static func parseFood(_ content: String) -> AIFoodResult {
        var stripped = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("```") {
            let lines = stripped.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 2 {
                stripped = lines.dropFirst().dropLast(lines.last?.hasPrefix("```") == true ? 1 : 0)
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let data = stripped.data(using: .utf8),
           let result = try? JSONDecoder().decode(AIFoodResult.self, from: data) {
            return result
        }
        return AIFoodResult(message: stripped)
    }
}

/// Ufak kilitli metin biriktirici — chunk'lar arka plan kuyruğundan gelir.
private final class OSAllocatedUnfairLockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ chunk: String) -> String {
        lock.lock(); defer { lock.unlock() }
        text += chunk
        return text
    }

    var value: String {
        lock.lock(); defer { lock.unlock() }
        return text
    }
}

#endif
