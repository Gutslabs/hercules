import Foundation
import Observation
import os

/// Diyet dönemi ("epoch"). Kullanıcı diyeti bırakıp yeniden başladığında ilerleme
/// sıfırdan sayılsın, ama eski dönem ve aradaki boşluk da kaybolmasın diye var.
///
/// Yalnız DÖNEMLER saklanır; ara (mola) saklanmaz — bir dönemin son günü ile
/// sonrakinin başlangıcı arasındaki boşluktan türetilir (bkz. `DietTimeline`).
/// Böylece "ara ne kadar sürdü?" sorusunun tek kaynağı tarihlerdir; ayrıca tutulup
/// bayatlayan bir sayı yoktur ve bir tarihi düzeltmek arayı da kendiliğinden düzeltir.
struct DietEpoch: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    /// İlk diyet günü (gün başı).
    var start: Date
    /// Son diyet günü, DAHİL (gün başı). nil → dönem sürüyor.
    var lastDay: Date?
    /// Dönem açılırken sabitlenen başlangıç kilosu. nil → ölçümlerden türetilir
    /// (dönemin ilk tartısı; o da yoksa başlangıçtan önceki son tartı).
    var startWeight: Double?
    var note: String?

    var isActive: Bool { lastDay == nil }
}

// MARK: - Zaman çizgisi (saf hesap)

/// Dönemlerden + kilo ölçümlerinden türeyen zaman çizgisi: dönem · ara · dönem …
///
/// Gün sayımı DAHİLDİR: 18 Mayıs–20 Mayıs = 3 gün, süren dönemin bugünü "N. gün".
/// Komşu parçalar boşluksuz döşenir; dönem + ara günlerinin toplamı, ilk başlangıçtan
/// bugüne geçen takvim günlerine eşittir.
enum DietTimeline {
    struct Segment: Identifiable, Equatable {
        enum Kind: Equatable {
            /// `number` 1'den başlar (Dönem 1, Dönem 2 …).
            case epoch(number: Int, id: UUID)
            /// İki dönem arası (ya da son dönem bittiyse bugüne kadar süren) ara.
            case rest
        }

        let kind: Kind
        let firstDay: Date
        /// DAHİL son gün; süren parça için bugün.
        let lastDay: Date
        let isOngoing: Bool
        /// DAHİL gün sayısı.
        let days: Int
        let startWeight: Double?
        let endWeight: Double?

        var id: String {
            switch kind {
            case .epoch(_, let id): return id.uuidString
            case .rest: return "rest-\(Int(firstDay.timeIntervalSinceReferenceDate))"
            }
        }

        var isEpoch: Bool {
            if case .epoch = kind { return true }
            return false
        }

        /// Parça boyunca kilo değişimi (negatif = verilen kilo).
        var delta: Double? {
            guard let startWeight, let endWeight else { return nil }
            return endWeight - startWeight
        }
    }

    /// Tarihleri gün başına çeker, başlangıca göre sıralar ve çakışmaları çözer:
    /// yalnız SON dönem sürebilir; bir dönemin son günü sonraki dönemin başlangıcından
    /// önce olmalı. Bozuk/elle düzenlenmiş dosya da buradan geçince tutarlı olur.
    static func normalized(_ epochs: [DietEpoch], calendar: Calendar = .current) -> [DietEpoch] {
        var sorted = epochs
            .map { epoch -> DietEpoch in
                var copy = epoch
                copy.start = calendar.startOfDay(for: epoch.start)
                copy.lastDay = epoch.lastDay.map { calendar.startOfDay(for: $0) }
                if let weight = copy.startWeight, !(weight.isFinite && weight > 0) {
                    copy.startWeight = nil
                }
                let note = copy.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                copy.note = note.isEmpty ? nil : note
                return copy
            }
            .sorted { $0.start < $1.start }

        // Aynı gün başlayan iki dönem ayırt edilemez; sonradan geleni at.
        var seenStarts = Set<Date>()
        sorted = sorted.filter { seenStarts.insert($0.start).inserted }

        for index in sorted.indices {
            if let next = sorted.indices.contains(index + 1) ? sorted[index + 1] : nil {
                let latestAllowed = calendar.date(byAdding: .day, value: -1, to: next.start) ?? next.start
                let last = sorted[index].lastDay ?? latestAllowed
                sorted[index].lastDay = max(sorted[index].start, min(last, latestAllowed))
            } else if let last = sorted[index].lastDay, last < sorted[index].start {
                sorted[index].lastDay = sorted[index].start
            }
        }
        return sorted
    }

