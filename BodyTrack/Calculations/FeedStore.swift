import Foundation
import Observation

/// Mac → telefon "feed" akışının tek bir öğesi. Mac Hercules sohbetinden "Telefona gönder"
/// ile oluşturulur, vault sync ile mobile Hercules'e taşınır ve Akış sekmesinde görünür.
struct FeedItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let kind: String            // "chat" | "recipe" | "note"
    let source: String          // "Mac"
    let createdAt: Date
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

/// Feed öğelerini `hercules-feed.json` (Application Support/Hercules) içinde tutar. Bu dosya
/// BackupService'in "support files" listesine eklidir → ana veri MERGE'üne DOKUNMADAN,
/// var olan vault transport'uyla Mac↔mobil taşınır. Birleştirme id bazında union (append-only,
/// kayıp yok); "okundu" durumu cihaz-yerel UserDefaults'ta. @Observable → UI reaktif.
@Observable
final class FeedStore {
    static let shared = FeedStore()
    static let fileName = "hercules-feed.json"

    private static let maxItems = 120
    private static let seenKey = "hercules.feed.seen_ids_v1"

    private(set) var items: [FeedItem] = []
    private var seenIDs: Set<String>

    @ObservationIgnored private let url: URL

    private init() {
        url = FeedStore.makeURL()
        seenIDs = Set(UserDefaults.standard.stringArray(forKey: FeedStore.seenKey) ?? [])
        items = FeedStore.load(from: url)
    }

    var unseenCount: Int { items.reduce(0) { $0 + (seenIDs.contains($1.id) ? 0 : 1) } }
    func isSeen(_ id: String) -> Bool { seenIDs.contains(id) }

    /// Mac: yeni feed öğesi ekle (en üste), diske yaz. Çağıran ayrıca vault push tetikler.
    func add(_ item: FeedItem) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        trim()
        writeFile()
    }

    /// Sync: gelen feed.json'u id bazında BİRLEŞTİR (append-only — hiçbir öğe kaybolmaz).
    func mergeIncoming(_ data: Data) {
        guard let incoming = try? Self.decoder.decode([FeedItem].self, from: data) else { return }
        var byID: [String: FeedItem] = [:]
        for it in items { byID[it.id] = it }
        for it in incoming { byID[it.id] = it }
        items = byID.values.sorted { $0.createdAt > $1.createdAt }
        trim()
        writeFile()
        NotificationCenter.default.post(name: .herculesFeedUpdated, object: nil)
    }

    func reloadFromDisk() {
        items = Self.load(from: url)
    }

    func markSeen(_ id: String) {
        guard !seenIDs.contains(id) else { return }
        seenIDs.insert(id)
        persistSeen()
    }

    func markAllSeen() {
        let all = Set(items.map(\.id))
        guard !all.isSubset(of: seenIDs) else { return }
        seenIDs.formUnion(all)
        persistSeen()
    }

    func clear() {
        items = []
        writeFile()
    }

    // MARK: - Private

    private func trim() {
        if items.count > Self.maxItems { items = Array(items.prefix(Self.maxItems)) }
    }

    private func persistSeen() {
        UserDefaults.standard.set(Array(seenIDs), forKey: Self.seenKey)
    }

    private func writeFile() {
        guard let data = try? Self.encoder.encode(items) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static func load(from url: URL) -> [FeedItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? decoder.decode([FeedItem].self, from: data)
        else { return [] }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    private static func makeURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension Notification.Name {
    static let herculesFeedUpdated = Notification.Name("hercules.feed.updated")
}
