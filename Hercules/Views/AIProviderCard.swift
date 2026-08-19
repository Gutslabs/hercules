import SwiftUI
import LucideKit
import SwiftData
#if os(macOS)
import AppKit
#endif

/// AI Sağlayıcı — Sistem kartının sol bölümü (kart kromu ProfileView.systemCard'da).
struct AIProviderCard: View {
    @State private var provider: AIProvider = AIKeyStore.shared.provider
    @State private var model: String = AIKeyStore.shared.model
    @State private var apiKey: String = ""
    /// Keychain yazımını yazım durana kadar erteleyen görev (bkz. onChange).
    @State private var keySaveTask: Task<Void, Never>?
    @State private var codexStatus: CodexAuth.Status = .noCodexCLI
    @State private var importing = false
    @State private var importResult: String? = nil       // başarı/hata mesajı
    @State private var importSuccess: Bool = false       // ikon rengi için
    @State private var showLoginHelp: Bool = false       // yardım panelini aç/kapat
    // Gateway (CLIProxy) ayarları
    @State private var gatewayURL: String = ""
    @State private var gatewayKey: String = ""
    @State private var gatewayModel: String = ""
    @State private var gatewayTest: String? = nil
    @State private var gatewayTesting = false
    @State private var gatewayTestOK = false
    @State private var gatewayModelList: [String] = []   // /v1/models'ten canlı liste

