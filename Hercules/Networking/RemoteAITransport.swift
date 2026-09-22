import Foundation
#if os(macOS)
import HerculesIslandBridge
#endif

struct RemoteAIChatRequest: Codable, Sendable {
    var history: [ChatTurn]
    var newUserText: String
    var userContext: String?
    var images: [Data]
    /// Telefonun yazdığı konuşma. Verilirse Mac turu O kanala ekler; boşsa yeni
    /// konuşma açar. Eski istemciler bu alanı göndermez (opsiyonel → uyumlu).
    var conversationID: UUID?
}

struct RemoteAIChatResponse: Codable, Sendable {
    var result: AIFoodResult
    var searchQuery: String?
    var searchEvidence: AIWebSearchEvidence?
    var provider: String
    var model: String
    /// Turun yazıldığı konuşma — telefon bir sonraki mesajı buraya ekler.
    var conversationID: UUID?
}

/// Mac'in kimliği: koç adı, profil ve koç fotoğrafları. Telefonda ayrı bir
/// özelleştirme YOK — ne Mac'te seçildiyse telefon onu gösterir.
struct RemoteAIIdentityResponse: Codable, Sendable {
    var coachName: String
    var profileAvatar: Data?
    var coachAvatar: Data?
    /// İçeriğin parmak izi; değişmediyse telefon diske tekrar yazmaz.
    var signature: String
}

/// Eşleştirme durumu — onaysız telefonun görebildiği tek cevap.
struct RemoteAIIrohPairResponse: Codable, Sendable {
    var endpointId: String
    var paired: Bool
    var pending: Bool
}

/// Mac'in kanalının tam aynası. Telefon kendi kopyasını tutmaz; bunu aynalar.
struct RemoteAIChatHistoryResponse: Codable, Sendable {
    var conversations: [ChatConversation]
    var currentConversationID: UUID?
    var savedAt: Date
}

struct RemoteAICompletionRequest: Codable, Sendable {
    var systemPrompt: String
    var userPrompt: String
    var images: [Data]
    var mode: RemoteAICompletionMode?
    var webSearch: RemoteAIWebSearchPolicy?
    /// Web source/sink yetkisinin tek kaynağı olan gerçek son kullanıcı metni. Birleşik
    /// prompttan sunucuda tekrar çıkarılmaz.
    var webAuthorizationText: String?
}

enum RemoteAICompletionMode: String, Codable, Sendable {
    case utility
    case conversation
}

enum RemoteAIWebSearchPolicy: String, Codable, Sendable {
    case disabled
    case auto
    case required
}

struct RemoteAICompletionResponse: Codable, Sendable {
    var text: String
    var provider: String
    var model: String
}

struct RemoteAIHealthResponse: Codable, Sendable {
    var status: String
    var service: String
    var provider: String
    var model: String
    var serverTime: Date
}

private struct RemoteAIErrorResponse: Codable {
    var error: String
}

enum RemoteAIClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Koç bağlantı adresi geçersiz."
        case .invalidResponse:
            return "Koç geçerli bir yanıt vermedi."
        case .server(let status, let message):
            return "Koç HTTP \(status): \(message)"
        }
    }
}

/// iPhone'daki bütün standart Hercules AI çağrılarını, Tailscale HTTPS üzerinden
/// Mac'te çalışan yerel Hercules AI sunucusuna taşır. Telefonda API anahtarı tutulmaz.
final class RemoteAIClient: AIClient {
    static let defaultBaseURL = "https://cans-mac-studio.tailbf8b4c.ts.net/hercules-ai"

    private let session: URLSession
    private let baseURL: URL?

    /// TEK paylaşılan session: çağıranlar her işlem için yeni `RemoteAIClient()`
    /// kuruyor; instance başına ephemeral session açmak bağlantı havuzunu ve TLS
    /// session cache'ini her seferinde sıfırlayıp her mesaja tam TCP+TLS el
    /// sıkışması (tünel üzerinden yüzlerce ms) ekliyordu.
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Tailscale kapalıyken 15 dakika bağlantı bekleyip arayüzü spinner'da bırakma.
        // Health hızlı düşer; gerçek Koç isteğine modelin düşünmesi için yeterli süre kalır.
        configuration.timeoutIntervalForRequest = 150
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    init(baseURL: URL? = RemoteAIClient.configuredBaseURL, session: URLSession? = nil) {
        self.session = session ?? Self.sharedSession
        self.baseURL = baseURL
    }

