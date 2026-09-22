import SwiftUI
import SwiftData
import LucideKit
import UIKit

@main
struct HerculesMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var appDelegate
    let container: ModelContainer

    init() {
        // Lucide ikon fontunu süreç geneline kaydet.
        LucideFont.registerIfNeeded()

        do {
            let fm = FileManager.default
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("Hercules", isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            let config = ModelConfiguration(
                url: dir.appendingPathComponent("Hercules.store"),
                cloudKitDatabase: .private("iCloud.com.samorai.hercules")
            )
            let models: [any PersistentModel.Type] = [
                Measurement.self,
                ProgressPhoto.self,
                UserProfile.self,
                Recipe.self,
                RecipeVideo.self,
                FoodEntry.self,
                FoodPreset.self,
                WorkoutSession.self,
                WorkoutTemplateExercise.self,
                WorkoutProgramArchive.self,
                WorkoutPlanOverride.self,
                StepEntry.self,
                MonthlyGoal.self,
                WorkoutLog.self,
                WorkoutExerciseEntry.self,
                ExerciseSet.self,
                FeedItem.self,
                LabPanel.self,
                LabResult.self,
            ]
            container = try ModelContainer(for: Schema(models), configurations: config)

            let ctx = container.mainContext
            // Observer kurulumu launch yolunda kalmalı: HealthKit uygulamayı arka
            // planda uyandırdığında callback'i kaçırmayalım.
            HealthService.shared.installLaunchObservers(into: ctx)
            CloudSyncMonitor.shared.start(container: container)
            DemoSeed.seedIfEmpty(ctx)
            DemoSeed.dedupUserProfiles(ctx)
            #if DEBUG && targetEnvironment(simulator)
            // Yalnız simülatörde ve yalnız açıkça istendiğinde: tasarım üstünde
            // çalışırken boş ekranlara bakmamak için gerçekçi demo store.
            DemoSeed.seedSampleDataIfRequested(ctx)
            #endif
            // Kalan bakım işleri İLK KAREDEN SONRA: bunlar filtresiz tam-tablo
            // fetch'leri (StepEntry yılların satırını tutabilir) ve hepsi ilk body
            // çalışmadan önce ana thread'i bloke ediyordu → uzun cold launch,
            // büyük store'da watchdog riski.
            let bootContainer = container
            Task { @MainActor in
                let bootCtx = bootContainer.mainContext
                FoodPresetSeed.upsertDefaults(bootCtx)
                SyncDataReconciler.reconcile(in: bootCtx)
                // Koç adı ve avatarlar Mac'ten gelir; koç sekmesine girilmesini
                // beklemeden açılışta çekiyoruz (profil sayfası da bunu gösteriyor).
                await MobileChatStore.shared.syncIdentityFromMac()
            }
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
        }
        .modelContainer(container)
    }
}

final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            HealthService.shared.installLaunchObservers()
        }
        return true
    }
}
