import SwiftUI
import SwiftData
import AppKit

@main
struct BodyTrackApp: App {
    let container: ModelContainer
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
                for: Measurement.self, UserProfile.self, Recipe.self, FoodEntry.self, WorkoutSession.self, WorkoutPlanOverride.self, StepEntry.self, MonthlyGoal.self, MealPlanOverride.self, WorkoutLog.self, WorkoutExerciseEntry.self, ExerciseSet.self,
                configurations: config
            )
            // 1) Önce default profil/workout seed (boşsa)
            DemoSeed.seedIfEmpty(container.mainContext)
            // 2) Sonra JSON yedekten otomatik geri yükle (store boşsa)
            let ctx = container.mainContext
            Task { @MainActor in
                BackupService.shared.importIfStoreEmpty(into: ctx)
                BackupService.shared.restoreFromICloudIfNewer(into: ctx)
                ShortcutHealthSyncService.shared.startAutoImport(into: ctx)
            }
            // 3) AppDelegate'e container'ı paylaş — quit'te yedek alacak
            AppDelegate.sharedContainer = container
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }

    var body: some Scene {
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
    }
}

/// App quit / sleep / background olduğunda JSON yedek al.
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
                ShortcutHealthSyncService.shared.importIfAvailable(into: ctx)
            }
        }
    }
}

enum DemoSeed {
    static func seedIfEmpty(_ ctx: ModelContext) {
        let profileCount = (try? ctx.fetchCount(FetchDescriptor<UserProfile>())) ?? 0
        let workoutCount = (try? ctx.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0

        if profileCount == 0 {
            let p = UserProfile(
                name: "",
                sex: .male,
                birthDate: Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now,
                height: 178,
                activity: .moderate,
                goal: .maintain
            )
            ctx.insert(p)
        }

        if workoutCount == 0 {
            // Salı (3) - Sırt + Göğüs, Perşembe (5) - Biceps + Triceps, Cumartesi (7) - Karın + Bacak
            let defaults = [
                WorkoutSession(weekday: 3, name: "Sırt + Göğüs", estimatedCalories: 350),
                WorkoutSession(weekday: 5, name: "Biceps + Triceps", estimatedCalories: 280),
                WorkoutSession(weekday: 7, name: "Karın + Bacak", estimatedCalories: 380)
            ]
            for w in defaults { ctx.insert(w) }
        }

        try? ctx.save()
    }
}
