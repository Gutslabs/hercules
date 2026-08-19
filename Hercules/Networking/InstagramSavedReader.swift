#if os(macOS)
import Foundation
import WebKit

/// Kullanıcının Instagram'da kaydettiği gönderilerin listesini çıkarır.
///
/// NEDEN WKWebView: "kaydedilenler" listesi hiçbir resmî API'de yok, yalnızca oturum açmış
/// kullanıcıya görünüyor. WKWebView zaten gerçek bir tarayıcı ve app'in içinde — ayrı bir
/// Python/Selenium/Docker parçası kurmak yerine oturum uygulamanın kendi çerez deposunda
/// kalıyor, bir kere giriş yapılıyor.
///
/// Girişi KULLANICI kendi yapıyor. Bu sınıf hiçbir yere kimlik bilgisi yazmıyor; sadece giriş
/// yapılmış oturumda gezinip `<a href>` topluyor.
///
/// Yalnızca LİSTE için oturum gerekiyor. Gönderi içeriğini `InstagramPostScraper` oturumsuz
/// çekiyor (ölçüldü: halka açık gönderide `/embed/captioned/` caption + görselleri veriyor).
@MainActor
final class InstagramSavedReader {
    /// Kaç ardışık kaydırma yeni gönderi getirmezse liste bitmiş sayılır. Cömert tutuluyor:
    /// 3 tur × 0.9 sn ile Instagram'ın bir sonraki partisini yetiştirememesi yüzünden tarama
    /// ~20 kayıtta bitiyordu. Yükleniyor göstergesi varken bu sayaç hiç artmıyor.
    private static let idleRoundsBeforeStop = 8
    /// Üst sınır — beklenmedik bir döngüde sonsuza kadar kaydırmayalım.
    private static let maxScrollRounds = 400
    /// Kaydırma sonrası yeni içeriğin gelmesi için bekleme.
    private static let scrollSettleNanos: UInt64 = 1_400_000_000

    /// Taramanın neden bittiği + hangi öğenin kaydırıldığı. UI bunu gösteriyor ki "21 kayıt"
    /// gibi bir sonuç gerçek mi yoksa erken durma mı olduğu görünür olsun.
    private(set) var lastStopReason = ""
    private(set) var lastScrollKind = "?"
    private(set) var lastRoundCount = 0
    /// Izgaranın ilk render'ı için kaç yoklama (× scrollSettleNanos ≈ 9 sn).
    private static let firstPostPollAttempts = 10
    /// Üst üste kaç bilinen gönderi görülünce tarama kesilsin. Tek bilinene bakmak riskli:
    /// arada yeni bir kayıt eski bir kaydın önüne düşebiliyor.
    private static let knownRunToStop = 12

    private let webView: WKWebView
    private var navigationWaiter: NavigationWaiter?