    static var configuredBaseURL: URL? {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "HERCULES_AI_BASE") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: configured?.isEmpty == false ? configured! : defaultBaseURL)
    }

    func health() async throws -> RemoteAIHealthResponse {
        let (data, response) = try await request(path: "health", method: "GET", body: nil)
        try Self.validate(response: response, data: data)
        return try JSONDecoder.remoteAI.decode(RemoteAIHealthResponse.self, from: data)
    }

    func send(
        history: [ChatTurn],
        newUserText: String,
        userContext: String?,
        images: [Data],
        onSearchStart: @MainActor @escaping (String) -> Void,
        onMessageUpdate: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, AIWebSearchEvidence?) {
        let payload = RemoteAIChatRequest(
            history: history,
            newUserText: newUserText,
            userContext: userContext,
            images: images
        )
        let body = try JSONEncoder.remoteAI.encode(payload)
        let (data, response) = try await request(path: "v1/chat", method: "POST", body: body)
        try Self.validate(response: response, data: data)
        let decoded = try JSONDecoder.remoteAI.decode(RemoteAIChatResponse.self, from: data)
        let evidence = decoded.searchEvidence ?? decoded.searchQuery.map {
            AIWebSearchEvidence(query: $0, completedSuccessfully: false, sourceURLs: [])
        }
        if let search = evidence?.query { await onSearchStart(search) }
        let result = AIModelIngress.sanitized(decoded.result, searchEvidence: evidence)
        await onMessageUpdate(result.message)
        return (result, evidence)
    }

    /// Kanal senkronlu gönderim: Mac turu KENDİ kanalına yazar ve konuşma
    /// id'sini geri verir. Telefon böylece Mac'in geçmişini aynalar, ayrı bir
    /// kopya biriktirmez. `nil` dönerse Mac o an akıştaydı ve yazamadı.
    func sendInChannel(
        conversationID: UUID?,
        history: [ChatTurn],
        newUserText: String,
        userContext: String?,
        images: [Data]
    ) async throws -> (AIFoodResult, AIWebSearchEvidence?, UUID?) {
        let payload = RemoteAIChatRequest(
            history: history,
            newUserText: newUserText,
            userContext: userContext,
            images: images,
            conversationID: conversationID
        )
        let body = try JSONEncoder.remoteAI.encode(payload)
        let (data, response) = try await request(path: "v1/chat", method: "POST", body: body)
        try Self.validate(response: response, data: data)
        let decoded = try JSONDecoder.remoteAI.decode(RemoteAIChatResponse.self, from: data)
        let evidence = decoded.searchEvidence ?? decoded.searchQuery.map {
            AIWebSearchEvidence(query: $0, completedSuccessfully: false, sourceURLs: [])
        }
        let result = AIModelIngress.sanitized(decoded.result, searchEvidence: evidence)
        return (result, evidence, decoded.conversationID)
    }

    /// Eşleştirme durumu. Onaysızken çalışan TEK uç budur.
    func irohPairStatus() async throws -> RemoteAIIrohPairResponse {
        let (data, response) = try await request(path: "v1/iroh/pair", method: "GET", body: nil)
        try Self.validate(response: response, data: data)
        return try JSONDecoder.remoteAI.decode(RemoteAIIrohPairResponse.self, from: data)
    }

    /// Mac'in koç adı + avatarları.
    func identity() async throws -> RemoteAIIdentityResponse {
        let (data, response) = try await request(path: "v1/identity", method: "GET", body: nil)
        try Self.validate(response: response, data: data)
        return try JSONDecoder.remoteAI.decode(RemoteAIIdentityResponse.self, from: data)
    }

    /// Mac'in kanalının tam aynası.
    func chatHistory() async throws -> RemoteAIChatHistoryResponse {
        let (data, response) = try await request(path: "v1/chat/history", method: "GET", body: nil)
        try Self.validate(response: response, data: data)
        return try JSONDecoder.remoteAI.decode(RemoteAIChatHistoryResponse.self, from: data)
    }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt, images: [])
    }

    func complete(systemPrompt: String, userPrompt: String, images: [Data]) async throws -> String {
        try await complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images,
            mode: .utility,
            webSearch: .disabled,
            webAuthorizationText: nil
        )
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        images: [Data],
        mode: RemoteAICompletionMode,
        webSearch: RemoteAIWebSearchPolicy,
        webAuthorizationText: String?
    ) async throws -> String {
        let payload = RemoteAICompletionRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images,
            mode: mode,
            webSearch: webSearch,
            webAuthorizationText: webAuthorizationText
        )
        let body = try JSONEncoder.remoteAI.encode(payload)
        let (data, response) = try await request(path: "v1/complete", method: "POST", body: body)
        try Self.validate(response: response, data: data)
        return try JSONDecoder.remoteAI.decode(RemoteAICompletionResponse.self, from: data).text
    }

    private func request(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        let timeout: TimeInterval = method == "GET" ? 6 : 150
        // baseURL yoksa bile iroh yolu çalışabilir: eşleştirme QR'dan gelir,
        // Tailscale adresine hiç ihtiyaç duymaz.
        let url = (baseURL ?? URL(string: "http://hercules.local")!).appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        #if os(iOS)
        // ÖNCE IROH: telefonda VPN profili gerektirmeyen doğrudan QUIC yolu.
        // Tutmazsa sessizce Tailscale'e düşeriz — kullanıcı fark etmez, ama
        // `lastPathWasIroh` göstergesi hangi yoldan gidildiğini söyler.
        if HerculesIrohTransport.isAvailable {
            do {
                return try await HerculesIrohTransport.shared.perform(request, timeout: timeout)
            } catch {
                HerculesIrohTransport.noteFallback()
            }
        }
        #endif

        guard baseURL != nil else { throw RemoteAIClientError.invalidBaseURL }
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else {
            throw RemoteAIClientError.invalidResponse
        }
        return (data, response)
    }

    private static func validate(response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let decoded = try? JSONDecoder.remoteAI.decode(RemoteAIErrorResponse.self, from: data)
            let fallback = String(data: data, encoding: .utf8) ?? "Bilinmeyen sunucu hatası"
            throw RemoteAIClientError.server(response.statusCode, decoded?.error ?? fallback)
        }
    }
}

// `static let`: computed var her erişimde (her decode/encode/sendJSON'da)
// yeni coder alloc ediyordu. JSONEncoder/Decoder yapılandırma-sonrası thread-safe.
private extension JSONEncoder {
    static let remoteAI: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let remoteAI: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

#if os(macOS)
import Network
import SwiftData

struct RemoteAIConfiguration: Equatable, Sendable {
    var enabled: Bool
    var allowedUsers: Set<String>
    var dnsName: String?

    static let disabled = RemoteAIConfiguration(enabled: false, allowedUsers: [], dnsName: nil)

    static var fileURL: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return support
            .appendingPathComponent("Hercules", isDirectory: true)
            .appendingPathComponent("remote-ai.plist")
    }

