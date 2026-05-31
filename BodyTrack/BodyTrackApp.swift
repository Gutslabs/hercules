import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct BodyTrackApp: App {
    let container: ModelContainer
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        do {
            let fm = FileManager.default
            let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = appSupport.appendingPathComponent("Hercules", isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let storeURL = dir.appendingPathComponent("Hercules.store")
            let config = ModelConfiguration(url: storeURL)
            container = try ModelContainer(
                for: Measurement.self, UserProfile.self, Recipe.self, FoodEntry.self, FoodPreset.self, WorkoutSession.self, WorkoutTemplateExercise.self, WorkoutProgramArchive.self, WorkoutPlanOverride.self, StepEntry.self, MonthlyGoal.self, WorkoutLog.self, WorkoutExerciseEntry.self, ExerciseSet.self, UserGuideSection.self, UserGuideCard.self, Exercise.self, TrainingProgram.self, TrainingWeek.self, TrainingDay.self, TrainingBlock.self,
                configurations: config
            )
            // 1) Önce default profil/workout seed (boşsa)
            DemoSeed.seedIfEmpty(container.mainContext)
            FoodPresetSeed.upsertDefaults(container.mainContext)
            // 2) Sonra JSON yedekten otomatik geri yükle (store boşsa)
            let ctx = container.mainContext
            Task { @MainActor in
                BackupService.shared.importIfStoreEmpty(into: ctx)
                BackupService.shared.restoreFromICloudIfNewer(into: ctx)
                BackupService.shared.restoreFromVaultIfNewer(into: ctx)
                FoodPresetSeed.upsertDefaults(ctx)
                ShortcutHealthSyncService.shared.startAutoImport(into: ctx)
                // Embedding modeli zaten indirilmişse yükle (indirme TETİKLEMEZ) ve
                // eksik hafıza embedding'lerini arka planda tamamla.
                await EmbeddingService.shared.warmUpIfDownloaded()
                await MemoryManager.shared.embedPendingMemories()
            }
            // 3) AppDelegate'e container'ı paylaş — quit'te yedek alacak
            #if os(macOS)
            AppDelegate.sharedContainer = container
            #endif
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 720)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        .commands {
            // App menüsünde Hercules-specific actions
            CommandMenu("Hercules") {
                Button("Şimdi Yedekle") {
                    _ = BackupService.shared.export(from: container.mainContext)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Health Sync Dosyasını İçe Aktar") {
                    ShortcutHealthSyncService.shared.importIfAvailable(into: container.mainContext)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Yedek Klasörünü Aç") {
                    NSWorkspace.shared.activateFileViewerSelecting([BackupService.shared.backupURL])
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Yedek Konumunu Kopyala") {
                    let path = BackupService.shared.backupURL.path
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }

            // "New" komutu — aktif view'deki ⌘N'yi zaten kullanıyoruz,
            // burası genel bir kategori başlığı.
            CommandGroup(replacing: .newItem) {
                // Boş — her view kendi ⌘N'sini ToolbarItem üzerinden veriyor.
            }
        }
        #else
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        #endif
    }
}

/// App quit / sleep / background olduğunda JSON yedek al.
#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedContainer: ModelContainer?

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            if let ctx = Self.sharedContainer?.mainContext {
                _ = BackupService.shared.export(from: ctx)
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // UI'ı dondurmamak için async export — fetch main'de, encode/write background'da.
        Task { @MainActor in
            if let ctx = Self.sharedContainer?.mainContext {
                BackupService.shared.exportAsync(from: ctx)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            if let ctx = Self.sharedContainer?.mainContext {
                BackupService.shared.restoreFromVaultIfNewer(into: ctx)
                ShortcutHealthSyncService.shared.importIfAvailable(into: ctx)
            }
        }
    }
}
#endif
