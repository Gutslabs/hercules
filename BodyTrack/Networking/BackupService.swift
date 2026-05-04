import Foundation
import SwiftData

// MARK: - Snapshot DTOs (codable mirrors of @Model classes)

private struct HerculesBackup: Codable {
    let version: Int
    let exportedAt: Date
    let profile: ProfileSnapshot?
    let measurements: [MeasurementSnapshot]
    let foods: [FoodSnapshot]
    let workouts: [WorkoutSnapshot]
    let recipes: [RecipeSnapshot]
    let steps: [StepSnapshot]
}

private struct ProfileSnapshot: Codable {
    let name: String
    let sex: String
    let birthDate: Date
    let height: Double
    let activity: String
    let goal: String
    let targetWeight: Double?
    let manualBodyFat: Double?
    let manualCalorieOffset: Double
}

private struct MeasurementSnapshot: Codable {
    let date: Date
    let weight: Double?
    let bodyFat: Double?
    let waist: Double?
    let chest: Double?
    let neck: Double?
    let note: String?
}

private struct FoodSnapshot: Codable {
    let date: Date
    let name: String
    let grams: Double?
    let calories: Double
    let protein: Double?
    let carbs: Double?
    let fat: Double?
}

private struct WorkoutSnapshot: Codable {
    let weekday: Int
    let name: String
    let estimatedCalories: Double
}

private struct RecipeSnapshot: Codable {
    let title: String
    let urlString: String
    let category: String
    let createdAt: Date
}

private struct StepSnapshot: Codable {
    let date: Date
    let steps: Int
    let source: String
}

// MARK: - Service

@MainActor
final class BackupService {
    static let shared = BackupService()

