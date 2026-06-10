import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Yedekleme — Sistem kartının sağ bölümü (kart kromu ProfileView.systemCard'da).
struct BackupCard: View {
    @Environment(\.modelContext) private var ctx
    @State private var lastBackup: Date? = nil
    @State private var backupSize: Int? = nil
    @State private var vaultLastSync: Date? = nil
    @State private var vaultConfigured = false
    @State private var vaultBackupExists = false
    @State private var statusMessage: String? = nil
    @State private var showRestoreConfirm = false
    @State private var showVaultRestoreConfirm = false
    @State private var importing = false

    private var systemsHealthy: Bool {
        BackupService.shared.iCloudMirrorAvailable && vaultConfigured
    }

    private var systemsStatusText: String {
        let mirror = BackupService.shared.iCloudMirrorAvailable ? "iCloud mirror aktif" : "iCloud mirror yok"
        let vault = vaultConfigured ? "vault aktif" : "vault seçilmedi"
        return "\(mirror) · \(vault)"
    }

    private var lastBackupText: String {
        guard let date = lastBackup else { return "Henüz yedek yok" }
        var text = "Son: \(Fmt.dateLong.string(from: date))"
        if let size = backupSize { text += " · \(formatSize(size))" }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Yedekleme").eyebrow()
                HStack(spacing: 6) {
                    Circle()
                        .fill(systemsHealthy ? Palette.positive : Palette.warning)
                        .frame(width: 5, height: 5)
                    Text(systemsStatusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.leading, 10)
                Spacer(minLength: Spacing.md)
                Text(lastBackupText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(lastBackup == nil ? Palette.warning : Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(backupLocationText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 12)
            Text(BackupService.shared.vaultDisplayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 4)
                .help(vaultConfigured
                      ? "Vault klasör yapısı: manifest.json, data/, support/, backups/, conflicts/. iPhone'da aynı klasör seçilince bu snapshot okunur."
                      : "Henüz vault klasörü seçilmedi — Klasör butonuyla seç.")

            Text("Ölçümler, antrenmanlar, takvim, tarifler, profil, Hakkımda, chat geçmişi, memory ve presetler bu sisteme girer. Restore öncesi otomatik safety backup alınır; çakışma yakalanırsa eski dosya conflicts klasörüne kopyalanır.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            ChatHintFlow(spacing: 8) {
                Button(action: syncNow) {
                    Text("Şimdi Senkronize Et")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.btnFg)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(importing)
                .help("Mobil/diğer cihazların verisini çek + kendi verini yaz (iki yönlü)")

                ghostButton("Yedekle", action: backupNow)
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .help("Şimdi yedekle (⌘⇧B)")

                ghostButton("Finder", disabled: !BackupService.shared.backupExists, action: revealInFinder)
                    .help("Yedek klasörünü Finder'da göster")

                ghostButton("Klasör", action: selectVaultFolder)
                    .help(vaultConfigured ? "Vault klasörünü değiştir" : "Veri klasörü seç")

                ghostButton("Vault Yaz", disabled: !vaultConfigured, action: exportVaultNow)
                    .help("Vault klasörüne yaz")

                ghostButton("Geri Al", disabled: !BackupService.shared.backupExists || importing) {
                    showRestoreConfirm = true
                }
                .help("Local yedekten geri yükle")

                ghostButton("Vault Al", disabled: !vaultBackupExists || importing) {
                    showVaultRestoreConfirm = true
                }
                .help("Vault snapshot'ını içeri al")
            }
            .padding(.top, 13)

            if let msg = statusMessage {
                Text(msg)
                    .font(.system(size: 10.5))
                    .foregroundStyle(msg.hasPrefix("✓") ? Palette.positive : Palette.warning)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .padding(.init(top: 20, leading: 28, bottom: 18, trailing: 28))
        .onAppear { refreshInfo() }
        .alert("Geri Yükle?", isPresented: $showRestoreConfirm) {
            Button("İptal", role: .cancel) { }
            Button("Tüm veriyi değiştir", role: .destructive) { restoreNow() }
        } message: {
            Text("Mevcut tüm veri silinip yedekteki veriyle değiştirilecek. Önce bir yedek aldığından emin ol.")
        }
        .alert("Vault'tan Geri Yükle?", isPresented: $showVaultRestoreConfirm) {
            Button("İptal", role: .cancel) { }
            Button("Tüm veriyi değiştir", role: .destructive) { restoreVaultNow() }
        } message: {
            Text("Seçili veri klasöründeki snapshot içeri alınacak. Mevcut local verinin safety backup'ı önce hem local yedeklere hem vault/backups içine yazılır.")
        }
    }

    private func ghostButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(disabled ? Palette.textQuaternary : Palette.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func backupNow() {
        let ok = BackupService.shared.export(from: ctx)
        statusMessage = ok ? "✓ Yedek alındı" : "Yedek alınamadı"
        refreshInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            statusMessage = nil
        }
    }

    private func restoreNow() {
        importing = true
        defer { importing = false }
        do {
            try BackupService.shared.restore(from: BackupService.shared.latestBackupURL, into: ctx, mode: .replaceAll)
            statusMessage = "✓ Geri yüklendi"
        } catch {
            statusMessage = "Hata: \(error.localizedDescription)"
        }
        refreshInfo()
    }

    private func selectVaultFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Hercules veri klasörünü seç"
        panel.message = "iCloud Drive/Hercules gibi cihazların arasında sync olacak bir klasör seç."
        panel.prompt = "Bu Klasörü Kullan"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let summary = try BackupService.shared.configureVaultRoot(url, from: ctx)
                statusMessage = summary.didWriteConflictCopy
                    ? "✓ Vault seçildi, mevcut uzak kopya conflicts içine korundu"
                    : "✓ Vault seçildi ve tüm veri yazıldı"
            } catch {
                statusMessage = "Vault hata: \(error.localizedDescription)"
            }
            refreshInfo()
        }
        #endif
    }

    private func exportVaultNow() {
        do {
            let summary = try BackupService.shared.exportToVault(from: ctx)
            statusMessage = summary.didWriteConflictCopy
                ? "✓ Vault yazıldı, eski uzak kopya conflicts içine alındı"
                : "✓ Vault yazıldı"
        } catch {
            statusMessage = "Vault hata: \(error.localizedDescription)"
        }
        refreshInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            statusMessage = nil
        }
    }

    private func restoreVaultNow() {
        importing = true
        defer { importing = false }
        do {
            try BackupService.shared.restoreFromVault(into: ctx)
            statusMessage = "✓ Vault'tan geri yüklendi"
        } catch {
            statusMessage = "Vault hata: \(error.localizedDescription)"
        }
        refreshInfo()
    }

    /// Tek dokunuşla iki-yönlü senkron: diğer cihazların (mobil) yazdığı daha yeni
    /// veriyi vault + iCloud'dan çek, sonra yerel veriyi tüm hedeflere yaz.
    private func syncNow() {
        importing = true
        Task { @MainActor in
            // Tam iki-yönlü merge senkron (pull-merge + push), bloklamayan.
            let syncError = await BackupService.shared.syncWithVaultNonBlocking(into: ctx)
            BackupService.shared.restoreFromICloudIfNewer(into: ctx) // legacy iCloud mirror (gated)
            FoodPresetSeed.upsertDefaults(ctx)
            _ = BackupService.shared.export(from: ctx)                // yerel yedek
            // Push başarısızsa sahte "✓" gösterme — gerçek hatayı bildir.
            if let syncError {
                statusMessage = "Senkron hatası: \(syncError.localizedDescription)"
            } else {
                statusMessage = "✓ " + BackupService.shared.syncDiagnostics(ctx: ctx)
            }
            refreshInfo()
            importing = false
        }
    }

    private func revealInFinder() {
        #if os(macOS)
        if let vaultURL = BackupService.shared.selectedVaultRootURL {
            NSWorkspace.shared.activateFileViewerSelecting([vaultURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([BackupService.shared.latestBackupURL])
        }
        #endif
    }

    private func refreshInfo() {
        lastBackup = BackupService.shared.lastBackupDate
        backupSize = BackupService.shared.backupSizeBytes
        vaultLastSync = BackupService.shared.vaultLastSyncDate
        vaultConfigured = BackupService.shared.vaultIsConfigured
        vaultBackupExists = BackupService.shared.vaultBackupExists
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    private var backupLocationText: String {
        if BackupService.shared.iCloudMirrorAvailable {
            return "~/Documents/Hercules + iCloud Drive/Hercules"
        }
        return "~/Documents/Hercules/hercules-backup.json"
    }
}
