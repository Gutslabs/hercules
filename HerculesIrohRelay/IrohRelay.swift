import Foundation
import IrohLib
import Network

// ---------------------------------------------------------------------------
// HERCULES IROH RELAY — telefon Mac'e VPN profili olmadan bağlanır.
//
// Tailscale bir AĞ kurar (iOS'ta sistem VPN profili). Iroh bunun yerine
// UYGULAMA seviyesinde tek bir QUIC bağlantısı açar: telefon Mac'i IP ile
// değil Ed25519 public key ile bulur, NAT delme tutmazsa relay'e düşer.
// Telefonda kurulacak hiçbir şey yoktur.
//
// NEDEN AYRI SÜREÇ: `Iroh.xcframework` ile hafıza aramasının kullandığı
// `sentencepiece.xcframework` aynı `include/module.modulemap` yoluna yazıyor;
// ikisini tek hedefte linklemek Xcode'da "Multiple commands produce" hatası
// veriyor. Relay'i ayrı bir hedefe alınca çakışma tamamen ortadan kalkıyor ve
// bonus olarak RemoteAIServer'a hiç dokunmamış oluyoruz: bu süreç bugün
// Tailscale Serve'ün yaptığı işi yapıyor — QUIC'i 127.0.0.1:8765'e taşıyor.
//
// KİMLİK HEADER'DAN GELMEZ. Karşı ucun public key'i QUIC handshake'inde
// doğrulanır; relay isteğe onu KENDİ yazar ve istemcinin gönderdiği aynı adlı
// header'ı ATAR. Yoksa telefon kendini istediği kimlikle tanıtabilirdi.
// ---------------------------------------------------------------------------

let alpn = Data("hercules/api/1".utf8)
let backendPort: NWEndpoint.Port = 8765
/// Relay'in doğruladığı kimliği taşıyan tek başlık. Gelen istekte varsa silinir.
let identityHeader = "x-hercules-iroh-endpoint"

// MARK: - Dosya konumları

enum RelayPaths {
    static var directory: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Hercules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Relay'in kalıcı Iroh secret key'i. Değişirse telefondaki eşleştirme
    /// geçersizleşir ve kullanıcı QR'ı yeniden okutmak zorunda kalır.
    static var secret: URL { directory.appendingPathComponent("iroh-relay-key") }
    /// Uygulamanın QR'da göstereceği kimlik + ticket.
    static var published: URL { directory.appendingPathComponent("iroh-endpoint.json") }
    /// Eşleştirilmiş telefon anahtarları. Listede olmayan hiçbir uç geçemez.
    static var peers: URL { directory.appendingPathComponent("iroh-peers.json") }
}

// MARK: - Kalıcı kimlik

func loadOrCreateSecret() -> Data {
    if let existing = try? Data(contentsOf: RelayPaths.secret), existing.count == 32 {
        return existing
    }
    var fresh = Data(count: 32)
    let ok = fresh.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        return SecRandomCopyBytes(kSecRandomDefault, 32, base) == errSecSuccess
    }
    if !ok { fresh = Data((0..<32).map { _ in UInt8.random(in: 0...255) }) }
    try? fresh.write(to: RelayPaths.secret, options: [.atomic, .completeFileProtection])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: RelayPaths.secret.path)
    return fresh
}

// MARK: - Eşleştirme listesi

struct PairedPeers: Codable {
    var paired: [String] = []
    /// Bağlanmayı deneyen ama henüz onaylanmamış uçlar.
    var pending: [String] = []
}

/// Liste her istekte diskten okunur: uygulama bir telefonu onaylayınca relay'i
/// yeniden başlatmak gerekmesin.
func isPaired(_ endpointID: String) -> Bool {
    guard let data = try? Data(contentsOf: RelayPaths.peers),
          let list = try? JSONDecoder().decode(PairedPeers.self, from: data)
    else { return false }
    return list.paired.contains(endpointID)
}

// MARK: - HTTP başlık yeniden yazımı

