import Foundation
import SwiftData

// MARK: - Snapshot DTOs (codable mirrors of @Model classes)
//
// Schema versiyonu:
//   1 — başlangıç: profile, measurements, foods, workouts (templates), recipes, steps, monthlyGoals
//   2 — eklendi: profile.about, workoutLogs (date+exercises+sets nested)
//   3 — eklendi: chat history, agent memory, research cache ve küçük app tercihleri
//   4 — eklendi: AI/user yemek planı override'ları
//   5 — eklendi: AI/user antrenman planı override'ları
//   6 — eklendi: tarif içerikleri, malzemeler, yapılış ve makro özeti
//
// Eski v1 backup'ları okumaya devam ediyoruz — eksik alanlar nil/default kalır.

private struct HerculesBackup: Codable {
    let version: Int
    let exportedAt: Date
    let profile: ProfileSnapshot?
    let measurements: [MeasurementSnapshot]
    let foods: [FoodSnapshot]
    let workouts: [WorkoutSnapshot]
    let workoutPlanOverrides: [WorkoutPlanOverrideSnapshot]?
    let recipes: [RecipeSnapshot]
    let steps: [StepSnapshot]
    let monthlyGoals: [MonthlyGoalSnapshot]?
    /// v4+: Yemek planı üstüne gelen AI/user override'ları.
    let mealPlanOverrides: [MealPlanOverrideSnapshot]?
    /// v2+: gerçek antrenman log'ları (her log'un exercise+set'leri nested).
    let workoutLogs: [WorkoutLogSnapshot]?
    /// v3+: Application Support/Hercules altındaki JSON state dosyaları.
    let supportFiles: [SupportFileSnapshot]?
    /// v3+: SwiftData dışında kalan küçük UserDefaults tercihleri.
    let preferences: [PreferenceSnapshot]?
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
    /// v2+: AI'a sürekli enjekte edilen "hakkında" metni.
    let about: String?
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

private struct WorkoutPlanOverrideSnapshot: Codable {
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

private struct RecipeSnapshot: Codable {
    let title: String
    let urlString: String
    let category: String
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

private struct StepSnapshot: Codable {
    let date: Date
    let steps: Int
    let source: String
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
    let syncedAt: Date?
}

private struct MonthlyGoalSnapshot: Codable {
    let anchorDate: Date
    let targetWeight: Double
    let note: String?
}

private struct MealPlanOverrideSnapshot: Codable {
    let weekday: Int
    let operationRaw: String
    let dayTypeRaw: String?
    let slotRaw: String?
    let itemName: String?
    let amount: Double?
    let unit: String?
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let note: String?
    let source: String
    let createdAt: Date
}

// MARK: - v2 workout log snapshots

private struct WorkoutLogSnapshot: Codable {
    let date: Date
    let name: String
    let durationMinutes: Int
    let estimatedCalories: Double
    let notes: String?
    let exercises: [WorkoutExerciseSnapshot]
}

private struct WorkoutExerciseSnapshot: Codable {
    let name: String
    let order: Int
    let sets: [ExerciseSetSnapshot]
}

private struct ExerciseSetSnapshot: Codable {
    let order: Int
    let reps: Int
    let weight: Double?
}

// MARK: - v3 app support snapshots

private struct SupportFileSnapshot: Codable {
    let name: String
    let data: Data
    let modifiedAt: Date?
}

private struct PreferenceSnapshot: Codable {
    let key: String
    let stringValue: String?
    let intValue: Int?
    let doubleValue: Double?
    let boolValue: Bool?
}

// MARK: - Service

@MainActor
final class BackupService {
    static let shared = BackupService()

    private static let supportFileNames = [
        "chat-history.json",
        "agent-memory.json",
        "research-library.json"
    ]

    private static let preferenceKeys = [
        "mealplan.deficit",
        "mealplan.selectedWeekday",
        "hercules.ai.provider",
        "hercules.codex.model",
        "hercules.codex.reasoning",
        "hercules.openrouter.model"
    ]

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

    /// Paid Developer / CloudKit entitlement gerekmeden çalışan iCloud Drive mirror.
    /// iCloud Drive kapalıysa nil döner ve app normal local backup ile devam eder.
    var iCloudBackupURL: URL? {
        let fm = FileManager.default
        let cloudDocs = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard fm.fileExists(atPath: cloudDocs.path) else { return nil }
        let dir = cloudDocs.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("hercules-backup.json")
    }

