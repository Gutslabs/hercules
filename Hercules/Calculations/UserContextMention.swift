import Foundation

enum MentionTag: String, CaseIterable, Identifiable, Hashable {
    case genelBakis, olcumler, grafikler, antrenman, takvim, kalori, yemekPlani, tarifler, profil, tahlil, hepsi

    var id: String { rawValue }

    /// Autocomplete'te gösterilecek güncel sayfa/veri etiketleri.
    /// Eski/ara etiketler (`yemekPlani` gibi) parse için kalır, picker'da görünmez.
    static let pickerCases: [MentionTag] = [
        .genelBakis,
        .kalori,
        .olcumler,
        .tahlil,
        .grafikler,
        .takvim,
        .tarifler,
        .antrenman,
        .profil,
        .hepsi
    ]

    /// Eski etiketleri güncel veri kapsamına yönlendirir.
    var canonical: MentionTag {
        switch self {
        case .yemekPlani: return .takvim
        default:          return self
        }
    }

    /// Birincil görünür isim (sidebar'daki güncel isimlerle uyumlu).
    var displayName: String {
        switch self {
        case .genelBakis: return "Genel Bakış"
        case .olcumler:   return "Ölçümler"
        case .grafikler:  return "Grafikler"
        case .antrenman:  return "Antrenman"
        case .takvim:     return "Öğün Takip"
        case .kalori:     return "Analiz"
        case .yemekPlani: return "Yemek Planı"
        case .tarifler:   return "Tarifler"
        case .profil:     return "Profil"
        case .tahlil:     return "Tahliller"
        case .hepsi:      return "Hepsi"
        }
    }

    /// Eşleşme için ek varyantlar.
    var aliases: [String] {
        switch self {
        case .genelBakis: return ["genel bakış", "genel bakis", "dashboard", "overview", "ozet", "özet"]
        case .olcumler:   return ["ölçümler", "olcumler", "ölçüm", "olcum", "tartı", "tarti", "kilo", "vücut", "vucut"]
        case .grafikler:  return ["grafikler", "grafik", "charts", "chart", "trend", "trendler", "değişim", "degisim", "ilerleme"]
        case .antrenman:  return ["antrenman", "workout", "spor", "egzersiz", "training", "gym", "seans", "hareket"]
        case .takvim:     return ["öğün takip", "ogun takip", "öğün", "ogun", "takvim", "calendar", "günlük", "gunluk", "yemek günlüğü", "yemek gunlugu", "hedef", "hedefler", "aylık", "aylik", "ay"]
        case .kalori:     return ["analiz", "analysis", "kalori", "calorie", "calories", "macros", "makro", "bugün", "bugun", "ortalama", "average"]
        case .yemekPlani: return ["yemek planı", "yemek plani", "meal plan", "meal", "yemek", "diyet", "plan"]
        case .tarifler:   return ["tarifler", "tarif", "recipe", "recipes", "yemek tarif"]
        case .profil:     return ["profil", "profile", "ayar", "settings"]
        case .tahlil:     return ["tahliller", "tahlil", "kan tahlili", "kan tahlilleri", "kan değerleri",
                                  "kan degerleri", "lab", "labs", "hemogram", "kan sayımı", "kan sayimi",
                                  "tahlil sonuçları", "tahlil sonuclari"]
        case .hepsi:      return ["hepsi", "tümü", "tumu", "all", "everything", "her şey", "her sey"]
        }
    }

    /// Autocomplete için kısa hint (gösterilecek alias).
    var hintAlias: String {
        switch self {
        case .genelBakis: return "dashboard, özet"
        case .olcumler:   return "kilo, yağ %"
        case .grafikler:  return "trendler, değişim"
        case .antrenman:  return "seans, hareket, tempo"
        case .takvim:     return "günlük yiyecek, aylık hedefler"
        case .kalori:     return "kalori, makro, dönemler"
        case .yemekPlani: return "meal, diyet"
        case .tarifler:   return "kayıtlı tarifler"
        case .profil:     return "kimlik, aktivite, hedef"
        case .tahlil:     return "kan değerleri, referans dışı"
        case .hepsi:      return "all — tüm veri"
        }
    }

    /// Verilen prefix bu tag'in displayName veya aliaslarından birine eşleşiyor mu?
    /// Türkçe aksanlara duyarsız.
    func matches(prefix: String) -> Bool {
        guard !prefix.isEmpty else { return true }
        let needle = UserContextSnapshot.publicNormalize(prefix)
        let haystack = ([displayName] + aliases).map { UserContextSnapshot.publicNormalize($0) }
        return haystack.contains { $0.hasPrefix(needle) || $0.contains(needle) }
    }