    /// UI'ın sahip olduğu web view geçilir: giriş ve kazıma AYNI view'da olmalı, yoksa
    /// oturum paylaşılmaz.
    init(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Oturum

    /// Giriş yapılmış mı? Giriş sayfasına yönlendirilirsek yapılmamış demektir.
    func isLoggedIn() async -> Bool {
        guard let url = URL(string: "https://www.instagram.com/accounts/edit/") else { return false }
        do { try await load(url) } catch { return false }
        let current = webView.url?.absoluteString ?? ""
        return !current.contains("/accounts/login")
    }

    /// Kullanıcı adını hesap düzenleme formundan okumayı dener. Sayfadaki gömülü JSON'dan
    /// tahmin etmiyoruz — orada başka hesapların adı da geçiyor, yanlış handle sessizce
    /// boş liste üretirdi. Bulamazsa nil döner ve UI kullanıcıya sorar.
    func detectHandle() async -> String? {
        guard let url = URL(string: "https://www.instagram.com/accounts/edit/") else { return nil }
        try? await load(url)
        guard !(webView.url?.absoluteString.contains("/accounts/login") ?? true) else { return nil }

        let js = """
        (function(){
          var el = document.querySelector('input[name="username"]');
          return el && el.value ? el.value : null;
        })()
        """
        let value = try? await webView.evaluateJavaScript(js)
        guard let handle = value as? String, !handle.isEmpty else { return nil }
        return handle
    }

    // MARK: - Kaydedilenler

    /// Kaydedilenler ızgarasını kaydırarak gönderi kodlarını toplar. Sıra korunur:
    /// Instagram en yeniyi başa koyuyor, yani ilk gelenler en son kaydettikleri.
    ///
    /// `known` verilirse (zaten içe aktarılmış kodlar) ve üst üste
    /// `knownRunToStop` tanesine denk gelinirse tarama kesilir. Sıralama yeniden-eskiye
    /// olduğu için bu, ilk tam koşudan sonraki taramaları birkaç satıra indiriyor —
    /// yüzlerce kaydı her seferinde baştan kaydırmak gerekmiyor.
    func collectSavedShortcodes(
        handle: String,
        limit: Int,
        known: Set<String> = [],
        onProgress: @MainActor (Int) -> Void = { _ in }
    ) async throws -> [String] {
        let clean = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !clean.isEmpty,
              let url = URL(string: "https://www.instagram.com/\(clean)/saved/all-posts/")
        else { throw InstagramReaderError.badHandle(handle) }

        try await load(url)
        if webView.url?.absoluteString.contains("/accounts/login") == true {
            throw InstagramReaderError.notLoggedIn
        }

        // `didFinish` kabuk yüklenince tetikleniyor, ızgara ise sonra render ediliyor.
        // Beklemeden harvest'e girersek ilk turlar boş döner ve haksız yere "kaydedilen yok"
        // deriz. İlk gönderi görünene kadar sınırlı süre bekle.
        try await waitForFirstPost()

        var ordered: [String] = []
        var seen = Set<String>()
        var idleRounds = 0
        var rounds = 0
        var knownRun = 0
        var reachedKnownTail = false
        var probe = ScrollProbe()
        /// Izgarada tek gönderi hiç görülmediyse "boş koleksiyon" diyebilmek için ayrı tutuyoruz;
        /// `ordered` filtreleme yüzünden boş kalabilir ama sayfa dolu olabilir.
        var sawAnyPost = false

        while ordered.count < limit,
              idleRounds < Self.idleRoundsBeforeStop,
              rounds < Self.maxScrollRounds,
              !reachedKnownTail {
            rounds += 1
            let before = ordered.count
            var sawNewCode = false

            for code in await harvestShortcodes() where !seen.contains(code) {
                seen.insert(code)
                sawAnyPost = true
                sawNewCode = true

                if known.contains(code) {
                    knownRun += 1
                    if knownRun >= Self.knownRunToStop {
                        reachedKnownTail = true
                        break
                    }
                    continue
                }
                knownRun = 0
                ordered.append(code)
                if ordered.count >= limit { break }
            }

            // İlerleme ölçüsü yeni KOD görmek; yeni kod hiç gelmediyse liste bitti demektir.
            // `ordered` sayısına bakmak yanıltıcı olurdu: hepsi bilinen çıkabilir.
            if sawNewCode {
                idleRounds = 0
                if ordered.count != before { onProgress(ordered.count) }
            } else if probe.busy {
                // Instagram hâlâ sonraki partiyi yüklüyor — boşta saymıyoruz.
            } else {
                idleRounds += 1
            }

            guard ordered.count < limit, !reachedKnownTail else { break }
            probe = await scrollToBottom()
            lastScrollKind = probe.kind
            try? await Task.sleep(nanoseconds: Self.scrollSettleNanos)
        }

        lastRoundCount = rounds
        lastStopReason = {
            if reachedKnownTail { return "zaten aktarılmış kayıtlara ulaşıldı" }
            if ordered.count >= limit { return "üst sınıra (\(limit)) ulaşıldı" }
            if rounds >= Self.maxScrollRounds { return "kaydırma turu sınırı" }
            if idleRounds >= Self.idleRoundsBeforeStop { return "liste sonu (yeni kayıt gelmedi)" }
            return "bitti"
        }()

        if !sawAnyPost { throw InstagramReaderError.emptyCollection(clean) }
        return ordered
    }

    /// Izgarada ilk gönderi görünene kadar bekler. Bulamazsa gerçekten boş/erişilemez.
    private func waitForFirstPost() async throws {
        for _ in 0..<Self.firstPostPollAttempts {
            if !(await harvestShortcodes()).isEmpty { return }
            try? await Task.sleep(nanoseconds: Self.scrollSettleNanos)
        }
    }

    /// Sayfadaki gönderi linklerinden kodları çıkarır. CSS class'larına değil `href`
    /// desenine bakıyoruz — class isimleri sürekli değişiyor, link deseni değişmiyor.
    private func harvestShortcodes() async -> [String] {
        let js = """
        (function(){
          var out = [], seen = {};
          var links = document.querySelectorAll('a[href*="/p/"], a[href*="/reel/"], a[href*="/tv/"]');
          for (var i = 0; i < links.length; i++) {
            var h = links[i].getAttribute('href') || '';
            var m = h.match(/\\/(?:p|reel|reels|tv)\\/([A-Za-z0-9_-]+)/);
            if (m && !seen[m[1]]) { seen[m[1]] = 1; out.push(m[1]); }
          }
          return out;
        })()
        """
        let value = try? await webView.evaluateJavaScript(js)
        return (value as? [String]) ?? []
    }

    /// Izgarayı bir tur daha yükletmek için aşağı kaydırır.
    ///
    /// `window.scrollTo` tek başına yetmiyor: Instagram ızgarayı kendi kaydırılabilir
    /// kapsayıcısında tutabiliyor, o durumda pencereyi kaydırmak sayfalamayı hiç
    /// tetiklemiyor ve tarama ilk iki partide bitiyormuş gibi görünüyor. Gerçek kaydırma
    /// hedefini gönderi linkinden yukarı yürüyerek buluyoruz, hem onu hem pencereyi
    /// kaydırıyoruz. Teşhis için de hedefin ne olduğunu geri döndürüyoruz.
    @discardableResult
    private func scrollToBottom() async -> ScrollProbe {
        let js = """
        (function(){
          var link = document.querySelector('a[href*="/p/"], a[href*="/reel/"], a[href*="/tv/"]');
          var target = null;
          var el = link;
          while (el && el !== document.body) {
            var s = window.getComputedStyle(el);
            if ((s.overflowY === 'auto' || s.overflowY === 'scroll') &&
                el.scrollHeight > el.clientHeight + 40) { target = el; break; }
            el = el.parentElement;
          }
          if (target) {
            target.scrollTop = target.scrollHeight;
          }
          window.scrollTo(0, document.body.scrollHeight);
          var docEl = document.scrollingElement || document.documentElement;
          if (docEl) { docEl.scrollTop = docEl.scrollHeight; }
          // Instagram sonraki partiyi yüklerken bir yükleniyor göstergesi bırakıyor;
          // varsa "boşta" saymayalım.
          var busy = !!document.querySelector('[role="progressbar"], [aria-busy="true"]');
          return {
            kind: target ? 'container' : 'window',
            height: (target ? target.scrollHeight : document.body.scrollHeight) | 0,
            busy: busy
          };
        })()
        """
        let value = try? await webView.evaluateJavaScript(js)
        guard let dict = value as? [String: Any] else { return ScrollProbe() }
        return ScrollProbe(
            kind: dict["kind"] as? String ?? "?",
            height: (dict["height"] as? NSNumber)?.intValue ?? 0,
            busy: dict["busy"] as? Bool ?? false
        )
    }

    struct ScrollProbe {
        var kind = "?"
        var height = 0
        var busy = false
    }

    // MARK: - Kaydı kaldırma

    /// Gönderiyi Instagram'daki kaydedilenlerden çıkarır.
    ///
    /// Gönderi sayfasına gidip kaydet düğmesine DOM'dan tıklamıyoruz: düğmenin etiketi dile
    /// göre değişiyor ve yanlış öğeye tıklamak beğenmek/takip etmek gibi istenmeyen bir işlem
    /// yapabilir. Bunun yerine oturumun kendi web ucunu çağırıyoruz — istek web view içinden
    /// gittiği için çerezler ve same-origin bağlamı hazır.
    ///
    /// Yanıtı DOĞRULUYORUZ: uç nokta onaylamadıkça "kaldırıldı" demiyoruz.
    func unsave(shortcode: String) async throws {
        guard let pk = InstagramPostScraper.mediaPK(from: shortcode) else {
            throw InstagramReaderError.unsaveFailed(shortcode, "media id hesaplanamadı")
        }

        // fetch same-origin olmalı — web view instagram.com'da değilse oraya götür.
        if webView.url?.host?.contains("instagram.com") != true {
            guard let home = URL(string: "https://www.instagram.com/") else {
                throw InstagramReaderError.unsaveFailed(shortcode, "adres kurulamadı")
            }
            try await load(home)
        }

        let js = """
        const m = document.cookie.match(/csrftoken=([^;]+)/);
        if (!m) { return { ok: false, detail: 'csrftoken bulunamadı — oturum yok olabilir' }; }
        const r = await fetch(`/api/v1/web/save/${pk}/unsave/`, {
          method: 'POST',
          headers: {
            'x-csrftoken': m[1],
            'x-requested-with': 'XMLHttpRequest',
            'content-type': 'application/x-www-form-urlencoded'
          },
          credentials: 'same-origin'
        });
        const body = await r.text();
        return { ok: r.ok, status: r.status, detail: body.slice(0, 200) };
        """

        let value = try await webView.callAsyncJavaScript(
            js, arguments: ["pk": pk], in: nil, contentWorld: .page)

        guard let dict = value as? [String: Any] else {
            throw InstagramReaderError.unsaveFailed(shortcode, "beklenmedik yanıt")
        }
        let ok = dict["ok"] as? Bool ?? false
        let detail = (dict["detail"] as? String) ?? ""
        let status = (dict["status"] as? NSNumber)?.intValue
        guard ok else {
            let code = status.map { "HTTP \($0) · " } ?? ""
            throw InstagramReaderError.unsaveFailed(shortcode, code + detail)
        }
    }

    // MARK: - Navigasyon

    /// Sayfa yüklenmesini bekler. `WKNavigationDelegate` geri çağrısını tek seferlik bir
    /// continuation'a bağlıyoruz; çift resume Swift'te çökme olduğu için sarmalayıcı
    /// devralmayı bir kez yapılacak şekilde koruyor.
    private func load(_ url: URL) async throws {
        let waiter = NavigationWaiter()
        navigationWaiter = waiter
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: url))
        try await waiter.wait()
    }
}