    var latestBackupURL: URL {
        newestExistingBackupURL() ?? backupURL
    }

    private var backupDirectoryURL: URL {
        backupURL.deletingLastPathComponent()
    }

    private var supportDirectoryURL: URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// .sortedKeys kaldırıldı — encode time'ı yaklaşık yarı yarıya düşürür,
    /// dosya hala valid JSON.
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Export

    /// Store "yedekleme yapmaya değecek kadar dolu" mu?
    /// Profile + measurements + foods + recipes + workout logs hepsi sıfırsa,
    /// app yeni kuruldu veya store sıfırlandı demektir → mevcut backup'ı
    /// EZMEMELİYİZ (kullanıcının elindeki tek yedek olabilir).
    private func storeHasMeaningfulData(_ ctx: ModelContext) -> Bool {
        let measurementCount = (try? ctx.fetchCount(FetchDescriptor<Measurement>())) ?? 0
        let foodCount = (try? ctx.fetchCount(FetchDescriptor<FoodEntry>())) ?? 0
        let recipeCount = (try? ctx.fetchCount(FetchDescriptor<Recipe>())) ?? 0
        let logCount = (try? ctx.fetchCount(FetchDescriptor<WorkoutLog>())) ?? 0
        let goalCount = (try? ctx.fetchCount(FetchDescriptor<MonthlyGoal>())) ?? 0
        // En az birinin dolu olması yeterli — DemoSeed sadece profile + 3 template kurar,
        // o yüzden onları sayıma katmıyoruz.
        return (measurementCount + foodCount + recipeCount + logCount + goalCount) > 0 || hasSupportFiles()
    }

    /// Mevcut tüm verileri JSON'a yaz. Hatalar sessizce yutulur (best-effort).
    /// Senkron — ModelContext main-actor okumayı gerektirir. Quit path'i için.
    /// Store boşsa NO-OP — kullanıcının backup'ını korur.
    @discardableResult
    func export(from ctx: ModelContext) -> Bool {
        guard storeHasMeaningfulData(ctx) else {
            print("[Backup] store boş, mevcut yedek korunuyor.")
            return false
        }
        do {
            let backup = try buildBackup(ctx: ctx)
            let data = try encoder.encode(backup)
            try data.write(to: backupURL, options: [.atomic])
            mirrorToICloud(data)
            return true
        } catch {
            print("[Backup] export failed: \(error)")
            return false
        }
    }

    /// Snapshot'ı main thread'de inşa eder, sonra encode + write'ı detached
    /// task'a kaydırır — applicationDidResignActive gibi sık çağrılan path'lerde
    /// UI'ı dondurmamak için. Quit path'inde senkron `export(from:)` kullan.
    /// Store boşsa NO-OP — kullanıcının backup'ını korur.
    func exportAsync(from ctx: ModelContext) {
        guard storeHasMeaningfulData(ctx) else {
            print("[Backup] store boş, async export atlandı.")
            return
        }
        let snapshot: HerculesBackup
        do {
            snapshot = try buildBackup(ctx: ctx)
        } catch {
            print("[Backup] async build failed: \(error)")
            return
        }
        let url = backupURL
        let cloudURL = iCloudBackupURL
        let encoder = self.encoder
        Task.detached(priority: .utility) {
            do {
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: [.atomic])
                if let cloudURL {
                    try? data.write(to: cloudURL, options: [.atomic])
                }
            } catch {
                print("[Backup] async write failed: \(error)")
            }
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
                manualCalorieOffset: p.manualCalorieOffset,
                about: p.about
            )
        }()

        let measurements = (try? ctx.fetch(FetchDescriptor<Measurement>())) ?? []
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let workouts = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let workoutPlanOverrides = (try? ctx.fetch(FetchDescriptor<WorkoutPlanOverride>())) ?? []
        let recipes = (try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []
        let steps = (try? ctx.fetch(FetchDescriptor<StepEntry>())) ?? []
        let monthlyGoals = (try? ctx.fetch(FetchDescriptor<MonthlyGoal>())) ?? []
        let mealPlanOverrides = (try? ctx.fetch(FetchDescriptor<MealPlanOverride>())) ?? []
        let workoutLogs = (try? ctx.fetch(FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.date)]))) ?? []

