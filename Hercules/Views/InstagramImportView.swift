#if os(macOS)
import SwiftUI
import SwiftData
import WebKit
import LucideKit

/// İçe aktarma sırasında tek bir gönderinin durumu.
struct ImportCandidate: Identifiable {
    var id: String { shortcode }
    let shortcode: String
    var result: AIRecipeResult?
    /// Gerçek hata (ağ, erişilemez gönderi, çözümlenemeyen yanıt).
    var failure: String?
    /// Gönderi tarif değil — hata DEĞİL, beklenen sonuç. Ayrı tutuluyor ki kırmızı hata gibi
    /// görünmesin ve Instagram'daki kaydı KALDIRILMASIN (başka sebeple saklanmış olabilir).
    var skippedReason: String?
    var savedToLibrary = false
    var unsavedOnInstagram = false
    var unsaveError: String?
    var strategyNote: String?

    var isDone: Bool { savedToLibrary || failure != nil || skippedReason != nil }
}

@MainActor
@Observable
final class InstagramImportModel {
    enum Phase {
        case session      // giriş / kullanıcı adı
        case scanning     // kaydedilenler taranıyor
        case working      // gönderiler tek tek işleniyor
        case finished     // özet
    }

    private static let handleKey = "hercules.instagram.handle"
    private static let unsaveKey = "hercules.instagram.unsaveAfterImport"

    /// Web view'a gerçek bir boyut veriyoruz: Instagram ızgarası viewport'a bağlı tembel
    /// yükleme yapıyor, sıfır boyutlu bir view'da hiç içerik render etmez.
    @ObservationIgnored let webView: WKWebView
    /// Okuyucu web view ile AYNI örneği paylaşmalı, yoksa oturum ortak olmaz. İkisi de
    /// init'te kuruluyor: `@Observable` makrosu `lazy` özelliklerle çalışmıyor.
    @ObservationIgnored private let reader: InstagramSavedReader
    @ObservationIgnored private let scraper = InstagramPostScraper()
    @ObservationIgnored private let extractor = RecipeExtractor()

    var phase: Phase = .session
    var handle: String {
        didSet { UserDefaults.standard.set(handle, forKey: Self.handleKey) }
    }
    /// Kütüphaneye giren gönderinin Instagram kaydı kaldırılsın mı. Açıkken kaydedilenler bir
    /// gelen-kutusu gibi çalışıyor: aktarılan çıkar, kalan sırada bekler.
    var unsaveAfterImport: Bool {
        didSet { UserDefaults.standard.set(unsaveAfterImport, forKey: Self.unsaveKey) }
    }
    var status = ""
    var errorText: String?
    var isBusy = false
    var candidates: [ImportCandidate] = []
    var scanLimit = 400

    /// Zaten kütüphanede olan gönderi kodları — hem dedup hem tarama erken-durdurma için.
    var knownShortcodes: Set<String> = []

    var doneCount: Int { candidates.filter(\.isDone).count }
    var savedCount: Int { candidates.filter(\.savedToLibrary).count }
    var skippedCount: Int { candidates.filter { $0.skippedReason != nil }.count }
    var failedCount: Int { candidates.filter { $0.failure != nil }.count }

