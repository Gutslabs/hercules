import Foundation
import HealthKit
import Combine

/// HealthKit'ten bugünün adım sayısı + aktif yakılan kalori okur.
/// macOS 13+ gerekli. iPhone'dan iCloud Health sync açık olmalı.
@MainActor
final class HealthService: ObservableObject {
    static let shared = HealthService()
    private let store = HKHealthStore()

    enum Status {
        case unavailable                // HealthKit yok (eski macOS)
        case notAuthorized              // Kullanıcı izin vermedi
        case authorized
        case error(String)
    }

    @Published var status: Status = .unavailable
    @Published var stepsToday: Int = 0
    @Published var activeCaloriesToday: Double = 0
    @Published var lastUpdate: Date? = nil

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
        case .unavailable: return "HealthKit kullanılamıyor"
        case .notAuthorized: return "İzin gerekli"
        case .error(let m): return m
        case .authorized:
            return "\(Fmt.int(Double(stepsToday))) adım · \(Fmt.int(activeCaloriesToday)) kcal"
        }
    }
}