/// İstek başlığını ayırır, sahte kimlik başlığını atar, doğrulanmış kimliği ekler.
/// Gövdeye dokunulmaz — Content-Length/chunked akışı olduğu gibi geçer.
func rewriteHead(_ head: String, endpointID: String) -> String {
    var lines = head.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return head }
    let requestLine = lines.removeFirst()
    let kept = lines.filter { line in
        guard let colon = line.firstIndex(of: ":") else { return !line.isEmpty }
        return line[line.startIndex..<colon].lowercased() != identityHeader
    }
    var out = [requestLine]
    out.append(contentsOf: kept)
    out.append("X-Hercules-Iroh-Endpoint: \(endpointID)")
    return out.joined(separator: "\r\n") + "\r\n\r\n"
}

/// Onaysız uçların geçebildiği TEK yol.
func isPairingRequest(_ head: String) -> Bool {
    guard let line = head.components(separatedBy: "\r\n").first else { return false }
    let parts = line.split(separator: " ")
    guard parts.count >= 2 else { return false }
    let path = parts[1].split(separator: "?").first.map(String.init) ?? ""
    return path == "/v1/iroh/pair"
}

// MARK: - Backend köprüsü (QUIC stream ↔ 127.0.0.1:8765)

/// Tek bir QUIC bidi-stream'i backend'e bağlar. Bir stream = bir HTTP isteği:
/// RemoteAIServer her cevaptan sonra bağlantıyı kapattığı için keep-alive yok.
/// `restricted` → uç henüz onaylanmadı; yalnız eşleştirme yoluna izin verilir.
func bridge(_ bi: BiStream, endpointID: String, restricted: Bool) async {
    let recv = bi.recv()
    let send = bi.send()

    // 1) İstek başlığını topla (gövde başlamadan önce kimliği yazmalıyız).
    var buffer = Data()
    var head: String?
    var bodyStart = Data()
    while head == nil {
        guard let chunk = try? await recv.read(sizeLimit: 64 * 1024), !chunk.isEmpty else { break }
        buffer.append(chunk)
        if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
            head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
            bodyStart = buffer[range.upperBound...]
        }
        // Kötü niyetli/bozuk istemci sonsuz başlık göndermesin.
        if buffer.count > 256 * 1024 { break }
    }
    guard let head else {
        try? await send.finish()
        return
    }

    // Onaylanmamış uç yalnız eşleştirme durumunu sorabilir. Bu kapı relay'de
    // duruyor ki istek backend'e HİÇ ulaşmasın.
    if restricted, !isPairingRequest(head) {
        let body = "{\"error\":\"Bu telefon bu Mac ile eşleşmemiş.\"}"
        let response = "HTTP/1.1 403 Forbidden\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
        try? await send.writeAll(buf: Data(response.utf8))
        try? await send.finish()
        return
    }

    // 2) Backend'e bağlan.
    let connection = NWConnection(
        host: .ipv4(.loopback),
        port: backendPort,
        using: .tcp
    )
    let queue = DispatchQueue(label: "hercules.iroh.bridge")
    let ready = AsyncStreamGate()
    connection.stateUpdateHandler = { state in
        switch state {
        case .ready: ready.open(nil)
        case .failed(let error): ready.open(error)
        case .cancelled: ready.open(URLError(.cancelled))
        default: break
        }
    }
    connection.start(queue: queue)
    if let error = await ready.wait() {
        FileHandle.standardError.write(Data("iroh relay: backend'e bağlanılamadı — \(error)\n".utf8))
        try? await send.finish()
        connection.cancel()
        return
    }

    // 3) Yeniden yazılmış başlık + varsa gövdenin ilk parçası.
    var outbound = Data(rewriteHead(head, endpointID: endpointID).utf8)
    outbound.append(bodyStart)
    connection.send(content: outbound, completion: .contentProcessed { _ in })

    // 4) Kalan gövdeyi QUIC'ten TCP'ye pompala.
    let uplink = Task {
        while true {
            guard let chunk = try? await recv.read(sizeLimit: 64 * 1024), !chunk.isEmpty else { break }
            connection.send(content: chunk, completion: .contentProcessed { _ in })
        }
        // İstek bitti: backend'e EOF ver ki cevabı üretsin.
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
    }

    // 5) Cevabı TCP'den QUIC'e pompala.
    await pumpDownstream(connection, to: send)
    uplink.cancel()
    connection.cancel()
    try? await send.finish()
}

