import Foundation
import SwiftData

/// Haftalık gelişim fotoğrafı (karın bölgesi + tüm vücut). Görsel dış-depolamada tutulur;
/// ait olduğu ay (`monthKey`) ve ayın haftası (`week`) çekim tarihinden (`capturedAt`) türetilir.
/// Koç'a/AI'ya gösterim için saklanır ve SwiftData tarafından yönetilir.
@Model
final class ProgressPhoto {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data = Data()
    var capturedAt: Date = Date()
    var monthKey: String = ""        // "2026-06"
    var week: Int = 1                // ayın haftası (1-5)
    var createdAt: Date = Date()

    init(imageData: Data, capturedAt: Date = Date()) {
        self.id = UUID()
        self.imageData = imageData
        self.capturedAt = capturedAt
        self.createdAt = Date()
        self.monthKey = Self.monthKey(for: capturedAt)
        self.week = Self.weekOfMonth(for: capturedAt)
    }

    /// "2026-06" — yıl-ay gruplama anahtarı.
    static func monthKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// Ayın kaçıncı haftası (1-5) — gün/7 tabanlı sade hesap.
    static func weekOfMonth(for date: Date) -> Int {
        let day = Calendar.current.component(.day, from: date)
        return min(5, (day - 1) / 7 + 1)
    }
}