    static func load() -> RemoteAIConfiguration {
        guard let url = fileURL,
              let plist = NSDictionary(contentsOf: url) as? [String: Any]
        else { return .disabled }

        let users = (plist["AllowedUsers"] as? [String] ?? [])
            .map(normalizeUser)
            .filter { !$0.isEmpty }
        return RemoteAIConfiguration(
            enabled: plist["Enabled"] as? Bool ?? false,
            allowedUsers: Set(users),
            dnsName: (plist["DNSName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func normalizeUser(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Iroh ile eşleştirilmiş telefon anahtarları. Relay ve uygulama AYNI dosyayı
/// okur; uygulama yazar, relay ve yetki katmanı yalnız okur.
enum IrohPairedPeers {
    struct Payload: Codable {
        var paired: [String] = []
        /// Bağlanmayı deneyen ama henüz onaylanmamış uçlar (relay yazar).
        var pending: [String] = []
    }

    static var url: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Hercules", isDirectory: true)
            .appendingPathComponent("iroh-peers.json")
    }

    /// Her istekte diskten okunur: uygulamadan bir telefon onaylanınca relay'i
    /// yeniden başlatmak gerekmesin.
    static func load() -> Payload {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return Payload() }
        return payload
    }

    static func contains(_ endpointID: String) -> Bool {
        load().paired.contains(endpointID)
    }

    static func save(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func pair(_ endpointID: String) {
        let clean = endpointID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.count == 64, clean.allSatisfy(\.isHexDigit) else { return }
        var payload = load()
        payload.pending.removeAll { $0 == clean }
        guard !payload.paired.contains(clean) else { save(payload); return }
        payload.paired.append(clean)
        save(payload)
    }

    static func reject(_ endpointID: String) {
        var payload = load()
        payload.pending.removeAll { $0 == endpointID }
        save(payload)
    }

    static func revoke(_ endpointID: String) {
        var payload = load()
        payload.paired.removeAll { $0 == endpointID }
        payload.pending.removeAll { $0 == endpointID }
        save(payload)
    }

    /// Relay'in yayınladığı Mac kimliği + ticket (QR bunu taşır).
    struct Published: Codable {
        var endpointId: String
        var ticket: String
        var updatedAt: String
    }

    static var publishedURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("iroh-endpoint.json")
    }

    static func published() -> Published? {
        guard let data = try? Data(contentsOf: publishedURL) else { return nil }
        return try? JSONDecoder().decode(Published.self, from: data)
    }
}

enum RemoteAIRequestAccess: Equatable {
    case local
    case remote(user: String)
    case denied(String)

    static func authorize(
        headers rawHeaders: [String: String],
        configuration: RemoteAIConfiguration
    ) -> RemoteAIRequestAccess {
        let headers = Dictionary(uniqueKeysWithValues: rawHeaders.map { ($0.key.lowercased(), $0.value) })
        let host = headers["host"]?.lowercased() ?? ""

        // IROH YOLU: kimlik bir e-posta değil kriptografik anahtardır ve bu
        // başlığı isteğe RELAY yazar — QUIC handshake'inde doğruladıktan sonra.
        // Relay, istemcinin gönderdiği aynı adlı başlığı atar, yani buraya gelen
        // değer taklit edilemez. Yetkiyi `allowedUsers` değil eşleştirme listesi
        // (iroh-peers.json) verir; oraya yazma yetkisi yalnız uygulamadadır.
        if let peer = headers["x-hercules-iroh-endpoint"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !peer.isEmpty {
            guard configuration.enabled else {
                return .denied("Hercules uzaktan AI erişimi kapalı.")
            }
            guard IrohPairedPeers.contains(peer) else {
                return .denied("Bu telefon bu Mac ile eşleşmemiş.")
            }
            return .remote(user: "iroh:\(peer)")
        }

        let identity = headers["tailscale-user-login"]
            ?? headers["tailscale-user-name"]
            ?? headers["x-tailscale-user-login"]
        let hasRemoteHint = host.contains(".ts.net")
            || identity != nil
            || headers["x-forwarded-for"] != nil
            || headers["x-forwarded-proto"]?.lowercased() == "https"

        guard hasRemoteHint else { return .local }
        guard configuration.enabled else {
            return .denied("Hercules uzaktan AI erişimi kapalı.")
        }
        guard let identity else {
            return .denied("Tailscale kullanıcı kimliği bulunamadı.")
        }
        let user = RemoteAIConfiguration.normalizeUser(identity)
        guard configuration.allowedUsers.contains(user) else {
            return .denied("Bu Tailscale kullanıcısına izin verilmemiş.")
        }
        return .remote(user: user)
    }
}

private struct RemoteAIHTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

/// `NWConnection` yaşam döngüsünü structured-concurrency işine bağlar. Bağlantı cevap
/// teslim edilmeden kapanırsa model çağrısı ve onu izleyen memory side-effect'i iptal edilir.
private final class RemoteAIWorkCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: Task<Void, Never>?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func clear() {
        lock.lock()
        task = nil
        lock.unlock()
    }
}

/// Mac uygulamasının içinde çalışan minimal HTTP sunucusu. Yalnız loopback'e
/// bind olur; TLS ve cihaz kimliği Tailscale Serve tarafından sağlanır.
final class RemoteAIServer {
    static let shared = RemoteAIServer()
    static let port: NWEndpoint.Port = 8765

    private let queue = DispatchQueue(label: "com.samorai.hercules.remote-ai")
    private let workLock = NSLock()
    private var listener: NWListener?
    private var context: ModelContext?
    private var busy = false
    private var pendingIslandFoods: [UUID: PendingIslandFood] = [:]

    private struct PendingIslandFood {
        var food: HerculesIslandFoodCandidate
        var expiresAt: Date
        var saved = false
    }

    private init() {}

    @MainActor
    func start(context: ModelContext) {
        self.context = context
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("Hercules Remote AI listener failed: %@", error.localizedDescription)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            NSLog("Hercules Remote AI could not start: %@", error.localizedDescription)
        }
    }

    /// Gövde biriktirme tamponu — referans tip. Değer tipli `Data`'yı closure'a
    /// parametre olarak taşımak her chunk'ta buffer'ın TAMAMINI kopyalıyordu
    /// (closure eski kopyayı tuttuğu için append hiçbir zaman in-place olamıyordu):
    /// 12 MB'lık bir görsel yüklemesinde yüzlerce MB memcpy demekti.
    private final class ReceiveBuffer {
        var data = Data()
    }

    private func accept(_ connection: NWConnection) {
        // İptal köprüsü BAĞLANTI başına ve start()'tan ÖNCE kurulur: handler
        // route()'ta sonradan takılınca, gövde yüklenirken kopan istemciler
        // hiç görülmüyor ve iş ölü sokete karşı çalışmaya devam ediyordu.
        // (Sunucu her cevaptan sonra bağlantıyı kapattığı için bağlantı = istek.)
        let cancellation = RemoteAIWorkCancellation()
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed(_), .cancelled:
                cancellation.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: ReceiveBuffer(), cancellation: cancellation)
    }

    private func receive(
        on connection: NWConnection,
        buffer: ReceiveBuffer,
        cancellation: RemoteAIWorkCancellation
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            if let data { buffer.data.append(data) }
            if buffer.data.count > 12 * 1024 * 1024 {
                self.sendError(status: 413, message: "İstek gövdesi çok büyük.", on: connection)
                return
            }
            if let request = Self.parseRequest(buffer.data) {
                self.route(request, on: connection, cancellation: cancellation)
            } else if isComplete || error != nil {
                self.sendError(status: 400, message: "Eksik veya geçersiz HTTP isteği.", on: connection)
            } else {
                self.receive(on: connection, buffer: buffer, cancellation: cancellation)
            }
        }
    }

