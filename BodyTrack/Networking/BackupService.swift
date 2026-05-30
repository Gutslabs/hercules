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
//   7 — eklendi: tek tık kalori presetleri
//   8 — eklendi: detaylı antrenman programı, template hareketleri ve program arşivi
//   9 — eklendi: profil manuel makro hedefleri
//   10 — eklendi: manuel kalori offset makro kaynağı
//   11 — eklendi: tarif favorileri
//   12 — eklendi: profil supplement listesi
//
// Eski v1 backup'ları okumaya devam ediyoruz — eksik alanlar nil/default kalır.

struct VaultOperationSummary {
    let didWriteConflictCopy: Bool
    let snapshotURL: URL
    let manifestURL: URL
}

enum BackupServiceError: LocalizedError {
    case vaultNotConfigured
    case vaultSnapshotMissing
    case emptyStoreExportSkipped
    case richerVaultSnapshotExists

    var errorDescription: String? {
        switch self {
        case .vaultNotConfigured:
            return "Veri klasörü seçilmedi."
        case .vaultSnapshotMissing:
            return "Seçili veri klasöründe Hercules snapshot bulunamadı."
        case .emptyStoreExportSkipped:
            return "Bu cihazda aktarılacak anlamlı veri yok; mevcut vault ezilmedi."
        case .richerVaultSnapshotExists:
            return "Vault'ta daha dolu bir snapshot var; önce Vault'tan Al yap."
        }
    }
}

// MARK: - Service

@MainActor
final class BackupService {
    static let shared = BackupService()

    // NOT: codex_auth.json bilinçli olarak yok — OAuth token'ları artık Keychain'de
    // tutuluyor ve taşınabilir yedeklere/iCloud'a asla yazılmıyor (güvenlik).
    private static let supportFileNames = [
        "chat-history.json",
        "agent-memory.json",
        "research-library.json"
    ]

    private static let preferenceKeys = [
        "hercules.ai.provider",
        "hercules.codex.model",
        "hercules.codex.reasoning",
        "hercules.openrouter.model"
    ]

    private let vaultBookmarkKey = "hercules.vault.bookmark_v1"
    private let vaultLastSeenExportKey = "hercules.vault.last_seen_exported_at_v1"
    private let vaultDeviceIDKey = "hercules.vault.device_id_v1"
    private let vaultSnapshotRelativePath = "data/hercules-backup.json"
    private let vaultLegacySnapshotName = "hercules-backup.json"
    private let vaultManifestName = "manifest.json"
    private let vaultReadmeName = "README.md"

