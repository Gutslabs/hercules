import SwiftUI
import SwiftData

@main
struct HerculesMobileApp: App {
    let container: ModelContainer

    init() {
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

            let config = ModelConfiguration(url: dir.appendingPathComponent("Hercules.store"))
            container = try ModelContainer(
                for: Measurement.self,
                UserProfile.self,
                Recipe.self,
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
                configurations: config
            )

            let ctx = container.mainContext
            DemoSeed.seedIfEmpty(ctx)
            FoodPresetSeed.upsertDefaults(ctx)
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
