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
        #if os(macOS)
        // TEK-INSTANCE KORUMASI: Aynı SQLite store'u iki süreç açamaz. LaunchAgent
        // (sabah 08/10) uygulama zaten açıkken ikinci bir kopya başlatırsa, store
        // çakışır → "Hercules.store couldn't be opened" + yazımlar geri alınır (veri
        // kaybı). Bu yüzden zaten çalışan bir instance varsa, bu duplicate süreç
        // store'a HİÇ DOKUNMADAN hemen çıkar; açık olan instance işi yürütür.
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != myPID }
        if !others.isEmpty {
            // Var olan instance'ı öne getir (kullanıcı elle çift açtıysa), sonra çık.
            _ = others.first?.activate(options: [])
            exit(0)
        }
        #endif
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
                for: Measurement.self, UserProfile.self, Recipe.self, FoodEntry.self, FoodPreset.self, WorkoutSession.self, WorkoutTemplateExercise.self, WorkoutProgramArchive.self, WorkoutPlanOverride.self, StepEntry.self, MonthlyGoal.self, WorkoutLog.self, WorkoutExerciseEntry.self, ExerciseSet.self, CoachReport.self, CoachFocusItem.self, CoachRecipe.self,
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
                await BackupService.shared.autoSyncWithVault(into: ctx) // vault: pull-merge + push
                FoodPresetSeed.upsertDefaults(ctx)
                ShortcutHealthSyncService.shared.startAutoImport(into: ctx)
            }
            // 3) AppDelegate'e container'ı paylaş — quit'te yedek alacak
            #if os(macOS)
            AppDelegate.sharedContainer = container
            // 4) Embedding modeli zaten indirildiyse launch'ta arka planda RAM'e ısıt —
            //    her sohbet (Hafıza ekranını açmaya gerek kalmadan) semantic retrieval
            //    kullansın. Diskte yoksa DOKUNMAZ (2.4GB indirmeyi tetiklemez).
            Task {
                await EmbeddingService.shared.warmUpIfDownloaded()
                await MemoryManager.shared.embedPendingMemories()
            }
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

    /// Eski sabah-08:00 LaunchAgent'ı (varsa) diskten temizle. Koç özelliği kaldırıldı;
    /// daha önce kurulmuş bir agent geride kalmasın diye her açılışta uninstall çağrılır.
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached { CoachLaunchAgent.uninstall() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // SENKRON çağrı — Task{} sadece main-actor kuyruğuna iş ekler; quit'te run loop
        // bir daha dönmeden exit() çağrıldığı için o iş HİÇ çalışmaz (ölü kod). NSApplicationDelegate
        // zaten @MainActor, BackupService de @MainActor + senkron export → doğrudan çağır.
        if let ctx = Self.sharedContainer?.mainContext {
            _ = BackupService.shared.export(from: ctx)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // UI'ı dondurmamak için async export — fetch main'de, encode/write background'da.
        Task { @MainActor in
            if let ctx = Self.sharedContainer?.mainContext {
                BackupService.shared.exportAsync(from: ctx)
                await BackupService.shared.autoSyncWithVault(into: ctx) // değişiklikleri vault'a it
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Artık güvenli: vault senkronu MERGE (union) — ezmez, katar. Foreground'da
        // otomatik pull-merge + push (throttle'lı). Health import additive.
        Task { @MainActor in
            if let ctx = Self.sharedContainer?.mainContext {
                ShortcutHealthSyncService.shared.importIfAvailable(into: ctx)
                await BackupService.shared.autoSyncWithVault(into: ctx)
            }
        }
    }
}
#endif