    var sections: [SnapshotSection] {
        switch self {
        case .genelBakis: return [.profile, .latestMeasurement, .trend, .todayIntake, .workout, .goals]
        case .olcumler:   return [.latestMeasurement, .measurementLog, .trend]
        case .grafikler:  return [.trend, .latestMeasurement, .measurementLog]
        case .antrenman:  return [.workout, .workoutLogs]
        case .takvim:     return [.todayIntake, .foodDiary, .goals]
        case .kalori:     return [.profile, .todayIntake, .caloriePeriods]
        case .yemekPlani: return [.todayIntake, .foodDiary, .goals, .recipes]
        case .tarifler:   return [.recipes]
        case .profil:     return [.profile, .workout]
        case .tahlil:     return [.labs, .profile]
        case .hepsi:      return SnapshotSection.allCases
        }
    }
}

// MARK: - Açık tarih aralığı

/// `@Öğün Takip` gibi zaman serisi taşıyan etiketlere KULLANICININ seçtiği aralık.
///
/// NEDEN: aralık şimdiye kadar kullanıcının cümlesinden regex'le tahmin ediliyordu —
/// "bugün", "geçen ay", "son 3 ay", "24 Mayıs", "1 Temmuz'dan beri" için ayrı ayrı desenler,
/// hepsi Türkçe ekleriyle boğuşuyor, ay adları (haziran/temmuz) aralık olarak hiç tanınmıyordu.
/// Kullanıcı seçtiğinde tahmine gerek kalmıyor: seçim varsa metin ayrıştırıcı o etiket için
/// HİÇ çalışmaz, yoksa iki kaynak çakışır ve yine tahmine düşerdik.
///
/// Metinde `@Öğün Takip[2026-06..2026-07]` biçiminde taşınır: kullanıcı ne seçtiğini görür,
/// mesajı düzenlese bile seçim mesajla birlikte kalır.
enum MentionRange: Equatable, Hashable, Sendable {
    /// Kapsayıcı ay aralığı: [from, to] — tek ay için ikisi de aynı.
    case months(fromYear: Int, fromMonth: Int, toYear: Int, toMonth: Int)
    /// Bugünden geriye N gün.
    case lastDays(Int)
    case today

    /// Metne yazılan biçim. Ay aralığı ISO benzeri, presetler kısa isimli.
    var token: String {
        switch self {
        case .today:
            return "bugun"
        case .lastDays(let n):
            return "son-\(n)g"
        case .months(let fy, let fm, let ty, let tm):
            let from = String(format: "%04d-%02d", fy, fm)
            let to = String(format: "%04d-%02d", ty, tm)
            return from == to ? from : "\(from)..\(to)"
        }
    }

    static func parse(token: String) -> MentionRange? {
        let t = token.trimmingCharacters(in: .whitespaces).lowercased()
        if t == "bugun" || t == "bugün" { return .today }
        if t.hasPrefix("son-"), t.hasSuffix("g"),
           let n = Int(t.dropFirst(4).dropLast()), n > 0, n <= 3_650 {
            return .lastDays(n)
        }
        func ym(_ s: Substring) -> (Int, Int)? {
            let parts = s.split(separator: "-")
            guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]),
                  (1...12).contains(m), (2000...2100).contains(y) else { return nil }
            return (y, m)
        }
        if t.contains("..") {
            let sides = t.components(separatedBy: "..")
            guard sides.count == 2, let a = ym(Substring(sides[0])), let b = ym(Substring(sides[1]))
            else { return nil }
            return .months(fromYear: a.0, fromMonth: a.1, toYear: b.0, toMonth: b.1)
        }
        guard let a = ym(Substring(t)) else { return nil }
        return .months(fromYear: a.0, fromMonth: a.1, toYear: a.0, toMonth: a.1)
    }

    /// Kullanıcıya gösterilecek okunur etiket.
    var displayLabel: String {
        switch self {
        case .today: return "bugün"
        case .lastDays(let n):
            if n % 30 == 0, n >= 30 { return "son \(n / 30) ay" }
            if n % 7 == 0, n >= 7 { return "son \(n / 7) hafta" }
            return "son \(n) gün"
        case .months(let fy, let fm, let ty, let tm):
            let a = Self.monthName(fm) + (fy == Self.currentYear ? "" : " \(fy)")
            if fy == ty && fm == tm { return a }
            let b = Self.monthName(tm) + (ty == Self.currentYear ? "" : " \(ty)")
            return "\(a) – \(b)"
        }
    }

    /// Somut aralık. Üst sınır DIŞLAYICI.
    func interval(now: Date = .now, calendar cal: Calendar = .current) -> (start: Date, endExclusive: Date) {
        switch self {
        case .today:
            let start = cal.startOfDay(for: now)
            return (start, cal.date(byAdding: .day, value: 1, to: start) ?? now)
        case .lastDays(let n):
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            let start = cal.date(byAdding: .day, value: -n, to: end) ?? end
            return (start, end)
        case .months(let fy, let fm, let ty, let tm):
            var from = DateComponents(); from.year = fy; from.month = fm; from.day = 1
            var to = DateComponents(); to.year = ty; to.month = tm; to.day = 1
            let start = cal.date(from: from) ?? now
            let toStart = cal.date(from: to) ?? now
            // Bitiş ayının SONUNU dahil et: bir sonraki ayın başı dışlayıcı sınır.
            let end = cal.date(byAdding: .month, value: 1, to: toStart) ?? now
            return (start, max(start, end))
        }
    }

    static func monthName(_ m: Int) -> String {
        let names = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                     "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
        guard (1...12).contains(m) else { return "\(m)" }
        return names[m - 1]
    }

    private static var currentYear: Int { Calendar.current.component(.year, from: .now) }
}

