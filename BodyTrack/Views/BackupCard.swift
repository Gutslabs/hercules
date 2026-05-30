import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("Yedekleme").eyebrow()
                }
                Spacer()
                if let date = lastBackup {
                    Text("Son: \(Fmt.dateLong.string(from: date))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    Text("Henüz yedek yok")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.warning)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                    Text(backupLocationText)
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let size = backupSize {
                        Text("· \(formatSize(size))")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Image(systemName: BackupService.shared.iCloudMirrorAvailable ? "icloud" : "icloud.slash")
                        .font(.system(size: 11, weight: .semibold))
                    Text(BackupService.shared.iCloudMirrorAvailable ? "iCloud Drive mirror aktif" : "iCloud Drive klasörü bulunamadı")
                        .font(Typography.captionBold)
                    if BackupService.shared.iCloudBackupExists {
                        Text("· yedek var")
                            .font(Typography.caption)
                    }
                }
                .foregroundStyle(BackupService.shared.iCloudMirrorAvailable ? Palette.positive : Palette.textTertiary)

                vaultStatusBlock

                Text("Ölçümler, antrenmanlar, takvim, tarifler, profil, Hakkında, chat geçmişi, memory, research cache ve presetler bu sisteme girer. Restore öncesi otomatik safety backup alınır; vault yazarken çakışma yakalanırsa eski dosya conflicts klasörüne kopyalanır.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                Button(action: backupNow) {
                    backupActionLabel("Yedekle", systemImage: "arrow.up.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .help("Şimdi yedekle (⌘⇧B)")

                Button(action: revealInFinder) {
                    backupActionLabel("Finder", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!BackupService.shared.backupExists)
                .help("Yedek klasörünü Finder'da göster")

                Button(action: selectVaultFolder) {
                    backupActionLabel("Klasör", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(vaultConfigured ? "Vault klasörünü değiştir" : "Veri klasörü seç")

                Button(action: exportVaultNow) {
                    backupActionLabel("Vault Yaz", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!vaultConfigured)
                .help("Vault klasörüne yaz")

                Button(role: .destructive) {
                    showRestoreConfirm = true
                } label: {
                    backupActionLabel("Geri Al", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.warning)
                .disabled(!BackupService.shared.backupExists || importing)
                .help("Local yedekten geri yükle")

                Button(role: .destructive) {
                    showVaultRestoreConfirm = true
                } label: {
                    backupActionLabel("Vault Al", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.warning)
                .disabled(!vaultBackupExists || importing)
                .help("Vault snapshot'ını içeri al")
            }

            if let msg = statusMessage {
                Text(msg)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.positive)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
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

    private var vaultStatusBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: vaultConfigured ? "externaldrive.connected.to.line.below" : "externaldrive.badge.questionmark")
                    .font(.system(size: 11, weight: .semibold))
                Text(vaultConfigured ? "Dosya tabanlı vault aktif" : "Dosya tabanlı vault seçilmedi")
                    .font(Typography.captionBold)
                if let vaultLastSync {
                    Text("· \(Fmt.dateLong.string(from: vaultLastSync))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .foregroundStyle(vaultConfigured ? Palette.positive : Palette.warning)

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                Text(BackupService.shared.vaultDisplayPath)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            if vaultConfigured {
                Text("Klasör yapısı: manifest.json, data/hercules-backup.json, support/, backups/, conflicts/. iPhone tarafında aynı klasör seçildiğinde bu snapshot okunacak.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func backupActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(Typography.captionBold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
