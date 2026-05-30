import Foundation

enum MentionTag: String, CaseIterable, Identifiable, Hashable {
    case genelBakis, olcumler, grafikler, antrenman, takvim, kalori, yemekPlani, tarifler, profil, hepsi

    var id: String { rawValue }

    /// Birincil görünür isim (sidebar'daki etiketle uyumlu).
    var displayName: String {
        switch self {
        case .genelBakis: return "Genel Bakış"
        case .olcumler:   return "Ölçümler"
        case .grafikler:  return "Grafikler"
        case .antrenman:  return "Antrenman"
        case .takvim:     return "Takvim"
        case .kalori:     return "Kalori"
        case .yemekPlani: return "Yemek Planı"
        case .tarifler:   return "Tarifler"
        case .profil:     return "Profil"
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
        case .takvim:     return ["takvim", "calendar", "hedef", "hedefler", "aylık", "ay"]
        case .kalori:     return ["kalori", "calorie", "macros", "makro", "bugün", "bugun"]
        case .yemekPlani: return ["yemek planı", "yemek plani", "meal plan", "meal", "yemek", "diyet", "plan"]
        case .tarifler:   return ["tarifler", "tarif", "recipe", "recipes", "yemek tarif"]
        case .profil:     return ["profil", "profile", "ayar", "settings"]
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
        case .kalori:     return "bugün, makro"
        case .yemekPlani: return "meal, diyet"
        case .tarifler:   return "kayıtlı tarifler"
        case .profil:     return "kimlik, aktivite, hedef"
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
        case .olcumler:   return [.latestMeasurement, .trend]
        case .grafikler:  return [.trend, .latestMeasurement]
        case .antrenman:  return [.workout, .workoutLogs]
        case .takvim:     return [.todayIntake, .foodDiary, .goals]
        case .kalori:     return [.profile, .todayIntake, .caloriePeriods]
        case .yemekPlani: return []
        case .tarifler:   return [.recipes]
        case .profil:     return [.profile, .workout]
        case .hepsi:      return SnapshotSection.allCases
        }
    }
}
