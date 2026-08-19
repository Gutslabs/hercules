import Foundation
import CloudKit
import CoreData
import Observation
import SwiftData
import os
#if os(macOS)
import Security
#endif

/// Uygulama geneli structured logging — `print` yerine os.Logger (kategorili,
/// gizlilik-bilinçli). Konsoldan/Instruments'tan filtrelenebilir.
enum AppLog {
    static let subsystem = "com.hercules"
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let memory = Logger(subsystem: subsystem, category: "memory")
    static let ai = Logger(subsystem: subsystem, category: "ai")
}

/// App Support artifact'ları için macOS ve iOS hedeflerinde ortak hardening.
/// Dosyaları yalnız mevcut kullanıcıya, klasörleri yalnız mevcut kullanıcıya
/// erişilebilir yapar ve yeniden üretilebilir/özel veriyi cihaz yedeğinden çıkarır.
enum HerculesFileHardening {
    static func hardenFile(_ url: URL) {
        harden(url, permissions: 0o600)
    }

    static func hardenDirectory(_ url: URL) {
        harden(url, permissions: 0o700)
    }

    private static func harden(_ url: URL, permissions: Int) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}

/// Kaydetme hatalarını kullanıcıya tek bir noktadan bildirir. Root view bunu bir
/// alert'e bağlar; böylece "kaydedildi" der ama aslında diske yazılamamış (disk
/// dolu / iCloud çakışması) sessiz veri kaybı görünür olur.
@MainActor
@Observable
final class SaveErrorReporter {
    static let shared = SaveErrorReporter()
    private init() {}

    /// Son kaydetme hatası (nil = hata yok). Set edilince root alert tetiklenir.
    var message: String?
}

extension ModelContext {
    /// `try? save()` yerine kullan: hatayı YUTMAZ. Loglar (os.Logger) ve kullanıcıya
    /// tek bir uyarı gösterir (SaveErrorReporter). Başarıda tamamen sessizdir.
    ///
    /// Ayrıca bu kaydetmede değişen modellerin `updatedAt` alanını günceller.
    @discardableResult
    func saveOrReport(_ operation: String = "") -> Bool {
        stampUpdatedAtOnChangedModels()
        do {
            try save()
            return true
        } catch {
            let desc = error.localizedDescription
            AppLog.persistence.error("SwiftData save failed [\(operation, privacy: .public)]: \(desc, privacy: .public)")
            let op = operation
            Task { @MainActor in
                SaveErrorReporter.shared.message = op.isEmpty
                    ? "Kaydedilemedi: \(desc)"
                    : "Kaydedilemedi (\(op)): \(desc)"
            }
            return false
        }
    }

    /// saveOrReport'un throw eden kardeşi: damgalar + kaydeder, hatayı çağırana bırakır.
    /// Ham `try save()` çağrıları `updatedAt` damgasını atlıyordu; damga CloudKit
    /// dedup'unda hangi kopyanın hayatta kalacağını belirlediği için damgasız bir
    /// güncelleme, cihazlar arası birleşmede YENİ verinin silinmesine yol açabiliyordu.
    func saveStamped() throws {
        stampUpdatedAtOnChangedModels()
        try save()
    }

    /// Bu bağlamda değişmiş modellerin `updatedAt` alanını şimdiye çeker.
    /// Yeni eklenenler zaten init'te `.now` aldığı için sadece `changedModelsArray`'e bakılır.
    private func stampUpdatedAtOnChangedModels() {
        let now = Date.now
        for model in changedModelsArray {
            switch model {
            case let x as UserProfile: x.updatedAt = now
            case let x as Measurement: x.updatedAt = now
            case let x as FoodEntry: x.updatedAt = now
            case let x as Recipe: x.updatedAt = now
            case let x as WorkoutLog: x.updatedAt = now
            case let x as StepEntry: x.updatedAt = now
            case let x as MonthlyGoal: x.updatedAt = now
            case let x as WorkoutSession: x.updatedAt = now
            case let x as WorkoutTemplateExercise: x.session?.updatedAt = now
            case let x as WorkoutExerciseEntry: x.log?.updatedAt = now
            case let x as ExerciseSet: x.entry?.log?.updatedAt = now
            case let x as FoodPreset: x.updatedAt = now
            case let x as RecipeVideo: x.updatedAt = now
            default: break
            }
        }
    }
}

