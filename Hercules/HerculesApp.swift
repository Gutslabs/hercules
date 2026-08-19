import SwiftUI
import SwiftData
import LucideKit
#if os(macOS)
import AppKit
#endif

@main
struct HerculesApp: App {
    let container: ModelContainer
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        let testEnvironment = ProcessInfo.processInfo.environment
        let isRunningTests = testEnvironment["XCTestConfigurationFilePath"] != nil
            || testEnvironment["XCTestBundlePath"] != nil
            || testEnvironment["XCInjectBundleInto"] != nil
            || NSClassFromString("XCTestCase") != nil
        #if os(macOS)
        // TEK-INSTANCE KORUMASI: Aynı SQLite store'u iki süreç açamaz. LaunchAgent
        // (sabah 08/10) uygulama zaten açıkken ikinci bir kopya başlatırsa, store
        // çakışır → "Hercules.store couldn't be opened" + yazımlar geri alınır (veri
        // kaybı). Bu yüzden zaten çalışan bir instance varsa, bu duplicate süreç
        // store'a HİÇ DOKUNMADAN hemen çıkar; açık olan instance işi yürütür.
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != myPID }
        if !isRunningTests, !others.isEmpty {
            // ODAK ÇALMA YOK: bu duplicate süreç kullanıcıdan değil, arka plandan da
            // doğmuş olabilir (LaunchAgent / login item / `open -gj`). Çalışan
            // instance'ı buradan aktive etmek, kullanıcı başka bir uygulamadayken
            // Hercules'i öne fırlatıyordu — remote-ai agent'ı dakikada bir
            // tetiklendiği için pratikte sürekli odak çalınması demekti. Kullanıcı
            // elle çift açtığında pencereyi zaten LaunchServices öne getirir;
            // bu süreç store'a dokunmadan sessizce çıkar.
            exit(0)
        }
        #endif

        // Lucide ikon fontunu süreç geneline kaydet (Lucide view'ları lazy de kaydeder; bu garanti).
        LucideFont.registerIfNeeded()

        do {
            let fm = FileManager.default
            let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = appSupport.appendingPathComponent("Hercules", isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let storeURL = dir.appendingPathComponent("Hercules.store")
            // Entitlement kontrolü container KURULMADAN önce: `.private(...)` verilince
            // SwiftData CloudKit container'ını hemen kuruyor ve entitlement yoksa süreç
            // SIGTRAP ile ölüyor — kontrol eskiden bu satırdan SONRA çalışıyordu.
            let config: ModelConfiguration
            if isRunningTests {
                config = ModelConfiguration(isStoredInMemoryOnly: true)
            } else if CloudSyncMonitor.cloudKitEntitlementPresent {
                config = ModelConfiguration(
                    url: storeURL,
                    cloudKitDatabase: .private("iCloud.com.samorai.hercules")
                )
            } else {
                config = ModelConfiguration(url: storeURL)
            }
            let models: [any PersistentModel.Type] = [
                Measurement.self, ProgressPhoto.self, UserProfile.self, Recipe.self, RecipeVideo.self, FoodEntry.self, FoodPreset.self, WorkoutSession.self, WorkoutTemplateExercise.self, WorkoutProgramArchive.self, WorkoutPlanOverride.self, StepEntry.self, MonthlyGoal.self, WorkoutLog.self, WorkoutExerciseEntry.self, ExerciseSet.self, CoachReport.self, CoachFocusItem.self, CoachRecipe.self, FeedItem.self,
            ]
            container = try ModelContainer(for: Schema(models), configurations: config)
            if !isRunningTests {
                CloudSyncMonitor.shared.start(container: container)
                // 1) Önce default profil/workout seed (boşsa) — bu ucuz ve ilk
                //    kareden önce profil gerekiyor.
                DemoSeed.seedIfEmpty(container.mainContext)
                DemoSeed.dedupUserProfiles(container.mainContext)
                // 2) Geri kalanı İLK KAREDEN SONRA. Bunlar ~13 filtresiz tam-tablo
                //    fetch'i demek (StepEntry yılların satırını tutabiliyor) ve hepsi
                //    launch yolunda, ana thread'de, ilk body çalışmadan önce koşuyordu.
                let bootContainer = container
                Task { @MainActor in
                    let ctx = bootContainer.mainContext
                    FoodPresetSeed.upsertDefaults(ctx)
                    FeedStore.migrateLegacyFile(into: ctx)
                    SyncDataReconciler.reconcile(in: ctx)
                }
            }
            #if os(macOS)
            if !isRunningTests {
                // iPhone'daki Hercules AI isteklerini Tailscale Serve üzerinden alan
                // loopback-only sunucu. Kimlik/allowlist kontrolü her istekte yapılır.
                RemoteAIServer.shared.start(context: container.mainContext)
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

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bridgeOnlyLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--island-bridge")
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard bridgeOnlyLaunch else { return }
        // Copper yalnız veri/AI köprüsünü istediğinde Hercules'in pencere veya
        // Dock ikonu göstermesine gerek yok. Kullanıcı app ikonuna sonradan
        // tıklarsa applicationShouldHandleReopen normal arayüzü geri getirir.
        NSApp.setActivationPolicy(.accessory)
    }

    /// Eski sabah-08:00 LaunchAgent'ı (varsa) diskten temizle. Koç özelliği kaldırıldı;
    /// daha önce kurulmuş bir agent geride kalmasın diye her açılışta uninstall çağrılır.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let isRunningTests = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCInjectBundleInto"] != nil
            || NSClassFromString("XCTestCase") != nil
        guard !isRunningTests else { return }
        // Yalnız gerçekten kurulu bir agent varken temizle: koşulsuz `uninstall()`
        // her açılışta bir fork/exec + launchd IPC'si demekti (ilk temizlikten
        // sonra sonsuza dek boşa).
        if CoachLaunchAgent.isInstalled {
            Task.detached { CoachLaunchAgent.uninstall() }
        }
        if bridgeOnlyLaunch {
            DispatchQueue.main.async {
                NSApp.windows.forEach { $0.orderOut(nil) }
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else { return true }
        if sender.activationPolicy() == .accessory {
            sender.setActivationPolicy(.regular)
        }
        sender.windows.first?.makeKeyAndOrderFront(nil)
        sender.activate(ignoringOtherApps: true)
        return true
    }

    /// On-device embedding modeli yüzlerce MB tutar. App odağı kaybolduğunda bırak;
    /// sonraki gerçek semantic sorgu diskteki modeli lazy-load eder.
    ///
    /// Gecikmeli + iptal edilebilir: `resignActive` her ⌘-Tab'da, her Spotlight'ta
    /// tetikleniyor. Anında boşaltmak, tarayıcıyla Hercules arasında gidip gelen
    /// kullanıcıya her dönüşte yüzlerce MB'lık yeniden yükleme ödetiyordu.
    private var embeddingUnloadTask: Task<Void, Never>?

    func applicationDidResignActive(_ notification: Notification) {
        embeddingUnloadTask?.cancel()
        embeddingUnloadTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await EmbeddingService.shared.unload()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        embeddingUnloadTask?.cancel()
        embeddingUnloadTask = nil
    }

}
#endif