    /// Dönem · ara · dönem … sıralı parçalar. `weights` tarihe göre artan sıralı olmalı
    /// (`TrendAnalysis.points` öyle döner).
    static func segments(
        epochs: [DietEpoch],
        weights: [TrendPoint],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [Segment] {
        let epochs = normalized(epochs, calendar: calendar)
        let today = calendar.startOfDay(for: today)
        var result: [Segment] = []

        for (index, epoch) in epochs.enumerated() {
            let ongoing = epoch.lastDay == nil
            let last = max(epoch.start, epoch.lastDay ?? today)
            let epochSegment = Segment(
                kind: .epoch(number: index + 1, id: epoch.id),
                firstDay: epoch.start,
                lastDay: last,
                isOngoing: ongoing,
                days: inclusiveDays(from: epoch.start, to: last, calendar: calendar),
                startWeight: startWeight(of: epoch, weights: weights, calendar: calendar),
                endWeight: endWeight(of: epoch, weights: weights, calendar: calendar)
            )
            result.append(epochSegment)

            guard let finishedOn = epoch.lastDay else { continue }
            let restFirst = calendar.date(byAdding: .day, value: 1, to: finishedOn) ?? finishedOn
            let next = epochs.indices.contains(index + 1) ? epochs[index + 1] : nil
            // Sonraki dönem varsa ara onun başlangıcından bir gün önce biter; yoksa sürüyor.
            let restLast = next.map { calendar.date(byAdding: .day, value: -1, to: $0.start) ?? $0.start } ?? today
            guard restLast >= restFirst else { continue }

            // Biten ara sonraki dönemin başlangıç kilosuna varır; süren ara en son tartıya.
            let restEndWeight: Double?
            if let next {
                restEndWeight = startWeight(of: next, weights: weights, calendar: calendar)
            } else {
                restEndWeight = weights.last(where: { $0.date >= restFirst })?.value
            }
            result.append(Segment(
                kind: .rest,
                firstDay: restFirst,
                lastDay: restLast,
                isOngoing: next == nil,
                days: inclusiveDays(from: restFirst, to: restLast, calendar: calendar),
                // Ara, önceki dönemin bıraktığı kilodan başlar.
                startWeight: epochSegment.endWeight,
                endWeight: restEndWeight
            ))
        }
        return result
    }

    /// İlerleme'nin ölçtüğü dönem: süren dönem; aradaysa en son biten dönem.
    static func current(in epochs: [DietEpoch], calendar: Calendar = .current) -> (epoch: DietEpoch, number: Int)? {
        let epochs = normalized(epochs, calendar: calendar)
        guard let last = epochs.last else { return nil }
        return (last, epochs.count)
    }

    /// Dönemin başlangıç kilosu: sabitlenmişse o; değilse dönemin ilk tartısı; o da
    /// yoksa (dönem bugün açıldı, henüz tartılmadı) başlangıçtan önceki son tartı.
    static func startWeight(of epoch: DietEpoch, weights: [TrendPoint], calendar: Calendar = .current) -> Double? {
        if let pinned = epoch.startWeight { return pinned }
        if let first = self.weights(in: epoch, from: weights, calendar: calendar).first {
            return first.value
        }
        let start = calendar.startOfDay(for: epoch.start)
        return weights.last(where: { $0.date < start })?.value
    }

    /// Dönemin vardığı kilo: dönem içindeki son tartı. Dönemde hiç tartı yoksa nil —
    /// başka bir dönemin/aranın tartısı bu dönemin sonucu gibi gösterilmez.
    static func endWeight(of epoch: DietEpoch, weights: [TrendPoint], calendar: Calendar = .current) -> Double? {
        self.weights(in: epoch, from: weights, calendar: calendar).last?.value
    }

    /// Dönemin kapsadığı tartılar (ritim/regresyon yalnız bu dönemin verisinden hesaplanır).
    /// `lastDay` dahil olduğu için üst sınır onun ertesi gününün başıdır.
    static func weights(in epoch: DietEpoch, from weights: [TrendPoint], calendar: Calendar = .current) -> [TrendPoint] {
        let start = calendar.startOfDay(for: epoch.start)
        let endExclusive = epoch.lastDay.map {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) ?? $0
        }
        return weights.filter { point in
            guard point.date >= start else { return false }
            if let endExclusive { return point.date < endExclusive }
            return true
        }
    }

    static func inclusiveDays(from first: Date, to last: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: first),
            to: calendar.startOfDay(for: last)
        ).day ?? 0
        return max(0, days) + 1
    }
}

// MARK: - Saklama