// MARK: - CloudKit durumu

/// SwiftData'nın alttaki CloudKit olaylarını gerçek zamanlı izler. UI artık sabit
/// "yeşil" göstermek yerine hesap, aktarım ve hata durumunu bu kaynaktan gösterir.
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()
    static let containerIdentifier = "iCloud.com.samorai.hercules"

    enum State: Equatable {
        case checking
        case ready(Date?)
        case syncing
        case unavailable(String)
        case error(String)
    }

    private(set) var state: State = .checking
    private(set) var lastSuccessfulSync: Date?

    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private weak var modelContainer: ModelContainer?
    @ObservationIgnored private var started = false
    private let lastSuccessKey = "hercules.cloudkit.last_success_v1"

    private init() {
        lastSuccessfulSync = UserDefaults.standard.object(forKey: lastSuccessKey) as? Date
    }

    var statusText: String {
        switch state {
        case .checking: return "iCloud kontrol ediliyor"
        case .ready(let date):
            guard let date else { return "iCloud hazır" }
            return "Senkronlandı · \(Fmt.relative(date))"
        case .syncing: return "iCloud senkronlanıyor…"
        case .unavailable: return "iCloud kullanılamıyor"
        case .error: return "Senkron hatası"
        }
    }

    var detailText: String {
        switch state {
        case .unavailable(let message), .error(let message): return message
        default:
            return "Ölçümler, yemekler, antrenmanlar, tarifler, profil, adımlar ve Akış Mac ile iPhone arasında CloudKit ile senkronlanır."
        }
    }

    var isHealthy: Bool {
        if case .ready = state { return true }
        return false
    }

    func start(container: ModelContainer) {
        modelContainer = container
        guard !started else { return }
        started = true

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handle(notification)
            }
        }

        Task { await refreshAccountStatus() }
    }

    /// `CKContainer(identifier:)` entitlement yoksa hata FIRLATMAZ — süreci anında
    /// SIGTRAP ile öldürür, aşağıdaki `do/catch` bunu yakalayamaz. Entitlement'sız
    /// imzalanmış bir macOS kopyası (ör. profilsiz Developer ID imzası) bu yüzden
    /// açılışta çakıyordu. Container'a dokunmadan önce imzada var mı diye bak.
    /// Container kurulmadan ÖNCE de sorulabilsin diye dışarı açık. `cloudKitDatabase`
    /// verildiğinde SwiftData aynı identifier'la CloudKit container'ı kuruyor; yani
    /// entitlement yoksa çakma, bu kontrolü yapan `refreshAccountStatus`tan ÖNCE
    /// gerçekleşiyordu.
    static var cloudKitEntitlementPresent: Bool { isCloudKitEntitled }

    private static var isCloudKitEntitled: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-identifiers" as CFString,
            nil
        )
        guard let containers = value as? [String] else { return false }
        return containers.contains(containerIdentifier)
        #else
        // iOS'ta uygulama provisioning profile olmadan kurulamaz; entitlement
        // her zaman imzanın içindedir.
        return true
        #endif
    }

    func refreshAccountStatus() async {
        guard Self.isCloudKitEntitled else {
            AppLog.sync.error(
                "CloudKit entitlement yok (\(Self.containerIdentifier, privacy: .public)) — senkron kapatıldı"
            )
            state = .unavailable("Uygulama iCloud yetkisi olmadan imzalanmış; bu kopyada senkron kapalı.")
            return
        }

        do {
            let accountStatus = try await CKContainer(identifier: Self.containerIdentifier).accountStatus()
            switch accountStatus {
            case .available:
                // Geçici ağ/hesap hatası düzeldikten sonra elle ya da yeniden açılışta
                // yapılan kontrol göstergede takılı kalmasın. Aktif aktarımı ise ezme.
                if case .syncing = state { break }
                state = .ready(lastSuccessfulSync)
            case .noAccount:
                state = .unavailable("Bu cihazda iCloud hesabı açık değil.")
            case .restricted:
                state = .unavailable("iCloud erişimi bu cihazda kısıtlanmış.")
            case .couldNotDetermine, .temporarilyUnavailable:
                state = .unavailable("iCloud hesabının durumu belirlenemedi. İnternet bağlantısını kontrol et.")
            @unknown default:
                state = .unavailable("Bilinmeyen bir iCloud hesap durumu oluştu.")
            }
        } catch {
            state = .error(error.localizedDescription)
            AppLog.sync.error("CloudKit account status failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// İlk senkron yüzlerce import olayı yayınlıyor ve her biri 13 tam tablo
    /// taramasını ana thread'de yeniden çalıştırıyordu → senkron penceresi boyunca
    /// donuk arayüz. Olayları sessizleşene kadar tek bir çalıştırmada topla.
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?

    private func scheduleReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let context = self?.modelContainer?.mainContext else { return }
            SyncDataReconciler.reconcile(in: context)
        }
    }

    private func handle(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        else { return }

        guard let endedAt = event.endDate else {
            state = .syncing
            return
        }

        if event.succeeded {
            lastSuccessfulSync = endedAt
            UserDefaults.standard.set(endedAt, forKey: lastSuccessKey)
            state = .ready(endedAt)

            if event.type == .import {
                scheduleReconcile()
            }
        } else {
            let message = event.error?.localizedDescription ?? "CloudKit işlemi tamamlanamadı."
            state = .error(message)
            AppLog.sync.error("CloudKit event failed: \(message, privacy: .public)")
        }
    }
}