    private let pillInk = Palette.btnFg
    private let pillPaper = Palette.btnBg

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI Sağlayıcı").eyebrow()
                Spacer(minLength: Spacing.md)
                Text(model)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                ForEach(AIProvider.selectable) { p in
                    Button {
                        provider = p
                        AIKeyStore.shared.provider = p
                        model = AIKeyStore.shared.model
                        if p == .gateway { Task { await reloadGatewayModels() } }
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    } label: {
                        Text(p.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(provider == p ? pillInk : Palette.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(provider == p ? pillPaper : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(provider == p ? Color.clear : Palette.border, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 13)

            switch provider {
            case .codex:      codexSection
            case .gateway:    gatewaySection
            case .openRouter: openRouterSection
            }
        }
        .padding(.init(top: 20, leading: 28, bottom: 18, trailing: 28))
        .onAppear {
            refreshCodexStatus()
            apiKey = AIKeyStore.shared.apiKey   // kayıtlı anahtarı alana yansıt
            gatewayURL = AIKeyStore.shared.gatewayBaseURL
            gatewayKey = AIKeyStore.shared.gatewayKey
            gatewayModel = AIKeyStore.shared.gatewayModel
            gatewayModelList = AIKeyStore.shared.gatewayModels
            if provider == .gateway { Task { await reloadGatewayModels() } }
        }
    }

    private var openRouterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Lucide(sf: "key", size: 10)
                    .foregroundStyle(Palette.textTertiary)
                SecureField("sk-or-...", text: $apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    // Debounce: setter senkron bir Keychain yazımı (SecItem XPC) yapıyor.
                    // Her tuşta çağrılınca 70 karakterlik bir anahtar = 70 XPC gidiş-dönüşü.
                    // Yazma yine otomatik (kayıp olmasın), sadece yazım durunca.
                    .onChange(of: apiKey) { _, newValue in
                        keySaveTask?.cancel()
                        keySaveTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            AIKeyStore.shared.apiKey = newValue
                        }
                    }
                    .onSubmit {
                        keySaveTask?.cancel()
                        AIKeyStore.shared.apiKey = apiKey
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    }
                if !apiKey.isEmpty {
                    Lucide(sf: "checkmark.circle.fill", size: 11)
                        .foregroundStyle(Palette.positive)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .padding(.top, 14)

            Text("openrouter.ai/keys adresinden API key al, buraya yapıştır. Terminal gerekmez.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Gateway (CLIProxy) bölümü

    private var gatewaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            gatewayField(icon: "link", placeholder: "http://localhost:8317/v1",
                         text: $gatewayURL, secure: false, filled: !gatewayURL.isEmpty) {
                AIKeyStore.shared.gatewayBaseURL = gatewayURL
                gatewayTest = nil
            } onSubmit: {
                AIKeyStore.shared.gatewayBaseURL = gatewayURL
                NotificationCenter.default.post(name: .aiClientChanged, object: nil)
            }

            gatewayField(icon: "key", placeholder: "CLIProxy api-key",
                         text: $gatewayKey, secure: true, filled: !gatewayKey.isEmpty) {
                AIKeyStore.shared.gatewayKey = gatewayKey
                gatewayTest = nil
            } onSubmit: {
                AIKeyStore.shared.gatewayKey = gatewayKey
                NotificationCenter.default.post(name: .aiClientChanged, object: nil)
            }

            gatewayModelPicker

            HStack(spacing: 8) {
                Button { Task { await testGateway() } } label: {
                    Label {
                        Text(gatewayTesting ? "Test ediliyor…" : "Bağlantıyı test et")
                    } icon: {
                        Lucide(sf: gatewayTesting ? "arrow.triangle.2.circlepath" : "bolt", size: 10)
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(gatewayTesting || gatewayURL.isEmpty)

                if let gatewayTest {
                    HStack(spacing: 4) {
                        Lucide(sf: gatewayTestOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", size: 10)
                        Text(gatewayTest).font(.system(size: 10.5)).lineLimit(1)
                    }
                    .foregroundStyle(gatewayTestOK ? Palette.positive : Palette.warning)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            Text("Kendi OpenAI-uyumlu proxy'n (CLIProxyAPI). URL + api-key gir → \"Bağlantıyı test et\" → havuzdaki TÜM modeller yukarıdaki menüde listelenir, tıkla seç. Aynı seçim Koç'a Sor chat'inde de var. Web araması bu modda kapalı.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private func gatewayField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        secure: Bool,
        filled: Bool,
        onEdit: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Lucide(sf: icon, size: 10)
                .foregroundStyle(Palette.textTertiary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(Palette.textPrimary)
            .onChange(of: text.wrappedValue) { _, _ in onEdit() }
            .onSubmit(onSubmit)
            if filled {
                Lucide(sf: "checkmark.circle.fill", size: 11)
                    .foregroundStyle(Palette.positive)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    /// Ayarları kaydedip `<base>/models`'i çeker; listeyi menüye yükler + sonucu raporlar.
    @MainActor
    private func testGateway() async {
        gatewayTesting = true
        gatewayTest = nil
        defer { gatewayTesting = false }

        // Alan değerlerini önce kaydet ki çekme canlı ayarı yansıtsın.
        AIKeyStore.shared.gatewayBaseURL = gatewayURL
        AIKeyStore.shared.gatewayKey = gatewayKey

        let count = await AIKeyStore.shared.refreshGatewayModels()
        gatewayModelList = AIKeyStore.shared.gatewayModels
        if count > 0 {
            gatewayTest = "Bağlandı · \(count) model"
            gatewayTestOK = true
            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
        } else {
            gatewayTest = "Bağlanılamadı — proxy açık mı, URL/api-key doğru mu?"
            gatewayTestOK = false
        }
    }

    /// Sessizce model listesini tazele (sekme açılışı / provider'a geçiş).
    @MainActor
    private func reloadGatewayModels() async {
        _ = await AIKeyStore.shared.refreshGatewayModels()
        gatewayModelList = AIKeyStore.shared.gatewayModels
    }

    /// Ayarlarda model seçimi — canlı liste varsa marka-gruplu menü, yoksa öneriler.
    private var gatewayModelPicker: some View {
        let models = gatewayModelList.isEmpty ? AIProvider.gateway.availableModels : gatewayModelList
        return Menu {
            ForEach(GatewayModelGrouping.grouped(models), id: \.family) { group in
                Section(group.family) {
                    ForEach(group.models, id: \.self) { m in
                        Button {
                            gatewayModel = m
                            AIKeyStore.shared.gatewayModel = m
                            model = m   // üst şeritteki etiketi güncelle
                            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                        } label: {
                            if m == gatewayModel { Label(m, systemImage: "checkmark") }
                            else { Text(m) }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Lucide(sf: "sparkles", size: 10).foregroundStyle(Palette.textTertiary)
                Text(gatewayModel.isEmpty ? "Model seç" : gatewayModel)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(gatewayModel.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(models.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                Lucide(sf: "chevron.up.chevron.down", size: 8).foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                switch codexStatus {
                case .noCodexCLI:
                    Circle().fill(Palette.warning).frame(width: 5, height: 5)
                    Text("Codex CLI bulunamadı")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("Terminal'de: codex login")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                case .ready(let acct):
                    Circle().fill(Palette.positive).frame(width: 5, height: 5)
                    Text("Bağlandı")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(acct.map { "\($0.prefix(8))…" } ?? "Token hazır")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                    Button {
                        Task { await reimport() }
                    } label: {
                        Lucide(sf: importing ? "arrow.triangle.2.circlepath" : "arrow.clockwise", size: 9)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().strokeBorder(Palette.border, lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(importing)
                    .help("auth.json'dan token'ı yeniden yükle")
                case .error(let m):
                    Circle().fill(Palette.negative).frame(width: 5, height: 5)
                    Text("Hata")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(m)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)

            // Import sonucu (başarı/hata mesajı)
            if let msg = importResult {
                HStack(spacing: 5) {
                    Lucide(sf: importSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", size: 10)
                    Text(msg)
                        .font(.system(size: 10.5))
                        .lineLimit(2)
                }
                .foregroundStyle(importSuccess ? Palette.positive : Palette.warning)
            }

            // Yardım butonu (toggle)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showLoginHelp.toggle() }
            } label: {
                Text("Token expire oldu / 401 hatası alıyorsan yeniden bağlan.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Yeniden bağlanma adımlarını göster")

            if showLoginHelp {
                loginHelpPanel
            }
        }
    }

    /// Codex login yardım paneli — token süresi dolduğunda yapılacaklar.
    private var loginHelpPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token expire olunca üç adım:")
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textSecondary)

            helpStep(num: "1", text: "Terminal'i aç ve şu komutu çalıştır:")
            HStack(spacing: 6) {
                Text("codex login")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Palette.background))

                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("codex login", forType: .string)
                    importResult = "✓ Komut panoya kopyalandı"
                    importSuccess = true
                    #else
                    importResult = "Bu kopyalama aksiyonu şu an Mac tarafında kullanılabiliyor"
                    importSuccess = false
                    #endif
                } label: {
                    Label { Text("Kopyala") } icon: { Lucide(sf: "doc.on.doc") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openTerminal()
                } label: {
                    Label { Text("Terminal'i Aç") } icon: { Lucide(sf: "terminal") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            helpStep(num: "2", text: "Browser açılacak — ChatGPT hesabınla giriş yap.")

            helpStep(num: "3", text: "Buraya dön, üstteki ↻ butonuna bas — yeni token yüklenir.")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private func helpStep(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(num)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Palette.accent.opacity(0.15)))
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func openTerminal() {
        #if os(macOS)
        // Terminal.app'i aç
        if let url = URL(string: "file:///System/Applications/Utilities/Terminal.app") {
            NSWorkspace.shared.open(url)
        }
        #else
        importResult = "Terminal aksiyonu iPhone tarafında kullanılmaz"
        importSuccess = false
        #endif
    }

    private func refreshCodexStatus() {
        codexStatus = CodexAuth.shared.currentStatus()
    }

    @MainActor
    private func reimport() async {
        importing = true
        importResult = nil
        defer { importing = false }

        // 1) auth.json'dan token yükle
        let tokens: CodexTokens
        do {
            tokens = try CodexAuth.shared.importFromCodexCLI()
        } catch {
            importResult = "Token dosyası okunamadı: \(error.localizedDescription). Terminal'de 'codex login' çalıştır."
            importSuccess = false
            showLoginHelp = true
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            importResult = nil
            return
        }

        // 2) Gerçek test — refresh endpoint'ine post et. Bu sunucunun token'ı
        //    hala kabul edip etmediğini canlı doğrular.
        do {
            _ = try await CodexAuth.shared.refresh(tokens)
            refreshCodexStatus()
            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
            importResult = "✓ Token doğrulandı — chat hazır"
            importSuccess = true
            showLoginHelp = false
        } catch {
            // Refresh API'den hata geldi — token sunucuda invalidated, yeniden login gerek
            let msg = error.localizedDescription
            if msg.contains("401") || msg.lowercased().contains("invalid") || msg.lowercased().contains("reused") {
                importResult = "Token sunucuda geçersiz — 'codex login' çalıştırman gerekiyor."
            } else {
                importResult = "Doğrulama başarısız: \(msg)"
            }
            importSuccess = false
            showLoginHelp = true
        }

        try? await Task.sleep(nanoseconds: 6_000_000_000)
        importResult = nil
    }
}

extension Notification.Name {
    static let aiClientChanged = Notification.Name("hercules.ai.client.changed")
}

// MARK: - Cloud sync card