/// Backend cevabını okuyup QUIC send tarafına yazar; bağlantı kapanınca biter.
func pumpDownstream(_ connection: NWConnection, to send: SendStream) async {
    while true {
        let chunk: Data? = await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    _ = error
                    continuation.resume(returning: nil)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
        guard let chunk else { return }
        if chunk.isEmpty { continue }
        do { try await send.writeAll(buf: chunk) } catch { return }
    }
}

/// NWConnection'ın state callback'ini tek seferlik await'e çevirir.
final class AsyncStreamGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Error?, Never>?
    private var settled = false
    private var value: Error??

    func open(_ error: Error?) {
        lock.lock()
        guard !settled else { lock.unlock(); return }
        settled = true
        let waiting = continuation
        continuation = nil
        value = .some(error)
        lock.unlock()
        waiting?.resume(returning: error)
    }

    func wait() async -> Error? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if settled, let value {
                lock.unlock()
                continuation.resume(returning: value)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

// MARK: - Kabul döngüsü

func serve(_ connection: Connection) async {
    let peer = connection.remoteId().description
    // Eşleşmemiş uç KAPATILMAZ, kısıtlanır: yalnız eşleştirme isteği geçebilir.
    // Tamamen reddetseydik telefonun kendini tanıtmasının hiçbir yolu kalmazdı
    // (QR Mac'in kimliğini taşır, telefonunkini değil).
    let paired = isPaired(peer)
    if !paired { notePending(peer) }
    while true {
        guard let bi = try? await connection.acceptBi() else { return }
        Task { await bridge(bi, endpointID: peer, restricted: !paired) }
    }
}

/// Eşleşme bekleyenler — uygulama bunları "onayla" listesinde gösterir.
func notePending(_ endpointID: String) {
    var payload = (try? Data(contentsOf: RelayPaths.peers))
        .flatMap { try? JSONDecoder().decode(PairedPeers.self, from: $0) } ?? PairedPeers()
    guard !payload.paired.contains(endpointID), !payload.pending.contains(endpointID) else { return }
    payload.pending.append(endpointID)
    if let data = try? JSONEncoder().encode(payload) {
        try? data.write(to: RelayPaths.peers, options: .atomic)
    }
    FileHandle.standardError.write(Data("iroh relay: eşleşme bekliyor — \(endpointID)\n".utf8))
}

func publish(_ endpoint: Endpoint) {
    let id = endpoint.id().description
    let ticket = (try? EndpointTicket.fromAddr(addr: endpoint.addr()))?.description
    let payload: [String: Any] = [
        "endpointId": id,
        "ticket": ticket ?? "",
        "updatedAt": ISO8601DateFormatter().string(from: Date())
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    else { return }
    try? data.write(to: RelayPaths.published, options: .atomic)
    FileHandle.standardError.write(Data("iroh relay: dinliyor → \(id)\n".utf8))
}

@main
struct Relay {
    static func main() async {
        let endpoint: Endpoint
        do {
            endpoint = try await Endpoint.bind(
                options: EndpointOptions(preset: presetN0(), secretKey: loadOrCreateSecret(), alpns: [alpn])
            )
        } catch {
            FileHandle.standardError.write(Data("iroh relay: başlatılamadı — \(error)\n".utf8))
            exit(1)
        }
        publish(endpoint)
        // Relay seçimi birkaç yüz ms sürer; telefonun bizi bulabilmesi için şart.
        // Hazır olunca ticket'ı relay bilgisiyle tazele.
        Task {
            try? await endpoint.online()
            publish(endpoint)
        }

        while true {
            guard let incoming = await endpoint.acceptNext() else { break }
            Task {
                guard let accepting = try? await incoming.accept(),
                      let connection = try? await accepting.connect() else { return }
                await serve(connection)
            }
        }
    }
}
