import Foundation

/// Mikro besin analizi — yemek KAYITLARINDAN (isim + gram) türetilen tahmini
/// vitamin/mineral alımı ve referans değerlerle karşılaştırma.
///
/// Tasarım notları:
/// - Veri SwiftData'ya YAZILMAZ. Üretim CloudKit şeması kilitli; bu tamamen
///   türetilmiş bir katman, her an sıfırdan üretilebilir. Bu yüzden tahminler
///   diskte JSON olarak yaşar (`MicroNutrientStore`).
/// - Tahminler AI'dan gelir ve TAHMİN ÜSTÜNE TAHMİNDİR (makrolar da tahminti).
///   Tek besinde sapma büyük olabilir; anlamlı olan 30 günlük ORTALAMA ve
///   aylar arası TREND'dir. Arayüz bunu böyle sunar.
enum MicroNutrient: String, CaseIterable, Identifiable, Codable, Sendable {
    case fiber, sodium, potassium, calcium, iron, magnesium, zinc
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminK, vitaminB12, folate
    case omega3

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fiber:      return "Lif"
        case .sodium:     return "Sodyum"
        case .potassium:  return "Potasyum"
        case .calcium:    return "Kalsiyum"
        case .iron:       return "Demir"
        case .magnesium:  return "Magnezyum"
        case .zinc:       return "Çinko"
        case .vitaminA:   return "A vitamini"
        case .vitaminC:   return "C vitamini"
        case .vitaminD:   return "D vitamini"
        case .vitaminE:   return "E vitamini"
        case .vitaminK:   return "K vitamini"
        case .vitaminB12: return "B12"
        case .folate:     return "Folat"
        case .omega3:     return "Omega-3"
        }
    }

    var unit: String {
        switch self {
        case .fiber, .omega3: return "g"
        case .sodium, .potassium, .calcium, .iron, .magnesium, .zinc, .vitaminC, .vitaminE: return "mg"
        case .vitaminA, .vitaminD, .vitaminK, .vitaminB12, .folate: return "µg"
        }
    }

    /// Fazlası sorun olan besinler (sodyum) hedefi AŞMAMAK üzere okunur.
    var lowerIsBetter: Bool { self == .sodium }

    /// Günlük referans alım. Yetişkin DRI/RDA bandı; cinsiyete göre ayrışanlar
    /// ayrıştırıldı, kalanlar ortak. Lif kiloya göre değil enerjiye göre değişir
    /// ama pratikte 25/38 g bandı yeterli.
    static func dailyTarget(_ n: MicroNutrient, isMale: Bool, age: Int) -> Double {
        switch n {
        case .fiber:      return isMale ? 38 : 25
        case .sodium:     return 2300                       // ÜST sınır
        case .potassium:  return isMale ? 3400 : 2600
        case .calcium:    return age >= 51 ? 1200 : 1000
        case .iron:       return isMale ? 8 : (age >= 51 ? 8 : 18)
        case .magnesium:  return isMale ? (age >= 31 ? 420 : 400) : (age >= 31 ? 320 : 310)
        case .zinc:       return isMale ? 11 : 8
        case .vitaminA:   return isMale ? 900 : 700         // µg RAE
        case .vitaminC:   return isMale ? 90 : 75
        case .vitaminD:   return age >= 71 ? 20 : 15        // µg
        case .vitaminE:   return 15
        case .vitaminK:   return isMale ? 120 : 90
        case .vitaminB12: return 2.4
        case .folate:     return 400                        // µg DFE
        case .omega3:     return isMale ? 1.6 : 1.1         // g (ALA tabanı)
        }
    }
}

/// Bir yemeğin 100 GRAM başına mikro besin tahmini.
struct MicroProfile: Codable, Sendable {
    /// Normalize edilmiş yemek adı (önbellek anahtarı).
    var key: String
    /// Modelin gördüğü orijinal isim — elle düzeltirken okunabilir olsun.
    var displayName: String
    /// 100 g başına değerler; birimler `MicroNutrient.unit`.
    var per100g: [String: Double]
    /// "ai" ya da "manual" — elle düzeltilenler yeniden tahmin edilmez.
    var source: String
    /// Modelin kendi güven beyanı (0–1). Muğlak isimlerde düşük gelir.
    var confidence: Double
    var updatedAt: Date

    func value(_ n: MicroNutrient) -> Double? { per100g[n.rawValue] }
}

/// Bir günün toplam alımı.
struct MicroDay: Sendable {
    let date: Date
    /// Besin → toplam miktar (birim `MicroNutrient.unit`).
    var totals: [MicroNutrient: Double]
    /// Tahmine dahil EDİLEMEYEN kayıt sayısı (gramsız ya da önbellekte yok).
    var uncoveredEntries: Int
    var coveredEntries: Int
}

/// Bir besinin pencere ortalaması ve hedefe göre durumu.
struct MicroFinding: Identifiable, Sendable {
    let nutrient: MicroNutrient
    /// Günlük ortalama alım (yalnız kapsanan günler).
    let average: Double
    let target: Double

    var id: String { nutrient.rawValue }
    /// Hedefin yüzdesi (sodyumda "üst sınırın yüzdesi").
    var percent: Double { target > 0 ? average / target * 100 : 0 }

    enum Status { case low, ok, high }

