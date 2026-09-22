import Foundation
import SwiftData

/// Mikro besin tahminlerinin DİSK önbelleği + toplu tahmin motoru.
///
/// Neden SwiftData değil: üretim CloudKit şeması kilitli ve bu veri tamamen
/// türetilmiş (yemek adı → 100 g başına tahmin). Kaybolursa yeniden üretilir.
/// `~/Library/Application Support/Hercules/micronutrients.json` — ProfileAvatarStore
/// ve RecipeImageStore ile aynı desen.
@MainActor
final class MicroNutrientStore: ObservableObject {
    static let shared = MicroNutrientStore()

    /// Normalize edilmiş isim → tahmin.
    @Published private(set) var profiles: [String: MicroProfile] = [:]
    /// Son toplu tahmin çalışması.
    @Published private(set) var lastRun: Date?
    /// Aylık tur özetleri (en yeni sonda).
    @Published private(set) var snapshots: [MicroSnapshot] = []
    /// Çalışırken arayüz ilerlemeyi gösterir.
    @Published private(set) var isRunning = false
    @Published private(set) var progress: (done: Int, total: Int)?
    @Published private(set) var lastError: String?

    /// Aylık ritim: son çalışmadan bu kadar gün sonra "sıradaki" gelir.
    static let cycleDays = 30

    private struct Payload: Codable {
        var lastRun: Date?
        var profiles: [String: MicroProfile]
        /// Aylık turların özeti — aylar arası TREND buradan okunur.
        var snapshots: [MicroSnapshot]?
    }

    /// Dosya yolu — aktörden bağımsız (koç özeti arka planda da okuyabilsin).
    nonisolated static var fileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("Hercules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("micronutrients.json")
    }

    private static var url: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("Hercules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("micronutrients.json")
    }

    private init() { load() }

    // MARK: - Disk

    private func load() {
        guard let url = Self.url, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else { return }
        profiles = payload.profiles
        lastRun = payload.lastRun
        snapshots = payload.snapshots ?? []
    }

    private func persist() {
        guard let url = Self.url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(
            Payload(lastRun: lastRun, profiles: profiles, snapshots: snapshots)
        ) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Ritim

    /// Sıradaki analize kalan gün (negatifse gecikmiş). İlk kez çalıştırılmadıysa nil.
    var daysUntilNextRun: Int? {
        guard let lastRun else { return nil }
        let cal = Calendar.current
        guard let due = cal.date(byAdding: .day, value: Self.cycleDays, to: cal.startOfDay(for: lastRun)) else { return nil }
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: due).day
    }

    /// "30 gün kaldı" / "bugün" / "3 gün gecikti" / henüz çalışmadıysa nil.
    var cycleText: String? {
        guard let days = daysUntilNextRun else { return nil }
        if days > 1 { return "\(days) gün kaldı" }
        if days == 1 { return "yarın" }
        if days == 0 { return "bugün" }
        return "\(-days) gün gecikti"
    }

    // MARK: - Elle düzeltme

    /// Modelin saçmaladığı bir tahmini elle düzelt — `source` "manual" olur ve
    /// sonraki turlarda yeniden tahmin edilmez.
    func override(key: String, displayName: String, per100g: [String: Double]) {
        profiles[key] = MicroProfile(key: key, displayName: displayName, per100g: per100g,
                                     source: "manual", confidence: 1, updatedAt: .now)
        persist()
    }

    func forget(key: String) {
        profiles.removeValue(forKey: key)
        persist()
    }

    // MARK: - Toplu tahmin

    /// Önbellekte karşılığı olmayan isimleri bulur (gramsızlar hariç — onlar
    /// zaten hesaba giremez).
    func missingNames(from entries: [(name: String, grams: Double?, date: Date)]) -> [(key: String, display: String)] {
        var seen: [String: String] = [:]
        for e in entries {
            guard let g = e.grams, g > 0 else { continue }
            let key = MicroNutrition.normalize(e.name)
            guard !key.isEmpty, profiles[key] == nil, seen[key] == nil else { continue }
            seen[key] = e.name
        }
        return seen.map { (key: $0.key, display: $0.value) }.sorted { $0.key < $1.key }
    }

    /// Eksik isimleri toplu olarak modele sorar ve önbelleğe yazar.
    /// `force` verilirse AI kaynaklı TÜM tahminler yeniden hesaplanır (elle
    /// düzeltilenlere dokunulmaz).
    func refresh(entries: [(name: String, grams: Double?, date: Date)],
                 force: Bool = false,
                 advanceCycle: Bool = true) async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        defer { isRunning = false; progress = nil }

        if force {
            profiles = profiles.filter { $0.value.source == "manual" }
        }