    private static func parseRequest(_ data: Data) -> RemoteAIHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        guard let length = Int(headers["content-length"] ?? "0"),
              length >= 0,
              length <= 12 * 1024 * 1024
        else { return nil }
        let bodyStart = headerRange.upperBound
        // `bodyStart + length` overflow etmesin; önce kalan byte üzerinden doğrula.
        guard bodyStart <= data.count, length <= data.count - bodyStart else { return nil }
        let body = length > 0 ? Data(data[bodyStart..<(bodyStart + length)]) : Data()
        return RemoteAIHTTPRequest(method: parts[0].uppercased(), path: parts[1], headers: headers, body: body)
    }

    private func route(
        _ request: RemoteAIHTTPRequest,
        on connection: NWConnection,
        cancellation: RemoteAIWorkCancellation
    ) {
        let access = RemoteAIRequestAccess.authorize(
            headers: request.headers,
            configuration: RemoteAIConfiguration.load()
        )
        if case .denied(let reason) = access {
            sendError(status: 403, message: reason, on: connection)
            return
        }

        let path = normalizedPath(request.path)
        if request.method == "GET", path == "/health" {
            let store = AIKeyStore.shared
            sendJSON(
                RemoteAIHealthResponse(
                    status: "ok",
                    service: "Hercules Remote AI",
                    provider: store.provider.label,
                    model: store.model,
                    serverTime: .now
                ),
                on: connection
            )
            return
        }

        // Eşleştirme yolu: relay onaysız uçların YALNIZ buraya gelmesine izin
        // verir. Burada hiçbir veri yoktur — telefon "beni gördün mü, onaylandım
        // mı" diye sorar; onay Mac'te elle verilir.
        if request.method == "GET", path == "/v1/iroh/pair" {
            let peer = request.headers.first { $0.key.lowercased() == "x-hercules-iroh-endpoint" }?.value ?? ""
            let clean = peer.trimmingCharacters(in: .whitespacesAndNewlines)
            let state = IrohPairedPeers.load()
            sendJSON(
                RemoteAIIrohPairResponse(
                    endpointId: clean,
                    paired: state.paired.contains(clean),
                    pending: state.pending.contains(clean)
                ),
                on: connection
            )
            return
        }

        if request.method == "GET", path == "/v1/identity" {
            Task { @MainActor [weak self] in
                guard let self else { connection.cancel(); return }
                self.sendJSON(Self.identityPayload(), on: connection)
            }
            return
        }

        if request.method == "GET", path == "/v1/chat/history" {
            Task { @MainActor [weak self] in
                guard let self else { connection.cancel(); return }
                let snapshot = ChatStore.shared.remoteHistorySnapshot()
                self.sendJSON(
                    RemoteAIChatHistoryResponse(
                        conversations: snapshot.conversations,
                        currentConversationID: snapshot.currentID,
                        savedAt: .now
                    ),
                    on: connection
                )
            }
            return
        }

        if request.method == "GET", path == "/v1/island/status" {
            Task { @MainActor [weak self] in
                guard let self else { connection.cancel(); return }
                do {
                    self.sendJSON(try self.islandStatus(), on: connection)
                } catch {
                    self.sendError(status: 500, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        let postPaths: Set<String> = [
            "/v1/chat",
            "/v1/complete",
            "/v1/island/chat",
            "/v1/island/food",
            "/v1/island/weight"
        ]
        guard request.method == "POST", postPaths.contains(path) else {
            sendError(status: 404, message: "Endpoint bulunamadı.", on: connection)
            return
        }
        guard beginWork() else {
            sendError(status: 429, message: "Koç şu anda başka bir isteği işliyor.", on: connection)
            return
        }

        // Handler accept()'te kuruldu; burada yeniden kurulmaz. defer'da nil'lemek de
        // yok: MainActor'dan connection state'ini yazmak NW kuyruğuyla yarışıyordu —
        // clear() sonrası geç gelen cancel() zaten no-op.
        let processingTask = Task { @MainActor [weak self] in
            guard let self else { connection.cancel(); return }
            defer {
                cancellation.clear()
                self.finishWork()
            }
            do {
                try Task.checkCancellation()
                guard !cancellation.isCancelled else { throw CancellationError() }
                if path == "/v1/chat" {
                    let payload = try await Self.decodeOffMain(RemoteAIChatRequest.self, from: request.body)
                    try self.validate(payload)
                    let response = try await self.processChat(payload)
                    try Task.checkCancellation()
                    guard !cancellation.isCancelled else { throw CancellationError() }
                    try await self.sendJSONAwaitingDelivery(response, on: connection)
                    // Memory ancak yanıt gerçekten sokete teslim edildikten sonra başlar.
                    // Teslimden önce disconnect/cancel olmuş istek hiçbir kalıcı iz bırakamaz.
                    try Task.checkCancellation()
                    guard !cancellation.isCancelled else { throw CancellationError() }
                    if !payload.newUserText.contains("MOBIL YEMEK HESAPLAMA KARTI") {
                        AgentRouter.shared.absorbConversation(
                            userText: payload.newUserText,
                            assistantText: response.result.message
                        )
                    }
                    connection.cancel()
                } else if path == "/v1/complete" {
                    let payload = try await Self.decodeOffMain(RemoteAICompletionRequest.self, from: request.body)
                    try self.validate(payload)
                    let response = try await self.processCompletion(payload)
                    try Task.checkCancellation()
                    guard !cancellation.isCancelled else { throw CancellationError() }
                    try await self.sendJSONAwaitingDelivery(response, on: connection)
                    connection.cancel()
                } else if path == "/v1/island/chat" {
                    let payload = try await Self.decodeOffMain(
                        HerculesIslandChatRequest.self,
                        from: request.body
                    )
                    let response = try await self.processIslandChat(payload)
                    try Task.checkCancellation()
                    guard !cancellation.isCancelled else { throw CancellationError() }
                    try await self.sendJSONAwaitingDelivery(response, on: connection)
                    try Task.checkCancellation()
                    guard !cancellation.isCancelled else { throw CancellationError() }
                    AgentRouter.shared.absorbConversation(
                        userText: payload.text,
                        assistantText: response.reply
                    )
                    connection.cancel()
                } else if path == "/v1/island/food" {
                    let payload = try await Self.decodeOffMain(
                        HerculesIslandFoodSaveRequest.self,
                        from: request.body
                    )
                    let response = try self.saveIslandFood(payload)
                    try await self.sendJSONAwaitingDelivery(response, on: connection)
                    connection.cancel()
                } else {
                    let payload = try await Self.decodeOffMain(
                        HerculesIslandWeightSaveRequest.self,
                        from: request.body
                    )
                    let response = try self.saveIslandWeight(payload)
                    try await self.sendJSONAwaitingDelivery(response, on: connection)
                    connection.cancel()
                }
            } catch let error where Task.isCancelled
                || cancellation.isCancelled
                || error is CancellationError
                || (error as? URLError)?.code == .cancelled {
                connection.cancel()
            } catch let RemoteAIClientError.server(status, message) {
                self.sendError(status: status, message: message, on: connection)
            } catch is DecodingError {
                self.sendError(status: 400, message: "İstek gövdesi geçersiz.", on: connection)
            } catch {
                self.sendError(status: 500, message: error.localizedDescription, on: connection)
            }
        }
        cancellation.attach(processingTask)
    }

    /// İstek gövdesini MainActor DIŞINDA çöz: 10 MB'a varan base64 görsel JSON'ını
    /// ana thread'de parse etmek her telefon isteğinde Mac arayüzünü takıltıyordu.
    private static func decodeOffMain<T: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try JSONDecoder.remoteAI.decode(T.self, from: data)
        }.value
    }

    private func normalizedPath(_ rawPath: String) -> String {
        let noQuery = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        if noQuery == "/hercules-ai" { return "/" }
        if noQuery.hasPrefix("/hercules-ai/") {
            return String(noQuery.dropFirst("/hercules-ai".count))
        }
        return noQuery
    }

    @MainActor
    /// Avatarlar tam çözünürlük gönderilmez: telefon 256px'te gösteriyor,
    /// dosya megabaytlarca olabiliyor.
    private static func identityPayload() -> RemoteAIIdentityResponse {
        func compact(_ raw: Data?) -> Data? {
            guard let raw else { return nil }
            return ChatImageStore.downscaledJPEG(from: raw, maxPixel: 512, quality: 0.85) ?? raw
        }
        let profile = compact(ProfileAvatarStore.data())
        let coach = compact(CoachAvatarStore.data())
        let name = CoachIdentity.name
        var hasher = Hasher()
        hasher.combine(name)
        hasher.combine(profile?.count ?? 0)
        hasher.combine(coach?.count ?? 0)
        hasher.combine(profile?.prefix(64))
        hasher.combine(coach?.prefix(64))
        return RemoteAIIdentityResponse(
            coachName: name,
            profileAvatar: profile,
            coachAvatar: coach,
            signature: String(hasher.finalize())
        )
    }

    private func processChat(_ request: RemoteAIChatRequest) async throws -> RemoteAIChatResponse {
        try Task.checkCancellation()
        guard let context else { throw RemoteAIClientError.server(503, "Veri katmanı hazır değil.") }
        let mentions = UserContextSnapshot.parseMentions(request.newUserText)
        let allMentions = mentions.union(UserContextSnapshot.aboutMentionTags(ctx: context))
        let appContext = UserContextSnapshot.coachContext(
            for: request.newUserText,
            explicitTags: mentions,
            ctx: context
        )
        let scope = AgentDataScope.infer(query: request.newUserText, explicitTags: allMentions)
        let data = AgentDataSnapshot.make(ctx: context, scope: scope)
        let skillContext = await AgentRouter.shared.buildSkillContext(
            query: request.newUserText,
            appContext: appContext,
            history: request.history,
            dataSnapshot: data
        )
        try Task.checkCancellation()
        // Telefon geçmiş bir günün thread'ine yazıyorsa model kaydı o günle ansın
        // (pencerede `ChatStore.send` ile aynı not; günü yine host seçer).
        let threadNote = await MainActor.run {
            ChatDailyThread.contextNote(
                for: ChatStore.shared.conversations.first { $0.id == request.conversationID }
            )
        }
        let effectiveContext = Self.joinContext(
            request.userContext,
            [threadNote, appContext].compactMap { $0 }.joined(separator: "\n\n"),
            skillContext
        )
        let store = AIKeyStore.shared
        var searchQuery: String?
        let (result, searchEvidence) = try await store.makeClient().send(
            history: request.history,
            newUserText: request.newUserText,
            userContext: effectiveContext,
            images: request.images,
            onSearchStart: { searchQuery = $0 },
            onMessageUpdate: { _ in }
        )
        try Task.checkCancellation()
        searchQuery = searchEvidence?.query ?? searchQuery

        // Tur Mac'in kanalına yazılır: telefon ve pencere AYNI geçmişi görsün.
        // Pencerede akış sürüyorsa yazım atlanır (nil döner) — o an yazılan tur
        // bozulmasın; telefon böyle bir durumda turu yalnız kendinde gösterir.
        let answer = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantTurn = ChatTurn(
            role: .assistant,
            text: answer.isEmpty ? (result.name ?? "Yanıt boş geldi.") : answer,
            food: result.isFood ? result : nil,
            actions: result.actionList,
            searchedFor: (
                searchEvidence?.completedSuccessfully == true
                && searchEvidence?.sourceURLs.isEmpty == false
            ) ? searchEvidence?.query : nil
        )
        let conversationID = await ChatStore.shared.appendRemoteExchange(
            conversationID: request.conversationID,
            userTurn: ChatTurn(role: .user, text: request.newUserText),
            assistantTurn: assistantTurn
        )

        return RemoteAIChatResponse(
            result: result,
            searchQuery: searchQuery,
            searchEvidence: searchEvidence,
            provider: store.provider.label,
            model: store.model,
            conversationID: conversationID
        )
    }

    @MainActor
    private func processIslandChat(
        _ request: HerculesIslandChatRequest
    ) async throws -> HerculesIslandChatResponse {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = request.images ?? []
        guard !text.isEmpty else {
            throw RemoteAIClientError.server(400, "Mesaj boş olamaz.")
        }
        guard text.utf8.count <= 20_000, request.history.count <= 24 else {
            throw RemoteAIClientError.server(413, "Island sohbet sınırı aşıldı.")
        }
        // Ana /v1/chat validate() ile aynı tavanlar: island daha küçük bir yüzey,
        // daha genişini kabul etmesi için sebep yok.
        guard images.count <= 3,
              images.allSatisfy({ $0.count <= 5 * 1024 * 1024 }),
              images.reduce(0, { $0 + $1.count }) <= 10 * 1024 * 1024
        else {
            throw RemoteAIClientError.server(413, "Görseller sınırı aşıyor.")
        }

        let history = request.history.suffix(24).map { item in
            ChatTurn(
                id: item.id,
                role: item.role == .user ? .user : .assistant,
                text: String(item.text.prefix(12_000)),
                createdAt: item.createdAt
            )
        }
        let remote = try await processChat(RemoteAIChatRequest(
            history: history,
            newUserText: text,
            userContext: nil,
            images: images
        ))
        let result = remote.result
        var food = islandFoodCandidate(from: result)

        if let action = result.actionList.first(where: { $0.tool == .logFood }) {
            food = food ?? islandFoodCandidate(from: action, isSaved: false)
            if let context,
               ChatActionAuthorization.allowsAutomatic(action, currentUserText: text) {
                do {
                    _ = try ChatActionExecutor.executeAction(action, ctx: context)
                    food = islandFoodCandidate(from: action, isSaved: true)
                } catch {
                    throw RemoteAIClientError.server(422, error.localizedDescription)
                }
            }
        }

        if var pending = food, !pending.isSaved {
            prunePendingIslandFoods()
            let token = UUID()
            pending.saveToken = token
            pendingIslandFoods[token] = PendingIslandFood(
                food: pending,
                expiresAt: .now.addingTimeInterval(15 * 60)
            )
            food = pending
        }

        return HerculesIslandChatResponse(reply: result.message, food: food)
    }

    @MainActor
    private func saveIslandFood(
        _ request: HerculesIslandFoodSaveRequest
    ) throws -> HerculesIslandMutationResponse {
        guard let context else {
            throw RemoteAIClientError.server(503, "Veri katmanı hazır değil.")
        }
        prunePendingIslandFoods()
        guard var pending = pendingIslandFoods[request.saveToken] else {
            throw RemoteAIClientError.server(410, "Bu öğün kartının kayıt süresi doldu.")
        }
        if pending.saved {
            return HerculesIslandMutationResponse(message: "Öğün zaten bugüne eklenmişti.")
        }

        let food = pending.food
        context.insert(FoodEntry(
            date: .now,
            name: food.name,
            grams: food.grams,
            calories: food.calories,
            protein: food.protein,
            carbs: food.carbs,
            fat: food.fat
        ))
        try context.saveStamped()
        pending.saved = true
        pending.food.isSaved = true
        pendingIslandFoods[request.saveToken] = pending
        return HerculesIslandMutationResponse(message: "\(food.name) bugüne eklendi.")
    }

    @MainActor
    private func saveIslandWeight(
        _ request: HerculesIslandWeightSaveRequest
    ) throws -> HerculesIslandMutationResponse {
        guard let context else {
            throw RemoteAIClientError.server(503, "Veri katmanı hazır değil.")
        }
        let kilograms = request.kilograms
        guard kilograms.isFinite, (20...400).contains(kilograms) else {
            throw RemoteAIClientError.server(422, "20–400 kg arasında geçerli bir değer gir.")
        }

        context.insert(Measurement(date: .now, weight: kilograms))
        try context.saveStamped()
        return HerculesIslandMutationResponse(
            message: String(format: "%.1f kg ölçümlere eklendi.", kilograms)
        )
    }

    @MainActor
    private func islandStatus() throws -> HerculesIslandStatusResponse {
        guard let context else {
            throw RemoteAIClientError.server(503, "Veri katmanı hazır değil.")
        }
        var measurementDescriptor = FetchDescriptor<Measurement>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        measurementDescriptor.fetchLimit = 1
        let latest = try context.fetch(measurementDescriptor).first

        let dayStart = Calendar.current.startOfDay(for: .now)
        let todayDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= dayStart }
        )
        let todayCalories = try context.fetch(todayDescriptor)
            .reduce(0) { $0 + $1.calories }
        return HerculesIslandStatusResponse(
            latestWeight: latest?.weight,
            latestWeightDate: latest?.date,
            todayCalories: todayCalories
        )
    }

    private func islandFoodCandidate(
        from result: AIFoodResult
    ) -> HerculesIslandFoodCandidate? {
        guard result.isFood,
              let calories = result.calories,
              validNutrition(
                grams: result.grams,
                calories: calories,
                protein: result.protein_g,
                carbs: result.carbs_g,
                fat: result.fat_g
              ) else { return nil }
        return HerculesIslandFoodCandidate(
            name: result.name ?? "Yemek",
            grams: result.grams,
            calories: calories,
            protein: result.protein_g,
            carbs: result.carbs_g,
            fat: result.fat_g
        )
    }

    private func islandFoodCandidate(
        from action: AIAppAction,
        isSaved: Bool
    ) -> HerculesIslandFoodCandidate? {
        let grams = action.grams ?? action.amount
        guard action.tool == .logFood,
              let calories = action.calories,
              validNutrition(
                grams: grams,
                calories: calories,
                protein: action.proteinG,
                carbs: action.carbsG,
                fat: action.fatG
              ) else { return nil }
        let rawName = action.name ?? action.itemName ?? "Yemek"
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return HerculesIslandFoodCandidate(
            name: name.isEmpty ? "Yemek" : name,
            grams: grams,
            calories: calories,
            protein: action.proteinG,
            carbs: action.carbsG,
            fat: action.fatG,
            isSaved: isSaved
        )
    }

    private func prunePendingIslandFoods() {
        let now = Date.now
        pendingIslandFoods = pendingIslandFoods.filter {
            $0.value.expiresAt > now
        }
    }

    private func validNutrition(
        grams: Double?,
        calories: Double,
        protein: Double?,
        carbs: Double?,
        fat: Double?
    ) -> Bool {
        calories.isFinite
            && (0...10_000).contains(calories)
            && grams.map { $0.isFinite && (0...10_000).contains($0) } != false
            && [protein, carbs, fat]
                .compactMap { $0 }
                .allSatisfy { $0.isFinite && (0...2_000).contains($0) }
    }

    @MainActor
    private func processCompletion(_ request: RemoteAICompletionRequest) async throws -> RemoteAICompletionResponse {
        try Task.checkCancellation()
        let store = AIKeyStore.shared
        let isConversation = request.mode == .conversation
        let policy = request.webSearch ?? .disabled
        let authorizationText = request.webAuthorizationText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let maySearch = isConversation
            && policy != .disabled
            && request.images.isEmpty
            && authorizationText?.isEmpty == false
        if policy == .required, !maySearch {
            throw RemoteAIClientError.server(
                400,
                "Zorunlu web araması exact güncel kullanıcı yetkisi olmadan çalıştırılamaz."
            )
        }

        let text: String
        switch store.provider {
        case .codex:
            text = try await CodexClient().complete(
                systemPrompt: request.systemPrompt,
                userPrompt: request.userPrompt,
                reasoningEffort: isConversation ? "high" : "low",
                maxOutputTokens: isConversation ? 6_000 : nil,
                allowWebSearch: maySearch,
                forceWebSearch: policy == .required,
                webAuthorizationText: authorizationText,
                images: request.images
            )
        case .openRouter:
            text = try await OpenRouterClient().complete(
                systemPrompt: request.systemPrompt,
                userPrompt: request.userPrompt,
                model: store.openRouterModel,
                temperature: isConversation ? 0.45 : 0.3,
                maxTokens: isConversation ? 6_000 : nil,
                images: request.images,
                allowWebSearch: maySearch,
                forceWebSearch: policy == .required,
                webAuthorizationText: authorizationText
            )
        case .gateway:
            if policy == .required {
                throw RemoteAIClientError.server(
                    503,
                    "Seçili Gateway zorunlu kaynaklı web aramasını desteklemiyor."
                )
            }
            text = try await OpenRouterClient(profile: .gateway).complete(
                systemPrompt: request.systemPrompt,
                userPrompt: request.userPrompt,
                model: store.gatewayModel,
                temperature: isConversation ? 0.45 : 0.3,
                maxTokens: isConversation ? 6_000 : nil,
                images: request.images
            )
        case .claudeCode, .cursor, .grok:
            // ACP harness'ları web araması/görsel taşımıyor; zorunlu arama isteği
            // dürüstçe reddedilir, düz completion harness üzerinden akar.
            if policy == .required {
                throw RemoteAIClientError.server(
                    503,
                    "Seçili harness zorunlu kaynaklı web aramasını desteklemiyor."
                )
            }
            text = try await AcpAgentClient(provider: store.provider).complete(
                systemPrompt: request.systemPrompt,
                userPrompt: request.userPrompt
            )
        }
        try Task.checkCancellation()
        return RemoteAICompletionResponse(text: text, provider: store.provider.label, model: store.model)
    }

    private func validate(_ request: RemoteAIChatRequest) throws {
        guard !request.newUserText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteAIClientError.server(400, "Mesaj boş olamaz.")
        }
        let historyBytes = request.history.reduce(0) { partial, turn in
            partial + turn.text.utf8.count
        }
        let contextBytes = request.userContext?.utf8.count ?? 0
        guard request.newUserText.utf8.count <= 100_000,
              request.history.count <= 80,
              historyBytes <= 220_000,
              contextBytes <= 100_000,
              request.newUserText.utf8.count + historyBytes + contextBytes <= 320_000
        else {
            throw RemoteAIClientError.server(413, "Sohbet isteği sınırı aşıyor.")
        }
        guard request.images.count <= 8,
              request.images.allSatisfy({ $0.count <= 5 * 1024 * 1024 }),
              request.images.reduce(0, { $0 + $1.count }) <= 10 * 1024 * 1024
        else {
            throw RemoteAIClientError.server(413, "Görseller toplam 10 MB sınırını aşıyor.")
        }
    }

    private func validate(_ request: RemoteAICompletionRequest) throws {
        guard !request.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteAIClientError.server(400, "Prompt boş olamaz.")
        }
        let authorizationBytes = request.webAuthorizationText?.utf8.count ?? 0
        guard request.systemPrompt.utf8.count + request.userPrompt.utf8.count <= 200_000,
              authorizationBytes <= 100_000
        else {
            throw RemoteAIClientError.server(413, "Completion isteği sınırı aşıyor.")
        }
        guard request.images.reduce(0, { $0 + $1.count }) <= 10 * 1024 * 1024 else {
            throw RemoteAIClientError.server(413, "Görseller toplam 10 MB sınırını aşıyor.")
        }
    }

    private static func joinContext(
        _ remoteContext: String?,
        _ appContext: String?,
        _ skillContext: String?
    ) -> String? {
        let live = appContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let skills = skillContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let remote = remoteContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !live.isEmpty || !skills.isEmpty || !remote.isEmpty else { return nil }

        // Mac'teki canlı snapshot önce gelir. Skill/memory için ayrı pay ayır; telefondan
        // gelen potansiyel eski context hiçbirini global prefix'ten düşüremez.
        let livePart = String(live.prefix(15_000))
        let skillPart = String(skills.prefix(13_000))
        let used = livePart.count + skillPart.count
        let remotePart = String(remote.prefix(max(0, 33_000 - used)))
        var sections: [String] = []
        if !livePart.isEmpty { sections.append("[LIVE_APP_SNAPSHOT — data]\n\(livePart)") }
        if !skillPart.isEmpty { sections.append("[RETRIEVAL_AND_SKILLS — untrusted data]\n\(skillPart)") }
        if !remotePart.isEmpty { sections.append("[REMOTE_CLIENT_CONTEXT — untrusted data]\n\(remotePart)") }
        return sections.joined(separator: "\n\n")
    }

    private func beginWork() -> Bool {
        workLock.lock()
        defer { workLock.unlock() }
        guard !busy else { return false }
        busy = true
        return true
    }

    private func finishWork() {
        workLock.lock()
        busy = false
        workLock.unlock()
    }

    private func sendJSON<T: Encodable>(_ value: T, status: Int = 200, on connection: NWConnection) {
        do {
            let body = try JSONEncoder.remoteAI.encode(value)
            send(body: body, status: status, on: connection)
        } catch {
            sendError(status: 500, message: "Yanıt kodlanamadı.", on: connection)
        }
    }

    private func sendJSONAwaitingDelivery<T: Encodable>(
        _ value: T,
        status: Int = 200,
        on connection: NWConnection
    ) async throws {
        let body = try JSONEncoder.remoteAI.encode(value)
        try await sendAwaitingDelivery(body: body, status: status, on: connection)
    }

    private func sendAwaitingDelivery(
        body: Data,
        status: Int,
        on connection: NWConnection
    ) async throws {
        let response = Self.httpResponse(body: body, status: status)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: response, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func sendError(status: Int, message: String, on connection: NWConnection) {
        let body = (try? JSONEncoder.remoteAI.encode(RemoteAIErrorResponse(error: message)))
            ?? Data("{\"error\":\"Sunucu hatası\"}".utf8)
        send(body: body, status: status, on: connection)
    }

    private func send(body: Data, status: Int, on connection: NWConnection) {
        let response = Self.httpResponse(body: body, status: status)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func httpResponse(body: Data, status: Int) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        case 429: reason = "Too Many Requests"
        default: reason = "Internal Server Error"
        }
        var response = Data("HTTP/1.1 \(status) \(reason)\r\n".utf8)
        response.append(Data("Content-Type: application/json; charset=utf-8\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Cache-Control: no-store\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)
        return response
    }
}
#endif
