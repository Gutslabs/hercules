import Foundation
import Observation
import SwiftData

/// Mac'ten "Telefona gönder" ile oluşturulan Akış öğesi. Artık dosya tabanlı özel
/// taşıma yerine SwiftData modelidir ve diğer veriler gibi CloudKit ile senkronlanır.
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

/// Akışın yalnızca cihaz-yerel "okundu" durumunu tutar. Öğelerin kendisi SwiftData'dadır.
@Observable
final class FeedStore {
    static let shared = FeedStore()
    private static let seenKey = "hercules.feed.seen_ids_v1"

    private var seenIDs: Set<String>

    private init() {
        seenIDs = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
    }

    func unseenCount(in items: [FeedItem]) -> Int {
        items.reduce(0) { $0 + (seenIDs.contains($1.id) ? 0 : 1) }
    }

    func isSeen(_ id: String) -> Bool {
        seenIDs.contains(id)
    }

    func markSeen(_ id: String) {
        guard seenIDs.insert(id).inserted else { return }
        persistSeen(liveIDs: nil)
    }

    func markAllSeen(_ items: [FeedItem]) {
        let liveIDs = Set(items.map(\.id))
        guard !liveIDs.isSubset(of: seenIDs) else { return }
        seenIDs.formUnion(liveIDs)
        persistSeen(liveIDs: liveIDs)
    }

    /// Bir defalık veri koruma geçişi: eski yerel feed JSON'u varsa CloudKit modeline
    /// aktarır ve dosyayı kaldırır. Sonraki çalışmalarda özel transport kalmaz.
    @MainActor
    static func migrateLegacyFile(into context: ModelContext) {
        // Tek seferlik bayrak: dosya silinse bile her açılışta fileExists + (varsa)
        // decode + TÜM FeedItem tablosunun fetch'i tekrarlanıyordu.
        let doneKey = "hercules.feed.legacy-migration.done.v1"
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }

        let url = legacyFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let legacyItems = try? decoder.decode([LegacyFeedItem].self, from: data)
        else {
            UserDefaults.standard.set(true, forKey: doneKey)
            return
        }

        let existing = (try? context.fetch(FetchDescriptor<FeedItem>())) ?? []
        var existingIDs = Set(existing.map(\.id))
        for item in legacyItems where existingIDs.insert(item.id).inserted {
            context.insert(FeedItem(
                id: item.id,
                title: item.title,
                body: item.body,
                kind: item.kind,
                source: item.source,
                createdAt: item.createdAt,
                conversationTitle: item.conversationTitle
            ))
        }
        guard context.saveOrReport("eski Akış verisini taşıma") else { return }
        UserDefaults.standard.set(true, forKey: doneKey)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            AppLog.persistence.error("Legacy feed removal failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    @discardableResult
    static func deduplicate(_ items: [FeedItem], in context: ModelContext, save: Bool = true) -> Bool {
        var seen: Set<String> = []
        var changed = false
        // Kararlı sıra anahtarı ÖNCE hesaplanır: `String(describing:)` karşılaştırıcının
        // içindeyken her kıyaslamada yeni bir tanım metni alloc ediyordu (O(n log n)
        // tahsis). Anahtarlar bir kez üretilince sıralama saf karşılaştırma olur.
        let keyed = items.map { (item: $0, key: String(describing: $0.persistentModelID)) }
        for entry in keyed.sorted(by: {
            if $0.item.createdAt != $1.item.createdAt { return $0.item.createdAt > $1.item.createdAt }
            return $0.key < $1.key
        }) {
            let item = entry.item
            if !seen.insert(item.id).inserted {
                context.delete(item)
                changed = true
            }
        }
        if changed, save {
            context.saveOrReport("Akış kayıtlarını tekilleştirme")
        }
        return changed
    }

    private func persistSeen(liveIDs: Set<String>?) {
        if let liveIDs { seenIDs.formIntersection(liveIDs) }
        UserDefaults.standard.set(Array(seenIDs), forKey: Self.seenKey)
    }

    private static var legacyFileURL: URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Hercules", isDirectory: true)
            .appendingPathComponent("hercules-feed.json")
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct LegacyFeedItem: Decodable {
    let id: String
    let title: String
    let body: String
    let kind: String
    let source: String
    let createdAt: Date
    let conversationTitle: String?
}