    init() {
        let cfg = WKWebViewConfiguration()
        // Öntanımlı (kalıcı) veri deposu — oturum uygulama kapanınca da kalsın, kullanıcı
        // bir kere giriş yapsın.
        cfg.websiteDataStore = .default()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: cfg)
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView = view
        reader = InstagramSavedReader(webView: view)
        handle = UserDefaults.standard.string(forKey: Self.handleKey) ?? ""
        unsaveAfterImport = UserDefaults.standard.object(forKey: Self.unsaveKey) as? Bool ?? true
    }

    // MARK: - Oturum

    func openLogin() {
        guard let url = URL(string: "https://www.instagram.com/") else { return }
        webView.load(URLRequest(url: url))
        status = "Instagram'a kendin giriş yap, sonra 'Kaydedilenleri Tara'ya bas."
    }

    func checkSession() async {
        isBusy = true
        errorText = nil
        status = "Oturum kontrol ediliyor…"
        defer { isBusy = false }

        guard await reader.isLoggedIn() else {
            status = "Giriş gerekiyor."
            errorText = "Instagram oturumu yok. Aşağıdaki pencereden giriş yap."
            openLogin()
            return
        }
        if handle.isEmpty, let detected = await reader.detectHandle() {
            handle = detected
        }
        status = handle.isEmpty ? "Oturum var. Kullanıcı adını yaz." : "Oturum var: @\(handle)"
    }

    // MARK: - Tarama

    func scan() async -> Bool {
        let clean = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            errorText = "Instagram kullanıcı adını yaz."
            return false
        }
        isBusy = true
        errorText = nil
        phase = .scanning
        status = "Kaydedilenler taranıyor…"
        defer { isBusy = false }

        do {
            let codes = try await reader.collectSavedShortcodes(
                handle: clean,
                limit: scanLimit,
                known: knownShortcodes
            ) { [weak self] count in
                self?.status = "\(count) yeni gönderi bulundu…"
            }
            candidates = codes.map { ImportCandidate(shortcode: $0) }
            if candidates.isEmpty {
                phase = .finished
                status = "Yeni kayıt yok — kütüphane güncel. (\(scanDiagnostics))"
                return false
            }
            status = "\(candidates.count) yeni gönderi bulundu. (\(scanDiagnostics))"
            phase = .working
            return true
        } catch {
            phase = .session
            errorText = error.localizedDescription
            status = "Tarama başarısız."
            return false
        }
    }

    /// Taramanın nasıl bittiği — bulunan sayı gerçek mi erken durma mı, görünür olsun.
    var scanDiagnostics: String {
        let reason = reader.lastStopReason
        guard !reason.isEmpty else { return "—" }
        return "\(reason) · \(reader.lastRoundCount) tur · kaydırma: \(reader.lastScrollKind)"
    }

    // MARK: - Tek tek işleme

    /// Her gönderiyi tek tek: kazı → tarife çevir → KÜTÜPHANEYE YAZ → Instagram kaydını kaldır.
    ///
    /// Sıra kritik: önce kaydet, sonra unsave. Tersi olsa unsave başarılıp kaydetme patladığında
    /// tarif ne Instagram'da ne burada olurdu. Ayrıca tarifin `urlString`'inde gönderi linki
    /// duruyor, yani kaydı kaldırmak videoya erişimi kaybettirmiyor.
    ///
    /// Kaydı yalnızca kütüphaneye GİREN gönderilerden kaldırıyoruz; "tarif değil" diye atlananlar
    /// ve hata verenler Instagram'da olduğu gibi kalıyor.
    func runImport(into ctx: ModelContext) async {
        isBusy = true
        defer {
            isBusy = false
            phase = .finished
            var parts = ["\(savedCount) tarif kaydedildi"]
            if skippedCount > 0 { parts.append("\(skippedCount) yemek değil") }
            if failedCount > 0 { parts.append("\(failedCount) hata") }
            status = parts.joined(separator: " · ")
        }

        for index in candidates.indices {
            if Task.isCancelled { return }
            let code = candidates[index].shortcode
            status = "\(index + 1)/\(candidates.count) — \(code)"

            do {
                let post = try await scraper.fetch(shortcode: code)
                candidates[index].strategyNote = post.strategy
                let result = try await extractor.extract(from: post)
                candidates[index].result = result

                ctx.insert(result.makeRecipe(shortcode: code))
                ctx.saveOrReport()
                candidates[index].savedToLibrary = true
                knownShortcodes.insert(code)

                guard unsaveAfterImport else { continue }
                do {
                    try await reader.unsave(shortcode: code)
                    candidates[index].unsavedOnInstagram = true
                } catch {
                    // Kaydetme başarılı, unsave değil — sessizce başarılı gösterme.
                    candidates[index].unsaveError = error.localizedDescription
                }
            } catch let error as RecipeExtractionError {
                if case .notARecipe(let note) = error {
                    candidates[index].skippedReason = note.isEmpty ? "yemek tarifi değil" : note
                } else {
                    candidates[index].failure = error.localizedDescription
                }
            } catch {
                candidates[index].failure = error.localizedDescription
            }
        }
    }
}