/// Dönemlerin diskteki hâli: Application Support/Hercules altında küçük bir JSON.
///
/// NEDEN SwiftData değil: canlı store CloudKit **Production** ile senkron; yeni bir
/// model/alan, şema Production'a deploy edilmeden yazılırsa export'lar reddedilir ve
/// senkron bozulur. Dönemler yalnız Mac'teki İlerleme + koç bağlamında kullanılıyor;
/// birkaç satırlık bu veri için o riski almaya değmez. Dosya, store'un yanında durur
/// (elle yedeklenen klasörle birlikte gelir); Debug koşusu canlı veriyi kirletmesin
/// diye store gibi `-dev` ekli kendi dosyasını kullanır.
enum DietEpochArchive {
    /// v1'de `IlerlemeView`'a gömülü olan başlangıç: kullanıcının cut'a başladığı gün.
    /// Dosya yokken Dönem 1 buradan doğar — dönem özelliğinden önceki davranışla aynı.
    static var legacyStart: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 18)) ?? .now
    }

    static var seed: [DietEpoch] { [DietEpoch(start: legacyStart)] }

    /// Testlerde nil: gerçek/dev dosyası okunmaz, yazılmaz (`ChatStore.shared` ile aynı kural).
    static var defaultURL: URL? {
        guard NSClassFromString("XCTestCase") == nil else { return nil }
        #if DEBUG
        let name = "diet-epochs-dev.json"
        #else
        let name = "diet-epochs.json"
        #endif
        return try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Hercules", isDirectory: true)
            .appendingPathComponent(name)
    }

    private struct Payload: Codable {
        var version: Int
        var epochs: [DietEpoch]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Kayıtlı dönemler; dosya yoksa/boşsa/okunamıyorsa `seed`. Asla boş dönmez.
    static func load(from url: URL? = defaultURL) -> [DietEpoch] {
        guard let url,
              let data = try? Data(contentsOf: url),
              let payload = try? decoder.decode(Payload.self, from: data)
        else { return seed }
        let epochs = DietTimeline.normalized(payload.epochs)
        return epochs.isEmpty ? seed : epochs
    }

    static func save(_ epochs: [DietEpoch], to url: URL) throws {
        let data = try encoder.encode(Payload(version: 1, epochs: epochs))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
        // Yalnız kullanıcı okusun. `HerculesFileHardening` KULLANILMAZ: o, dosyayı yedekten
        // de çıkarır; dönemler yeniden üretilemeyen kullanıcı verisi, yedeğe girmeli.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Dönemlerin canlı hâli — İlerleme bunu gözler, düzenlemeler buradan geçer.
/// `epochs` her zaman normalize ve en az bir dönemlidir.
@MainActor
@Observable
final class DietEpochStore {
    static let shared = DietEpochStore(fileURL: DietEpochArchive.defaultURL)

    private(set) var epochs: [DietEpoch]
    /// Son yazım hatası — sessizce yutulmasın, sheet gösterebilsin.
    private(set) var lastError: String?

    @ObservationIgnored private let fileURL: URL?

    /// `fileURL == nil` → yalnız bellek (testler/önizleme).
    init(fileURL: URL?, epochs: [DietEpoch]? = nil) {
        self.fileURL = fileURL
        if let epochs {
            let normalized = DietTimeline.normalized(epochs)
            self.epochs = normalized.isEmpty ? DietEpochArchive.seed : normalized
        } else {
            self.epochs = fileURL.map { DietEpochArchive.load(from: $0) } ?? DietEpochArchive.seed
        }
    }

    /// Süren dönem; aradaysa nil.
    var active: DietEpoch? { epochs.last.flatMap { $0.isActive ? $0 : nil } }

    /// Yeni dönem açar. Süren bir dönem varsa önce onu `previousLastDay`'de kapatır
    /// (verilmezse yeni başlangıçtan bir gün önce) — aradaki boşluk "ara" olur.
    func startNewEpoch(
        on start: Date,
        startWeight: Double?,
        note: String? = nil,
        previousLastDay: Date? = nil,
        calendar: Calendar = .current
    ) {
        var next = epochs
        let start = calendar.startOfDay(for: start)
        if let index = next.indices.last, next[index].isActive {
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: start) ?? start
            next[index].lastDay = min(previousLastDay.map { calendar.startOfDay(for: $0) } ?? dayBefore, dayBefore)
        }
        next.append(DietEpoch(start: start, startWeight: startWeight, note: note))
        commit(next)
    }

    /// Süren dönemi kapatır; yeni dönem açılana kadar "arada" olunur.
    func endActiveEpoch(lastDay: Date, calendar: Calendar = .current) {
        guard let index = epochs.indices.last, epochs[index].isActive else { return }
        var next = epochs
        next[index].lastDay = max(next[index].start, calendar.startOfDay(for: lastDay))
        commit(next)
    }

    func update(_ epoch: DietEpoch) {
        guard let index = epochs.firstIndex(where: { $0.id == epoch.id }) else { return }
        var next = epochs
        next[index] = epoch
        commit(next)
    }

    /// Son kalan dönem silinmez: İlerleme'nin her zaman ölçeceği bir başlangıç olmalı.
    func delete(id: UUID) {
        guard epochs.count > 1 else { return }
        commit(epochs.filter { $0.id != id })
    }

    private func commit(_ next: [DietEpoch]) {
        let normalized = DietTimeline.normalized(next)
        guard !normalized.isEmpty, normalized != epochs else { return }
        epochs = normalized
        guard let fileURL else { return }
        do {
            try DietEpochArchive.save(normalized, to: fileURL)
            lastError = nil
        } catch {
            // Bellekteki hâl geçerli kalır; kullanıcı, kaydın diske inmediğini görsün.
            let desc = error.localizedDescription
            lastError = desc
            AppLog.persistence.error("Diyet dönemleri yazılamadı: \(desc, privacy: .public)")
            SaveErrorReporter.shared.message = "Kaydedilemedi (diyet dönemleri): \(desc)"
        }
    }
}