/// Bir etiket + (varsa) kullanıcının seçtiği aralık.
struct MentionSelection: Equatable, Hashable, Sendable {
    let tag: MentionTag
    let range: MentionRange?

    var insertionText: String {
        guard let range else { return "@\(tag.displayName) " }
        return "@\(tag.displayName)[\(range.token)] "
    }
}

extension MentionTag {
    /// Zaman serisi taşıyan etiketler aralık seçimi sunar. Tarifler/Profil gibi
    /// zamansız veriler için ikinci adım gösterilmez.
    var supportsRange: Bool {
        switch self {
        case .takvim, .olcumler, .grafikler, .antrenman, .kalori, .yemekPlani, .hepsi:
            return true
        // Tahliller tarih taşır ama snapshot her zaman son panelleri verir —
        // hiçbir şeye yaramayan bir aralık adımı göstermiyoruz.
        case .genelBakis, .tarifler, .profil, .tahlil:
            return false
        }
    }
}

// MARK: - Composer eki

/// Kullanıcının picker'dan seçtiği veri eki — composer'ın ÜSTÜNDE chip olarak durur,
/// sohbet metnine yazılmaz.
///
/// NEDEN: seçimi `@Ölçümler[2026-06]` diye mesaja gömmek hem çirkindi hem de her ay için
/// menüyü yeniden açmayı gerektiriyordu. Chip'te birden çok aralık birikebilir; snapshot
/// tek pencere kullandığı için gönderirken en geniş aralığa birleştiriyoruz.
struct ContextAttachment: Identifiable, Equatable, Hashable {
    let tag: MentionTag
    var ranges: [MentionRange]

    var id: String { tag.rawValue }

    var displayLabel: String {
        guard !ranges.isEmpty else { return tag.displayName }
        return "\(tag.displayName) · \(ranges.map(\.displayLabel).joined(separator: ", "))"
    }

    /// Seçilenleri kapsayan tek aralık. Aylar bitişik olmasa bile en erken ile en geç
    /// arasını alıyoruz: eksik veri göstermektense fazlasını göstermek yeğ.
    var effectiveRange: MentionRange? {
        guard !ranges.isEmpty else { return nil }
        if ranges.count == 1 { return ranges[0] }
        let months = ranges.compactMap { r -> (Int, Int, Int, Int)? in
            if case .months(let fy, let fm, let ty, let tm) = r { return (fy, fm, ty, tm) }
            return nil
        }
        // Karışık seçim (preset + ay) ya da hepsi preset ise en geniş günlük pencereyi seç.
        guard months.count == ranges.count else {
            return ranges.max { lhs, rhs in lhs.approximateDayCount < rhs.approximateDayCount }
        }
        // Anahtar (ay - 1) ile kuruluyor: düz `y*12 + m` Aralık'ta `% 12 == 0` verip
        // ayı bir sonraki yılın "0. ayı" yapıyordu.
        let startKey = months.map { $0.0 * 12 + ($0.1 - 1) }.min() ?? 0
        let endKey = months.map { $0.2 * 12 + ($0.3 - 1) }.max() ?? 0
        return .months(fromYear: startKey / 12, fromMonth: startKey % 12 + 1,
                       toYear: endKey / 12, toMonth: endKey % 12 + 1)
    }
}

extension MentionRange {
    /// Kabaca kaç gün — yalnız "hangisi daha geniş" karşılaştırması için.
    var approximateDayCount: Int {
        switch self {
        case .today: return 1
        case .lastDays(let n): return n
        case .months(let fy, let fm, let ty, let tm):
            return max(1, ((ty * 12 + tm) - (fy * 12 + fm) + 1) * 30)
        }
    }
}