        let todo = missingNames(from: entries)
        guard !todo.isEmpty else {
            if advanceCycle { lastRun = .now }
            persist()
            return
        }

        let batches = stride(from: 0, to: todo.count, by: Self.batchSize).map {
            Array(todo[$0 ..< min($0 + Self.batchSize, todo.count)])
        }
        progress = (0, todo.count)
        var done = 0

        let client = CodexFirstFallbackClient()
        for batch in batches {
            do {
                let estimated = try await Self.estimate(batch: batch, client: client)
                for profile in estimated { profiles[profile.key] = profile }
                persist()
            } catch {
                lastError = error.localizedDescription
                // Kalan gruplar denenmeye devam eder: bir grubun bozuk JSON'u
                // tüm turu çöpe atmasın; eksik kalanlar sonraki turda toplanır.
            }
            done += batch.count
            progress = (done, todo.count)
        }

        lastRun = .now
        persist()
    }

    /// Aylık tur ZAMANI GELDİYSE kendiliğinden çalışır. Uygulama açılışında ve
    /// Analiz sayfası göründüğünde çağrılır; elle "Güncelle" ile aynı işi yapar.
    /// Yeni isim yoksa bile tur tarihi ilerler (rapor yine tazelenmiş sayılır).
    func runIfDue(entries: [(name: String, grams: Double?, date: Date)],
                  isMale: Bool,
                  age: Int) async {
        guard !isRunning else { return }
        let due = daysUntilNextRun.map { $0 <= 0 } ?? true      // hiç çalışmadıysa da çalış
        let hasNew = !missingNames(from: entries).isEmpty
        guard due || hasNew else { return }
        // Tur zamanı gelmediyse yalnız YENİ isimleri tamamla (rapor eksik kalmasın),
        // tarih ilerlemesin ki aylık ritim kaymasın.
        if !due && hasNew {
            await refresh(entries: entries, advanceCycle: false)
            return
        }
        await refresh(entries: entries)
        recordSnapshot(entries: entries, isMale: isMale, age: age)
    }

    /// Turun sonucunu aylık geçmişe yazar (aynı ay içinde tekrar çalışılırsa üzerine yazar).
    func recordSnapshot(entries: [(name: String, grams: Double?, date: Date)],
                        isMale: Bool,
                        age: Int) {
        guard let report = MicroNutrition.report(
            entries: entries, profiles: profiles, isMale: isMale, age: age
        ) else { return }

        let snapshot = MicroSnapshot(
            date: .now,
            coveragePercent: report.coveragePercent,
            coveredEntries: report.coveredEntries,
            uncoveredEntries: report.uncoveredEntries,
            percentByNutrient: Dictionary(uniqueKeysWithValues: report.findings.map {
                ($0.nutrient.rawValue, ($0.percent * 10).rounded() / 10)
            }),
            averageByNutrient: Dictionary(uniqueKeysWithValues: report.findings.map {
                ($0.nutrient.rawValue, ($0.average * 100).rounded() / 100)
            })
        )

        let cal = Calendar.current
        snapshots.removeAll { cal.isDate($0.date, equalTo: snapshot.date, toGranularity: .month) }
        snapshots.append(snapshot)
        snapshots.sort { $0.date < $1.date }
        // 24 ayı geçme: dosya şişmesin, trend için fazlasıyla yeterli.
        if snapshots.count > 24 { snapshots.removeFirst(snapshots.count - 24) }
        persist()
    }

    /// Uygulama açılışında ve Analiz sayfasında çağrılan tek giriş noktası:
    /// yemek kayıtlarını ve profili SwiftData'dan okuyup aylık turu tetikler.
    static func runMonthlyPassIfDue(in context: ModelContext) async {
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        guard !foods.isEmpty else { return }
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let age = profile.map {
            Calendar.current.dateComponents([.year], from: $0.birthDate, to: .now).year ?? 30
        } ?? 30
        await shared.runIfDue(
            entries: foods.map { (name: $0.name, grams: $0.grams, date: $0.date) },
            isMale: profile?.sex != .female,
            age: age
        )
    }

    // MARK: - Koç bağlamı

    /// Koç sohbetine giden özet. `nonisolated`: aktör durumuna değil DOSYAYA
    /// bakar, böylece bağlam derleyici hangi thread'de olursa olsun okuyabilir.
    /// Format sohbet bağlamı için sade tutuldu (satır satır, yorumsuz).
    nonisolated static func coachSummary() -> String? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct DiskPayload: Decodable {
            var lastRun: Date?
            var snapshots: [MicroSnapshot]?
        }
        guard let payload = try? decoder.decode(DiskPayload.self, from: data),
              let latest = payload.snapshots?.last else { return nil }

        let df = DateFormatter()
        df.locale = Locale(identifier: "tr_TR")
        df.dateFormat = "d MMM yyyy"

        var lines = ["[MİKRO BESİN TAHMİNİ — son 30 gün, \(df.string(from: latest.date)) turu]"]
        lines.append("Kapsama: %\(latest.coveragePercent) (\(latest.coveredEntries) kayıt hesaba girdi, \(latest.uncoveredEntries) giremedi).")
        lines.append("Değerler yemek adı + gramdan AI ile tahmin edildi; tek besinde sapma büyük olabilir, anlamlı olan ortalama ve trend.")

        let previous = payload.snapshots?.dropLast().last
        let rows = MicroNutrient.allCases.compactMap { n -> (MicroNutrient, Double, Double?)? in
            guard let pct = latest.percent(n) else { return nil }
            return (n, pct, latest.average(n))
        }.sorted { lhs, rhs in
            let a = lhs.0.lowerIsBetter ? max(0, lhs.1 - 100) : max(0, 100 - lhs.1)
            let b = rhs.0.lowerIsBetter ? max(0, rhs.1 - 100) : max(0, 100 - rhs.1)
            return a > b
        }

        for (n, pct, avg) in rows {
            var line = "- \(n.label): hedefin %\(Int(pct.rounded()))"
            if let avg {
                line += " (günde ~\(Fmt.num(avg, digits: avg < 10 ? 1 : 0)) \(n.unit), hedef \(Fmt.num(MicroNutrient.dailyTarget(n, isMale: true, age: 30), digits: 1)) \(n.unit))"
            }
            if let previous, let old = previous.percent(n) {
                let delta = pct - old
                if abs(delta) >= 5 {
                    line += " · geçen tur %\(Int(old.rounded())) (\(delta > 0 ? "+" : "")\(Int(delta.rounded())) puan)"
                }
            }
            if n.lowerIsBetter { line += " [üst sınır]" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static let batchSize = 15

    private static func estimate(
        batch: [(key: String, display: String)],
        client: AIClient
    ) async throws -> [MicroProfile] {
        let list = batch.enumerated()
            .map { "\($0.offset + 1). \($0.element.display)" }
            .joined(separator: "\n")

        let nutrients = MicroNutrient.allCases
            .map { "\($0.rawValue) (\($0.unit))" }
            .joined(separator: ", ")

        let system = """
        Sen bir besin bileşimi uzmanısın. Türkçe yemek adlarını bileşenlerine ayırıp \
        100 GRAM başına mikro besin değerlerini tahmin ediyorsun.

        Kurallar:
        - Yemek adı bileşikse ("tavuk + pilav + salata") bileşenleri tahmini ağırlık \
        oranlarıyla harmanla ve karışımın 100 gramı için tek bir değer üret.
        - Değerler ŞU birimlerde olmalı: \(nutrients).
        - Emin olamadığın isimlerde makul bir tahmin yap ama confidence'ı düşür.
        - Yalnızca JSON döndür, açıklama yazma, kod bloğu kullanma.

        Çıktı formatı:
        {"items":[{"index":1,"confidence":0.0-1.0,"per100g":{"fiber":0,"sodium":0,...}}]}
        """

        let user = """
        Aşağıdaki yemekler için 100 g başına mikro besin tahmini üret:

        \(list)
        """

        let raw = try await client.complete(systemPrompt: system, userPrompt: user)
        return parse(raw, batch: batch)
    }

    /// Model çıktısını çözer. Kod bloğu/önsöz gibi kirlilikleri tolere eder.
    static func parse(_ raw: String, batch: [(key: String, display: String)]) -> [MicroProfile] {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else { return [] }
        let jsonSlice = String(raw[start ... end])
        guard let data = jsonSlice.data(using: .utf8) else { return [] }

        struct Item: Decodable {
            let index: Int
            let confidence: Double?
            let per100g: [String: Double]
        }
        struct Envelope: Decodable { let items: [Item] }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return [] }
        let valid = Set(MicroNutrient.allCases.map(\.rawValue))

        return envelope.items.compactMap { item in
            let idx = item.index - 1
            guard batch.indices.contains(idx) else { return nil }
            // Bilinmeyen anahtarları at: model uydurursa hesaba karışmasın.
            let cleaned = item.per100g.filter { valid.contains($0.key) && $0.value >= 0 }
            guard !cleaned.isEmpty else { return nil }
            return MicroProfile(
                key: batch[idx].key,
                displayName: batch[idx].display,
                per100g: cleaned,
                source: "ai",
                confidence: min(max(item.confidence ?? 0.5, 0), 1),
                updatedAt: .now
            )
        }
    }
}
