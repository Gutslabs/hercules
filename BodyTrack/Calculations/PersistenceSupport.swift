import Foundation
import SwiftData
import os

/// Uygulama geneli structured logging — `print` yerine os.Logger (kategorili,
/// gizlilik-bilinçli). Konsoldan/Instruments'tan filtrelenebilir.
enum AppLog {
    static let subsystem = "com.hercules"
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let backup = Logger(subsystem: subsystem, category: "backup")
    static let memory = Logger(subsystem: subsystem, category: "memory")
    static let ai = Logger(subsystem: subsystem, category: "ai")
}

/// Kaydetme hatalarını kullanıcıya tek bir noktadan bildirir. Root view bunu bir
/// alert'e bağlar; böylece "kaydedildi" der ama aslında diske yazılamamış (disk
/// dolu / iCloud çakışması) sessiz veri kaybı görünür olur.
@MainActor
@Observable
final class SaveErrorReporter {
    static let shared = SaveErrorReporter()
    private init() {}

    /// Son kaydetme hatası (nil = hata yok). Set edilince root alert tetiklenir.
    var message: String?
}

extension ModelContext {
    /// `try? save()` yerine kullan: hatayı YUTMAZ. Loglar (os.Logger) ve kullanıcıya
    /// tek bir uyarı gösterir (SaveErrorReporter). Başarıda tamamen sessizdir.
    func saveOrReport(_ operation: String = "") {
        do {
            try save()
        } catch {
            let desc = error.localizedDescription
            AppLog.persistence.error("SwiftData save failed [\(operation, privacy: .public)]: \(desc, privacy: .public)")
            let op = operation
            Task { @MainActor in
                SaveErrorReporter.shared.message = op.isEmpty
                    ? "Kaydedilemedi: \(desc)"
                    : "Kaydedilemedi (\(op)): \(desc)"
            }
        }
    }
}