    var status: Status {
        if nutrient.lowerIsBetter { return percent > 100 ? .high : .ok }
        if percent < 70 { return .low }
        if percent < 90 { return .ok }
        return .ok
    }

    /// Sıralama için "ne kadar kötü": düşükler öne, sodyum aşımı da öne.
    var severity: Double {
        if nutrient.lowerIsBetter { return max(0, percent - 100) }
        return max(0, 100 - percent)
    }
}

/// Analiz penceresinin tamamı.
struct MicroReport: Sendable {
    let from: Date
    let to: Date
    let days: [MicroDay]
    let findings: [MicroFinding]
    /// Penceredeki toplam kayıt ve kaçının tahmine girebildiği.
    let coveredEntries: Int
    let uncoveredEntries: Int
    /// Önbellekte karşılığı olmayan (henüz tahmin edilmemiş) farklı isim sayısı.
    let missingNames: Int

    var coveragePercent: Int {
        let total = coveredEntries + uncoveredEntries
        guard total > 0 else { return 0 }
        return Int((Double(coveredEntries) / Double(total) * 100).rounded())
    }
}

enum MicroNutrition {
    /// Önbellek anahtarı: küçük harf, fazla boşluk yok, noktalama sadeleştirilmiş.
    /// "Protein tozlu yoğurt bowl" ile "protein tozlu  yoğurt bowl" aynı anahtara düşer.
    static func normalize(_ name: String) -> String {
        let lowered = name.lowercased(with: Locale(identifier: "tr_TR"))
        let collapsed = lowered
            .replacingOccurrences(of: "[^\\p{L}\\p{N}+ ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Kayıtları günlere toplar. `grams` yoksa kayıt tahmine GİRMEZ — uydurmak
    /// yüzdeyi yalancı yapar; rapor bunu "kapsanmayan" olarak gösterir.
    static func aggregate(
        entries: [(name: String, grams: Double?, date: Date)],
        profiles: [String: MicroProfile],
        calendar: Calendar = .current
    ) -> [MicroDay] {
        var byDay: [Date: (totals: [MicroNutrient: Double], covered: Int, uncovered: Int)] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            var bucket = byDay[day] ?? ([:], 0, 0)
            guard let grams = entry.grams, grams > 0,
                  let profile = profiles[normalize(entry.name)] else {
                bucket.uncovered += 1
                byDay[day] = bucket
                continue
            }
            let factor = grams / 100.0
            for n in MicroNutrient.allCases {
                guard let per100 = profile.value(n) else { continue }
                bucket.totals[n, default: 0] += per100 * factor
            }
            bucket.covered += 1
            byDay[day] = bucket
        }

        return byDay
            .map { MicroDay(date: $0.key, totals: $0.value.totals,
                            uncoveredEntries: $0.value.uncovered, coveredEntries: $0.value.covered) }
            .sorted { $0.date < $1.date }
    }

    /// Pencere raporu: yalnızca EN AZ BİR kaydı tahmine girmiş günler ortalamaya
    /// katılır (hiç yemek girilmemiş gün ortalamayı aşağı çekmesin).
    static func report(
        entries: [(name: String, grams: Double?, date: Date)],
        profiles: [String: MicroProfile],
        windowDays: Int = 30,
        isMale: Bool,
        age: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MicroReport? {
        let end = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: end) else { return nil }
        let window = entries.filter { $0.date >= start && $0.date <= now }
        guard !window.isEmpty else { return nil }

        let days = aggregate(entries: window, profiles: profiles, calendar: calendar)
        let loggedDays = days.filter { $0.coveredEntries > 0 }
        guard !loggedDays.isEmpty else { return nil }

        let findings: [MicroFinding] = MicroNutrient.allCases.map { n in
            let sum = loggedDays.reduce(0.0) { $0 + ($1.totals[n] ?? 0) }
            let avg = sum / Double(loggedDays.count)
            return MicroFinding(nutrient: n, average: avg,
                                target: MicroNutrient.dailyTarget(n, isMale: isMale, age: age))
        }

        let missing = Set(window.compactMap { entry -> String? in
            let key = normalize(entry.name)
            return profiles[key] == nil ? key : nil
        }).count

        return MicroReport(
            from: start,
            to: end,
            days: days,
            findings: findings.sorted { $0.severity > $1.severity },
            coveredEntries: days.reduce(0) { $0 + $1.coveredEntries },
            uncoveredEntries: days.reduce(0) { $0 + $1.uncoveredEntries },
            missingNames: missing
        )
    }
}


/// Aylık tur özeti — aylar arası trend ("geçen ay %60, bu ay %85") buradan okunur.
/// Diskte `micronutrients.json` içinde saklanır; koç sohbetine de bu özet gider.
struct MicroSnapshot: Codable, Sendable, Identifiable {
    var date: Date
    var coveragePercent: Int
    var coveredEntries: Int
    var uncoveredEntries: Int
    /// Besin (rawValue) → hedefin yüzdesi.
    var percentByNutrient: [String: Double]
    /// Besin (rawValue) → günlük ortalama alım (birim `MicroNutrient.unit`).
    var averageByNutrient: [String: Double]

    var id: Date { date }

    func percent(_ n: MicroNutrient) -> Double? { percentByNutrient[n.rawValue] }
    func average(_ n: MicroNutrient) -> Double? { averageByNutrient[n.rawValue] }
}
