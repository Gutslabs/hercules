import Foundation
import HealthKit
import Observation
import SwiftData
import UIKit

/// iPhone'daki Apple Health verisini günlük `StepEntry` kayıtlarına dönüştürür.
/// Bu kayıtlar normal SwiftData/CloudKit hattıyla Mac'e de ulaşır; arada dosya
/// tabanlı ayrı bir taşıma katmanı yoktur.
@MainActor
@Observable
final class HealthService {
    static let shared = HealthService()

    enum Status: Equatable {
        case unavailable
        case notDetermined
        case syncing
        case empty
        case ready
        case error(String)
    }

    var status: Status
    var stepsToday = 0
    var lastSyncDate: Date?
    var lastImportedDayCount = 0

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var observerQueries: [HKObserverQuery] = []
    @ObservationIgnored private var protectedDataObserver: NSObjectProtocol?
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var pendingSync = false
    /// Launch başına tek derin-geçmiş sorgusu: nil = henüz sorulmadı,
    /// .some(nil) = soruldu ve HealthKit'te hiç adım örneği yok.
    @ObservationIgnored private var cachedEarliestStepLookup: Date?? = nil
    @ObservationIgnored private var backgroundDeliveryReady = false

    private let initialImportKey = "hercules.healthkit.initial_import_v1"

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        ].compactMap { $0 }.reduce(into: Set<HKObjectType>()) { $0.insert($1) }
    }

    private var observedTypes: [HKSampleType] {
        [
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        ].compactMap { $0 }
    }

    private init() {
        status = HKHealthStore.isHealthDataAvailable() ? .notDetermined : .unavailable
    }

    var statusText: String {
        switch status {
        case .unavailable:
            return "Bu cihazda Apple Health kullanılamıyor"
        case .notDetermined:
            return "Apple Health izni bekleniyor"
        case .syncing:
            return "Apple Health okunuyor…"
        case .empty:
            return "HealthKit verisi bulunamadı"
        case .ready:
            if let lastSyncDate {
                return "HealthKit · \(Fmt.relative(lastSyncDate))"
            }
            return "HealthKit hazır"
        case .error(let message):
            return message
        }
    }

    /// İlk açılışta gerekirse Apple Health izin ekranını gösterir, geçmişi içe alır
    /// ve sonraki HealthKit değişiklikleri için observer kurar.
    func start(into context: ModelContext) async {
        installLaunchObservers(into: context)
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }

        do {
            if try await authorizationRequestStatus() == .shouldRequest {
                status = .notDetermined
                try await requestAuthorization()
            }
            try await enableBackgroundDeliveryIfNeeded()
            await synchronize(into: context)
        } catch {
            status = .error(error.localizedDescription)
            AppLog.sync.error("HealthKit startup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `application(_:didFinishLaunchingWithOptions:)` sırasında çağrılır. Observer
    /// query'leri burada kurulursa HealthKit, uygulamayı arka planda uyandırdığında
    /// callback'i kaçırmayız. Yetki isteme işi yine normal UI başlangıcında yapılır.
    func installLaunchObservers(into context: ModelContext? = nil) {
        if let context { self.context = context }
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        registerObserversIfNeeded()
        registerProtectedDataObserverIfNeeded()
    }

    /// Profil ekranındaki yeniden dene/yenile eylemi için.
    func requestAccessAndSync(into context: ModelContext) async {
        installLaunchObservers(into: context)
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        do {
            try await requestAuthorization()
            try await enableBackgroundDeliveryIfNeeded()
            await synchronize(into: context)
        } catch {
            status = .error(error.localizedDescription)
            AppLog.sync.error("HealthKit authorization/sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Son günleri HealthKit'ten yeniden okuyup SwiftData'ya yazar. İlk başarılı
    /// çalışmada HealthKit'teki en eski adım örneğine kadar geriye gider.
    func synchronize(into context: ModelContext) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if isSyncing {
            // Adım ve mesafe observer'ları peş peşe çalışabilir. Devam eden sorgu
            // varken gelen ikinci isteği kaybetme; ilk tur biter bitmez yeniden oku.
            pendingSync = true
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        // Observer'lar sync sürerken tetiklenmeye devam ederse zincir sonsuz uzayabilir
        // (her tur bir sonraki tetiklemeye yetecek kadar uzun). Sınırla; kaçan tur
        // bir sonraki observer tetiklemesinde zaten telafi edilir.
        var rounds = 0
        repeat {
            rounds += 1
            pendingSync = false
            status = .syncing

            do {
                let calendar = Calendar.current
                let end = Date()
                let today = calendar.startOfDay(for: end)
                let didInitialImport = UserDefaults.standard.bool(forKey: initialImportKey)
                let fallbackStart = calendar.date(byAdding: .day, value: didInitialImport ? -35 : -365, to: today) ?? today
                // Derin-geçmiş sorgusu launch başına EN FAZLA bir kez: adım izni hiç
                // verilmemiş (ya da cihaz kilitli) kurulumlarda initialImportKey hiç
                // yazılmıyor ve her observer tetiklemesi tüm geçmişi yeniden tarıyordu.
                let earliest: Date?
                if didInitialImport {
                    earliest = nil
                } else if let cached = cachedEarliestStepLookup {
                    earliest = cached
                } else {
                    earliest = try await earliestStepDate()
                    cachedEarliestStepLookup = .some(earliest)
                    if earliest == nil {
                        // HealthKit'te hiç adım örneği yok — içe aktarılacak geçmiş de yok.
                        // Bunu "ilk import tamam" say ki mesafe-izinli/adımsız kurulumlar
                        // sonsuza dek 365 günlük pencereyi taramasın.
                        UserDefaults.standard.set(true, forKey: initialImportKey)
                    }
                }
                let start = calendar.startOfDay(for: earliest ?? fallbackStart)

                let stepTotals = try await dailyTotals(
                    identifier: .stepCount,
                    unit: .count(),
                    from: start,
                    to: end
                )
                let distanceTotals = try await dailyTotals(
                    identifier: .distanceWalkingRunning,
                    unit: .meter(),
                    from: start,
                    to: end
                )
                let imported = try upsert(
                    stepTotals: stepTotals,
                    distanceTotals: distanceTotals,
                    from: start,
                    through: end,
                    purgeLegacyEntries: !stepTotals.isEmpty,
                    into: context
                )

                stepsToday = Int((stepTotals[today] ?? 0).rounded())
                lastImportedDayCount = imported
                lastSyncDate = .now
                // Bu servis bir adım sayacı. Mesafe izni/verisi tek başına varsa bunu
                // başarılı adım senkronu gibi göstermeyelim ve sıfır adımlı gün üretmeyelim.
                let hasHealthData = !stepTotals.isEmpty
                status = hasHealthData ? .ready : .empty
                if !stepTotals.isEmpty {
                    UserDefaults.standard.set(true, forKey: initialImportKey)
                }
            } catch {
                status = .error(error.localizedDescription)
                AppLog.sync.error("HealthKit sync failed: \(error.localizedDescription, privacy: .public)")
            }
        } while pendingSync && rounds < 3
    }

    private func requestAuthorization() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthServiceError.authorizationFailed)
                }
            }
        }
    }

    private func authorizationRequestStatus() async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func earliestStepDate() async throws -> Date? {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first?.startDate)
                }
            }
            store.execute(query)
        }
    }

    private func dailyTotals(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { [weak store] query, collection, error in
                defer { store?.stop(query) }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var totals: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    let value = quantity.doubleValue(for: unit)
                    if value > 0 {
                        totals[calendar.startOfDay(for: statistics.startDate)] = value
                    }
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    private func upsert(
        stepTotals: [Date: Double],
        distanceTotals: [Date: Double],
        from start: Date,
        through end: Date,
        purgeLegacyEntries: Bool,
        into context: ModelContext
    ) throws -> Int {
        let calendar = Calendar.current
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let descriptor = FetchDescriptor<StepEntry>(
            predicate: #Predicate<StepEntry> { entry in
                entry.date >= start && entry.date < rangeEnd
            },
            sortBy: [SortDescriptor(\StepEntry.date)]
        )
        let existing = try context.fetch(descriptor)
        var existingByDay: [Date: [StepEntry]] = [:]
        for entry in existing {
            existingByDay[calendar.startOfDay(for: entry.date), default: []].append(entry)
        }

        // `StepEntry` yalnız gerçekten bir adım toplamı gelen günler için oluşur.
        // Mesafe, aynı günün destekleyici alanıdır; tek başına kayıt yaratmaz.
        let incomingDays = Set(stepTotals.keys)
        let now = Date()
        var changed = false

        for day in incomingDays {
            let sameDay = existingByDay[day] ?? []
            let entry = StepEntry.preferredEntries(from: sameDay, calendar: calendar).first ?? StepEntry(date: day)
            if sameDay.isEmpty {
                context.insert(entry)
                changed = true
            }

            let newSteps = Int((stepTotals[day] ?? 0).rounded())
            let newDistance = distanceTotals[day]
            let valuesChanged = entry.date != day
                || entry.steps != newSteps
                || entry.distanceMeters != newDistance
                || entry.activeEnergyKcal != nil
                || entry.source != StepEntry.healthKitSource

            // Observer iki ayrı HealthKit tipi için tetiklenebilir. Değer gerçekten
            // değişmediyse `updatedAt`/`syncedAt` yazmayarak aynı 35 günü tekrar tekrar
            // CloudKit'e export etmiyoruz; yalnız değişen gün karşı cihaza gider.
            if valuesChanged || sameDay.isEmpty {
                entry.date = day
                entry.steps = newSteps
                entry.distanceMeters = newDistance
                // Aktif enerji yürüyüş dışındaki antrenmanları da içerir. Antrenman kalorileri
                // ayrı hesaplandığı için burada saklamak çift sayıma yol açardı.
                entry.activeEnergyKcal = nil
                entry.source = StepEntry.healthKitSource
                entry.syncedAt = now
                entry.updatedAt = now
                changed = true
            }

            for duplicate in sameDay where duplicate.persistentModelID != entry.persistentModelID {
                context.delete(duplicate)
                changed = true
            }
        }

        // HealthKit kilitli cihazda veya veri-koruma penceresinde bazı günleri geçici
        // olarak boş döndürebilir. "Boş cevap = sil" yapmıyoruz; aksi halde doğru bir
        // günlük özet silinip CloudKit'teki eski bir kayıt yeniden yüzeye çıkabilir.

        // Her başarılı HealthKit okumasından sonra eski dosya tabanlı dönemden kalan
        // kayıtları temizle. Böylece başka cihazdan sonradan dönen bir `shortcuts`
        // kaydı da bir sonraki HealthKit turunda tekrar yaşayamaz.
        if purgeLegacyEntries {
            // Yalnız legacy satırları çek: filtresiz fetch her sync'te yılların
            // StepEntry'sini ana thread'e materialize ediyordu (ilk temizlikten
            // sonra sonuç garanti boş — predicate ile bedava).
            let healthKitSource = StepEntry.healthKitSource
            let legacyDescriptor = FetchDescriptor<StepEntry>(
                predicate: #Predicate { $0.source != healthKitSource }
            )
            for entry in try context.fetch(legacyDescriptor) {
                context.delete(entry)
                changed = true
            }
        }

        if changed {
            try context.saveStamped()
        }
        return incomingDays.count
    }

    private func registerObserversIfNeeded() {
        guard observerQueries.isEmpty else { return }
        for type in observedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                guard let self else {
                    completion()
                    return
                }
                if let error {
                    AppLog.sync.error("HealthKit observer failed: \(error.localizedDescription, privacy: .public)")
                    completion()
                    return
                }
                Task { @MainActor in
                    if let context = self.context {
                        await self.synchronize(into: context)
                    }
                    completion()
                }
            }
            observerQueries.append(query)
            store.execute(query)
        }
    }

    private func registerProtectedDataObserverIfNeeded() {
        guard protectedDataObserver == nil else { return }
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let context = self.context else { return }
                await self.synchronize(into: context)
            }
        }
    }

    private func enableBackgroundDeliveryIfNeeded() async throws {
        guard !backgroundDeliveryReady else { return }
        for type in observedTypes {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.enableBackgroundDelivery(for: type, frequency: .immediate) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: HealthServiceError.backgroundDeliveryFailed)
                    }
                }
            }
        }
        backgroundDeliveryReady = true
    }
}

private enum HealthServiceError: LocalizedError {
    case authorizationFailed
    case backgroundDeliveryFailed

    var errorDescription: String? {
        switch self {
        case .authorizationFailed:
            return "Apple Health izni alınamadı"
        case .backgroundDeliveryFailed:
            return "Apple Health arka plan güncellemesi etkinleştirilemedi"
        }
    }
}