        return HerculesBackup(
            version: 6,
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
            workoutPlanOverrides: workoutPlanOverrides.map {
                WorkoutPlanOverrideSnapshot(
                    weekday: $0.weekday,
                    operationRaw: $0.operationRaw,
                    exerciseName: $0.exerciseName,
                    sets: $0.sets,
                    reps: $0.reps,
                    weight: $0.weight,
                    note: $0.note,
                    source: $0.source,
                    createdAt: $0.createdAt
                )
            },
            recipes: recipes.map {
                RecipeSnapshot(
                    title: $0.title,
                    urlString: $0.urlString,
                    category: $0.category.rawValue,
                    summary: $0.summary,
                    ingredientsText: $0.ingredientsText,
                    instructionsText: $0.instructionsText,
                    servings: $0.servings,
                    prepMinutes: $0.prepMinutes,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    createdAt: $0.createdAt
                )
            },
            steps: steps.map {
                StepSnapshot(
                    date: $0.date,
                    steps: $0.steps,
                    source: $0.source,
                    distanceMeters: $0.distanceMeters,
                    activeEnergyKcal: $0.activeEnergyKcal,
                    syncedAt: $0.syncedAt
                )
            },
            monthlyGoals: monthlyGoals.map {
                MonthlyGoalSnapshot(anchorDate: $0.anchorDate, targetWeight: $0.targetWeight, note: $0.note)
            },
            mealPlanOverrides: mealPlanOverrides.map {
                MealPlanOverrideSnapshot(
                    weekday: $0.weekday,
                    operationRaw: $0.operationRaw,
                    dayTypeRaw: $0.dayTypeRaw,
                    slotRaw: $0.slotRaw,
                    itemName: $0.itemName,
                    amount: $0.amount,
                    unit: $0.unit,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    note: $0.note,
                    source: $0.source,
                    createdAt: $0.createdAt
                )
            },
            workoutLogs: workoutLogs.map { log in
                let exs = log.exercises.sorted { $0.order < $1.order }.map { ex in
                    WorkoutExerciseSnapshot(
                        name: ex.name,
                        order: ex.order,
                        sets: ex.setEntries.sorted { $0.order < $1.order }.map { s in
                            ExerciseSetSnapshot(order: s.order, reps: s.reps, weight: s.weight)
                        }
                    )
                }
                return WorkoutLogSnapshot(
                    date: log.date,
                    name: log.name,
                    durationMinutes: log.durationMinutes,
                    estimatedCalories: log.estimatedCalories,
                    notes: log.notes,
                    exercises: exs
                )
            },
            supportFiles: buildSupportFileSnapshots(),
            preferences: buildPreferenceSnapshots()
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
        guard isEmpty, let restoreURL = newestExistingBackupURL() else {
            // Store boş değilse veya yedek yoksa — flag'i true yap, bir daha gelmesin
            UserDefaults.standard.set(true, forKey: importedFlagKey)
            return
        }
        do {
            try restore(from: restoreURL, into: ctx, mode: .replaceAll)
            UserDefaults.standard.set(true, forKey: importedFlagKey)
            print("[Backup] auto-restored from \(restoreURL.path)")
        } catch {
            print("[Backup] auto-restore failed: \(error)")
        }
    }