    /// Yedek konumu: ~/Documents/Hercules/hercules-backup.json
    /// Kullanıcı görsün, Dropbox/iCloud Drive'a kopyalayabilsin diye Documents'da.
    var backupURL: URL {
        let fm = FileManager.default
        #if os(macOS)
        let fallbackDocs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        #else
        let fallbackDocs = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        #endif
        let docs = (try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fallbackDocs
        let dir = docs.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("hercules-backup.json")
    }

    /// Paid Developer / CloudKit entitlement gerekmeden çalışan iCloud Drive mirror.
    /// iCloud Drive kapalıysa nil döner ve app normal local backup ile devam eder.
    var iCloudBackupURL: URL? {
        #if os(macOS)
        let fm = FileManager.default
        let cloudDocs = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard fm.fileExists(atPath: cloudDocs.path) else { return nil }
        let dir = cloudDocs.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("hercules-backup.json")
        #else
        return nil
        #endif
    }

    /// Kullanıcının seçtiği Obsidian-style veri klasörü. iCloud Drive, Dropbox
    /// veya düz klasör olabilir; app bu klasörün içine `manifest.json`,
    /// `data/`, `backups/`, `conflicts/` yazar.
    var selectedVaultRootURL: URL? {
        try? resolveVaultBookmark().url
    }

    var vaultIsConfigured: Bool {
        selectedVaultRootURL != nil
    }

    var vaultDisplayPath: String {
        guard let url = selectedVaultRootURL else {
            return "Seçilmedi"
        }
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var vaultBackupExists: Bool {
        (try? withVaultRoot { root in
            bestVaultRestoreCandidate(root: root) != nil
        }) ?? false
    }

    var vaultLastSyncDate: Date? {
        guard let value = try? withVaultRoot({ root in
            bestVaultRestoreCandidate(root: root)?.backup.exportedAt
        }) else { return nil }
        return value
    }

    var latestBackupURL: URL {
        newestExistingBackupURL() ?? backupURL
    }

    private var backupDirectoryURL: URL {
        backupURL.deletingLastPathComponent()
    }

    private var supportDirectoryURL: URL {
        let fm = FileManager.default
        #if os(macOS)
        let fallback = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        #else
        let fallback = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        #endif
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fallback
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
        let stepCount = (try? ctx.fetchCount(FetchDescriptor<StepEntry>())) ?? 0
        let archiveCount = (try? ctx.fetchCount(FetchDescriptor<WorkoutProgramArchive>())) ?? 0
        let workoutOverrideCount = (try? ctx.fetchCount(FetchDescriptor<WorkoutPlanOverride>())) ?? 0
        let profile = (try? ctx.fetch(FetchDescriptor<UserProfile>()))?.first
        let hasProfileData = {
            guard let profile else { return false }
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let about = profile.about.trimmingCharacters(in: .whitespacesAndNewlines)
            let supplements = profile.supplements.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasCustomSupplements = !supplements.isEmpty && supplements != UserProfile.defaultSupplements
            return !name.isEmpty
                || !about.isEmpty
                || hasCustomSupplements
                || profile.targetWeight != nil
                || profile.manualBodyFat != nil
                || profile.manualCalorieOffset != 0
                || profile.manualCalorieOffsetMacro != .carbs
                || profile.manualProteinGrams != nil
                || profile.manualCarbsGrams != nil
                || profile.manualFatGrams != nil
        }()
        let presets = (try? ctx.fetch(FetchDescriptor<FoodPreset>())) ?? []
        let hasCustomPreset = presets.contains { !FoodPresetSeed.defaultPresetIDs.contains($0.presetID) }
        // En az birinin dolu olması yeterli — DemoSeed sadece profile + 3 template kurar,
        // o yüzden onları sayıma katmıyoruz.
        return (
            measurementCount +
            foodCount +
            recipeCount +
            logCount +
            goalCount +
            stepCount +
            archiveCount +
            workoutOverrideCount
        ) > 0 || hasProfileData || hasCustomPreset || hasSupportFiles()
    }

    /// Mevcut tüm verileri JSON'a yaz. Hatalar sessizce yutulur (best-effort).
    /// Senkron — ModelContext main-actor okumayı gerektirir. Quit path'i için.
    /// Store boşsa NO-OP — kullanıcının backup'ını korur.
    @discardableResult
    func export(from ctx: ModelContext) -> Bool {
        guard storeHasMeaningfulData(ctx) else {
            AppLog.backup.notice("[Backup] store boş, mevcut yedek korunuyor.")
            return false
        }
        do {
            let backup = try buildBackup(ctx: ctx)
            guard richerVaultCandidate(than: backup) == nil else {
                AppLog.backup.notice("[Backup] vault daha dolu, export atlandı.")
                return false
            }
            let data = try encoder.encode(backup)
            try data.write(to: backupURL, options: [.atomic])
            mirrorToICloud(data)
            _ = try? writeVaultSnapshot(backup, data: data)
            return true
        } catch {
            AppLog.backup.error("[Backup] export failed: \(String(describing: error))")
            return false
        }
    }

    /// Snapshot'ı main thread'de inşa eder, sonra encode + write'ı detached
    /// task'a kaydırır — applicationDidResignActive gibi sık çağrılan path'lerde
    /// UI'ı dondurmamak için. Quit path'inde senkron `export(from:)` kullan.
    /// Store boşsa NO-OP — kullanıcının backup'ını korur.
    func exportAsync(from ctx: ModelContext) {
        guard storeHasMeaningfulData(ctx) else {
            AppLog.backup.notice("[Backup] store boş, async export atlandı.")
            return
        }
        let snapshot: HerculesBackup
        do {
            snapshot = try buildBackup(ctx: ctx)
        } catch {
            AppLog.backup.error("[Backup] async build failed: \(String(describing: error))")
            return
        }
        guard richerVaultCandidate(than: snapshot) == nil else {
            AppLog.backup.notice("[Backup] vault daha dolu, async export atlandı.")
            return
        }
        let url = backupURL
        let cloudURL = iCloudBackupURL
        let vaultRoot = selectedVaultRootURL
        let vaultDeviceID = deviceID
        let lastSeen = lastSeenVaultExportedAt
        let vaultSnapshotRelativePath = self.vaultSnapshotRelativePath
        let vaultLegacySnapshotName = self.vaultLegacySnapshotName
        let vaultManifestName = self.vaultManifestName
        let vaultReadmeName = self.vaultReadmeName
        let encoder = self.encoder
        Task.detached(priority: .utility) {
            do {
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: [.atomic])
                if let cloudURL {
                    try? data.write(to: cloudURL, options: [.atomic])
                }
                if let vaultRoot {
                    _ = try Self.writeVaultSnapshotDetached(
                        snapshot,
                        data: data,
                        root: vaultRoot,
                        deviceID: vaultDeviceID,
                        lastSeenExportedAt: lastSeen,
                        snapshotRelativePath: vaultSnapshotRelativePath,
                        legacySnapshotName: vaultLegacySnapshotName,
                        manifestName: vaultManifestName,
                        readmeName: vaultReadmeName,
                        encoder: encoder
                    )
                    await MainActor.run {
                        self.lastSeenVaultExportedAt = snapshot.exportedAt
                    }
                }
            } catch {
                AppLog.backup.error("[Backup] async write failed: \(String(describing: error))")
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
                manualCalorieOffsetMacro: p.manualCalorieOffsetMacro.rawValue,
                manualProteinGrams: p.manualProteinGrams,
                manualCarbsGrams: p.manualCarbsGrams,
                manualFatGrams: p.manualFatGrams,
                about: p.about,
                supplements: p.effectiveSupplements
            )
        }()

        let measurements = (try? ctx.fetch(FetchDescriptor<Measurement>())) ?? []
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let foodPresets = (try? ctx.fetch(FetchDescriptor<FoodPreset>())) ?? []
        let workouts = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let workoutArchives = (try? ctx.fetch(FetchDescriptor<WorkoutProgramArchive>())) ?? []
        let workoutPlanOverrides = (try? ctx.fetch(FetchDescriptor<WorkoutPlanOverride>())) ?? []
        let recipes = (try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []
        let steps = (try? ctx.fetch(FetchDescriptor<StepEntry>())) ?? []
        let monthlyGoals = (try? ctx.fetch(FetchDescriptor<MonthlyGoal>())) ?? []
        let workoutLogs = (try? ctx.fetch(FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.date)]))) ?? []