enum InstagramReaderError: LocalizedError {
    case badHandle(String)
    case notLoggedIn
    case emptyCollection(String)
    case navigationFailed(String)
    case unsaveFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .badHandle(let h):
            return "Instagram kullanıcı adı geçersiz: \(h)"
        case .notLoggedIn:
            return "Instagram oturumu yok — önce giriş yap."
        case .emptyCollection(let h):
            return "@\(h) için kaydedilen gönderi bulunamadı. Kullanıcı adı doğru mu?"
        case .navigationFailed(let m):
            return "Sayfa yüklenemedi: \(m)"
        case .unsaveFailed(let code, let detail):
            return "\(code) kaydedilenlerden çıkarılamadı: \(detail)"
        }
    }
}

/// Tek bir navigasyonu bekleyen delege. Her `load` için yenisi kurulur.
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    func wait() async throws {
        try await withCheckedThrowingContinuation { c in
            if finished { c.resume(); return }
            continuation = c
        }
    }

    private func settle(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        let c = continuation
        continuation = nil
        switch result {
        case .success: c?.resume()
        case .failure(let e): c?.resume(throwing: e)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settle(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        settle(.failure(InstagramReaderError.navigationFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        settle(.failure(InstagramReaderError.navigationFailed(error.localizedDescription)))
    }
}
#endif
