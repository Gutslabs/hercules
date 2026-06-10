import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// AI Sağlayıcı — Sistem kartının sol bölümü (kart kromu ProfileView.systemCard'da).
struct AIProviderCard: View {
    @State private var provider: AIProvider = AIKeyStore.shared.provider
    @State private var model: String = AIKeyStore.shared.model
    @State private var apiKey: String = ""
    @State private var codexStatus: CodexAuth.Status = .noCodexCLI
    @State private var importing = false
    @State private var importResult: String? = nil       // başarı/hata mesajı
    @State private var importSuccess: Bool = false       // ikon rengi için
    @State private var showLoginHelp: Bool = false       // yardım panelini aç/kapat

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

            if provider == .codex {
                codexSection
            } else {
                openRouterSection
            }
        }
        .padding(.init(top: 20, leading: 28, bottom: 18, trailing: 28))
        .onAppear {
            refreshCodexStatus()
            apiKey = AIKeyStore.shared.apiKey   // kayıtlı anahtarı alana yansıt
        }
    }

    private var openRouterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "key")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                SecureField("sk-or-...", text: $apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .onChange(of: apiKey) { _, newValue in
                        AIKeyStore.shared.apiKey = newValue   // her değişiklikte sessizce kaydet (kayıp olmasın)
                    }
                    .onSubmit {
                        AIKeyStore.shared.apiKey = apiKey
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    }
                if !apiKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
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
                        Image(systemName: importing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().strokeBorder(Palette.border, lineWidth: 1))
                            .contentShape(Circle())
                            .symbolEffect(.rotate, value: importing)
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
                    Image(systemName: importSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
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
                    Label("Kopyala", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openTerminal()
                } label: {
                    Label("Terminal'i Aç", systemImage: "terminal")
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

// MARK: - Backup card
