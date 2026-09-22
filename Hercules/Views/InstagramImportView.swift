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

/// Instagram'dan içe aktarma penceresi — tasarım: tuval ▸ Pencereler · Beslenme (az yazı). Oturum ve
/// tarama aşamasında ayarlar + gömülü Instagram; işlerken büyük sayaç, her gönderi için bir çizgi
/// ve satır satır sonuç (kaydedildi ✓, tarif değil ○, hata ●, IG'de kaldı uyarısı).
struct InstagramImportView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var recipes: [Recipe]

    @State private var model = InstagramImportModel()
    @State private var task: Task<Void, Never>?

    var body: some View {
        SadeSheet(title: "Instagram'dan içe aktar",
                  subtitle: model.handle.isEmpty ? nil : "@\(model.handle)",
                  onClose: { task?.cancel(); dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                switch model.phase {
                case .session, .scanning:
                    settingsRow
                        .padding(.horizontal, 28)
                        .padding(.top, 18)
                    if let error = model.errorText {
                        SadeNote(text: error, color: Palette.negative)
                            .padding(.horizontal, 28)
                            .padding(.top, 12)
                    }
                    InstagramWebView(webView: model.webView)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Palette.textPrimary.opacity(0.08), lineWidth: 1))
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .padding(.bottom, 22)
                case .working, .finished:
                    progressBlock
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                    resultList
                        .padding(.top, 14)
                }
            }
        } footerLeading: {
            if model.isBusy {
                ProgressView().controlSize(.small)
                    .help(model.status)
            }
        } footerTrailing: {
            SadeButton(title: model.isBusy ? "Durdur" : "Kapat") {
                task?.cancel()
                if !model.isBusy { dismiss() }
            }
            switch model.phase {
            case .session, .scanning:
                SadeButton(title: "Kaydedilenleri tara", role: .primary, enabled: !model.isBusy, bindsKey: false) { startScan() }
            case .working:
                SadeButton(title: "İşleniyor…", role: .primary, enabled: false, bindsKey: false) {}
            case .finished:
                SadeButton(title: "Tekrar tara", role: .primary, enabled: !model.isBusy, bindsKey: false) { startScan() }
            }
        }
        .frame(width: 960, height: 760)
        .onAppear {
            model.knownShortcodes = Self.shortcodes(in: recipes)
            task = Task { await model.checkSession() }
        }
        .onDisappear { task?.cancel() }
    }

    private func startScan() {
        task = Task {
            if await model.scan() { await model.runImport(into: ctx) }
        }
    }

    // MARK: - Ayarlar (oturum · tarama)

    private var settingsRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            SadeField(label: "Kullanıcı") {
                Text("@")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textTertiary)
                TextField("", text: $model.handle, prompt: Text("kullanıcı adın").foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
            }
            .frame(width: 220)
            VStack(alignment: .leading, spacing: 6) {
                Text("En fazla")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                Menu {
                    ForEach([50, 150, 400, 1000], id: \.self) { limit in
                        Button("\(limit)") { model.scanLimit = limit }
                    }
                } label: {
                    Text("\(model.scanLimit)")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(width: 110, height: 38, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Lucide(sf: "chevron.down", size: 11)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.trailing, 12)
                        .allowsHitTesting(false)
                }
                .sadeBox(radius: 10)
            }
            SadeCheckRow(title: "IG'den çıkar", isOn: $model.unsaveAfterImport,
                         help: "Kütüphaneye giren gönderinin Instagram kaydı kaldırılsın")
            Spacer(minLength: 8)
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .padding(.bottom, 11)
            }
        }
    }

    // MARK: - İlerleme

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(model.doneCount)")
                        .foregroundStyle(Palette.textPrimary)
                    Text(" / \(model.candidates.count)")
                        .foregroundStyle(Palette.textTertiary)
                }
                .font(.system(size: 30, weight: .semibold).monospacedDigit())
                Spacer(minLength: 12)
                HStack(spacing: 14) {
                    legend("\(model.savedCount) tarif", Palette.positive)
                    if model.skippedCount > 0 { legend("\(model.skippedCount) değil", Palette.textPrimary.opacity(0.3)) }
                    if model.failedCount > 0 { legend("\(model.failedCount) hata", Palette.negative) }
                }
            }
            progressBar
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
        .font(.system(size: 12.5).monospacedDigit())
        .foregroundStyle(Palette.textSecondary)
    }

    /// Her gönderi için bir çizgi (60'a kadar); daha fazlasında oranlı dört parça.
    @ViewBuilder private var progressBar: some View {
        let items = model.candidates
        if items.count <= 60 {
            HStack(spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tickColor(item, current: index == currentIndex))
                        .frame(height: 10)
                }
            }
        } else {
            GeometryReader { geo in
                let total = max(1, CGFloat(items.count))
                let parts: [(CGFloat, Color)] = [
                    (CGFloat(model.savedCount), Palette.positive),
                    (CGFloat(model.skippedCount), Palette.textPrimary.opacity(0.22)),
                    (CGFloat(model.failedCount), Palette.negative),
                    (CGFloat(items.count - model.doneCount), Palette.textPrimary.opacity(0.07)),
                ]
                HStack(spacing: 3) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        if part.0 > 0 {
                            Capsule().fill(part.1).frame(width: max(3, (geo.size.width - 9) * part.0 / total))
                        }
                    }
                }
            }
            .frame(height: 10)
        }
    }

    /// İşlenmekte olan gönderi: bitmemiş ilk gönderi (meşgulken).
    private var currentIndex: Int? {
        guard model.isBusy else { return nil }
        return model.candidates.firstIndex { !$0.isDone }
    }

    private func tickColor(_ item: ImportCandidate, current: Bool) -> Color {
        if item.savedToLibrary { return Palette.positive }
        if item.failure != nil { return Palette.negative }
        if item.skippedReason != nil { return Palette.textPrimary.opacity(0.22) }
        return current ? Palette.textSecondary : Palette.textPrimary.opacity(0.07)
    }

    // MARK: - Sonuçlar

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.candidates.isEmpty {
                    Text("Yeni kayıt yok")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, 20)
                }
                ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                    candidateRow(candidate, current: index == currentIndex)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func candidateRow(_ item: ImportCandidate, current: Bool) -> some View {
        HStack(spacing: 12) {
            statusMark(item, current: current)
                .frame(width: 17)
            Text(item.result?.title ?? item.shortcode)
                .font(.system(size: 14, weight: item.savedToLibrary ? .medium : .regular))
                .foregroundStyle(item.savedToLibrary ? Palette.textPrimary : (current ? Palette.textSecondary : Palette.textTertiary))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.strategyNote ?? "")
            if let unsaveError = item.unsaveError {
                HStack(spacing: 5) {
                    Lucide(sf: "exclamationmark.triangle", size: 12)
                    Text("IG'de kaldı")
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.warning)
                .help("Instagram kaydı kaldırılamadı — \(unsaveError)")
            }
            if let result = item.result {
                Text(macroLine(result))
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            } else if let skipped = item.skippedReason {
                Text(skipped == "yemek tarifi değil" ? "tarif değil" : skipped)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .help(skipped)
            } else if let failure = item.failure {
                Text("hata")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.negative)
                    .help(failure)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .overlay(alignment: .top) { SadeRule().opacity(0.75) }
    }

    @ViewBuilder
    private func statusMark(_ item: ImportCandidate, current: Bool) -> some View {
        if item.savedToLibrary {
            Lucide(sf: "checkmark.circle.fill", size: 16).foregroundStyle(Palette.positive)
        } else if item.failure != nil {
            Circle().fill(Palette.negative).frame(width: 10, height: 10)
        } else if item.skippedReason != nil {
            Circle().strokeBorder(Palette.textTertiary, lineWidth: 1.5).frame(width: 13, height: 13)
        } else if current {
            ProgressView().controlSize(.mini)
        } else {
            Circle().fill(Palette.textQuaternary).frame(width: 7, height: 7)
        }
    }

    /// "310 kcal · P 24 · K 32 · Y 9"; makro yoksa boş.
    private func macroLine(_ result: AIRecipeResult) -> String {
        var parts: [String] = []
        if let c = result.calories { parts.append("\(Fmt.int(c)) kcal") }
        if let p = result.protein_g { parts.append("P \(Fmt.int(p))") }
        if let k = result.carbs_g { parts.append("K \(Fmt.int(k))") }
        if let f = result.fat_g { parts.append("Y \(Fmt.int(f))") }
        return parts.joined(separator: " · ")
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
