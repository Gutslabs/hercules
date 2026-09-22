import Foundation
import SwiftData

/// KULLANIM DIŞI — Akış (gelen kutusu) arayüzü kaldırıldı.
///
/// Model ŞEMADA KALIYOR ve bilerek: üretim CloudKit şeması kilitli, bir modeli
/// şemadan düşürmek mevcut kayıtları budayıp yeniden import'ta kopya üretiyor.
/// Tip burada duruyor ki şema aynı kalsın; hiçbir yerden yazılmıyor/okunmuyor.
@Model
final class FeedItem {
    var id: String = UUID().uuidString
    var title: String = ""
    var body: String = ""
    var kind: String = "chat"
    var source: String = "Mac"
    var createdAt: Date = Date()
    var conversationTitle: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        kind: String = "chat",
        source: String = "Mac",
        createdAt: Date = Date(),
        conversationTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.kind = kind
        self.source = source
        self.createdAt = createdAt
        self.conversationTitle = conversationTitle
    }
}
