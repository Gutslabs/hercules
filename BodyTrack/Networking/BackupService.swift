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
    /// Merge öncesi güvenlik yedeği oturumda bir kez yazılsın (her foreground'da değil).
    private var didWriteMergeSafety = false
    /// Oto-senkron throttle'ı — sık foreground/background olaylarında vault'u dövmesin.
    private var lastAutoSyncAt: Date?
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
            version: 13,
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
            preferences: buildPreferenceSnapshots(),
            // Sync v13: kayıt-başına updatedAt + mevcut tombstone seti (SAF — burada
            // mutasyon yok; yeni silme tespiti push anında recordPushDeletionsAndTombstones'da).
            recordTimestamps: currentKeysAndTimestamps(ctx: ctx).timestamps,
            tombstones: Array(loadTombstones().values)
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
    func exportToVault(from ctx: ModelContext, force: Bool = false) throws -> VaultOperationSummary {
        // force=true (merge-sync push): guard'lar atlanır. Pull-merge sonrası local
        // OTORİTEDİR; silme local'i "daha az zengin" yapsa bile vault'a YAZILMALI —
        // yoksa silmeler (tombstone) karşı cihaza hiç ulaşmaz ve kayıt geri dirilir.
        if !force {
            guard storeHasMeaningfulData(ctx) else {
                throw BackupServiceError.emptyStoreExportSkipped
            }
        }
        let backup = try buildBackup(ctx: ctx)
        if !force {
            guard richerVaultCandidate(than: backup) == nil else {
                throw BackupServiceError.richerVaultSnapshotExists
            }
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
    /// Geri-uyumluluk girişi: artık "ifNewer" gating + replaceAll YOK. Union merge her
    /// zaman güvenli olduğu için tam iki-yönlü senkronu (pull-merge + push) çalıştırır.
    func restoreFromVaultIfNewer(into ctx: ModelContext) {
        do { try syncWithVault(into: ctx) }
        catch { AppLog.backup.error("[Vault] sync failed: \(String(describing: error))") }
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
        await syncWithVaultNonBlocking(into: ctx)
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

    /// SADECE kanonik snapshot'ı okur (data/hercules-backup.json, yoksa legacy) — en yeni
    /// exportedAt'i seçer. `backups/` ve `conflicts/` TARANMAZ. Merge/pull ve diagnostic
    /// bunu kullanır: yoksa en "zengin" eski yedek seçilip SİLİNEN kayıtlar geri dirilir
    /// ve cihazlar güncel snapshot'a yakınsamaz. bestVaultRestoreCandidate (backups dahil)
    /// yalnız elle "tam geri yükle" kurtarması içindir.
    private func canonicalVaultSnapshot(root: URL) -> (url: URL, backup: HerculesBackup)? {
        let urls = [
            root.appendingPathComponent(vaultSnapshotRelativePath),
            root.appendingPathComponent(vaultLegacySnapshotName)
        ]
        return urls.compactMap { url -> (url: URL, backup: HerculesBackup)? in
            guard let data = try? Data(contentsOf: url),
                  let b = try? decoder.decode(HerculesBackup.self, from: data) else { return nil }
            return (url, b)
        }
        .sorted { $0.backup.exportedAt > $1.backup.exportedAt }
        .first
    }

    private func richerVaultCandidate(than backup: HerculesBackup, minimumScoreDelta: Int = 25) -> (url: URL, backup: HerculesBackup)? {
        (try? withVaultRoot { root in
            guard let candidate = canonicalVaultSnapshot(root: root) else { return nil }
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

// MARK: - Sync merge engine (union + çakışma + tombstone)
//
// İki cihazı KATARAK senkronlar (replaceAll gibi ezmez): bir cihazda olup
// diğerinde olmayan kayıt eklenir; aynı kayıt iki yerde değiştiyse updatedAt
// yenisi kazanır; silmeler tombstone ile propagate olur (geri dirilmez).
//
// Kimlik: uid YOK. Anahtarlar DEĞİŞMEZ alanlardan türetilir; böylece eski
// replaceAll-sync ile zaten kopyalanmış kayıtlar iki cihazda aynı anahtarı
// üretir ve ilk merge'de çiftlenmez.
extension BackupService {

    enum SyncKey {
        // SANİYE hassasiyeti (ms DEĞİL): snapshot JSON'u iso8601 ile yazıldığından Date
        // round-trip'te milisaniye KAYBOLUR. ms kullansaydık aynı kayıt her turda farklı
        // anahtar alır → union/dedup bozulur, cihazlar yakınsamaz. Saniye round-trip'te sabit.
        static func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970.rounded()) }
        static func day(_ date: Date) -> String {
            let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        }
        static func month(_ date: Date) -> String {
            let c = Calendar.current.dateComponents([.year, .month], from: date)
            return "\(c.year ?? 0)-\(c.month ?? 0)"
        }

        static let profile = "profile"
        static func measurement(_ d: Date) -> String { "m-\(ms(d))" }
        static func food(_ d: Date, _ name: String) -> String { "f-\(ms(d))-\(name)" }
        static func step(_ d: Date) -> String { "s-\(day(d))" }
        static func goal(_ anchor: Date) -> String { "g-\(month(anchor))" }
        static func recipe(_ createdAt: Date) -> String { "r-\(ms(createdAt))" }
        static func workoutLog(_ d: Date, _ name: String) -> String { "wl-\(ms(d))-\(name)" }
        static func workout(_ weekday: Int) -> String { "ws-\(weekday)" }
        static func archive(_ archivedAt: Date, _ title: String) -> String { "wa-\(ms(archivedAt))-\(title)" }
        static func planOverride(_ createdAt: Date, _ weekday: Int, _ name: String) -> String { "wo-\(ms(createdAt))-\(weekday)-\(name)" }
        static func preset(_ id: String) -> String { "fp-\(id)" }
    }

    // MARK: Local sync state (tombstones + son sync anahtarları)

    private var syncStateDir: URL { backupURL.deletingLastPathComponent() }
    private var tombstonesFileURL: URL { syncStateDir.appendingPathComponent("sync-tombstones.json") }
    private var lastKeysFileURL: URL { syncStateDir.appendingPathComponent("sync-lastkeys.json") }

    /// key → en yeni tombstone.
    func loadTombstones() -> [String: TombstoneSnapshot] {
        guard let data = try? Data(contentsOf: tombstonesFileURL),
              let arr = try? decoder.decode([TombstoneSnapshot].self, from: data) else { return [:] }
        var map: [String: TombstoneSnapshot] = [:]
        for t in arr {
            if let e = map[t.key] { if t.deletedAt > e.deletedAt { map[t.key] = t } } else { map[t.key] = t }
        }
        return map
    }

    func saveTombstones(_ map: [String: TombstoneSnapshot]) {
        // 180 günden eski tombstone'ları buda (sınırsız büyümesin).
        let cutoff = Date().addingTimeInterval(-180 * 86_400)
        let kept = map.values.filter { $0.deletedAt >= cutoff }
        if let data = try? encoder.encode(Array(kept)) {
            try? data.write(to: tombstonesFileURL, options: [.atomic])
        }
    }

    private func loadLastSyncedKeys() -> Set<String> {
        guard let data = try? Data(contentsOf: lastKeysFileURL),
              let arr = try? decoder.decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    private func saveLastSyncedKeys(_ keys: Set<String>) {
        if let data = try? encoder.encode(Array(keys)) {
            try? data.write(to: lastKeysFileURL, options: [.atomic])
        }
    }

    /// Anahtar formatı değişince (ms→saniye) eski lastSyncedKeys/tombstone'lar GEÇERSİZ —
    /// bir kez sıfırla. Yoksa eski ms-anahtarlar yeni saniye-anahtarlarla eşleşmez, hepsi
    /// "silinmiş" sanılıp kütlesel tombstone üretilir (mevcut veri yok olur).
    private func migrateSyncKeyFormatIfNeeded() {
        let k = "hercules.sync.keyformat"
        let current = 2
        guard UserDefaults.standard.integer(forKey: k) != current else { return }
        try? FileManager.default.removeItem(at: lastKeysFileURL)
        try? FileManager.default.removeItem(at: tombstonesFileURL)
        UserDefaults.standard.set(current, forKey: k)
        AppLog.backup.notice("[Sync] anahtar formatı geçişi → baseline + tombstone sıfırlandı")
    }

    /// Tüm canlı kayıtların merge anahtarları + updatedAt'leri.
    func currentKeysAndTimestamps(ctx: ModelContext) -> (keys: Set<String>, timestamps: [String: Date]) {
        var keys = Set<String>()
        var ts: [String: Date] = [:]
        func add(_ k: String, _ d: Date) { keys.insert(k); ts[k] = d }

        if let p = (try? ctx.fetch(FetchDescriptor<UserProfile>()))?.first { add(SyncKey.profile, p.updatedAt) }
        for m in (try? ctx.fetch(FetchDescriptor<Measurement>())) ?? [] { add(SyncKey.measurement(m.date), m.updatedAt) }
        for f in (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? [] { add(SyncKey.food(f.date, f.name), f.updatedAt) }
        for s in (try? ctx.fetch(FetchDescriptor<StepEntry>())) ?? [] { add(SyncKey.step(s.date), s.updatedAt) }
        for g in (try? ctx.fetch(FetchDescriptor<MonthlyGoal>())) ?? [] { add(SyncKey.goal(g.anchorDate), g.updatedAt) }
        for r in (try? ctx.fetch(FetchDescriptor<Recipe>())) ?? [] { add(SyncKey.recipe(r.createdAt), r.updatedAt) }
        for w in (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? [] { add(SyncKey.workout(w.weekday), w.updatedAt) }
        for a in (try? ctx.fetch(FetchDescriptor<WorkoutProgramArchive>())) ?? [] { add(SyncKey.archive(a.archivedAt, a.title), a.archivedAt) }
        for o in (try? ctx.fetch(FetchDescriptor<WorkoutPlanOverride>())) ?? [] { add(SyncKey.planOverride(o.createdAt, o.weekday, o.exerciseName), o.createdAt) }
        for fp in (try? ctx.fetch(FetchDescriptor<FoodPreset>())) ?? [] { add(SyncKey.preset(fp.presetID), fp.updatedAt) }
        for l in (try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? [] { add(SyncKey.workoutLog(l.date, l.name), l.updatedAt) }
        return (keys, ts)
    }

    /// Push öncesi: son sync'ten bu yana SİLİNEN anahtarlar için tombstone üretir,
    /// lastSyncedKeys'i günceller. Dönen liste snapshot'a yazılır.
    func recordPushDeletionsAndTombstones(ctx: ModelContext) -> [TombstoneSnapshot] {
        let current = currentKeysAndTimestamps(ctx: ctx).keys
        var tombs = loadTombstones()
        let deleted = loadLastSyncedKeys().subtracting(current)
        if !deleted.isEmpty {
            let now = Date()
            for key in deleted {
                let entity = String(key.prefix(while: { $0 != "-" }))
                if let existing = tombs[key], existing.deletedAt >= now { continue }
                tombs[key] = TombstoneSnapshot(entity: entity, key: key, deletedAt: now)
            }
            saveTombstones(tombs)
        }
        // NOT: canlı anahtarlar için tombstone SİLİNMEZ — recreate senaryosunu applyMerge
        // zaten (record.updatedAt > tombstone.deletedAt) ile çözer. Burada silmek, henüz
        // merge etmemiş diğer cihaza giden silmeyi kaybettirirdi.
        saveLastSyncedKeys(current)
        return Array(tombs.values)
    }

    /// İki-yönlü union merge. Incoming snapshot'ı local'e KATAR. Çakışmada updatedAt
    /// yenisi kazanır; tombstone'lar silmeleri uygular. Ham save() kullanır (updatedAt
    /// snapshot'tan gelir, saveOrReport damgası onu ezmesin).
    func applyMerge(_ backup: HerculesBackup, into ctx: ModelContext) {
        let incomingTS = backup.recordTimestamps ?? [:]

        // 1) tombstone'ları birleştir
        var tombs = loadTombstones()
        for t in (backup.tombstones ?? []) {
            if let e = tombs[t.key] { if t.deletedAt > e.deletedAt { tombs[t.key] = t } } else { tombs[t.key] = t }
        }
        func resolvedTS(_ key: String, _ fallback: Date) -> Date { incomingTS[key] ?? fallback }
        func tombstoned(_ key: String, _ recordDate: Date) -> Bool {
            if let t = tombs[key], t.deletedAt >= recordDate { return true }
            return false
        }

        // 2) PROFILE (singleton)
        if let ps = backup.profile {
            let key = SyncKey.profile
            let u = resolvedTS(key, backup.exportedAt)
            let existing = (try? ctx.fetch(FetchDescriptor<UserProfile>()))?.first
            if !tombstoned(key, u) {
                if let existing {
                    if u > existing.updatedAt { applyProfileSnapshot(ps, to: existing); existing.updatedAt = u }
                } else {
                    let p = UserProfile(); ctx.insert(p); applyProfileSnapshot(ps, to: p); p.updatedAt = u
                }
            }
        }

        // 3) MEASUREMENTS
        mergeUpsert(
            Measurement.self,
            ctx: ctx, incoming: backup.measurements,
            key: { SyncKey.measurement($0.date) }, fallbackDate: { $0.date },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.measurement($0.date) }, localUpdatedAt: { $0.updatedAt },
            insert: { snap, u in
                let m = Measurement(date: snap.date, weight: snap.weight, bodyFat: snap.bodyFat, waist: snap.waist, chest: snap.chest, neck: snap.neck, note: snap.note)
                m.updatedAt = u; ctx.insert(m)
            }
        )

        // 4) FOODS
        mergeUpsert(
            FoodEntry.self,
            ctx: ctx, incoming: backup.foods,
            key: { SyncKey.food($0.date, $0.name) }, fallbackDate: { $0.date },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.food($0.date, $0.name) }, localUpdatedAt: { $0.updatedAt },
            insert: { snap, u in
                let f = FoodEntry(date: snap.date, name: snap.name, grams: snap.grams, calories: snap.calories, protein: snap.protein, carbs: snap.carbs, fat: snap.fat)
                f.updatedAt = u; ctx.insert(f)
            }
        )

        // 5) STEPS
        mergeUpsert(
            StepEntry.self,
            ctx: ctx, incoming: backup.steps,
            key: { SyncKey.step($0.date) }, fallbackDate: { $0.date },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.step($0.date) }, localUpdatedAt: { $0.updatedAt },
            insert: { snap, u in
                let s = StepEntry(date: snap.date, steps: snap.steps, source: snap.source, distanceMeters: snap.distanceMeters, activeEnergyKcal: snap.activeEnergyKcal, syncedAt: snap.syncedAt)
                s.updatedAt = u; ctx.insert(s)
            }
        )

        // 6) MONTHLY GOALS
        mergeUpsert(
            MonthlyGoal.self,
            ctx: ctx, incoming: backup.monthlyGoals ?? [],
            key: { SyncKey.goal($0.anchorDate) }, fallbackDate: { $0.anchorDate },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.goal($0.anchorDate) }, localUpdatedAt: { $0.updatedAt },
            insert: { snap, u in
                let g = MonthlyGoal(anchorDate: snap.anchorDate, targetWeight: snap.targetWeight, note: snap.note)
                g.updatedAt = u; ctx.insert(g)
            }
        )

        // 7) RECIPES
        mergeUpsert(
            Recipe.self,
            ctx: ctx, incoming: backup.recipes,
            key: { SyncKey.recipe($0.createdAt) }, fallbackDate: { $0.createdAt },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.recipe($0.createdAt) }, localUpdatedAt: { $0.updatedAt },
            insert: { snap, u in
                let r = Recipe(title: snap.title, urlString: snap.urlString, category: RecipeCategory(rawValue: snap.category) ?? .dinner, isFavorite: snap.isFavorite ?? false, summary: snap.summary, ingredientsText: snap.ingredientsText, instructionsText: snap.instructionsText, servings: snap.servings, prepMinutes: snap.prepMinutes, calories: snap.calories, protein: snap.protein, carbs: snap.carbs, fat: snap.fat, createdAt: snap.createdAt)
                r.updatedAt = u; ctx.insert(r)
            }
        )

        // 8) WORKOUT SESSIONS (template + nested exercises)
        mergeUpsert(
            WorkoutSession.self,
            ctx: ctx, incoming: backup.workouts,
            key: { SyncKey.workout($0.weekday) }, fallbackDate: { _ in backup.exportedAt },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.workout($0.weekday) }, localUpdatedAt: { $0.updatedAt },
            insert: { snap, u in
                let session = WorkoutSession(weekday: snap.weekday, name: snap.name, estimatedCalories: snap.estimatedCalories, durationMinutes: snap.durationMinutes ?? 60, focus: snap.focus, warmup: snap.warmup, progression: snap.progression, notes: snap.notes)
                session.updatedAt = u
                ctx.insert(session)
                for ex in (snap.exercises ?? []).sorted(by: { $0.order < $1.order }) {
                    let e = WorkoutTemplateExercise(name: ex.name, order: ex.order, sets: ex.sets, reps: ex.reps, load: ex.load, rir: ex.rir, rest: ex.rest, sourceURL: ex.sourceURL, notes: ex.notes)
                    ctx.insert(e)
                    session.templateExercises.append(e)
                }
            }
        )

        // 9) WORKOUT ARCHIVES (archivedAt = recency proxy)
        mergeUpsert(
            WorkoutProgramArchive.self,
            ctx: ctx, incoming: backup.workoutArchives ?? [],
            key: { SyncKey.archive($0.archivedAt, $0.title) }, fallbackDate: { $0.archivedAt },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.archive($0.archivedAt, $0.title) }, localUpdatedAt: { $0.archivedAt },
            insert: { snap, _ in
                ctx.insert(WorkoutProgramArchive(title: snap.title, summary: snap.summary, notes: snap.notes, source: snap.source, archivedAt: snap.archivedAt, sessionsJSON: snap.sessionsJSON))
            }
        )

        // 10) WORKOUT PLAN OVERRIDES (createdAt = recency proxy)
        mergeUpsert(
            WorkoutPlanOverride.self,
            ctx: ctx, incoming: backup.workoutPlanOverrides ?? [],
            key: { SyncKey.planOverride($0.createdAt, $0.weekday, $0.exerciseName) }, fallbackDate: { $0.createdAt },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.planOverride($0.createdAt, $0.weekday, $0.exerciseName) }, localUpdatedAt: { $0.createdAt },
            insert: { snap, _ in
                ctx.insert(WorkoutPlanOverride(weekday: snap.weekday, operation: WorkoutPlanOverrideOperation(rawValue: snap.operationRaw) ?? .addExercise, exerciseName: snap.exerciseName, sets: snap.sets, reps: snap.reps, weight: snap.weight, note: snap.note, source: snap.source, createdAt: snap.createdAt))
            }
        )

        // 11) FOOD PRESETS
        mergeUpsert(
            FoodPreset.self,
            ctx: ctx, incoming: backup.foodPresets ?? [],
            key: { SyncKey.preset($0.presetID) }, fallbackDate: { $0.updatedAt },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.preset($0.presetID) }, localUpdatedAt: { $0.updatedAt },
            insert: { snap, u in
                let p = FoodPreset(presetID: snap.presetID, name: snap.name, brand: snap.brand, category: snap.category, servingLabel: snap.servingLabel, servingGrams: snap.servingGrams, defaultServings: snap.defaultServings, calories: snap.calories, protein: snap.protein, carbs: snap.carbs, fat: snap.fat, note: snap.note, searchText: snap.searchText, sortOrder: snap.sortOrder, createdAt: snap.createdAt, updatedAt: snap.updatedAt)
                p.updatedAt = u; ctx.insert(p)
            }
        )

        // 12) WORKOUT LOGS (nested exercises + sets)
        mergeUpsert(
            WorkoutLog.self,
            ctx: ctx, incoming: backup.workoutLogs ?? [],
            key: { SyncKey.workoutLog($0.date, $0.name) }, fallbackDate: { $0.date },
            ts: incomingTS, tombs: tombs,
            localKey: { SyncKey.workoutLog($0.date, $0.name) }, localUpdatedAt: { $0.updatedAt },
            insert: { snap, u in
                let log = WorkoutLog(date: snap.date, name: snap.name, durationMinutes: snap.durationMinutes, estimatedCalories: snap.estimatedCalories, notes: snap.notes)
                log.updatedAt = u
                ctx.insert(log)
                for ex in snap.exercises.sorted(by: { $0.order < $1.order }) {
                    let entry = WorkoutExerciseEntry(name: ex.name, order: ex.order)
                    ctx.insert(entry)
                    for st in ex.sets.sorted(by: { $0.order < $1.order }) {
                        let set = ExerciseSet(order: st.order, reps: st.reps, weight: st.weight)
                        ctx.insert(set)
                        entry.setEntries.append(set)
                    }
                    log.exercises.append(entry)
                }
            }
        )

        // 13) tombstone'ları KALAN local kayıtlara uygula (incoming'de olmayanlar dahil)
        applyTombstonesToLocalRecords(tombs, ctx: ctx)

        // 14) ham save (saveOrReport DEĞİL — updatedAt ezilmesin)
        do { try ctx.save() } catch {
            AppLog.backup.error("[Merge] save failed: \(String(describing: error))")
        }

        // 15) durumu güncelle
        saveTombstones(tombs)
        saveLastSyncedKeys(currentKeysAndTimestamps(ctx: ctx).keys)
        AppLog.backup.notice("[Merge] union merge applied")
    }

    /// Generic upsert: incoming kayıtları local'e katar; çakışmada updatedAt yenisi
    /// kazanır (eski local'i silip yenisini ekler); tombstone'lanmışsa atlar/siler.
    private func mergeUpsert<Snapshot, Model: PersistentModel>(
        _ modelType: Model.Type,
        ctx: ModelContext,
        incoming: [Snapshot],
        key: (Snapshot) -> String,
        fallbackDate: (Snapshot) -> Date,
        ts: [String: Date],
        tombs: [String: TombstoneSnapshot],
        localKey: (Model) -> String,
        localUpdatedAt: (Model) -> Date,
        insert: (Snapshot, Date) -> Void
    ) {
        var localByKey: [String: Model] = [:]
        for m in (try? ctx.fetch(FetchDescriptor<Model>())) ?? [] {
            let k = localKey(m)
            if localByKey[k] == nil { localByKey[k] = m }
            else { ctx.delete(m) } // aynı anahtarlı yerel çift (kararsız-anahtar döneminden) → temizle
        }
        for snap in incoming {
            let k = key(snap)
            let u = ts[k] ?? fallbackDate(snap)
            if let t = tombs[k], t.deletedAt >= u {
                if let local = localByKey[k] { ctx.delete(local); localByKey[k] = nil }
                continue
            }
            if let local = localByKey[k] {
                if u > localUpdatedAt(local) {
                    ctx.delete(local)
                    insert(snap, u)
                }
            } else {
                insert(snap, u)
            }
        }
    }

    /// Tombstone'u olan ve updatedAt'i tombstone'dan eski olan TÜM local kayıtları sil.
    private func applyTombstonesToLocalRecords(_ tombs: [String: TombstoneSnapshot], ctx: ModelContext) {
        guard !tombs.isEmpty else { return }
        func purge<Model: PersistentModel>(_ type: Model.Type, key: (Model) -> String, updatedAt: (Model) -> Date) {
            for m in (try? ctx.fetch(FetchDescriptor<Model>())) ?? [] {
                if let t = tombs[key(m)], t.deletedAt >= updatedAt(m) { ctx.delete(m) }
            }
        }
        purge(Measurement.self, key: { SyncKey.measurement($0.date) }, updatedAt: { $0.updatedAt })
        purge(FoodEntry.self, key: { SyncKey.food($0.date, $0.name) }, updatedAt: { $0.updatedAt })
        purge(StepEntry.self, key: { SyncKey.step($0.date) }, updatedAt: { $0.updatedAt })
        purge(MonthlyGoal.self, key: { SyncKey.goal($0.anchorDate) }, updatedAt: { $0.updatedAt })
        purge(Recipe.self, key: { SyncKey.recipe($0.createdAt) }, updatedAt: { $0.updatedAt })
        purge(WorkoutSession.self, key: { SyncKey.workout($0.weekday) }, updatedAt: { $0.updatedAt })
        purge(WorkoutProgramArchive.self, key: { SyncKey.archive($0.archivedAt, $0.title) }, updatedAt: { $0.archivedAt })
        purge(WorkoutPlanOverride.self, key: { SyncKey.planOverride($0.createdAt, $0.weekday, $0.exerciseName) }, updatedAt: { $0.createdAt })
        purge(WorkoutLog.self, key: { SyncKey.workoutLog($0.date, $0.name) }, updatedAt: { $0.updatedAt })
        // FoodPreset/UserProfile silinmez (preset'ler seed, profil tekil) — tombstone uygulanmaz.
    }

    private func applyProfileSnapshot(_ ps: ProfileSnapshot, to p: UserProfile) {
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

    // MARK: Kanonik sync (pull-merge + push) — kayıpsız, atomik.

    /// Vault ile iki-yönlü senkron: (1) yerel silmeleri tombstone'a çevir, (2) vault'u
    /// local'e KATARAK çek (merge), (3) birleşmiş local'i vault'a yaz. Sıra kritik:
    /// silme tespiti merge'den ÖNCE olmalı, yoksa merge silineni vault'tan geri ekler.
    func syncWithVault(into ctx: ModelContext) throws {
        migrateSyncKeyFormatIfNeeded()                  // 0) eski ms-anahtar baseline'ını sıfırla
        _ = recordPushDeletionsAndTombstones(ctx: ctx) // 1) pull öncesi silme tespiti
        try withVaultRoot { root in                    // 2) PULL: union merge
            try Self.ensureVaultLayout(
                root: root,
                snapshotRelativePath: vaultSnapshotRelativePath,
                legacySnapshotName: vaultLegacySnapshotName,
                manifestName: vaultManifestName,
                readmeName: vaultReadmeName
            )
            if let candidate = canonicalVaultSnapshot(root: root) {
                writeMergeSafetyBackupOnce(into: root, from: ctx)
                applyMerge(candidate.backup, into: ctx)
            }
        }
        do {                                            // 3) PUSH: birleşmiş local → vault
            // force: silme propagation için guard'sız yaz (local merge sonrası otorite).
            _ = try exportToVault(from: ctx, force: true)
        } catch {
            AppLog.backup.error("[Sync] push failed: \(String(describing: error))")
        }
    }

    /// Oto-tetikleyiciler (launch/foreground/background) için throttle'lı sürüm —
    /// 8 sn içinde tekrar çağrılırsa atlar. Manuel "Şimdi Senkronize Et" throttle'sızdır.
    func autoSyncWithVault(into ctx: ModelContext) async {
        guard UserDefaults.standard.data(forKey: vaultBookmarkKey) != nil else { return }
        if let last = lastAutoSyncAt, Date().timeIntervalSince(last) < 8 { return }
        lastAutoSyncAt = Date()
        await syncWithVaultNonBlocking(into: ctx)
    }

    /// `syncWithVault`'un bloklamayan sürümü: iCloud dosyalarını arka planda ısıtır,
    /// sonra senkronu main'de çalıştırır (ağır okuma ana thread'i dondurmaz).
    func syncWithVaultNonBlocking(into ctx: ModelContext) async {
        guard let bookmarkData = UserDefaults.standard.data(forKey: vaultBookmarkKey) else { return }
        let relativePaths = [vaultSnapshotRelativePath, vaultLegacySnapshotName, vaultManifestName]
        await Task.detached(priority: .utility) {
            BackupService.warmVaultFilesDetached(bookmarkData: bookmarkData, relativePaths: relativePaths)
        }.value
        do { try syncWithVault(into: ctx) }
        catch { AppLog.backup.error("[Sync] syncWithVault failed: \(String(describing: error))") }
    }

    private func writeMergeSafetyBackupOnce(into root: URL, from ctx: ModelContext) {
        guard !didWriteMergeSafety else { return }
        didWriteMergeSafety = true
        try? writePreVaultRestoreSafetyBackup(into: root, from: ctx)
    }

    /// Teşhis: yerel ve vault'taki yemek/ölçüm sayısı + vault'un son yazılma zamanı.
    /// Sync sonrası UI'da gösterilir — kopmanın nerede olduğunu görmek için.
    func syncDiagnostics(ctx: ModelContext) -> String {
        let localFoods = (try? ctx.fetchCount(FetchDescriptor<FoodEntry>())) ?? -1
        guard UserDefaults.standard.data(forKey: vaultBookmarkKey) != nil else {
            return "Yerel \(localFoods) yemek · VAULT SEÇİLİ DEĞİL"
        }
        let info: (foods: Int, meas: Int, at: Date)? = (try? withVaultRoot { root in
            guard let c = canonicalVaultSnapshot(root: root) else { return nil }
            return (c.backup.foods.count, c.backup.measurements.count, c.backup.exportedAt)
        }) ?? nil
        guard let info else { return "Yerel \(localFoods) yemek · vault dosyası OKUNAMADI" }
        let t = info.at.formatted(date: .omitted, time: .standard)
        return "Yerel \(localFoods) · Vault \(info.foods) yemek (\(t))"
    }
}
