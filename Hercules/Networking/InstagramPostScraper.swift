import Foundation

/// Instagram gönderisinden ham içerik çeker: caption + görseller.
///
/// NEDEN embed yüzeyi: normal gönderi sayfası bir SPA kabuğu, içerik CSS class'larının
/// arkasında duruyor — oradan kazımak her arayüz değişikliğinde kırılır. `/embed/captioned/`
/// ise sunucuda render ediliyor ve gönderi verisini `contextJSON` alanında taşıyor.
/// Geçersiz veya erişilemez shortcode'da bu alan `null` geliyor, yani geçerlilik kontrolü
/// de bedava (ölçüldü: uydurma shortcode HTTP 200 dönüyor, durum kodu ayırt etmiyor).
///
/// Alan adlarına sabitlenmiyoruz. contextJSON içinde derinlemesine arayıp caption adayları
/// arasından EN UZUN metni seçiyoruz: Instagram şemayı değiştirse bile tarif caption'ı hâlâ
/// en uzun metin olur, sabit bir JSON yolu ise sessizce kırılırdı.
struct ScrapedPost: Sendable {
    var shortcode: String
    var caption: String?
    var images: [Data]
    /// Hangi strateji tuttu. İlk gerçek koşuda hangisinin yaşadığını görmek için taşınıyor.
    var strategy: String

    var hasContent: Bool {
        !(caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || !images.isEmpty
    }
}

enum InstagramScrapeError: LocalizedError {
    case badShortcode(String)
    case postUnavailable(String)
    case noContent(String)

    var errorDescription: String? {
        switch self {
        case .badShortcode(let s):
            return "Instagram linkinden gönderi kodu çıkarılamadı: \(s)"
        case .postUnavailable(let code):
            return "Gönderi açılamadı (silinmiş, gizli hesap veya oturum gerekiyor): \(code)"
        case .noContent(let code):
            return "Gönderide okunabilir caption veya görsel bulunamadı: \(code)"
        }
    }
}

struct InstagramPostScraper: Sendable {
    /// Safari kimliği: embed yüzeyi bot benzeri istemcilere farklı kabuk döndürüyor.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Tek gönderiden en fazla kaç görsel indirilsin. Carousel tarifleri genelde ilk
    /// birkaç slaytta olur; hepsini almak vision maliyetini boşa şişirir.
    private static let maxImages = 4
    /// Tek görsel için üst sınır — beklenmedik büyük dosya vision çağrısını patlatmasın.
    private static let maxImageBytes = 6 * 1024 * 1024

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Shortcode