    /// Yedek konumu: ~/Documents/Hercules/hercules-backup.json
    /// Kullanıcı görsün, Dropbox/iCloud Drive'a kopyalayabilsin diye Documents'da.
    var backupURL: URL {
        let fm = FileManager.default
        let docs = (try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let dir = docs.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("hercules-backup.json")
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Export

    /// Mevcut tüm verileri JSON'a yaz. Hatalar sessizce yutulur (best-effort).
    @discardableResult
    func export(from ctx: ModelContext) -> Bool {
        do {
            let backup = try buildBackup(ctx: ctx)
            let data = try encoder.encode(backup)
            try data.write(to: backupURL, options: [.atomic])
            return true
        } catch {
            print("[Backup] export failed: \(error)")
            return false
        }
    }

    private func buildBackup(ctx: ModelContext) throws -> HerculesBackup {
        let profileData: ProfileSnapshot? = {
            guard let p = (try? ctx.fetch(FetchDescriptor<UserProfile>()))?.first else { return nil }
            return ProfileSnapshot(
                name: p.name,
                sex: p.sex.rawValue,
                birthDate: p.birthDate,
                height: p.height,
                activity: p.activity.rawValue,
                goal: p.goal.rawValue,
                targetWeight: p.targetWeight,
                manualBodyFat: p.manualBodyFat,
                manualCalorieOffset: p.manualCalorieOffset
            )
        }()

        let measurements = (try? ctx.fetch(FetchDescriptor<Measurement>())) ?? []
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let workouts = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let recipes = (try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []
        let steps = (try? ctx.fetch(FetchDescriptor<StepEntry>())) ?? []

        return HerculesBackup(
            version: 1,
            exportedAt: .now,
            profile: profileData,
            measurements: measurements.map {
                MeasurementSnapshot(
                    date: $0.date, weight: $0.weight, bodyFat: $0.bodyFat,
                    waist: $0.waist, chest: $0.chest, neck: $0.neck, note: $0.note
                )
            },
            foods: foods.map {
                FoodSnapshot(
                    date: $0.date, name: $0.name, grams: $0.grams,
                    calories: $0.calories, protein: $0.protein,
                    carbs: $0.carbs, fat: $0.fat
                )
            },
            workouts: workouts.map {
                WorkoutSnapshot(weekday: $0.weekday, name: $0.name, estimatedCalories: $0.estimatedCalories)
            },
            recipes: recipes.map {
                RecipeSnapshot(title: $0.title, urlString: $0.urlString, category: $0.category.rawValue, createdAt: $0.createdAt)
            },
            steps: steps.map {
                StepSnapshot(date: $0.date, steps: $0.steps, source: $0.source)
            }
        )
    }

    // MARK: - Import

    private let importedFlagKey = "hercules.backup.imported_v1"

    /// Sadece store boşsa VE daha önce hiç import etmediysek otomatik geri yükle.
    /// Flag UserDefaults'ta saklanır → app silinince sıfırlanır → temiz kurulumda restore tetiklenir.
    /// Kullanıcı veriyi sildikten sonra tekrar GERI GELMEZ çünkü flag hala true.
    func importIfStoreEmpty(into ctx: ModelContext) {
        // Daha önce import yaptıysak bir daha asla yapma — silinen veri geri gelmesin
        if UserDefaults.standard.bool(forKey: importedFlagKey) {
            return
        }

        let measurementCount = (try? ctx.fetchCount(FetchDescriptor<Measurement>())) ?? 0
        let recipeCount = (try? ctx.fetchCount(FetchDescriptor<Recipe>())) ?? 0
        let foodCount = (try? ctx.fetchCount(FetchDescriptor<FoodEntry>())) ?? 0

        let isEmpty = measurementCount == 0 && recipeCount == 0 && foodCount == 0
        guard isEmpty, FileManager.default.fileExists(atPath: backupURL.path) else {
            // Store boş değilse veya yedek yoksa — flag'i true yap, bir daha gelmesin
            UserDefaults.standard.set(true, forKey: importedFlagKey)
            return
        }
        do {
            try restore(from: backupURL, into: ctx, mode: .replaceAll)
            UserDefaults.standard.set(true, forKey: importedFlagKey)
            print("[Backup] auto-restored from \(backupURL.path)")
        } catch {
            print("[Backup] auto-restore failed: \(error)")
        }
    }

    /// Manuel restore'dan sonra flag'i set et — sonraki açılışta tekrar tetiklenmesin.
    func markAsImported() {
        UserDefaults.standard.set(true, forKey: importedFlagKey)
    }

    enum RestoreMode {
        case replaceAll      // Mevcut tüm veriyi sil, yedeği yükle
        case mergeAdditive   // Sadece yedekteki yeni öğeleri ekle (existing korunur)
    }

    /// Manuel restore — kullanıcının seçtiği dosyadan veya default backup'dan.
    func restore(from url: URL, into ctx: ModelContext, mode: RestoreMode) throws {
        let data = try Data(contentsOf: url)
        let backup = try decoder.decode(HerculesBackup.self, from: data)

        if mode == .replaceAll {
            // Mevcut veriyi temizle
            ((try? ctx.fetch(FetchDescriptor<Measurement>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<StepEntry>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []).forEach { ctx.delete($0) }
        }

        // Profile (always overwrite if backup has one)
        if let ps = backup.profile {
            let existing = (try? ctx.fetch(FetchDescriptor<UserProfile>()))?.first
            let p = existing ?? UserProfile()
            if existing == nil { ctx.insert(p) }
            p.name = ps.name
            p.sex = Sex(rawValue: ps.sex) ?? .male
            p.birthDate = ps.birthDate
            p.height = ps.height
            p.activity = ActivityLevel(rawValue: ps.activity) ?? .moderate
            p.goal = Goal(rawValue: ps.goal) ?? .maintain
            p.targetWeight = ps.targetWeight
            p.manualBodyFat = ps.manualBodyFat
            p.manualCalorieOffset = ps.manualCalorieOffset
        }

        for m in backup.measurements {
            ctx.insert(Measurement(
                date: m.date, weight: m.weight, bodyFat: m.bodyFat,
                waist: m.waist, chest: m.chest, neck: m.neck, note: m.note
            ))
        }
        for f in backup.foods {
            ctx.insert(FoodEntry(
                date: f.date, name: f.name, grams: f.grams,
                calories: f.calories, protein: f.protein,
                carbs: f.carbs, fat: f.fat
            ))
        }
        for w in backup.workouts {
            ctx.insert(WorkoutSession(
                weekday: w.weekday, name: w.name, estimatedCalories: w.estimatedCalories
            ))
        }
        for r in backup.recipes {
            ctx.insert(Recipe(
                title: r.title,
                urlString: r.urlString,
                category: RecipeCategory(rawValue: r.category) ?? .dinner,
                createdAt: r.createdAt
            ))
        }
        for s in backup.steps {
            ctx.insert(StepEntry(date: s.date, steps: s.steps, source: s.source))
        }
        try ctx.save()
    }

    // MARK: - Info

    var lastBackupDate: Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: backupURL.path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    var backupExists: Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    var backupSizeBytes: Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: backupURL.path) else { return nil }
        return (attrs[.size] as? NSNumber)?.intValue
    }
}
