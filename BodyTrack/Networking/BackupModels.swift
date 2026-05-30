import Foundation
import SwiftData

struct HerculesBackup: Codable {
    let version: Int
    let exportedAt: Date
    let profile: ProfileSnapshot?
    let measurements: [MeasurementSnapshot]
    let foods: [FoodSnapshot]
    /// v7+: tek tık kalori/makro presetleri.
    let foodPresets: [FoodPresetSnapshot]?
    let workouts: [WorkoutSnapshot]
    let workoutArchives: [WorkoutArchiveSnapshot]?
    let workoutPlanOverrides: [WorkoutPlanOverrideSnapshot]?
    let recipes: [RecipeSnapshot]
    let steps: [StepSnapshot]
    let monthlyGoals: [MonthlyGoalSnapshot]?
    /// v2+: gerçek antrenman log'ları (her log'un exercise+set'leri nested).
    let workoutLogs: [WorkoutLogSnapshot]?
    /// v3+: Application Support/Hercules altındaki JSON state dosyaları.
    let supportFiles: [SupportFileSnapshot]?
    /// v3+: SwiftData dışında kalan küçük UserDefaults tercihleri.
    let preferences: [PreferenceSnapshot]?
    /// v13+: kayıt başına son-değişiklik zamanı (mergeKey → updatedAt). Union-merge'de
    /// aynı anahtar çakışırsa yenisi kazansın diye. Eski snapshot'larda nil.
    let recordTimestamps: [String: Date]?
    /// v13+: silinen kayıtların mezar taşları — silme propagate olsun, geri dirilmesin.
    let tombstones: [TombstoneSnapshot]?
}

/// Bir kaydın silindiğini iki-yönlü merge'e bildiren kayıt. `key` = entity'nin
/// türetilmiş merge anahtarı (örn. "f-1717180000000-kıyma").
struct TombstoneSnapshot: Codable, Hashable {
    let entity: String
    let key: String
    let deletedAt: Date
}

struct ProfileSnapshot: Codable {
    let name: String
    let sex: String
    let birthDate: Date
    let height: Double
    let activity: String
    let goal: String
    let targetWeight: Double?
    let manualBodyFat: Double?
    let manualCalorieOffset: Double
    let manualCalorieOffsetMacro: String?
    let manualProteinGrams: Double?
    let manualCarbsGrams: Double?
    let manualFatGrams: Double?
    /// v2+: AI'a sürekli enjekte edilen "hakkında" metni.
    let about: String?
    /// v12+: AI'a kalıcı profil bilgisi olarak verilen supplement listesi.
    let supplements: String?
}

struct MeasurementSnapshot: Codable {
    let date: Date
    let weight: Double?
    let bodyFat: Double?
    let waist: Double?
    let chest: Double?
    let neck: Double?
    let note: String?
}

struct FoodSnapshot: Codable {
    let date: Date
    let name: String
    let grams: Double?
    let calories: Double
    let protein: Double?
    let carbs: Double?
    let fat: Double?
}

struct FoodPresetSnapshot: Codable {
    let presetID: String
    let name: String
    let brand: String
    let category: String
    let servingLabel: String
    let servingGrams: Double
    let defaultServings: Double
    let calories: Double
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let note: String
    let searchText: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
}

struct WorkoutSnapshot: Codable {
    let weekday: Int
    let name: String
    let estimatedCalories: Double
    let durationMinutes: Int?
    let focus: String?
    let warmup: String?
    let progression: String?
    let notes: String?
    let exercises: [WorkoutTemplateExerciseSnapshot]?
}

struct WorkoutArchiveSnapshot: Codable {
    let title: String
    let summary: String?
    let notes: String?
    let source: String
    let archivedAt: Date
    let sessionsJSON: String
}

struct WorkoutPlanOverrideSnapshot: Codable {
    let weekday: Int
    let operationRaw: String
    let exerciseName: String
    let sets: Int?
    let reps: Int?
    let weight: Double?
    let note: String?
    let source: String
    let createdAt: Date
}

struct RecipeSnapshot: Codable {
    let title: String
    let urlString: String
    let category: String
    let isFavorite: Bool?
    let summary: String?
    let ingredientsText: String?
    let instructionsText: String?
    let servings: Int?
    let prepMinutes: Int?
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let createdAt: Date
}

struct StepSnapshot: Codable {
    let date: Date
    let steps: Int
    let source: String
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
    let syncedAt: Date?
}

struct MonthlyGoalSnapshot: Codable {
    let anchorDate: Date
    let targetWeight: Double
    let note: String?
}


// MARK: - v2 workout log snapshots

struct WorkoutLogSnapshot: Codable {
    let date: Date
    let name: String
    let durationMinutes: Int
    let estimatedCalories: Double
    let notes: String?
    let exercises: [WorkoutExerciseSnapshot]
}

struct WorkoutExerciseSnapshot: Codable {
    let name: String
    let order: Int
    let sets: [ExerciseSetSnapshot]
}

struct ExerciseSetSnapshot: Codable {
    let order: Int
    let reps: Int
    let weight: Double?
}

// MARK: - v3 app support snapshots

struct SupportFileSnapshot: Codable {
    let name: String
    let data: Data
    let modifiedAt: Date?
}

struct PreferenceSnapshot: Codable {
    let key: String
    let stringValue: String?
    let intValue: Int?
    let doubleValue: Double?
    let boolValue: Bool?
}

// MARK: - Vault metadata

struct VaultManifest: Codable {
    struct Counts: Codable {
        let measurements: Int
        let foods: Int
        let foodPresets: Int
        let workouts: Int
        let workoutArchives: Int
        let workoutPlanOverrides: Int
        let recipes: Int
        let steps: Int
        let monthlyGoals: Int
        let workoutLogs: Int
        let supportFiles: Int
        let preferences: Int
    }

    let version: Int
    let appName: String
    let updatedAt: Date
    let deviceID: String
    let snapshotFile: String
    let legacySnapshotFile: String
    let backupVersion: Int
    let exportedAt: Date
    let counts: Counts
    let domains: [String]
}
