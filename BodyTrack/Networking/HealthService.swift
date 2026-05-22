import Foundation
import HealthKit
import Observation
import SwiftData

/// Native macOS app'lerde HealthKit framework linklenebilir ama Apple Health verisi
/// okunamaz/yazılamaz. Bu servis ileride iOS companion target için kullanılabilir.
@MainActor
@Observable
final class HealthService {
    static let shared = HealthService()
    @ObservationIgnored private let store = HKHealthStore()

    enum Status {
        case unavailable                // Native macOS'ta HealthKit data store yok
        case notAuthorized              // Kullanıcı izin vermedi
        case authorized
        case error(String)
    }

    var status: Status = .unavailable
    var stepsToday: Int = 0
    var activeCaloriesToday: Double = 0
    var lastUpdate: Date? = nil

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let s = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(s) }
        if let e = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(e) }
        return types
    }

    init() {
        if !isAvailable {
            status = .unavailable
        } else {
            status = currentAuthStatus()
        }
    }

    private func currentAuthStatus() -> Status {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return .unavailable
        }
        let st = store.authorizationStatus(for: stepType)
        switch st {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .notAuthorized
        case .notDetermined: return .notAuthorized
        @unknown default: return .notAuthorized
        }
    }

    /// İzin iste — diyalog ilk seferde açılır.
    func requestAuthorization() async {
        guard isAvailable else { status = .unavailable; return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            status = currentAuthStatus()
            if case .authorized = status {
                await refresh()
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Bugünün adım sayısını ve aktif kalorisini çek.
    func refresh() async {
        guard isAvailable else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let stepsCount = sumQuantity(.stepCount, unit: .count(), predicate: predicate)
        async let energyCount = sumQuantity(.activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)

        let (steps, energy) = await (stepsCount, energyCount)
        stepsToday = Int(steps ?? 0)
        activeCaloriesToday = energy ?? 0
        lastUpdate = .now
    }

    private func sumQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                let v = stats?.sumQuantity()?.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            store.execute(query)
        }
    }

    /// UI'ı bilgilendirici metin döndürür (status + step/kcal).
    var summary: String {
        switch status {
        case .unavailable: return "Mac app Apple Health verisini direkt okuyamaz"
        case .notAuthorized: return "İzin gerekli"
        case .error(let m): return m
        case .authorized:
            return "\(Fmt.int(Double(stepsToday))) adım · \(Fmt.int(activeCaloriesToday)) kcal"
        }
    }
}

// MARK: - iPhone Shortcuts health sync

@MainActor
@Observable
final class ShortcutHealthSyncService {
    static let shared = ShortcutHealthSyncService()

    var lastImportDate: Date?
    var lastImportedDays: Int = 0
    var lastMessage: String = "iCloud Drive dosyası bekleniyor"

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var autoImportContext: ModelContext?

    private let filename = "health-sync.json"
    private let legacyFilename = "health-sync.txt"