struct InstagramImportView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var recipes: [Recipe]

    @State private var model = InstagramImportModel()
    @State private var task: Task<Void, Never>?

    var body: some View {
        SheetChrome(
            eyebrow: "Tarifler",
            title: "Instagram'dan İçe Aktar",
            subtitle: model.errorText ?? (model.status.isEmpty
                ? "Her gönderi tek tek işlenir: tarifse kütüphaneye eklenir ve Instagram kaydı kaldırılır."
                : model.status),
            size: .full,
            // İçerik kendi kaydırmasını yönetiyor (tarayıcı + sonuç listesi).
            scrollsContent: false,
            onClose: { task?.cancel(); dismiss() }
        ) {
            switch model.phase {
            case .session, .scanning:
                browserPane
            case .working, .finished:
                resultPane
            }
        } footer: {
            footerContent
        }
        .onAppear {
            model.knownShortcodes = Self.shortcodes(in: recipes)
            task = Task { await model.checkSession() }
        }
        .onDisappear { task?.cancel() }
    }

    // MARK: - Bölümler

    private var browserPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("@")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                TextField("instagram kullanıcı adın", text: $model.handle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: 180)
                Text("· en fazla")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                Picker("", selection: $model.scanLimit) {
                    Text("50").tag(50)
                    Text("150").tag(150)
                    Text("400").tag(400)
                    Text("1000").tag(1000)
                }
                .labelsHidden()
                .frame(width: 88)
                Toggle("Aktarılanı Instagram'dan çıkar", isOn: $model.unsaveAfterImport)
                    .toggleStyle(.checkbox)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("\(model.knownShortcodes.count) kayıt kütüphanede")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            InstagramWebView(webView: model.webView)
                .overlay(alignment: .top) { Divider().overlay(Palette.border) }
        }
    }

    private var resultPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.candidates.isEmpty {
                    Text("Yeni kayıt yok.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textQuaternary)
                        .padding(.top, 20)
                }
                ForEach(model.candidates) { candidate in
                    candidateRow(candidate)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func candidateRow(_ item: ImportCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusDot(item)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.result?.title ?? item.shortcode)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(item.savedToLibrary ? Palette.textPrimary : Palette.textQuaternary)
                    if item.savedToLibrary {
                        badge(item.unsavedOnInstagram ? "kaydedildi · IG'den çıkarıldı" : "kaydedildi",
                              tint: Palette.positive)
                    }
                }

                if let result = item.result {
                    Text(macroLine(result))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textQuaternary)
                }
                if let unsaveError = item.unsaveError {
                    Text("Instagram kaydı kaldırılamadı, orada duruyor — \(unsaveError)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.warning)
                        .lineLimit(2)
                }
                if let skipped = item.skippedReason {
                    Text(skipped)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textQuaternary)
                        .lineLimit(2)
                }
                if let failure = item.failure {
                    Text(failure)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.negative.opacity(0.85))
                        .lineLimit(2)
                }
                if !item.isDone {
                    Text("bekliyor…")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            Spacer(minLength: 8)
            if let strategy = item.strategyNote {
                Text(strategy)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
    }

    @ViewBuilder
    private func statusDot(_ item: ImportCandidate) -> some View {
        if item.savedToLibrary {
            Lucide(sf: "checkmark", size: 11).foregroundStyle(Palette.positive)
        } else if item.failure != nil {
            Circle().fill(Palette.negative.opacity(0.75)).frame(width: 7, height: 7)
        } else if item.skippedReason != nil {
            Circle().strokeBorder(Palette.border, lineWidth: 1.2).frame(width: 7, height: 7)
        } else {
            Circle().fill(Palette.border).frame(width: 7, height: 7)
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tint.opacity(0.12))
            )
    }

    private func macroLine(_ result: AIRecipeResult) -> String {
        var parts: [String] = []
        if let c = result.calories { parts.append("\(Fmt.int(c)) kcal") }
        if let p = result.protein_g { parts.append("P \(Fmt.int(p))g") }
        if let k = result.carbs_g { parts.append("K \(Fmt.int(k))g") }
        if let f = result.fat_g { parts.append("Y \(Fmt.int(f))g") }
        if let s = result.servings { parts.append("\(s) porsiyon") }
        if result.macrosEstimated == true { parts.append("tahmin") }
        return parts.isEmpty ? "makro yok" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var footerContent: some View {
        Group {
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            if !model.candidates.isEmpty {
                Text("\(model.doneCount)/\(model.candidates.count) işlendi · \(model.savedCount) kaydedildi")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
            }
            Spacer()

            Button(model.isBusy ? "Durdur" : "Kapat") {
                task?.cancel()
                if !model.isBusy { dismiss() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.textSecondary)

            switch model.phase {
            case .session, .scanning:
                actionButton("Kaydedilenleri Tara", enabled: !model.isBusy) {
                    task = Task {
                        if await model.scan() { await model.runImport(into: ctx) }
                    }
                }
            case .working:
                actionButton("İşleniyor…", enabled: false) {}
            case .finished:
                actionButton("Tekrar Tara", enabled: !model.isBusy) {
                    task = Task {
                        if await model.scan() { await model.runImport(into: ctx) }
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(enabled ? Palette.btnFg : Palette.textQuaternary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(enabled ? Palette.accent : Palette.border.opacity(0.4))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Kütüphanedeki tarif linklerinden gönderi kodlarını çıkarır — dedup anahtarı bu.
    /// Recipe'e yeni alan eklemiyoruz: kod zaten `urlString` içinde duruyor.
    static func shortcodes(in recipes: [Recipe]) -> Set<String> {
        Set(recipes.compactMap { InstagramPostScraper.shortcode(from: $0.urlString) })
    }
}

/// Model'in sahip olduğu web view'ı SwiftUI'a bağlar. View'ı burada YARATMIYORUZ: giriş ve
/// kazıma aynı örnek üzerinde olmalı, yoksa oturum paylaşılmaz.
private struct InstagramWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