// MARK: - Senkron sonrası tekilleştirme

/// CloudKit mantıksal unique constraint sunmadığı için aynı anda iki cihazda oluşan
/// kayıtları her import'tan sonra deterministik biçimde tekilleştirir.
@MainActor
enum SyncDataReconciler {
    private struct WorkoutLogKey: Hashable {
        let day: Date
        let name: String
    }

    private struct OverrideKey: Hashable {
        let weekday: Int
        let operation: String
        let exercise: String
    }

    private struct RecipeKey: Hashable {
        let title: String
        let url: String
    }

    static func reconcile(in context: ModelContext) {
        let calendar = Calendar.current
        var changed = false

        changed = DemoSeed.dedupUserProfiles(context, save: false) || changed

        // Ölçüm ve tarif de buraya AİT: şema küçüldüğünde (model silindiğinde)
        // CoreData persistent history'yi kesiyor, CloudKit da tüm kayıtları yeniden
        // import ediyor → her satır ikizleniyordu. Diğer tablolar zaten
        // tekilleşiyordu, bu ikisi listede yoktu ve çift kalıyordu.
        let measurements = (try? context.fetch(FetchDescriptor<Measurement>())) ?? []
        changed = removeDuplicates(
            measurements,
            groupedBy: { calendar.startOfDay(for: $0.date) },
            preferring: { $0.updatedAt > $1.updatedAt },
            from: context
        ) || changed

        // Başlık TEK BAŞINA anahtar değil: aynı adlı iki farklı tarif (farklı
        // kaynak URL'i) meşru. İkizler her iki alanda da birebir aynı olur.
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        changed = removeDuplicates(
            recipes,
            groupedBy: { RecipeKey(title: normalized($0.title), url: normalized($0.urlString)) },
            preferring: { $0.updatedAt > $1.updatedAt },
            from: context
        ) || changed

        let steps = (try? context.fetch(FetchDescriptor<StepEntry>())) ?? []
        changed = removeDuplicates(
            steps,
            groupedBy: { calendar.startOfDay(for: $0.date) },
            preferring: StepEntry.isPreferred,
            from: context
        ) || changed

        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        changed = removeDuplicates(
            sessions,
            groupedBy: \WorkoutSession.weekday,
            preferring: { $0.updatedAt > $1.updatedAt },
            from: context
        ) || changed

        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        changed = removeDuplicates(
            logs,
            groupedBy: {
                WorkoutLogKey(
                    day: calendar.startOfDay(for: $0.date),
                    name: normalized($0.name)
                )
            },
            preferring: { $0.updatedAt > $1.updatedAt },
            from: context
        ) || changed

        let goals = (try? context.fetch(FetchDescriptor<MonthlyGoal>())) ?? []
        changed = removeDuplicates(
            goals,
            groupedBy: { calendar.startOfDay(for: $0.anchorDate) },
            preferring: { $0.updatedAt > $1.updatedAt },
            from: context
        ) || changed

        let overrides = (try? context.fetch(FetchDescriptor<WorkoutPlanOverride>())) ?? []
        changed = removeDuplicates(
            overrides,
            groupedBy: {
                OverrideKey(
                    weekday: $0.weekday,
                    operation: $0.operationRaw,
                    exercise: normalized($0.exerciseName)
                )
            },
            preferring: { $0.createdAt > $1.createdAt },
            from: context
        ) || changed

        let feedItems = (try? context.fetch(FetchDescriptor<FeedItem>())) ?? []
        changed = FeedStore.deduplicate(feedItems, in: context, save: false) || changed

        #if os(macOS)
        let reports = (try? context.fetch(FetchDescriptor<CoachReport>())) ?? []
        changed = removeDuplicates(
            reports,
            groupedBy: { calendar.startOfDay(for: $0.day) },
            preferring: { $0.updatedAt > $1.updatedAt },
            from: context
        ) || changed

        let coachRecipes = (try? context.fetch(FetchDescriptor<CoachRecipe>())) ?? []
        changed = removeDuplicates(
            coachRecipes,
            groupedBy: { calendar.startOfDay(for: $0.day) },
            preferring: { $0.updatedAt > $1.updatedAt },
            from: context
        ) || changed

        let focusItems = (try? context.fetch(FetchDescriptor<CoachFocusItem>())) ?? []
        changed = removeDuplicates(
            focusItems,
            groupedBy: { normalized($0.area) },
            preferring: { $0.updatedAt > $1.updatedAt },
            from: context
        ) || changed
        #endif

        if changed {
            context.saveOrReport("iCloud kayıtlarını tekilleştirme")
        }

        // Varsayılan preset'ler kendi kararlı `presetID` anahtarlarıyla ayrıca
        // tekilleşir ve yalnız gerçekten değişiklik varsa kaydedilir.
        FoodPresetSeed.upsertDefaults(context)
    }

    @discardableResult
    private static func removeDuplicates<Model: PersistentModel, Key: Hashable>(
        _ models: [Model],
        groupedBy key: (Model) -> Key,
        preferring isPreferred: (Model, Model) -> Bool,
        from context: ModelContext
    ) -> Bool {
        var groups: [Key: [Model]] = [:]
        for model in models {
            groups[key(model), default: []].append(model)
        }

        var changed = false
        for group in groups.values where group.count > 1 {
            // Tie-break anahtarı sıralamadan ÖNCE üretilir: karşılaştırıcı içinde
            // `String(describing:)` her kıyaslamada iki tanım metni alloc ediyordu.
            let keyed = group.map { (model: $0, key: String(describing: $0.persistentModelID)) }
            let ordered = keyed.sorted { lhs, rhs in
                if isPreferred(lhs.model, rhs.model) { return true }
                if isPreferred(rhs.model, lhs.model) { return false }
                return lhs.key < rhs.key
            }.map(\.model)
            for duplicate in ordered.dropFirst() {
                context.delete(duplicate)
                changed = true
            }
        }
        return changed
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "tr_TR"))
    }
}