        return HerculesBackup(
            version: 12,
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
            foodPresets: foodPresets.map {
                FoodPresetSnapshot(
                    presetID: $0.presetID,
                    name: $0.name,
                    brand: $0.brand,
                    category: $0.category,
                    servingLabel: $0.servingLabel,
                    servingGrams: $0.servingGrams,
                    defaultServings: $0.defaultServings,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    note: $0.note,
                    searchText: $0.searchText,
                    sortOrder: $0.sortOrder,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            workouts: workouts.map {
                WorkoutSnapshot(
                    weekday: $0.weekday,
                    name: $0.name,
                    estimatedCalories: $0.estimatedCalories,
                    durationMinutes: $0.durationMinutes,
                    focus: $0.focus,
                    warmup: $0.warmup,
                    progression: $0.progression,
                    notes: $0.notes,
                    exercises: $0.sortedTemplateExercises.map(\.snapshot)
                )
            },
            workoutArchives: workoutArchives.map {
                WorkoutArchiveSnapshot(
                    title: $0.title,
                    summary: $0.summary,
                    notes: $0.notes,
                    source: $0.source,
                    archivedAt: $0.archivedAt,
                    sessionsJSON: $0.sessionsJSON
                )
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
                    isFavorite: $0.isFavorite,
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

    // MARK: - User-selected vault sync

    /// Kullanıcının seçtiği klasörü vault olarak kaydeder ve mevcut datayı
    /// mevcut cihazda anlamlı veri varsa oraya yazar. Boş/temiz mobil kurulumda
    /// seçim sadece klasörü kaydeder; var olan iCloud snapshot'ı ezmez.
    @discardableResult
    func configureVaultRoot(_ url: URL, from ctx: ModelContext) throws -> VaultOperationSummary {
        try persistVaultBookmark(for: url)
        guard storeHasMeaningfulData(ctx) else {
            return try withVaultRoot { root in
                try Self.ensureVaultLayout(
                    root: root,
                    snapshotRelativePath: vaultSnapshotRelativePath,
                    legacySnapshotName: vaultLegacySnapshotName,
                    manifestName: vaultManifestName,
                    readmeName: vaultReadmeName
                )
                return VaultOperationSummary(
                    didWriteConflictCopy: false,
                    snapshotURL: root.appendingPathComponent(vaultSnapshotRelativePath),
                    manifestURL: root.appendingPathComponent(vaultManifestName)
                )
            }
        }
        return try exportToVault(from: ctx)
    }

    func clearVaultSelection() {
        UserDefaults.standard.removeObject(forKey: vaultBookmarkKey)
        UserDefaults.standard.removeObject(forKey: vaultLastSeenExportKey)
    }

    @discardableResult
    func exportToVault(from ctx: ModelContext) throws -> VaultOperationSummary {
        guard storeHasMeaningfulData(ctx) else {
            throw BackupServiceError.emptyStoreExportSkipped
        }
        let backup = try buildBackup(ctx: ctx)
        guard richerVaultCandidate(than: backup) == nil else {
            throw BackupServiceError.richerVaultSnapshotExists
        }
        let data = try encoder.encode(backup)
        try data.write(to: backupURL, options: [.atomic])
        mirrorToICloud(data)
        return try writeVaultSnapshot(backup, data: data)
    }

    func restoreFromVault(into ctx: ModelContext) throws {
        try withVaultRoot { root in
            try Self.ensureVaultLayout(
                root: root,
                snapshotRelativePath: vaultSnapshotRelativePath,
                legacySnapshotName: vaultLegacySnapshotName,
                manifestName: vaultManifestName,
                readmeName: vaultReadmeName
            )
            guard let candidate = bestVaultRestoreCandidate(root: root) else {
                throw BackupServiceError.vaultSnapshotMissing
            }
            try writePreVaultRestoreSafetyBackup(into: root, from: ctx)
            try restore(from: candidate.url, into: ctx, mode: .replaceAll)
            if let data = try? Data(contentsOf: candidate.url) {
                try? data.write(to: backupURL, options: [.atomic])
            }
            lastSeenVaultExportedAt = candidate.backup.exportedAt
        }
    }

    /// App açıldığında/öne geldiğinde seçili vault daha yeniyse içeri alır.
    /// Local taraf anlamlı veri taşıyorsa restore öncesi local safety backup alınır.
    func restoreFromVaultIfNewer(into ctx: ModelContext) {
        do {
            let shouldRestore = try withVaultRoot { root in
                guard let candidate = bestVaultRestoreCandidate(root: root) else { return false }
                let vaultDate = candidate.backup.exportedAt
                let localDate = comparableBackupDate(for: backupURL) ?? .distantPast
                let localIsEmpty = !storeHasMeaningfulData(ctx)
                let candidateScore = Self.backupMeaningfulScore(candidate.backup)
                let candidateIsMeaningful = candidateScore > 0
                let localScore = (try? buildBackup(ctx: ctx)).map(Self.backupMeaningfulScore) ?? 0
                let candidateIsMuchRicher = candidateScore >= localScore + 25
                return (localIsEmpty && candidateIsMeaningful)
                    || candidateIsMuchRicher
                    || vaultDate.timeIntervalSince(localDate) > 2
            }
            guard shouldRestore else { return }
            try restoreFromVault(into: ctx)
            AppLog.backup.notice("[Vault] restored newer vault snapshot")
        } catch {
            AppLog.backup.error("[Vault] auto-restore failed: \(String(describing: error))")
        }
    }

    /// iCloud vault dosyalarını ana thread DIŞINDA indirip önbelleğe ısıtır.
    /// Decode yok, ctx yok — sadece indirmeyi tetikleyip byte'ları okur. Dataless bir
    /// iCloud dosyasında `Data(contentsOf:)` indirme bitene kadar BEKLER; bunu burada
    /// (arka thread'de) yapınca o bekleme ana thread'i dondurmaz.
    nonisolated private static func warmVaultFilesDetached(bookmarkData: Data, relativePaths: [String]) {
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        var isStale = false
        guard let root = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        for rel in relativePaths {
            let url = root.appendingPathComponent(rel)
            try? fm.startDownloadingUbiquitousItem(at: url) // dataless ise indirmeyi başlat (iCloud değilse no-op)
            _ = try? Data(contentsOf: url)                  // indirme bitene kadar BURADA bekler (arka thread)
        }
    }

    /// `restoreFromVaultIfNewer`'in BLOKLAMAYAN sürümü: önce iCloud dosyalarını arka
    /// planda ısıtır, sonra mevcut (kanıtlanmış) senkron mantığı main'de çalıştırır —
    /// ağır iCloud indirmesi artık ana thread'i (ve uygulama açılışını) dondurmaz.
    func restoreFromVaultIfNewerNonBlocking(into ctx: ModelContext) async {
        guard let bookmarkData = UserDefaults.standard.data(forKey: vaultBookmarkKey) else { return }
        let relativePaths = [vaultSnapshotRelativePath, vaultLegacySnapshotName, vaultManifestName]
        await Task.detached(priority: .utility) {
            BackupService.warmVaultFilesDetached(bookmarkData: bookmarkData, relativePaths: relativePaths)
        }.value
        restoreFromVaultIfNewer(into: ctx) // okumalar artık yerel önbellekten → hızlı
    }

    private func writeVaultSnapshot(_ backup: HerculesBackup, data: Data) throws -> VaultOperationSummary {
        try withVaultRoot { root in
            let summary = try Self.writeVaultSnapshotDetached(
                backup,
                data: data,
                root: root,
                deviceID: deviceID,
                lastSeenExportedAt: lastSeenVaultExportedAt,
                snapshotRelativePath: vaultSnapshotRelativePath,
                legacySnapshotName: vaultLegacySnapshotName,
                manifestName: vaultManifestName,
                readmeName: vaultReadmeName,
                encoder: encoder
            )
            lastSeenVaultExportedAt = backup.exportedAt
            return summary
        }
    }

    nonisolated private static func writeVaultSnapshotDetached(
        _ backup: HerculesBackup,
        data: Data,
        root: URL,
        deviceID: String,
        lastSeenExportedAt: Date?,
        snapshotRelativePath: String,
        legacySnapshotName: String,
        manifestName: String,
        readmeName: String,
        encoder: JSONEncoder
    ) throws -> VaultOperationSummary {
        let didStart = root.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                root.stopAccessingSecurityScopedResource()
            }
        }

        try ensureVaultLayout(
            root: root,
            snapshotRelativePath: snapshotRelativePath,
            legacySnapshotName: legacySnapshotName,
            manifestName: manifestName,
            readmeName: readmeName
        )

        let fm = FileManager.default
        let snapshotURL = root.appendingPathComponent(snapshotRelativePath)
        let legacyURL = root.appendingPathComponent(legacySnapshotName)
        let manifestURL = root.appendingPathComponent(manifestName)

        let didWriteConflict = try copyVaultConflictIfNeeded(
            snapshotURL: snapshotURL,
            conflictsDir: root.appendingPathComponent("conflicts", isDirectory: true),
            lastSeenExportedAt: lastSeenExportedAt
        )

        try data.write(to: snapshotURL, options: [.atomic])
        try data.write(to: legacyURL, options: [.atomic])

        let manifest = makeVaultManifest(
            backup,
            deviceID: deviceID,
            snapshotRelativePath: snapshotRelativePath,
            legacySnapshotName: legacySnapshotName
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: [.atomic])

        for supportFile in backup.supportFiles ?? [] {
            let destination = root
                .appendingPathComponent("support", isDirectory: true)
                .appendingPathComponent(supportFile.name)
            try supportFile.data.write(to: destination, options: [.atomic])
        }

        let readmeURL = root.appendingPathComponent(readmeName)
        if !fm.fileExists(atPath: readmeURL.path) {
            try defaultVaultReadme.write(to: readmeURL, atomically: true, encoding: .utf8)
        }

        return VaultOperationSummary(
            didWriteConflictCopy: didWriteConflict,
            snapshotURL: snapshotURL,
            manifestURL: manifestURL
        )
    }

    private func writePreVaultRestoreSafetyBackup(into root: URL, from ctx: ModelContext) throws {
        guard storeHasMeaningfulData(ctx) else { return }
        let backup = try buildBackup(ctx: ctx)
        let data = try encoder.encode(backup)
        let url = root
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("pre-vault-restore-\(timestampForFilename()).json")
        try data.write(to: url, options: [.atomic])
    }

    nonisolated private static func copyVaultConflictIfNeeded(
        snapshotURL: URL,
        conflictsDir: URL,
        lastSeenExportedAt: Date?
    ) throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: snapshotURL.path) else { return false }

        let data = try Data(contentsOf: snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let existing = try? decoder.decode(HerculesBackup.self, from: data)
        let existingDate = existing?.exportedAt ?? ((try? fm.attributesOfItem(atPath: snapshotURL.path)[.modificationDate]) as? Date)
        let lastSeen = lastSeenExportedAt ?? .distantPast
        guard let existingDate, existingDate.timeIntervalSince(lastSeen) > 2 else { return false }

        try fm.createDirectory(at: conflictsDir, withIntermediateDirectories: true)
        let conflictURL = conflictsDir.appendingPathComponent("hercules-conflict-\(timestampForFilename()).json")
        try fm.copyItem(at: snapshotURL, to: conflictURL)
        return true
    }

    private func bestVaultRestoreCandidate(root: URL) -> (url: URL, backup: HerculesBackup)? {
        let candidates = vaultCandidateURLs(root: root).compactMap { url -> (url: URL, backup: HerculesBackup)? in
            guard let data = try? Data(contentsOf: url),
                  let backup = try? decoder.decode(HerculesBackup.self, from: data)
            else { return nil }
            return (url, backup)
        }
        guard !candidates.isEmpty else { return nil }

        let ranked = candidates
            .map { candidate in
                (url: candidate.url, backup: candidate.backup, score: Self.backupMeaningfulScore(candidate.backup))
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.backup.exportedAt > $1.backup.exportedAt
            }

        if let meaningful = ranked.first(where: { $0.score > 0 }) {
            return (meaningful.url, meaningful.backup)
        }

        return ranked.first.map { ($0.url, $0.backup) }
    }

    private func richerVaultCandidate(than backup: HerculesBackup, minimumScoreDelta: Int = 25) -> (url: URL, backup: HerculesBackup)? {
        (try? withVaultRoot { root in
            guard let candidate = bestVaultRestoreCandidate(root: root) else { return nil }
            let vaultScore = Self.backupMeaningfulScore(candidate.backup)
            let localScore = Self.backupMeaningfulScore(backup)
            guard vaultScore >= localScore + minimumScoreDelta else { return nil }
            return candidate
        }) ?? nil
    }

    private func vaultCandidateURLs(root: URL) -> [URL] {
        let fm = FileManager.default
        let required = [
            root.appendingPathComponent(vaultSnapshotRelativePath),
            root.appendingPathComponent(vaultLegacySnapshotName)
        ]
        let generated = ["conflicts", "backups"].flatMap { directory -> [URL] in
            let dir = root.appendingPathComponent(directory, isDirectory: true)
            let files = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return files.filter { $0.pathExtension.lowercased() == "json" }
        }

        var seen = Set<String>()
        return (required + generated).filter { url in
            guard fm.fileExists(atPath: url.path), !seen.contains(url.path) else { return false }
            seen.insert(url.path)
            return true
        }
    }

    nonisolated private static func backupMeaningfulScore(_ backup: HerculesBackup) -> Int {
        let profileScore: Int = {
            guard let profile = backup.profile else { return 0 }
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let about = (profile.about ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let supplements = (profile.supplements ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasCustomSupplements = !supplements.isEmpty && supplements != UserProfile.defaultSupplements
            var score = 0
            if !name.isEmpty { score += 1 }
            if !about.isEmpty { score += 1 }
            if hasCustomSupplements { score += 1 }
            if profile.targetWeight != nil { score += 1 }
            if profile.manualBodyFat != nil { score += 1 }
            let offsetMacro = profile.manualCalorieOffsetMacro.flatMap(CalorieOffsetMacro.init(rawValue:)) ?? .carbs
            if profile.manualCalorieOffset != 0 || offsetMacro != .carbs { score += 1 }
            if profile.manualProteinGrams != nil || profile.manualCarbsGrams != nil || profile.manualFatGrams != nil { score += 1 }
            return score
        }()

        let customPresetCount = (backup.foodPresets ?? [])
            .filter { !FoodPresetSeed.defaultPresetIDs.contains($0.presetID) }
            .count

        return profileScore
            + backup.measurements.count * 4
            + backup.foods.count * 2
            + backup.recipes.count * 3
            + backup.steps.count
            + (backup.monthlyGoals?.count ?? 0)
            + (backup.workoutPlanOverrides?.count ?? 0)
            + (backup.workoutLogs?.count ?? 0) * 3
            + (backup.workoutArchives?.count ?? 0) * 2
            + (backup.supportFiles?.count ?? 0)
            + customPresetCount
    }

    nonisolated private static func ensureVaultLayout(
        root: URL,
        snapshotRelativePath: String,
        legacySnapshotName: String,
        manifestName: String,
        readmeName: String
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["data", "support", "backups", "conflicts"] {
            try fm.createDirectory(at: root.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
        _ = snapshotRelativePath
        _ = legacySnapshotName
        _ = manifestName
        _ = readmeName
    }

    nonisolated private static func makeVaultManifest(
        _ backup: HerculesBackup,
        deviceID: String,
        snapshotRelativePath: String,
        legacySnapshotName: String
    ) -> VaultManifest {
        VaultManifest(
            version: 1,
            appName: "Hercules",
            updatedAt: .now,
            deviceID: deviceID,
            snapshotFile: snapshotRelativePath,
            legacySnapshotFile: legacySnapshotName,
            backupVersion: backup.version,
            exportedAt: backup.exportedAt,
            counts: VaultManifest.Counts(
                measurements: backup.measurements.count,
                foods: backup.foods.count,
                foodPresets: backup.foodPresets?.count ?? 0,
                workouts: backup.workouts.count,
                workoutArchives: backup.workoutArchives?.count ?? 0,
                workoutPlanOverrides: backup.workoutPlanOverrides?.count ?? 0,
                recipes: backup.recipes.count,
                steps: backup.steps.count,
                monthlyGoals: backup.monthlyGoals?.count ?? 0,
                workoutLogs: backup.workoutLogs?.count ?? 0,
                supportFiles: backup.supportFiles?.count ?? 0,
                preferences: backup.preferences?.count ?? 0
            ),
            domains: [
                "profile",
                "about",
                "measurements",
                "foods",
                "food-presets",
                "workout-program",
                "workout-archives",
                "workout-plan-overrides",
                "workout-logs",
                "recipes",
                "steps",
                "monthly-goals",
                "chat-history",
                "agent-memory",
                "research-library",
                "preferences"
            ]
        )
    }

    private func persistVaultBookmark(for url: URL) throws {
        let bookmark = try url.bookmarkData(options: Self.bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: vaultBookmarkKey)
    }

    private func resolveVaultBookmark() throws -> (url: URL, isStale: Bool) {
        guard let data = UserDefaults.standard.data(forKey: vaultBookmarkKey) else {
            throw BackupServiceError.vaultNotConfigured
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: Self.bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            try? persistVaultBookmark(for: url)
        }
        return (url, isStale)
    }

    private func withVaultRoot<T>(_ body: (URL) throws -> T) throws -> T {
        let root = try resolveVaultBookmark().url
        let didStart = root.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                root.stopAccessingSecurityScopedResource()
            }
        }
        return try body(root)
    }

    private var deviceID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: vaultDeviceIDKey), !existing.isEmpty {
            return existing
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: vaultDeviceIDKey)
        return value
    }

    private var lastSeenVaultExportedAt: Date? {
        get {
            let raw = UserDefaults.standard.double(forKey: vaultLastSeenExportKey)
            return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: vaultLastSeenExportKey)
            } else {
                UserDefaults.standard.removeObject(forKey: vaultLastSeenExportKey)
            }
        }
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    nonisolated private static var defaultVaultReadme: String {
        """
        # Hercules Vault

        Bu klasor Hercules'in dosya tabanli veri kasasidir.

        - `data/hercules-backup.json`: Tum profil, olcum, yemek, tarif, antrenman, chat, memory ve research snapshot'i.
        - `manifest.json`: Son export tarihi, cihaz kimligi ve kayit sayilari.
        - `support/`: Chat history, agent memory ve research cache gibi okunabilir destek dosyalari.
        - `backups/`: Restore oncesi guvenlik kopyalari.
        - `conflicts/`: Baska cihazdan gelen daha yeni kopya ezilmeden once buraya alinmis conflict dosyalari.

        iCloud Drive, Dropbox veya benzeri bir klasoru bu vault olarak secebilirsin. SQLite store'u direkt sync etmiyoruz; veri kaybi riskini dusurmek icin JSON snapshot kullaniyoruz.
        """
    }

