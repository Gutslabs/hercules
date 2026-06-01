import Foundation
import SwiftData

/// Koç takip maddesinin yaşam döngüsü.
enum CoachItemStatus: String, Codable, CaseIterable, Sendable {
    case advised      // yeni önerildi / hâlâ açık
    case improving    // gelişiyor (kısmi ilerleme)
    case resolved     // halledildi
    case dropped      // artık geçerli değil

    var label: String {
        switch self {
        case .advised:   return "Açık"
        case .improving: return "Gelişiyor"
        case .resolved:  return "Halledildi"
        case .dropped:   return "Bırakıldı"
        }
    }

    /// Hâlâ takip edilen (rapora taşınacak) madde mi?
    var isOpen: Bool { self == .advised || self == .improving }
}

/// Günlük AI koç raporu — günde tek (day = start-of-day, idempotent anahtar).
@Model
final class CoachReport {
    /// Raporun ait olduğu gün (start-of-day). Günde tek rapor.
    var day: Date
    var createdAt: Date
    /// Uzun Türkçe analiz (kullanıcıya gösterilen metin).
    var narrative: String
    // Hızlı gösterim için o günkü metrik snapshot'ı:
    var weight: Double?
    var weeklyDelta: Double?
    var avgCalories: Double?
    var avgProtein: Double?
    var sessionsLast30: Int?
    /// Hangi sağlayıcı üretti (şeffaflık).
    var generatedBy: String?
    /// Sync merge için son değişiklik zamanı.
    var updatedAt: Date = Date.now

    init(
        day: Date,
        createdAt: Date = .now,
        narrative: String,
        weight: Double? = nil,
        weeklyDelta: Double? = nil,
        avgCalories: Double? = nil,
        avgProtein: Double? = nil,
        sessionsLast30: Int? = nil,
        generatedBy: String? = nil
    ) {
        self.day = day
        self.createdAt = createdAt
        self.narrative = narrative
        self.weight = weight
        self.weeklyDelta = weeklyDelta
        self.avgCalories = avgCalories
        self.avgProtein = avgProtein
        self.sessionsLast30 = sessionsLast30
        self.generatedBy = generatedBy
        self.updatedAt = .now
    }
}

/// Koçun takip ettiği geliştirilecek alan — günden güne durumu evrilir
/// (Açık → Gelişiyor → Halledildi). "area" kararlı anahtar; her gün aynı
/// area ile güncellenir.
@Model
final class CoachFocusItem {
    /// Kararlı anahtar (ör. "sebze-lif", "antrenman-frekansi").
    var area: String
    var title: String
    var detail: String?
    /// CoachItemStatus.rawValue
    var statusRaw: String
    var firstAdvisedAt: Date
    var lastCheckedAt: Date
    /// En son hangi rapor gününde değerlendirildi.
    var lastReportDay: Date
    var resolvedAt: Date?
    var updatedAt: Date = Date.now

    init(
        area: String,
        title: String,
        detail: String? = nil,
        status: CoachItemStatus = .advised,
        firstAdvisedAt: Date = .now,
        lastReportDay: Date
    ) {
        self.area = area
        self.title = title
        self.detail = detail
        self.statusRaw = status.rawValue
        self.firstAdvisedAt = firstAdvisedAt
        self.lastCheckedAt = .now
        self.lastReportDay = lastReportDay
        self.updatedAt = .now
    }

    var status: CoachItemStatus {
        get { CoachItemStatus(rawValue: statusRaw) ?? .advised }
        set { statusRaw = newValue.rawValue }
    }

    /// İlk önerildiğinden bu yana kaç gün geçti.
    var daysOpen: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: firstAdvisedAt), to: cal.startOfDay(for: .now)).day ?? 0
    }
}

/// Günlük koç tarif önerisi — kullanıcının yediklerine + tariflerine bakıp
/// internetten ARAŞTIRILMIŞ (kaynak URL'li) yüksek proteinli bowl tarifi.
/// Günde tek (day = start-of-day).
@Model
final class CoachRecipe {
    var day: Date
    var createdAt: Date
    var title: String
    /// "Neden sana uygun" kısa notu / giriş.
    var summary: String?
    var ingredientsText: String?
    var instructionsText: String?
    /// Araştırılan gerçek kaynağın URL'si (zorunlu olması beklenir).
    var sourceURL: String?
    var sourceName: String?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var servings: Int?
    var prepMinutes: Int?
    var category: String?
    var generatedBy: String?
    var updatedAt: Date = Date.now

    init(
        day: Date,
        createdAt: Date = .now,
        title: String,
        summary: String? = nil,
        ingredientsText: String? = nil,
        instructionsText: String? = nil,
        sourceURL: String? = nil,
        sourceName: String? = nil,
        calories: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        servings: Int? = nil,
        prepMinutes: Int? = nil,
        category: String? = nil,
        generatedBy: String? = nil
    ) {
        self.day = day
        self.createdAt = createdAt
        self.title = title
        self.summary = summary
        self.ingredientsText = ingredientsText
        self.instructionsText = instructionsText
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.category = category
        self.generatedBy = generatedBy
        self.updatedAt = .now
    }

    var sourceHost: String? {
        guard let u = sourceURL, let host = URL(string: u)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