    /// `https://www.instagram.com/p/ABC123/`, `/reel/ABC123/`, `/tv/ABC123/` → `ABC123`
    static func shortcode(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host.contains("instagram.com")
        else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let idx = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0.lowercased()) }),
              parts.count > idx + 1
        else { return nil }

        let code = parts[idx + 1]
        return code.isEmpty ? nil : code
    }

    static func postURL(for shortcode: String) -> String {
        "https://www.instagram.com/p/\(shortcode)/"
    }

    // MARK: - Media PK

    /// Shortcode alfabesi: gönderi kodu, 64'lük tabanda kodlanmış sayısal media pk'sı.
    private static let pkAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    private static let pkIndex: [Character: UInt64] = {
        var map: [Character: UInt64] = [:]
        for (i, c) in pkAlphabet.enumerated() { map[c] = UInt64(i) }
        return map
    }()

    /// Shortcode → sayısal media pk. Kaydı kaldırma (unsave) uç noktası shortcode değil bu
    /// sayıyı istiyor ve embed yükünde gelmiyor (oradaki `id` sahibin user id'si), o yüzden
    /// koddan hesaplıyoruz. Taşma olursa nil — uydurma bir id ile istek atmaktan iyidir.
    static func mediaPK(from shortcode: String) -> String? {
        guard !shortcode.isEmpty else { return nil }
        var pk: UInt64 = 0
        for c in shortcode {
            guard let value = pkIndex[c] else { return nil }
            let (scaled, mulOverflow) = pk.multipliedReportingOverflow(by: 64)
            guard !mulOverflow else { return nil }
            let (sum, addOverflow) = scaled.addingReportingOverflow(value)
            guard !addOverflow else { return nil }
            pk = sum
        }
        return String(pk)
    }

    /// Ters çevrim — yalnızca doğrulama/teşhis için.
    static func shortcode(fromMediaPK pk: UInt64) -> String {
        var n = pk
        var out = ""
        while n > 0 {
            out = String(pkAlphabet[Int(n % 64)]) + out
            n /= 64
        }
        return out
    }

    // MARK: - Fetch

    func fetch(shortcode: String) async throws -> ScrapedPost {
        guard !shortcode.isEmpty,
              shortcode.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { throw InstagramScrapeError.badShortcode(shortcode) }

        let html = try await embedHTML(shortcode: shortcode)

        // 1) contextJSON — sunucuda render edilen yapılandırılmış veri.
        if let context = Self.contextJSON(in: html) {
            let caption = Self.longestString(in: context, keys: Self.captionKeys)
            let urls = Self.imageURLs(in: context)
            let images = await downloadImages(urls)
            let post = ScrapedPost(shortcode: shortcode, caption: caption,
                                   images: images, strategy: "contextJSON")
            if post.hasContent { return post }
        }

        // 2) og: meta — contextJSON boş/null geldiğinde kabukta hâlâ olabiliyor.
        let ogCaption = Self.metaContent(in: html, property: "og:description")
        let ogImage = Self.metaContent(in: html, property: "og:image")
        let ogImages = await downloadImages(ogImage.map { [$0] } ?? [])
        let ogPost = ScrapedPost(shortcode: shortcode, caption: ogCaption,
                                 images: ogImages, strategy: "ogMeta")
        if ogPost.hasContent { return ogPost }

        // contextJSON null + og yok → gönderi gerçekten erişilemez.
        if Self.looksUnavailable(html) {
            throw InstagramScrapeError.postUnavailable(shortcode)
        }
        throw InstagramScrapeError.noContent(shortcode)
    }

    private func embedHTML(shortcode: String) async throws -> String {
        guard let url = URL(string: "https://www.instagram.com/p/\(shortcode)/embed/captioned/") else {
            throw InstagramScrapeError.badShortcode(shortcode)
        }
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InstagramScrapeError.postUnavailable(shortcode)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func downloadImages(_ urls: [String]) async -> [Data] {
        var out: [Data] = []
        for raw in urls.prefix(Self.maxImages) {
            guard let url = URL(string: raw) else { continue }
            var req = URLRequest(url: url)
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await session.data(for: req),
                  let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  !data.isEmpty, data.count <= Self.maxImageBytes
            else { continue }
            out.append(data)
        }
        return out
    }

    // MARK: - HTML / JSON ayıklama

    /// Kabuktaki `"contextJSON":"<kaçışlı json>"` alanını çözer.
    static func contextJSON(in html: String) -> Any? {
        // Alan bir JSON string olarak gömülü; kaçışları JSONSerialization'a çözdürüyoruz
        // ki elle unescape etmeye çalışıp köşe durumlarda bozmayalım.
        guard let range = html.range(of: "\"contextJSON\":") else { return nil }
        let tail = html[range.upperBound...]
        guard let quote = tail.firstIndex(of: "\"") else { return nil }

        var escaped = "\""
        var idx = tail.index(after: quote)
        var isEscape = false
        while idx < tail.endIndex {
            let ch = tail[idx]
            escaped.append(ch)
            if isEscape {
                isEscape = false
            } else if ch == "\\" {
                isEscape = true
            } else if ch == "\"" {
                break
            }
            idx = tail.index(after: idx)
        }
        guard escaped.count > 2,
              let outer = escaped.data(using: .utf8),
              let inner = try? JSONSerialization.jsonObject(
                  with: outer, options: [.fragmentsAllowed]) as? String,
              let innerData = inner.data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: innerData, options: [])
    }

    static let captionKeys: Set<String> = [
        "caption", "text", "accessibility_caption", "edge_media_to_caption", "description",
    ]

    /// Verilen anahtarların altında bulunan tüm metinlerden en uzununu döndürür.
    static func longestString(in json: Any, keys: Set<String>) -> String? {
        var found: [String] = []
        walk(json) { key, value in
            guard keys.contains(key), let s = value as? String else { return }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { found.append(t) }
        }
        return found.max(by: { $0.count < $1.count })
    }

    /// Instagram CDN'ine benzeyen görsel URL'lerini toplar, sırasını korur.
    static func imageURLs(in json: Any) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        walk(json) { _, value in
            guard let s = value as? String,
                  s.hasPrefix("http"),
                  s.contains("cdninstagram") || s.contains("fbcdn"),
                  !s.contains(".mp4"),
                  !seen.contains(s)
            else { return }
            seen.insert(s)
            out.append(s)
        }
        return out
    }

    /// Nesne ağacında her (anahtar, değer) çiftini gezer. Derinlik sınırı, beklenmedik
    /// döngüsel/aşırı derin yapıda takılmamak için.
    private static func walk(_ any: Any, depth: Int = 0, _ visit: (String, Any) -> Void) {
        guard depth < 24 else { return }
        if let dict = any as? [String: Any] {
            for (k, v) in dict {
                visit(k, v)
                walk(v, depth: depth + 1, visit)
            }
        } else if let arr = any as? [Any] {
            for v in arr { walk(v, depth: depth + 1, visit) }
        }
    }

    static func metaContent(in html: String, property: String) -> String? {
        // İki sıra da geçerli: content önce ya da property önce.
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(property)[\"'][^>]+content=[\"']([^\"']*)[\"']",
            "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+(?:property|name)=[\"']\(property)[\"']",
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: html)
            else { continue }
            let decoded = String(html[r])
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#039;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !decoded.isEmpty { return decoded }
        }
        return nil
    }

    static func looksUnavailable(_ html: String) -> Bool {
        html.contains("\"contextJSON\":null")
            || html.localizedCaseInsensitiveContains("Sorry, this page isn")
    }
}