    nonisolated private static func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func timestampForFilename() -> String {
        Self.timestampForFilename()
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
            AppLog.backup.notice("[Backup] auto-restored from \(restoreURL.path)")
        } catch {
            AppLog.backup.error("[Backup] auto-restore failed: \(String(describing: error))")
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
            AppLog.backup.notice("[Backup] restored newer iCloud backup from \(cloudURL.path)")
        } catch {
            AppLog.backup.error("[Backup] iCloud auto-restore failed: \(String(describing: error))")
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
            if backup.foodPresets != nil {
                ((try? ctx.fetch(FetchDescriptor<FoodPreset>())) ?? []).forEach { ctx.delete($0) }
            }
            ((try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<WorkoutProgramArchive>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<WorkoutPlanOverride>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<StepEntry>())) ?? []).forEach { ctx.delete($0) }
            ((try? ctx.fetch(FetchDescriptor<MonthlyGoal>())) ?? []).forEach { ctx.delete($0) }
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
            p.manualCalorieOffsetMacro = ps.manualCalorieOffsetMacro.flatMap(CalorieOffsetMacro.init(rawValue:)) ?? .carbs
            p.manualProteinGrams = ps.manualProteinGrams
            p.manualCarbsGrams = ps.manualCarbsGrams
            p.manualFatGrams = ps.manualFatGrams
            p.about = ps.about ?? ""
            p.supplements = (ps.supplements ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? UserProfile.defaultSupplements
                : (ps.supplements ?? UserProfile.defaultSupplements)
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
        if let presetSnapshots = backup.foodPresets {
            let existingPresets = (try? ctx.fetch(FetchDescriptor<FoodPreset>())) ?? []
            var presetsByID: [String: FoodPreset] = [:]
            for preset in existingPresets where presetsByID[preset.presetID] == nil {
                presetsByID[preset.presetID] = preset
            }
            for p in presetSnapshots {
                let preset = presetsByID[p.presetID] ?? FoodPreset(
                    presetID: p.presetID,
                    name: p.name,
                    brand: p.brand,
                    category: p.category,
                    servingLabel: p.servingLabel,
                    servingGrams: p.servingGrams,
                    defaultServings: p.defaultServings,
                    calories: p.calories,
                    protein: p.protein,
                    carbs: p.carbs,
                    fat: p.fat,
                    note: p.note,
                    searchText: p.searchText,
                    sortOrder: p.sortOrder,
                    createdAt: p.createdAt,
                    updatedAt: p.updatedAt
                )
                preset.name = p.name
                preset.brand = p.brand
                preset.category = p.category
                preset.servingLabel = p.servingLabel
                preset.servingGrams = p.servingGrams
                preset.defaultServings = p.defaultServings
                preset.calories = p.calories
                preset.protein = p.protein
                preset.carbs = p.carbs
                preset.fat = p.fat
                preset.note = p.note
                preset.searchText = p.searchText
                preset.sortOrder = p.sortOrder
                preset.createdAt = p.createdAt
                preset.updatedAt = p.updatedAt

                if presetsByID[p.presetID] == nil {
                    ctx.insert(preset)
                    presetsByID[p.presetID] = preset
                }
            }
        }
        for w in backup.workouts {
            let session = WorkoutSession(
                weekday: w.weekday,
                name: w.name,
                estimatedCalories: w.estimatedCalories,
                durationMinutes: w.durationMinutes ?? 60,
                focus: w.focus,
                warmup: w.warmup,
                progression: w.progression,
                notes: w.notes
            )
            ctx.insert(session)
            for exerciseSnapshot in (w.exercises ?? []).sorted(by: { $0.order < $1.order }) {
                let exercise = WorkoutTemplateExercise(
                    name: exerciseSnapshot.name,
                    order: exerciseSnapshot.order,
                    sets: exerciseSnapshot.sets,
                    reps: exerciseSnapshot.reps,
                    load: exerciseSnapshot.load,
                    rir: exerciseSnapshot.rir,
                    rest: exerciseSnapshot.rest,
                    sourceURL: exerciseSnapshot.sourceURL,
                    notes: exerciseSnapshot.notes
                )
                ctx.insert(exercise)
                session.templateExercises.append(exercise)
            }
        }
        for archive in (backup.workoutArchives ?? []) {
            ctx.insert(WorkoutProgramArchive(
                title: archive.title,
                summary: archive.summary,
                notes: archive.notes,
                source: archive.source,
                archivedAt: archive.archivedAt,
                sessionsJSON: archive.sessionsJSON
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
                isFavorite: r.isFavorite ?? false,
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
        #if os(macOS)
        LocalMemoryProvider.shared.reloadFromDisk()
        ResearchLibrary.shared.reloadFromDisk()
        #endif
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
