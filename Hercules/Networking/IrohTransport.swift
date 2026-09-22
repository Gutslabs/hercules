#if os(iOS)
import Foundation
import IrohLib
import Security

// ---------------------------------------------------------------------------
// IROH TAŞIMASI (telefon tarafı) — Mac'e VPN profili olmadan bağlanır.
//
// Tailscale iOS'ta bir VPN profilidir: sistem ayarlarında durur, uyur/uyanır,
// başka bir VPN ile çakışır. Iroh ise yalnız bu uygulamanın içinde yaşar.
// Mac'i IP ile değil Ed25519 public key ile buluruz; adres değişse de (wifi →
// hücresel, başka şehir) anahtar sabit kaldığı için bağlantı kurulur: önce
// doğrudan NAT delme denenir, olmazsa relay devreye girer.
//
// Bu katman HTTP'yi QUIC stream'i üzerinde taşır; RemoteAIClient'ın geri kalanı
// aynen çalışır. Mac tarafında karşılığı `hercules-iroh-relay` sürecidir.
// ---------------------------------------------------------------------------

struct IrohTransportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

actor HerculesIrohTransport {
    static let shared = HerculesIrohTransport()

    private static let macEndpointKey = "hercules.mobile.iroh.mac-endpoint.v1"
    private static let macTicketKey = "hercules.mobile.iroh.mac-ticket.v1"
    private static let alpn = Data("hercules/api/1".utf8)
    /// Üst üste başarısızlıkta her isteği bekletmeyelim: bu süre boyunca
    /// doğrudan Tailscale yoluna düş, arka planda tekrar denemeye devam et.
    private static let coolDown: TimeInterval = 30

    private var endpoint: Endpoint?
    private var connection: Connection?
    private var connectingTask: Task<Connection, Error>?
    private var blockedUntil: Date?

    // MARK: Mac kimliği (QR'dan okunur)

    /// QR'daki ticket'ı saklar. Ticket kimliği + güncel adresleri taşır; secret
    /// taşımaz. Geçersizse hiçbir şey yazılmaz — yarım eşleşme bırakmayalım.
    @discardableResult
    static func pair(ticket encoded: String) -> String? {
        let clean = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let parsed = try? EndpointTicket.fromString(str: clean) else { return nil }
        let id = parsed.endpointAddr().id().description
        UserDefaults.standard.set(id, forKey: macEndpointKey)
        UserDefaults.standard.set(clean, forKey: macTicketKey)
        return id
    }

    static var macEndpoint: String? {
        let stored = UserDefaults.standard.string(forKey: macEndpointKey) ?? ""
        return stored.isEmpty ? nil : stored
    }

    static func unpair() {
        UserDefaults.standard.removeObject(forKey: macEndpointKey)
        UserDefaults.standard.removeObject(forKey: macTicketKey)
    }

    /// Iroh yolu denenebilir mi?
    static var isAvailable: Bool { macEndpoint != nil }

    /// Son istek Iroh üzerinden mi gitti? Yalnız gösterge için — sessizce
    /// Tailscale'e düşüldüğünde kullanıcının bunu görebilmesi gerekir.
    static private(set) var lastPathWasIroh = false
    static func noteFallback() { lastPathWasIroh = false }

    /// Bu telefonun Iroh kimliği — Mac eşleştirme listesine bunu yazar.
    static func localEndpointID() async -> String? {
        try? await shared.currentEndpoint().id().description
    }

    // MARK: Bağlantı

    private func ensureConnection() async throws -> Connection {
        if let blockedUntil, blockedUntil > Date() {
            throw IrohTransportError(message: "iroh yolu geçici olarak devre dışı")
        }
        if let connection, connection.closeReason() == nil { return connection }
        if let connectingTask { return try await connectingTask.value }

        let task = Task<Connection, Error> { [self] in
            guard let macID = Self.macEndpoint else {
                throw IrohTransportError(message: "Mac'in Iroh kimliği henüz bilinmiyor")
            }
            let ep = try await currentEndpoint()
            let target = Self.rememberedAddress(for: macID)
            do {
                return try await ep.connect(addr: target.addr, alpn: Self.alpn)
            } catch {
                // Ticket'taki IP/relay Mac ağ değiştirdikten sonra bayat kalabilir.
                // Bir kez public-key discovery ile tekrar dene.
                guard target.usedTicket else { throw error }
                let discovery = EndpointAddr(
                    id: try EndpointId.fromString(s: macID), relayUrl: nil, addresses: []
                )
                return try await ep.connect(addr: discovery, alpn: Self.alpn)
            }
        }
        connectingTask = task
        defer { connectingTask = nil }

        do {
            let conn = try await task.value
            connection = conn
            blockedUntil = nil
            return conn
        } catch {
            connection = nil
            blockedUntil = Date().addingTimeInterval(Self.coolDown)
            throw error
        }
    }

    private static func rememberedAddress(for endpointID: String) -> (addr: EndpointAddr, usedTicket: Bool) {
        if let encoded = UserDefaults.standard.string(forKey: macTicketKey),
           let ticket = try? EndpointTicket.fromString(str: encoded) {
            let addr = ticket.endpointAddr()
            if addr.id().description == endpointID { return (addr, true) }
            UserDefaults.standard.removeObject(forKey: macTicketKey)
        }
        // Public-key discovery: adres bilinmese de relay üzerinden bulunur.
        let fallback = try? EndpointId.fromString(s: endpointID)
        return (EndpointAddr(id: fallback!, relayUrl: nil, addresses: []), false)
    }

    fileprivate func currentEndpoint() async throws -> Endpoint {
        if let endpoint, !endpoint.isClosed() { return endpoint }
        // Secret VERİLMEZSE iroh her bind'de yeni kimlik üretir; telefon her
        // açılışta başka bir uç olarak görünür ve Mac onu "eşleşmemiş" sayar.
        let created = try await Endpoint.bind(
            options: EndpointOptions(preset: presetN0(), secretKey: Self.endpointSecret())
        )
        endpoint = created
        return created
    }

    /// Ağ değişince (wifi ↔ hücresel) eski bağlantı ölür; bir sonraki istek
    /// yenisini kurar. closeReason kontrolü de yakalar, bu sadece hızlandırır.
    func invalidate() {
        connection = nil
        blockedUntil = nil
    }

    // MARK: Kalıcı kimlik (Keychain)

    private static let keychainService = "com.samorai.hercules.iroh"
    private static let keychainAccount = "endpoint-secret-v1"

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func endpointSecret() -> Data {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let existing = item as? Data, existing.count == 32 {
            return existing
        }
        var fresh = Data(count: 32)
        let ok = fresh.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base) == errSecSuccess
        }
        if !ok { fresh = Data((0..<32).map { _ in UInt8.random(in: 0...255) }) }
        var insert = keychainQuery()
        insert[kSecValueData as String] = fresh
        // Cihaz bir kez açıldıktan sonra erişilebilir: arka planda da bağlanabilmeli,
        // ama cihaz hiç açılmadan anahtar okunamamalı.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemDelete(keychainQuery() as CFDictionary)
        SecItemAdd(insert as CFDictionary, nil)
        return fresh
    }

    // MARK: HTTP over QUIC

    func perform(_ request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        let conn = try await ensureConnection()
        do {
            return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
                group.addTask { try await self.exchange(on: conn, request: request) }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw IrohTransportError(message: "iroh isteği zaman aşımına uğradı")
                }
                guard let first = try await group.next() else {
                    throw IrohTransportError(message: "iroh yanıtı alınamadı")
                }
                group.cancelAll()
                return first
            }
        } catch {
            connection = nil
            throw error
        }
    }

    private func exchange(on conn: Connection, request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw IrohTransportError(message: "geçersiz istek adresi") }
        let bi = try await conn.openBi()
        let send = bi.send()
        let recv = bi.recv()
        try await send.writeAll(buf: Self.serialize(request, url: url))
        try await send.finish()
        // `Connection: close` gönderdiğimiz için sunucu gövdeyi bitirince
        // stream'i kapatır; readToEnd tam yanıtı verir.
        let raw = try await recv.readToEnd(sizeLimit: 16 * 1024 * 1024)
        let parsed = try Self.parse(raw, url: url)
        Self.lastPathWasIroh = true
        return parsed
    }

    /// URLRequest → ham HTTP/1.1 istek baytları.
    private static func serialize(_ request: URLRequest, url: URL) -> Data {
        let method = request.httpMethod ?? "GET"
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty { path += "?\(query)" }
        var head = "\(method) \(path) HTTP/1.1\r\n"
        head += "Host: hercules.local\r\n"
        head += "Connection: close\r\n"
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            // Kimlik başlığını relay yazar; istemciden geleni zaten atıyor.
            guard key.lowercased() != "host", key.lowercased() != "connection" else { continue }
            head += "\(key): \(value)\r\n"
        }
        let body = request.httpBody ?? Data()
        head += "Content-Length: \(body.count)\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }

    /// Ham HTTP/1.1 yanıtı → (gövde, HTTPURLResponse).
    private static func parse(_ raw: Data, url: URL) throws -> (Data, HTTPURLResponse) {
        guard let split = raw.range(of: Data("\r\n\r\n".utf8)) else {
            throw IrohTransportError(message: "iroh yanıtı çözümlenemedi")
        }
        let headText = String(decoding: raw[..<split.lowerBound], as: UTF8.self)
        var lines = headText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw IrohTransportError(message: "iroh yanıtı boş") }
        let statusLine = lines.removeFirst().split(separator: " ", maxSplits: 2).map(String.init)
        guard statusLine.count >= 2, let status = Int(statusLine[1]) else {
            throw IrohTransportError(message: "iroh yanıt durumu okunamadı")
        }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let body = Data(raw[split.upperBound...])
        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        ) else {
            throw IrohTransportError(message: "iroh yanıtı kurulamadı")
        }
        return (body, response)
    }
}
#endif