    var syncURL: URL? {
        if let existing = syncCandidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existing
        }
        return primarySyncURL
    }

    private var primarySyncURL: URL? {
        let fm = FileManager.default
        guard let cloudDocs = cloudDocumentsURL else { return nil }

        let dir = cloudDocs
            .appendingPathComponent("Shortcuts", isDirectory: true)
            .appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(filename)
    }

    private var syncCandidateURLs: [URL] {
        guard let cloudDocs = cloudDocumentsURL else { return [] }
        return [
            shortcutsContainerDocumentsURL?.appendingPathComponent("Hercules/\(legacyFilename)"),
            shortcutsContainerDocumentsURL?.appendingPathComponent("Hercules/\(filename)"),
            cloudDocs.appendingPathComponent("Shortcuts/Hercules/\(filename)"),
            cloudDocs.appendingPathComponent("Shortcuts/Hercules/\(legacyFilename)"),
            cloudDocs.appendingPathComponent("Hercules/\(filename)")
        ].compactMap { $0 }
    }

    private var cloudDocumentsURL: URL? {
        let fm = FileManager.default
        let cloudDocs = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return fm.fileExists(atPath: cloudDocs.path) ? cloudDocs : nil
    }

    private var shortcutsContainerDocumentsURL: URL? {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents", isDirectory: true)
        return fm.fileExists(atPath: dir.path) ? dir : nil
    }

    var syncFileExists: Bool {
        guard let syncURL else { return false }
        return FileManager.default.fileExists(atPath: syncURL.path)
    }

    var displayPath: String {
        "Shortcuts iCloud/Hercules/\(legacyFilename)"
    }

    func startAutoImport(into ctx: ModelContext) {
        timer?.invalidate()
        autoImportContext = ctx
        importIfAvailable(into: ctx)
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runAutoImport()
            }
        }
    }

    private func runAutoImport() {
        guard let autoImportContext else { return }
        importIfAvailable(into: autoImportContext)
    }

    @discardableResult
    func importIfAvailable(into ctx: ModelContext) -> Int {
        guard let syncURL else {
            lastMessage = "iCloud Drive klasörü bulunamadı"
            return 0
        }
        guard FileManager.default.fileExists(atPath: syncURL.path) else {
            lastMessage = "\(displayPath) bekleniyor"
            return 0
        }

        do {
            guard ensureICloudFileIsDownloaded(syncURL) else {
                lastMessage = "iCloud dosyası indiriliyor..."
                return 0
            }
            let data = try Data(contentsOf: syncURL)
            let payload = try Self.decoder.decode(ShortcutHealthPayload.self, from: data)
            let imported = try upsert(payload.records, into: ctx)
            lastImportDate = .now
            lastImportedDays = imported
            lastMessage = imported == 0 ? "Dosya okundu, yeni gün yok" : "\(imported) gün senkronlandı"
            return imported
        } catch {
            lastMessage = "Sync okunamadı: \(error.localizedDescription)"
            return 0
        }
    }

    private func ensureICloudFileIsDownloaded(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true
        else { return true }

        if values.ubiquitousItemDownloadingStatus == .current {
            return true
        }

        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return false
        } catch {
            lastMessage = "iCloud indirme başlatılamadı: \(error.localizedDescription)"
            return false
        }
    }

    private func upsert(_ records: [ShortcutHealthDay], into ctx: ModelContext) throws -> Int {
        let usable = records.filter { $0.steps > 0 || ($0.distanceMeters ?? 0) > 0 || ($0.activeEnergyKcal ?? 0) > 0 }
        guard !usable.isEmpty else { return 0 }

        let calendar = Calendar.current
        var incomingByDay: [Date: ShortcutHealthDay] = [:]
        for record in usable {
            incomingByDay[calendar.startOfDay(for: record.date)] = record
        }

        let existing = (try? ctx.fetch(FetchDescriptor<StepEntry>())) ?? []
        var changedDays = 0

        for (day, record) in incomingByDay {
            let sameDay = existing
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .sorted { $0.date > $1.date }

            let entry = sameDay.first ?? StepEntry(date: day, source: "shortcuts")
            if sameDay.isEmpty {
                ctx.insert(entry)
            }

            let shouldUpdateSteps = record.steps > 0 || entry.source == "shortcuts"
            if shouldUpdateSteps {
                entry.steps = record.steps
            }
            if let distanceMeters = record.distanceMeters {
                entry.distanceMeters = distanceMeters
            }
            if let activeEnergyKcal = record.activeEnergyKcal {
                entry.activeEnergyKcal = activeEnergyKcal
            }
            entry.date = day
            entry.source = "shortcuts"
            entry.syncedAt = .now

            for duplicate in sameDay.dropFirst() {
                ctx.delete(duplicate)
            }
            changedDays += 1
        }

        try ctx.save()
        return changedDays
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct ShortcutHealthPayload: Decodable {
    let records: [ShortcutHealthDay]

    enum CodingKeys: String, CodingKey {
        case days
        case records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let days = try? container.decode([ShortcutHealthDay].self, forKey: .days) {
            records = days
        } else if let decodedRecords = try? container.decode([ShortcutHealthDay].self, forKey: .records) {
            records = decodedRecords
        } else {
            records = []
        }
    }
}

private struct ShortcutHealthDay: Decodable {
    let date: Date
    let steps: Int
    let distanceMeters: Double?
    let activeEnergyKcal: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case dateString
        case steps
        case distanceMeters
        case walkingRunningDistanceMeters
        case activeEnergyKcal
        case activeCaloriesKcal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = Self.decodeDate(container) ?? Calendar.current.startOfDay(for: .now)
        steps = Self.decodeInt(container, keys: [.steps])
        distanceMeters = Self.decodeDouble(container, keys: [.distanceMeters, .walkingRunningDistanceMeters])
        activeEnergyKcal = Self.decodeDouble(container, keys: [.activeEnergyKcal, .activeCaloriesKcal])
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>) -> Date? {
        if let date = try? container.decode(Date.self, forKey: .date) {
            return Calendar.current.startOfDay(for: date)
        }
        let raw = (try? container.decode(String.self, forKey: .date))
            ?? (try? container.decode(String.self, forKey: .dateString))
        guard let raw else { return nil }

        if let date = yyyyMMdd.date(from: raw) {
            return Calendar.current.startOfDay(for: date)
        }
        if let date = iso.date(from: raw) {
            return Calendar.current.startOfDay(for: date)
        }
        if let date = looseDateFormatter.date(from: raw) {
            return Calendar.current.startOfDay(for: date)
        }
        return nil
    }

    private static func decodeInt(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Int {
        for key in keys {
            if let value = try? container.decode(Int.self, forKey: key) { return value }
            if let value = try? container.decode(Double.self, forKey: key) { return Int(value.rounded()) }
            if let value = try? container.decode(String.self, forKey: key),
               let number = Double(value.replacingOccurrences(of: ",", with: ".")) {
                return Int(number.rounded())
            }
        }
        return 0
    }

    private static func decodeDouble(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Double? {
        for key in keys {
            if let value = try? container.decode(Double.self, forKey: key) { return value }
            if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
            if let value = try? container.decode(String.self, forKey: key),
               let number = Double(value.replacingOccurrences(of: ",", with: ".")) {
                return number
            }
        }
        return nil
    }

    private static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let iso = ISO8601DateFormatter()

    private static let looseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