    /// iCloud Drive'daki mirror local backup'tan daha yeniyse otomatik içeri al.
    /// Kullanım modeli: ana Mac yazar, diğer cihazlar okur. Restore öncesi safety
    /// backup alındığı için yanlış yönde sync olsa bile geri dönüş dosyası kalır.
    func restoreFromICloudIfNewer(into ctx: ModelContext) {
        guard let cloudURL = iCloudBackupURL,
              FileManager.default.fileExists(atPath: cloudURL.path)
        else { return }

        let cloudDate = comparableBackupDate(for: cloudURL) ?? .distantPast
        let localDate = comparableBackupDate(for: backupURL) ?? .distantPast
        guard cloudDate.timeIntervalSince(localDate) > 2 else { return }

        do {
            try restore(from: cloudURL, into: ctx, mode: .replaceAll)
            if let data = try? Data(contentsOf: cloudURL) {
                try? data.write(to: backupURL, options: [.atomic])
            }
            print("[Backup] restored newer iCloud backup from \(cloudURL.path)")
        } catch {
            print("[Backup] iCloud auto-restore failed: \(error)")
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
            try writePreRestoreSafetyBackup(from: ctx)
            // Mevcut veriyi temizle — workoutLog cascade'le exercises+sets de gider.
            ((try? ctx.fetch(FetchDescriptor<Measurement>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<WorkoutPlanOverride>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<StepEntry>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<MonthlyGoal>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<MealPlanOverride>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? []).forEach { ctx.delete($0) }
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
            p.about = ps.about ?? ""
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
        for w in (backup.workoutPlanOverrides ?? []) {
            ctx.insert(WorkoutPlanOverride(
                weekday: w.weekday,
                operation: WorkoutPlanOverrideOperation(rawValue: w.operationRaw) ?? .addExercise,
                exerciseName: w.exerciseName,
                sets: w.sets,
                reps: w.reps,
                weight: w.weight,
                note: w.note,
                source: w.source,
                createdAt: w.createdAt
            ))
        }
        for r in backup.recipes {
            ctx.insert(Recipe(
                title: r.title,
                urlString: r.urlString,
                category: RecipeCategory(rawValue: r.category) ?? .dinner,
                summary: r.summary,
                ingredientsText: r.ingredientsText,
                instructionsText: r.instructionsText,
                servings: r.servings,
                prepMinutes: r.prepMinutes,
                calories: r.calories,
                protein: r.protein,
                carbs: r.carbs,
                fat: r.fat,
                createdAt: r.createdAt
            ))
        }
        for s in backup.steps {
            ctx.insert(StepEntry(
                date: s.date,
                steps: s.steps,
                source: s.source,
                distanceMeters: s.distanceMeters,
                activeEnergyKcal: s.activeEnergyKcal,
                syncedAt: s.syncedAt
            ))
        }
        for g in (backup.monthlyGoals ?? []) {
            ctx.insert(MonthlyGoal(anchorDate: g.anchorDate, targetWeight: g.targetWeight, note: g.note))
        }
        for m in (backup.mealPlanOverrides ?? []) {
            ctx.insert(MealPlanOverride(
                weekday: m.weekday,
                operation: MealPlanOverrideOperation(rawValue: m.operationRaw) ?? .addItem,
                dayType: m.dayTypeRaw.flatMap(MealDayType.init(rawValue:)),
                slot: m.slotRaw.flatMap(MealSlot.init(rawValue:)),
                itemName: m.itemName,
                amount: m.amount,
                unit: m.unit,
                calories: m.calories,
                protein: m.protein,
                carbs: m.carbs,
                fat: m.fat,
                note: m.note,
                source: m.source,
                createdAt: m.createdAt
            ))
        }
        // v2: WorkoutLog + nested exercise/set restore. v1 backup'ında bu alan
        // yok (nil) — bu durumda log'lar restore edilmez (kullanıcı kaybetmemiş gibi davranır).
        for lg in (backup.workoutLogs ?? []) {
            let log = WorkoutLog(
                date: lg.date,
                name: lg.name,
                durationMinutes: lg.durationMinutes,
                estimatedCalories: lg.estimatedCalories,
                notes: lg.notes
            )
            ctx.insert(log)
            for ex in lg.exercises.sorted(by: { $0.order < $1.order }) {
                let entry = WorkoutExerciseEntry(name: ex.name, order: ex.order)
                ctx.insert(entry)
                for s in ex.sets.sorted(by: { $0.order < $1.order }) {
                    let setEntry = ExerciseSet(order: s.order, reps: s.reps, weight: s.weight)
                    ctx.insert(setEntry)
                    entry.setEntries.append(setEntry)
                }
                log.exercises.append(entry)
            }
        }
        restoreSupportFiles(backup.supportFiles ?? [], mode: mode)
        restorePreferences(backup.preferences ?? [])
        try ctx.save()
        LocalMemoryProvider.shared.reloadFromDisk()
        ResearchLibrary.shared.reloadFromDisk()
        NotificationCenter.default.post(name: .herculesSupportFilesRestored, object: nil)
    }

    // MARK: - Info

    var lastBackupDate: Date? {
        newestExistingBackupURL().flatMap(comparableBackupDate(for:))
    }

    var backupExists: Bool {
        newestExistingBackupURL() != nil
    }

    var backupSizeBytes: Int? {
        guard let url = newestExistingBackupURL(),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return nil }
        return (attrs[.size] as? NSNumber)?.intValue
    }

    var iCloudMirrorAvailable: Bool {
        iCloudBackupURL != nil
    }

    var iCloudBackupExists: Bool {
        guard let iCloudBackupURL else { return false }
        return FileManager.default.fileExists(atPath: iCloudBackupURL.path)
    }

    private func hasSupportFiles() -> Bool {
        Self.supportFileNames.contains { name in
            FileManager.default.fileExists(atPath: supportDirectoryURL.appendingPathComponent(name).path)
        }
    }

    private func buildSupportFileSnapshots() -> [SupportFileSnapshot] {
        Self.supportFileNames.compactMap { name in
            let url = supportDirectoryURL.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            return SupportFileSnapshot(name: name, data: data, modifiedAt: modifiedAt)
        }
    }

    private func restoreSupportFiles(_ files: [SupportFileSnapshot], mode: RestoreMode) {
        let fm = FileManager.default
        let dir = supportDirectoryURL
        if mode == .replaceAll {
            Self.supportFileNames.forEach { name in
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }

        for file in files where Self.supportFileNames.contains(file.name) {
            let destination = dir.appendingPathComponent(file.name)
            if mode == .mergeAdditive, fm.fileExists(atPath: destination.path) {
                continue
            }
            try? file.data.write(to: destination, options: [.atomic])
        }
    }

    private func buildPreferenceSnapshots() -> [PreferenceSnapshot] {
        let defaults = UserDefaults.standard
        return Self.preferenceKeys.compactMap { key in
            guard let value = defaults.object(forKey: key) else { return nil }
            return PreferenceSnapshot(
                key: key,
                stringValue: value as? String,
                intValue: value as? Int,
                doubleValue: value as? Double,
                boolValue: value as? Bool
            )
        }
    }

    private func restorePreferences(_ preferences: [PreferenceSnapshot]) {
        let defaults = UserDefaults.standard
        for preference in preferences where Self.preferenceKeys.contains(preference.key) {
            if let stringValue = preference.stringValue {
                defaults.set(stringValue, forKey: preference.key)
            } else if let intValue = preference.intValue {
                defaults.set(intValue, forKey: preference.key)
            } else if let doubleValue = preference.doubleValue {
                defaults.set(doubleValue, forKey: preference.key)
            } else if let boolValue = preference.boolValue {
                defaults.set(boolValue, forKey: preference.key)
            }
        }
    }

    private func writePreRestoreSafetyBackup(from ctx: ModelContext) throws {
        guard storeHasMeaningfulData(ctx) else { return }
        let snapshot = try buildBackup(ctx: ctx)
        let data = try encoder.encode(snapshot)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "hercules-pre-restore-\(formatter.string(from: Date())).json"
        try data.write(to: backupDirectoryURL.appendingPathComponent(name), options: [.atomic])
    }

    private func mirrorToICloud(_ data: Data) {
        guard let iCloudBackupURL else { return }
        try? data.write(to: iCloudBackupURL, options: [.atomic])
    }

    private func newestExistingBackupURL() -> URL? {
        [backupURL, iCloudBackupURL]
            .compactMap { $0 }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                (comparableBackupDate(for: $0) ?? .distantPast) > (comparableBackupDate(for: $1) ?? .distantPast)
            }
            .first
    }

    private func comparableBackupDate(for url: URL) -> Date? {
        if let data = try? Data(contentsOf: url),
           let backup = try? decoder.decode(HerculesBackup.self, from: data) {
            return backup.exportedAt
        }
        return modificationDate(for: url)
    }

    private func modificationDate(for url: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.modificationDate] as? Date
    }
}

extension Notification.Name {
    static let herculesSupportFilesRestored = Notification.Name("hercules.support-files.restored")
}
