import Foundation
import CryptoKit
import Security
import SwiftData
import Observation
import SwiftUI

struct HerculesChatHistoryPayload: Codable, Sendable {
    var version: Int
    var savedAt: Date
    var currentConversationID: UUID?
    var conversations: [ChatConversation]
    var memoryBackfilledUserTurnIDs: [UUID]?
}

struct HerculesConversationMemoryPair: Equatable, Sendable {
    var userTurnID: UUID
    var userText: String
    var assistantText: String
}

enum HerculesMemoryBackfillLedger {
    static func pairs(
        in conversations: [ChatConversation],
        excluding processedIDs: Set<UUID>
    ) -> [HerculesConversationMemoryPair] {
        conversations.flatMap { conversation in
            pairs(in: conversation.messages).filter {
                !processedIDs.contains($0.userTurnID)
            }
        }
    }

    static func allUserTurnIDs(in conversations: [ChatConversation]) -> Set<UUID> {
        Set(conversations.flatMap(\.messages).filter { $0.role == .user }.map(\.id))
    }

    private static func pairs(in messages: [ChatTurn]) -> [HerculesConversationMemoryPair] {
        var pairs: [HerculesConversationMemoryPair] = []
        var pendingUser: ChatTurn?
        var assistantParts: [String] = []

        for turn in messages {
            switch turn.role {
            case .user:
                if let pendingUser {
                    pairs.append(HerculesConversationMemoryPair(
                        userTurnID: pendingUser.id,
                        userText: pendingUser.text,
                        assistantText: assistantParts.joined(separator: "\n")
                    ))
                }
                pendingUser = turn
                assistantParts = []
            case .assistant:
                if pendingUser != nil {
                    assistantParts.append(turn.text)
                }
            }
        }

        if let pendingUser {
            pairs.append(HerculesConversationMemoryPair(
                userTurnID: pendingUser.id,
                userText: pendingUser.text,
                assistantText: assistantParts.joined(separator: "\n")
            ))
        }
        return pairs
    }
}

enum HerculesChatHistoryVault {
    enum VaultError: LocalizedError {
        case keyUnavailable(OSStatus)
        case keyMissingForExistingHistory
        case invalidKey
        case invalidEnvelope
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .keyUnavailable(let status):
                return "Sohbet geçmişi anahtarına erişilemiyor (Keychain \(status))."
            case .keyMissingForExistingHistory:
                return "Şifreli sohbet geçmişi var ama cihaz anahtarı bulunamadı."
            case .invalidKey:
                return "Sohbet geçmişi anahtarı geçersiz."
            case .invalidEnvelope:
                return "Şifreli sohbet geçmişi dosya formatı geçersiz."
            case .authenticationFailed:
                return "Sohbet geçmişinin bütünlük doğrulaması başarısız."
            }
        }
    }

    private enum KeyRead {
        case found(Data)
        case notFound
        case failed(OSStatus)
    }

    // Agent-memory kasasından bilerek farklı service/account, magic ve AAD.
    private static let service = "com.hercules.chat-history"
    private static let account = "aes-gcm-device-key-v1"
    private static let magic = Data([0x48, 0x43, 0x48, 0x56]) // HCHV
    private static let version: UInt8 = 1
    static let aad = "com.hercules.chat-history:v1"
    private static let lock = NSLock()

    static func seal(_ plaintext: Data, allowKeyCreation: Bool) throws -> Data {
        let key = try key(allowCreation: allowKeyCreation)
        return try seal(plaintext, using: key)
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: Data(aad.utf8)
        )
        guard let combined = sealed.combined else { throw VaultError.invalidEnvelope }
        var output = magic
        output.append(version)
        output.append(combined)
        return output
    }

    static func open(_ envelope: Data) throws -> Data {
        let key = try key(allowCreation: false)
        return try open(envelope, using: key)
    }

    static func open(_ envelope: Data, using key: SymmetricKey) throws -> Data {
        guard envelope.count > magic.count + 1,
              envelope.prefix(magic.count) == magic,
              envelope[magic.count] == version
        else { throw VaultError.invalidEnvelope }
        do {
            let box = try AES.GCM.SealedBox(
                combined: Data(envelope.dropFirst(magic.count + 1))
            )
            return try AES.GCM.open(
                box,
                using: key,
                authenticating: Data(aad.utf8)
            )
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.authenticationFailed
        }
    }

    private static func key(allowCreation: Bool) throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        switch readKey() {
        case .found(let raw):
            guard raw.count == 32 else { throw VaultError.invalidKey }
            return SymmetricKey(data: raw)
        case .failed(let status):
            throw VaultError.keyUnavailable(status)
        case .notFound:
            guard allowCreation else { throw VaultError.keyMissingForExistingHistory }
            let key = SymmetricKey(size: .bits256)
            let raw = key.withUnsafeBytes { Data($0) }
            let status = addKey(raw)
            if status == errSecSuccess {
                return key
            }
            if status == errSecDuplicateItem,
               case .found(let existing) = readKey(),
               existing.count == 32 {
                return SymmetricKey(data: existing)
            }
            throw VaultError.keyUnavailable(status)
        }
    }

    private static func readKey() -> KeyRead {
#if os(macOS)
        // Önce data-protection Keychain. Daha önce flagsiz yaratılmış aynı chat
        // key'i varsa aynı baytları DP + ThisDeviceOnly item'a taşı; iki domain
        // farklı değer içeriyorsa hiçbirini seçmeden fail closed.
        let protected = rawReadKey(dataProtection: true)
        let legacy = rawReadKey(dataProtection: false)
        switch (protected, legacy) {
        case (.failed(let status), _), (_, .failed(let status)):
            return .failed(status)
        case (.found(let protectedRaw), .found(let legacyRaw)):
            guard protectedRaw == legacyRaw else { return .failed(errSecDecode) }
            let status = deleteKey(dataProtection: false)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                return .failed(status)
            }
            return .found(protectedRaw)
        case (.found(let raw), .notFound):
            return .found(raw)
        case (.notFound, .found(let raw)):
            let addStatus = addKey(raw)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem,
                  case .found(let migrated) = rawReadKey(dataProtection: true),
                  migrated == raw
            else {
                return .failed(addStatus == errSecSuccess ? errSecDecode : addStatus)
            }
            let deleteStatus = deleteKey(dataProtection: false)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                return .failed(deleteStatus)
            }
            return .found(raw)
        case (.notFound, .notFound):
            return .notFound
        }
#else
        return rawReadKey()
#endif
    }

    private static func addKey(_ raw: Data) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: raw,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
#if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
#endif
        return SecItemAdd(query as CFDictionary, nil)
    }

#if os(macOS)
    private static func deleteKey(dataProtection: Bool) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtection
        ]
        return SecItemDelete(query as CFDictionary)
    }

    private static func rawReadKey(dataProtection: Bool) -> KeyRead {
        var query = baseReadQuery()
        query[kSecUseDataProtectionKeychain as String] = dataProtection
        return executeRead(query)
    }
#else
    private static func rawReadKey() -> KeyRead {
        executeRead(baseReadQuery())
    }
#endif

    private static func baseReadQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
    }

    private static func executeRead(_ query: [String: Any]) -> KeyRead {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .failed(errSecDecode) }
            return .found(data)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed(status)
        }
    }
}

enum HerculesChatHistoryMigration {
    struct Crypto {
        var seal: (Data) throws -> Data
        var open: (Data) throws -> Data

        static let live = Crypto(
            seal: { try HerculesChatHistoryVault.seal($0, allowKeyCreation: true) },
            open: { try HerculesChatHistoryVault.open($0) }
        )
    }

    /// Yeni ciphertext ayrı bir temp dosyada yazılıp tekrar decrypt edilmeden legacy
    /// JSON'a dokunulmaz. `moveItem` mevcut hedefi overwrite etmez.
    static func migrate(
        plaintext: Data,
        legacyURL: URL,
        encryptedURL: URL,
        crypto: Crypto = .live
    ) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: encryptedURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }

        HerculesFileHardening.hardenFile(legacyURL)
        let temporaryURL = encryptedURL.deletingLastPathComponent()
            .appendingPathComponent(".chat-history-migration-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temporaryURL) }

        let envelope = try crypto.seal(plaintext)
        try envelope.write(to: temporaryURL, options: [.atomic])
        HerculesFileHardening.hardenFile(temporaryURL)
        let written = try Data(contentsOf: temporaryURL, options: [.mappedIfSafe])
        guard written == envelope, try crypto.open(written) == plaintext else {
            throw HerculesChatHistoryVault.VaultError.authenticationFailed
        }

        try fm.moveItem(at: temporaryURL, to: encryptedURL)
        HerculesFileHardening.hardenFile(encryptedURL)
        let committed = try Data(contentsOf: encryptedURL, options: [.mappedIfSafe])
        guard committed == envelope, try crypto.open(committed) == plaintext else {
            throw HerculesChatHistoryVault.VaultError.authenticationFailed
        }
        try fm.removeItem(at: legacyURL)
    }
}

private enum HerculesChatHistoryDiagnostics {
    static func report(_ error: Error, operation: String) {
        let description = error.localizedDescription
        AppLog.persistence.error(
            "Chat history \(operation, privacy: .public) failed: \(description, privacy: .public)"
        )
        Task { @MainActor in
            SaveErrorReporter.shared.message =
                "Sohbet geçmişi işlemi başarısız (\(operation)): \(description)"
        }
    }
}

actor HerculesChatHistoryWriter {
    typealias Sealer = @Sendable (_ plaintext: Data, _ allowKeyCreation: Bool) throws -> Data
    typealias Opener = @Sendable (_ envelope: Data) throws -> Data

    enum Operation: Sendable {
        case save(HerculesChatHistoryPayload)
        case delete
    }

    private struct Request: Sendable {
        var operation: Operation
        var url: URL
        var sequence: Int
    }

    private var latestSequence = 0
    private var latestCommittedSequence = 0
    private var pending: Request?
    private var workerTask: Task<Void, Never>?
    private let sealer: Sealer
    private let opener: Opener

    init(
        sealer: @escaping Sealer = { plaintext, allowKeyCreation in
            try HerculesChatHistoryVault.seal(
                plaintext,
                allowKeyCreation: allowKeyCreation
            )
        },
        opener: @escaping Opener = { try HerculesChatHistoryVault.open($0) }
    ) {
        self.sealer = sealer
        self.opener = opener
    }

    func enqueue(operation: Operation, url: URL, sequence: Int) {
        guard sequence >= latestSequence else { return }
        latestSequence = sequence
        pending = Request(operation: operation, url: url, sequence: sequence)
        startWorkerIfNeeded()
    }

    func flush(through sequence: Int? = nil) async -> Bool {
        while let workerTask {
            await workerTask.value
        }
        return sequence.map { latestCommittedSequence >= $0 } ?? true
    }

    private func startWorkerIfNeeded() {
        guard workerTask == nil else { return }
        workerTask = Task { [weak self] in
            // Aynı main-actor turunda gelen snapshot'ların sonuncusunu coalesce et.
            await Task.yield()
            await self?.drain()
        }
    }

    private func drain() {
        while let request = pending {
            pending = nil
            do {
                try perform(request)
                latestCommittedSequence = max(latestCommittedSequence, request.sequence)
            } catch {
                HerculesChatHistoryDiagnostics.report(error, operation: "disk yazımı")
            }
        }
        workerTask = nil
        if pending != nil {
            startWorkerIfNeeded()
        }
    }

    private func perform(_ request: Request) throws {
        let fm = FileManager.default
        switch request.operation {
        case .delete:
            guard fm.fileExists(atPath: request.url.path) else { return }
            try fm.removeItem(at: request.url)
        case .save(let payload):
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // .sortedKeys determinizm için (aynı içerik → aynı bayt); .prettyPrinted
            // şifreli blob'u kimse okumadığı hâlde encode süresini ve boyutu şişiriyordu.
            encoder.outputFormatting = [.sortedKeys]
            let plaintext = try encoder.encode(payload)
            let envelope = try sealer(
                plaintext,
                !fm.fileExists(atPath: request.url.path)
            )
            let temporaryURL = request.url.deletingLastPathComponent()
                .appendingPathComponent(".chat-history-write-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: temporaryURL) }
            try envelope.write(to: temporaryURL, options: [.atomic])
            HerculesFileHardening.hardenFile(temporaryURL)
            let staged = try Data(contentsOf: temporaryURL, options: [.mappedIfSafe])
            guard staged == envelope, try opener(staged) == plaintext else {
                throw HerculesChatHistoryVault.VaultError.authenticationFailed
            }

            if fm.fileExists(atPath: request.url.path) {
                _ = try fm.replaceItemAt(
                    request.url,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fm.moveItem(at: temporaryURL, to: request.url)
            }
            HerculesFileHardening.hardenFile(request.url)
            let committed = try Data(contentsOf: request.url, options: [.mappedIfSafe])
            guard committed == envelope, try opener(committed) == plaintext else {
                throw HerculesChatHistoryVault.VaultError.authenticationFailed
            }
        }
    }
}

@MainActor
@Observable
final class ChatStore {
    var messages: [ChatTurn] = []
    var conversations: [ChatConversation] = []
    var currentConversationID: UUID?
    var input: String = ""
    var pendingImages: [Data] = []   // composer'da bekleyen ekli görseller (gönderince temizlenir)
    var isSending: Bool = false
    var searchingFor: String? = nil
    var lastError: String? = nil
    var lastUsedUserData: Bool = false

    @ObservationIgnored private var client: AIClient = AIKeyStore.shared.makeClient()
    @ObservationIgnored private var notificationToken: NSObjectProtocol?
    @ObservationIgnored private var historyWriteTask: Task<Void, Never>?
    @ObservationIgnored private var memoryBackfillTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var typewriterTask: Task<Void, Never>?
    @ObservationIgnored private var activeSendID: UUID?
    @ObservationIgnored private let historyWriter = HerculesChatHistoryWriter()
    @ObservationIgnored private var historyWriteSequence = 0
    @ObservationIgnored private let historyURLs = ChatStore.makeHistoryURLs()
    @ObservationIgnored private var historyWritesAllowed = true
    @ObservationIgnored private var memoryBackfilledUserTurnIDs: Set<UUID> = []
    @ObservationIgnored private let agentRouter: AgentRouter = .shared

    private static let historyRetention: TimeInterval = 7 * 24 * 60 * 60
    private static let memoryBackfillKey = "hercules.memory.backfill.v3.signature"

    private struct LegacyHistoryPayload: Codable, Sendable {
        var version: Int
        var savedAt: Date
        var messages: [ChatTurn]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        loadHistory()
        backfillMemoriesFromHistoryIfNeeded()
        notificationToken = NotificationCenter.default.addObserver(
            forName: .aiClientChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadClient() }
        }
    }

    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
        // En son submission actor'a ulaştıktan sonra writer'ın kendi kuyruğunu bitir.
        // Bu task writer'ı canlı tutar; ChatStore teardown'u son snapshot'ı iptal etmez.
        let finalSubmission = historyWriteTask
        let writer = historyWriter
        Task(priority: .userInitiated) {
            await finalSubmission?.value
            _ = await writer.flush()
        }
        memoryBackfillTask?.cancel()
    }

    /// Sağlayıcı/model değişti, istemciyi yeniden kur.
    func reloadClient() {
        client = AIKeyStore.shared.makeClient()
    }

    func reloadHistoryFromDisk() {
        guard !isSending else { return }
        loadHistory()
        backfillMemoriesFromHistoryIfNeeded()
        input = ""
        lastError = nil
        searchingFor = nil
        lastUsedUserData = false
    }

    var conversationList: [ChatConversation] {
        conversations.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var currentConversationTitle: String {
        guard let currentConversationID,
              let conversation = conversations.first(where: { $0.id == currentConversationID })
        else { return "Yeni sohbet" }
        return conversation.title
    }

    func newChat() {
        guard !isSending else { return }
        if messages.isEmpty, currentConversationID != nil {
            input = ""
            lastError = nil
            return
        }

        syncCurrentConversation()
        let conversation = ChatConversation(title: "Yeni sohbet")
        conversations.insert(conversation, at: 0)
        currentConversationID = conversation.id
        messages = []
        input = ""
        lastError = nil
        lastUsedUserData = false
        persistHistory()
    }

    func selectConversation(_ id: UUID) {
        guard !isSending else { return }
        syncCurrentConversation()
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        currentConversationID = conversation.id
        messages = Self.cleanMessages(conversation.messages)
        input = ""
        lastError = nil
        searchingFor = nil
        lastUsedUserData = false
        persistHistory()
    }

    /// Gönderimi kendi Task'ında başlatır; handle'ı saklar ki "Dur" butonu iptal edebilsin.
    func startSend(userContext: String? = nil, skillData: AgentDataSnapshot? = nil, ctx: ModelContext? = nil) {
        guard !isSending, sendTask == nil else { return }
        let requestID = UUID()
        activeSendID = requestID
        isSending = true
        sendTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.send(
                userContext: userContext,
                skillData: skillData,
                ctx: ctx,
                requestID: requestID
            )
            self.finishSend(requestID)
        }
    }

    /// Devam eden AI gönderimini durdurur (network + sonuç uygulaması iptal edilir).
    func stop() {
        sendTask?.cancel()
        typewriterTask?.cancel()
        searchingFor = nil
        // isSending, task gerçekten unwind edene kadar true kalır. Böylece eski task
        // sürerken yeni send başlayıp aynı messages/actions state'ini bozamaz.
    }

    private func finishSend(_ requestID: UUID) {
        guard activeSendID == requestID else { return }
        activeSendID = nil
        sendTask = nil
        typewriterTask = nil
        isSending = false
        searchingFor = nil
        persistHistory()
    }

    private func send(
        userContext: String? = nil,
        skillData: AgentDataSnapshot? = nil,
        ctx: ModelContext? = nil,
        requestID: UUID
    ) async {
        guard activeSendID == requestID else { return }
        if pruneExpiredConversations() {
            persistHistory()
        }

        let rawText = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard !rawText.isEmpty || !images.isEmpty else { return }
        // Görsel-yalnız mesajda modele/UI'a anlamlı bir metin ver.
        let text = (rawText.isEmpty && !images.isEmpty) ? "Bu görsele bakar mısın?" : rawText
        let requiresRecipeSource = AIConfig.requiresRecipeWebSearch(text)
        ensureCurrentConversation()
        if images.isEmpty, let ctx, handleInlineApprovalReply(text, ctx: ctx) {
            input = ""
            lastError = nil
            return
        }
        input = ""
        pendingImages = []
        lastError = nil

        // Görselleri küçült + diske kaydet; tura id'leriyle bağla, modele küçültülmüş veriyi gönder.
        var imageIDs: [String] = []
        for data in images {
            if let id = ChatImageStore.save(data) { imageIDs.append(id) }
        }
        let outboundImages = imageIDs.compactMap { ChatImageStore.load($0) }

        let historyBeforeSend = Array(messages)
        let userTurn = ChatTurn(role: .user, text: text, imageIDs: imageIDs.isEmpty ? nil : imageIDs)
        messages.append(userTurn)
        // Streaming için boş assistant turn'ü önceden ekle — chunk geldikçe text güncellenir
        let assistantTurn = ChatTurn(role: .assistant, text: "")
        messages.append(assistantTurn)
        syncCurrentConversation(titleSeed: text)
        persistHistory()
        let assistantId = assistantTurn.id
        // Index'i ekledikten hemen sonra cache'le — her token update'inde
        // lastIndex(where:) O(n) scan etmemek için. Mesaj sırası mutate olmadığı
        // sürece geçerli (sadece user yeni mesaj göndermez bu duruma kadar).
        let cachedAssistantIdx = messages.count - 1
        searchingFor = nil

        let skillContext = await agentRouter.buildSkillContext(
            query: text,
            appContext: userContext,
            history: historyBeforeSend,
            dataSnapshot: skillData
        )
        guard activeSendID == requestID, !Task.isCancelled else {
            if cachedAssistantIdx < messages.count,
               messages[cachedAssistantIdx].id == assistantId,
               messages[cachedAssistantIdx].text.isEmpty {
                messages[cachedAssistantIdx].text = "⏹︎ Durduruldu"
            }
            syncCurrentConversation(titleSeed: text)
            persistHistory()
            return
        }
        let effectiveContext = Self.joinContext(appContext: userContext, skillContext: skillContext)
        lastUsedUserData = (effectiveContext != nil)

        // Cached index'in hala doğru olduğunu doğrulayan helper.
        // Mesaj listesi mutate olduysa (clear vs.) fallback olarak full scan.
        func assistantIdx() -> Int? {
            if cachedAssistantIdx < messages.count,
               messages[cachedAssistantIdx].id == assistantId {
                return cachedAssistantIdx
            }
            return messages.lastIndex(where: { $0.id == assistantId })
        }

        // Typewriter: model token'ları (genelde kelime parçaları) buffer'a yazılır;
        // ayrı bir döngü buffer'ı SABİT HIZLA harf harf açar → gerçek daktilo hissi.
        // Model bizden çok ileri giderse (buffer büyürse) kademeli hızlanır, geri kalmaz.
        //
        // Hedef metin [Character] olarak tutulur: `String.count`/`prefix` her tick'te
        // baştan grapheme yürüyüşü yapıyordu (tick başına O(n) ICU işi → mesaj başına
        // O(n²)); dizide count O(1), tick başına yalnız yeni açılan dilim eklenir.
        var pendingChars: [Character] = []   // modelden gelen tam birikmiş hedef metin
        var revealed = 0                     // şu an gösterilen karakter sayısı
        var revealedText = ""                // gösterilen prefix (append ile büyür)
        var streamComplete = false           // ağ akışı bitti mi (kuyruğu boşalt)

        func setPendingStream(_ value: String) {
            pendingChars = Array(value)
            // Hedef, açılmış olandan KISAYSA (retry/fallback bildirimi gibi bir
            // değiştirme) prefix'i hedefe hizala; yoksa daktilo sonsuza dek susardı.
            if revealed > pendingChars.count {
                revealed = pendingChars.count
                revealedText = String(pendingChars[0..<revealed])
                setAssistantTextWithoutAnimation(revealedText)
            }
        }

        func setAssistantTextWithoutAnimation(_ value: String) {
            guard let idx = assistantIdx(), messages[idx].text != value else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                messages[idx].text = value
            }
        }

        /// Tek tick — gösterilen prefix'i hedefe doğru ilerletir. Yakınken yavaş
        /// (daktilo), çok geride kalınca hızlanır. Açılacak metin kaldıysa true.
        func advanceTypewriter() -> Bool {
            let target = pendingChars.count
            guard revealed < target else { return false }
            let behind = target - revealed
            let step: Int
            if behind > 600 { step = max(12, behind / 24) }
            else if behind > 200 { step = 6 }
            else if behind > 60 { step = 3 }
            else { step = streamComplete ? 4 : 2 }
            let next = min(target, revealed + step)
            revealedText.append(contentsOf: pendingChars[revealed..<next])
            revealed = next
            setAssistantTextWithoutAnimation(revealedText)
            return revealed < target
        }

        // Akış boyunca ~16ms'de bir tick'leyen daktilo görevi.
        let typer = Task { @MainActor in
            while !Task.isCancelled {
                let more = advanceTypewriter()
                if !more && streamComplete { break }
                do {
                    try await Task.sleep(nanoseconds: 16_000_000)
                } catch {
                    break
                }
            }
        }
        typewriterTask = typer

        do {
            let (result, searchEvidence) = try await client.send(
                history: messages.dropLast(2), // hem user hem empty assistant turn'ünü çıkar
                newUserText: text,
                userContext: effectiveContext,
                images: outboundImages,
                onSearchStart: { [weak self] q in
                    guard self?.activeSendID == requestID else { return }
                    self?.searchingFor = q
                },
                onMessageUpdate: { partial in
                    guard self.activeSendID == requestID else { return }
                    setPendingStream(partial)   // hedefi güncelle; daktilo kendi hızıyla açar
                }
            )
            guard activeSendID == requestID else { throw CancellationError() }
            try Task.checkCancellation()   // "Dur"a basıldıysa sonucu uygulama
            let rawAssistantText = result.message.isEmpty
                ? (result.name ?? "—")
                : result.message
            let recipeSearchSatisfied = !requiresRecipeSource
                || (
                    searchEvidence?.completedSuccessfully == true
                    && searchEvidence?.sourceURLs.isEmpty == false
                )
            let assistantText = recipeSearchSatisfied
                ? rawAssistantText
                : "Kanka tarif konusunda kaynaksız cevap vermeyi kapattım. Web araması tetiklenmediği için tarif üretmedim; tekrar denediğinde kaynaklı tarif arayacağım."
            // Daktilonun nihai metni harf harf bitirmesini bekle, sonra kartı tamamla.
            setPendingStream(assistantText)
            streamComplete = true
            await typer.value
            guard activeSendID == requestID else { throw CancellationError() }
            try Task.checkCancellation()
            if let idx = assistantIdx() {
                setAssistantTextWithoutAnimation(assistantText)
                messages[idx].food = (recipeSearchSatisfied && result.isFood) ? result : nil
                messages[idx].actions = recipeSearchSatisfied ? result.actionList : []
                messages[idx].searchedFor = (
                    searchEvidence?.completedSuccessfully == true
                    && searchEvidence?.sourceURLs.isEmpty == false
                ) ? searchEvidence?.query : nil
                if let ctx, recipeSearchSatisfied {
                    applyAutomaticActions(in: idx, currentUserText: text, ctx: ctx)
                }
            }
            syncCurrentConversation(titleSeed: text)
            absorbConversationAndRecord(
                userTurnID: userTurn.id,
                userText: text,
                assistantText: assistantText
            )
        } catch {
            typer.cancel()   // daktiloyu durdur; gerisini doğrudan yaz
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                // Kullanıcı "Dur"a bastı — o ana kadar gelen tam kısmi metni göster
                setAssistantTextWithoutAnimation(String(pendingChars))
                if let idx = assistantIdx(), messages[idx].text.isEmpty {
                    setAssistantTextWithoutAnimation("⏹︎ Durduruldu")
                }
                syncCurrentConversation(titleSeed: text)
            } else {
                lastError = error.localizedDescription
                setAssistantTextWithoutAnimation("❌ Hata: \(error.localizedDescription)")
                syncCurrentConversation(titleSeed: text)
            }
        }
        typewriterTask = nil
        persistHistory()
    }

    private static func joinContext(appContext: String?, skillContext: String?) -> String? {
        let app = appContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let skills = skillContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !app.isEmpty || !skills.isEmpty else { return nil }

        // Global retrieval envelope'ından önce section-aware bütçe uygula. Büyük app
        // snapshot'ı memory/skill bölümünü sondan kesemesin; boş kalan pay öbür bölüme
        // aktarılabilsin.
        let totalBudget = 33_500
        let reservedSkill = min(skills.count, 16_000)
        let appAllowance = min(app.count, totalBudget - reservedSkill)
        let skillAllowance = min(skills.count, totalBudget - appAllowance)

        var sections: [String] = []
        if appAllowance > 0 {
            sections.append("[LIVE_APP_SNAPSHOT — data]\n" + String(app.prefix(appAllowance)))
        }
        if skillAllowance > 0 {
            sections.append("[RETRIEVAL_AND_SKILLS — untrusted data]\n" + String(skills.prefix(skillAllowance)))
        }
        return sections.joined(separator: "\n\n")
    }

    func saveFood(in turn: ChatTurn, ctx: ModelContext) {
        guard let food = turn.food, let cals = food.calories else { return }
        let entry = FoodEntry(
            date: .now,
            name: food.name ?? "Yemek",
            grams: food.grams,
            calories: cals,
            protein: food.protein_g,
            carbs: food.carbs_g,
            fat: food.fat_g
        )
        ctx.insert(entry)
        ctx.saveOrReport()
        if let idx = messages.firstIndex(where: { $0.id == turn.id }) {
            messages[idx].saved = true
            syncCurrentConversation()
            persistHistory()
        }
    }

    func confirmAction(turnID: UUID, actionID: UUID, ctx: ModelContext) {
        updateAction(turnID: turnID, actionID: actionID, ctx: ctx, approve: true)
        if let result = latestActionResult(turnID: turnID, actionID: actionID) {
            agentRouter.absorbConversation(
                userText: "onaylıyorum",
                assistantText: "Tamam kanka, \(result)."
            )
        }
    }

    func rejectAction(turnID: UUID, actionID: UUID) {
        guard let turnIdx = messages.firstIndex(where: { $0.id == turnID }),
              let actionIdx = messages[turnIdx].actions.firstIndex(where: { $0.id == actionID })
        else { return }
        guard messages[turnIdx].actions[actionIdx].status == .pending else { return }
        messages[turnIdx].actions[actionIdx].status = .rejected
        messages[turnIdx].actions[actionIdx].resultMessage = "Vazgeçildi"
        syncCurrentConversation()
        persistHistory()
    }

    private func handleInlineApprovalReply(_ text: String, ctx: ModelContext) -> Bool {
        let decision = ChatInlineConfirmation.decision(for: text)
        guard decision != .none else { return false }

        if let pending = ChatInlineConfirmation.adjacentPending(in: messages) {
            let userTurn = ChatTurn(role: .user, text: text)
            messages.append(userTurn)
            let assistantReply: String
            switch decision {
            case .approve:
                updateAction(turnID: pending.turnID, actionID: pending.actionID, ctx: ctx, approve: true)
                let result = latestActionResult(turnID: pending.turnID, actionID: pending.actionID)
                assistantReply = "Tamam kanka, \(result ?? "onayladığın işlemi uyguladım")."
            case .reject:
                rejectAction(turnID: pending.turnID, actionID: pending.actionID)
                assistantReply = "Tamam kanka, işlemi uygulamadım."
            case .none:
                return false
            }
            messages.append(ChatTurn(
                role: .assistant,
                text: assistantReply
            ))
            absorbConversationAndRecord(
                userTurnID: userTurn.id,
                userText: text,
                assistantText: assistantReply
            )
            syncCurrentConversation(titleSeed: text)
            persistHistory()
            return true
        }

        if decision == .approve, let applied = latestAppliedAutomaticAction() {
            messages.append(ChatTurn(role: .user, text: text))
            messages.append(ChatTurn(role: .assistant, text: alreadyAppliedReply(for: applied)))
            syncCurrentConversation(titleSeed: text)
            persistHistory()
            return true
        }

        return false
    }

    private func absorbConversationAndRecord(
        userTurnID: UUID,
        userText: String,
        assistantText: String
    ) {
        Task { @MainActor [weak self] in
            // Turn işlendiği sürece store'u canlı tut; aksi halde provider commit
            // edip ledger yazılamadan deinit olmak aynı turn'ü sonraki açılışta replay eder.
            guard let self else { return }
            await MemoryManager.shared.ingest(
                userText: userText,
                assistantText: assistantText
            )
            // Ingest completion means this historical turn must never be replayed,
            // including when a concurrent manual delete invalidated its write.
            self.memoryBackfilledUserTurnIDs.insert(userTurnID)
            self.persistHistory()
            let submission = self.historyWriteTask
            let committedSequence = self.historyWriteSequence
            await submission?.value
            _ = await self.historyWriter.flush(through: committedSequence)
        }
    }

    private func latestAppliedAutomaticAction() -> AIAppAction? {
        let cutoff = Date().addingTimeInterval(-10 * 60)
        guard let turn = messages.last,
              turn.role == .assistant,
              turn.createdAt >= cutoff
        else { return nil }
        return turn.actions.reversed().first {
            $0.status == .applied && !$0.requiresConfirmation
        }
    }

    private func latestActionResult(turnID: UUID, actionID: UUID) -> String? {
        guard let turn = messages.first(where: { $0.id == turnID }),
              let action = turn.actions.first(where: { $0.id == actionID })
        else { return nil }
        return action.resultMessage
    }

    private func alreadyAppliedReply(for action: AIAppAction) -> String {
        switch action.tool {
        case .logFood:
            return "Zaten bugüne eklemiştim kanka; tekrar kalori yazmadım."
        case .addRecipe:
            return "Zaten tariflere eklemiştim kanka; tekrar duplicate oluşturmadım."
        case .updateWorkoutPlan:
            return "Bu işlem zaten uygulanmış görünüyor kanka."
        }
    }

    private func updateAction(turnID: UUID, actionID: UUID, ctx: ModelContext, approve: Bool) {
        guard approve,
              let turnIdx = messages.firstIndex(where: { $0.id == turnID }),
              let actionIdx = messages[turnIdx].actions.firstIndex(where: { $0.id == actionID })
        else { return }
        guard messages[turnIdx].actions[actionIdx].status == .pending else { return }

        do {
            let result = try ChatActionExecutor.executeAction(messages[turnIdx].actions[actionIdx], ctx: ctx)
            messages[turnIdx].actions[actionIdx].status = .applied
            messages[turnIdx].actions[actionIdx].resultMessage = result
            if messages[turnIdx].actions[actionIdx].tool == .logFood {
                messages[turnIdx].saved = true
            }
        } catch {
            messages[turnIdx].actions[actionIdx].status = .failed
            messages[turnIdx].actions[actionIdx].resultMessage = error.localizedDescription
        }
        syncCurrentConversation()
        persistHistory()
    }

    private func applyAutomaticActions(in turnIdx: Int, currentUserText: String, ctx: ModelContext) {
        guard messages.indices.contains(turnIdx) else { return }
        var appliedKeys: Set<String> = []
        for actionIdx in messages[turnIdx].actions.indices {
            let action = messages[turnIdx].actions[actionIdx]
            guard action.status == .pending, !action.requiresConfirmation else { continue }
            guard ChatActionAuthorization.allowsAutomatic(action, currentUserText: currentUserText) else {
                messages[turnIdx].actions[actionIdx].status = .rejected
                messages[turnIdx].actions[actionIdx].resultMessage =
                    "Güncel kullanıcı mesajında açık kayıt yetkisi olmadığı için uygulanmadı"
                continue
            }
            let idempotencyKey = ChatActionAuthorization.idempotencyKey(for: action)
            guard appliedKeys.insert(idempotencyKey).inserted else {
                messages[turnIdx].actions[actionIdx].status = .rejected
                messages[turnIdx].actions[actionIdx].resultMessage =
                    "Aynı yanıttaki yinelenen işlem ikinci kez uygulanmadı"
                continue
            }
            do {
                let result = try ChatActionExecutor.executeAction(action, ctx: ctx)
                messages[turnIdx].actions[actionIdx].status = .applied
                messages[turnIdx].actions[actionIdx].resultMessage = result
                if action.tool == .logFood {
                    messages[turnIdx].saved = true
                }
            } catch {
                messages[turnIdx].actions[actionIdx].status = .failed
                messages[turnIdx].actions[actionIdx].resultMessage = error.localizedDescription
            }
        }
    }


    /// Rail'den tek bir konuşmayı sil. Yalnızca chat-history JSON'una dokunur
    /// (SwiftData store'a HİÇ dokunmaz). Silinen aktif konuşmaysa bir sonrakine geçer.
    func deleteConversation(_ id: UUID) {
        guard !isSending else { return }
        let wasCurrent = (id == currentConversationID)
        conversations.removeAll { $0.id == id }
        if wasCurrent {
            if let next = conversationList.first {
                currentConversationID = next.id
                messages = Self.cleanMessages(next.messages)
            } else {
                startBlankConversation()
            }
            input = ""
            lastError = nil
            searchingFor = nil
            lastUsedUserData = false
        }
        persistHistory()
    }

    func clear() {
        guard !isSending else { return }
        if let currentConversationID {
            conversations.removeAll { $0.id == currentConversationID }
        }

        if let next = conversationList.first {
            currentConversationID = next.id
            messages = Self.cleanMessages(next.messages)
        } else {
            let conversation = ChatConversation(title: "Yeni sohbet")
            conversations = [conversation]
            currentConversationID = conversation.id
            messages = []
        }
        input = ""
        lastError = nil
        searchingFor = nil
        lastUsedUserData = false
        persistHistory()
    }

    private static func makeHistoryURLs() -> (encrypted: URL, legacy: URL) {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        HerculesFileHardening.hardenDirectory(dir)
        return (
            encrypted: dir.appendingPathComponent("chat-history.herculesbox"),
            legacy: dir.appendingPathComponent("chat-history.json")
        )
    }

    private func backfillMemoriesFromHistoryIfNeeded() {
        memoryBackfillTask?.cancel()
        memoryBackfillTask = nil

        let pairs = HerculesMemoryBackfillLedger.pairs(
            in: conversations,
            excluding: memoryBackfilledUserTurnIDs
        )
        guard !pairs.isEmpty else { return }

        // Token task kuyruğa alınmadan önce yakalanır. Kullanıcı bu task
        // başlamadan hafızayı siler/düzenlerse eski chat snapshot'ı yazamaz.
        let provider = LocalMemoryProvider.shared
        let automaticWriteGeneration = provider.automaticWriteGeneration
        // [weak self]: task uzun bir durable-persist beklerken store kapatılırsa
        // self→task→closure→self döngüsü deinit'i (ve deinit'teki cancel'ı) kilitliyordu.
        memoryBackfillTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let persisted = await provider.absorbConversationsDurably(
                pairs.map { (userText: $0.userText, assistantText: $0.assistantText) },
                expectedAutomaticWriteGeneration: automaticWriteGeneration
            )
            guard persisted, let self else { return }

            // Provider commit'i artık geri alınamaz: cancellation gelse bile bu turn
            // ID'lerini encrypted history ledger'ına yazmayı dene. Böylece sonraki
            // chat değişikliği eski turn'leri (ve silinmiş memory'leri) diriltmez.
            self.memoryBackfilledUserTurnIDs.formUnion(pairs.map(\.userTurnID))
            self.persistHistory()
            let submission = self.historyWriteTask
            let committedSequence = self.historyWriteSequence
            await submission?.value
            let ledgerCommitted = await self.historyWriter.flush(through: committedSequence)
            if ledgerCommitted {
                // Önceki sürümden upgrade bootstrap'ı için marker'ı koru.
                UserDefaults.standard.set(
                    Self.memoryBackfillSignature(for: self.conversations),
                    forKey: Self.memoryBackfillKey
                )
            }
        }
    }

    private static func memoryBackfillSignature(for conversations: [ChatConversation]) -> String {
        conversations
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { conversation in
                let latest = conversation.messages.map(\.createdAt).max() ?? conversation.updatedAt
                return "\(conversation.id.uuidString):\(conversation.messages.count):\(Int(latest.timeIntervalSince1970))"
            }
            .joined(separator: "|")
    }

    private func loadHistory() {
        historyWritesAllowed = true
        let fm = FileManager.default
        let encryptedExists = fm.fileExists(atPath: historyURLs.encrypted.path)
        let legacyExists = fm.fileExists(atPath: historyURLs.legacy.path)
        guard encryptedExists || legacyExists else {
            memoryBackfilledUserTurnIDs = []
            startBlankConversation()
            return
        }

        let data: Data
        if encryptedExists {
            HerculesFileHardening.hardenFile(historyURLs.encrypted)
            do {
                let envelope = try Self.readBoundedHistoryFile(historyURLs.encrypted)
                data = try HerculesChatHistoryVault.open(envelope)
            } catch {
                historyWritesAllowed = false
                HerculesChatHistoryDiagnostics.report(error, operation: "şifreli geçmişi açma")
                startBlankConversation()
                return
            }

            // Önceki migration ciphertext'i doğrulayıp plaintext'i silemeden
            // kesildiyse, yalnız byte-for-byte aynı plaintext güvenle temizlenir.
            if legacyExists {
                HerculesFileHardening.hardenFile(historyURLs.legacy)
                do {
                    let legacy = try Self.readBoundedHistoryFile(historyURLs.legacy)
                    guard legacy == data else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try fm.removeItem(at: historyURLs.legacy)
                } catch {
                    historyWritesAllowed = false
                    HerculesChatHistoryDiagnostics.report(error, operation: "eski düz metni temizleme")
                }
            }
        } else {
            HerculesFileHardening.hardenFile(historyURLs.legacy)
            do {
                data = try Self.readBoundedHistoryFile(historyURLs.legacy)
                guard (try? Self.decoder.decode(HerculesChatHistoryPayload.self, from: data)) != nil
                        || (try? Self.decoder.decode(LegacyHistoryPayload.self, from: data)) != nil
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            } catch {
                historyWritesAllowed = false
                HerculesChatHistoryDiagnostics.report(error, operation: "eski sohbet geçmişini okuma")
                startBlankConversation()
                return
            }

            do {
                try HerculesChatHistoryMigration.migrate(
                    plaintext: data,
                    legacyURL: historyURLs.legacy,
                    encryptedURL: historyURLs.encrypted
                )
            } catch {
                // Legacy kaynak yerinde kalır; bu süreçte başka snapshot onun
                // önüne geçmesin. Sonraki reload migration'ı güvenle tekrar dener.
                historyWritesAllowed = false
                HerculesChatHistoryDiagnostics.report(error, operation: "şifreli geçmişe geçiş")
            }
        }

        let cutoff = Date().addingTimeInterval(-Self.historyRetention)
        if let payload = try? Self.decoder.decode(HerculesChatHistoryPayload.self, from: data) {
            conversations = payload.conversations
                .map { Self.normalizedConversation($0, cutoff: cutoff, currentID: payload.currentConversationID) }
                .filter { conversation in
                    if conversation.id == payload.currentConversationID {
                        return true
                    }
                    return !conversation.messages.isEmpty && conversation.updatedAt >= cutoff
                }
            if let persistedIDs = payload.memoryBackfilledUserTurnIDs {
                memoryBackfilledUserTurnIDs = Set(persistedIDs)
            } else if UserDefaults.standard.string(forKey: Self.memoryBackfillKey) != nil {
                // v2 history + tamamlanmış eski signature: bütün mevcut turn'ler
                // zaten işlenmiştir; upgrade sırasında yeniden replay etme.
                memoryBackfilledUserTurnIDs =
                    HerculesMemoryBackfillLedger.allUserTurnIDs(in: conversations)
            } else {
                memoryBackfilledUserTurnIDs = []
            }

            currentConversationID = payload.currentConversationID
            if let currentConversationID,
               let current = conversations.first(where: { $0.id == currentConversationID }) {
                messages = current.messages
            } else if let next = conversationList.first {
                currentConversationID = next.id
                messages = next.messages
            } else {
                startBlankConversation()
            }

            persistHistory()
            return
        }

        if let legacyPayload = try? Self.decoder.decode(LegacyHistoryPayload.self, from: data) {
            let cleanedMessages = Self.cleanMessages(legacyPayload.messages, cutoff: cutoff)
            if cleanedMessages.isEmpty {
                startBlankConversation()
            } else {
                let conversation = ChatConversation(
                    title: Self.title(from: cleanedMessages) ?? "Geçmiş sohbet",
                    messages: cleanedMessages,
                    createdAt: cleanedMessages.first?.createdAt ?? legacyPayload.savedAt,
                    updatedAt: cleanedMessages.last?.createdAt ?? legacyPayload.savedAt
                )
                conversations = [conversation]
                currentConversationID = conversation.id
                messages = cleanedMessages
            }
            if UserDefaults.standard.string(forKey: Self.memoryBackfillKey) != nil {
                memoryBackfilledUserTurnIDs =
                    HerculesMemoryBackfillLedger.allUserTurnIDs(in: conversations)
            } else {
                memoryBackfilledUserTurnIDs = []
            }
            persistHistory()
            return
        }

        // Kaynak dosyayı overwrite/silme: sürüm uyumsuzluğu veya bütünlük sorunu
        // çözülene kadar yeni write'ları fail-closed engelle.
        historyWritesAllowed = false
        HerculesChatHistoryDiagnostics.report(
            CocoaError(.fileReadCorruptFile),
            operation: "sohbet geçmişini çözümleme"
        )
        startBlankConversation()
    }

    private static func readBoundedHistoryFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= 64 * 1_024 * 1_024
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    @discardableResult
    private func pruneExpiredConversations() -> Bool {
        let cutoff = Date().addingTimeInterval(-Self.historyRetention)
        syncCurrentConversation()
        let before = conversations

        conversations = conversations.map { conversation in
            Self.normalizedConversation(conversation, cutoff: cutoff, currentID: currentConversationID)
        }
        conversations.removeAll { conversation in
            if conversation.id == currentConversationID {
                return false
            }
            return conversation.messages.isEmpty || conversation.updatedAt < cutoff
        }

        if let currentConversationID,
           let current = conversations.first(where: { $0.id == currentConversationID }) {
            messages = current.messages
        } else if let next = conversationList.first {
            currentConversationID = next.id
            messages = next.messages
        } else {
            startBlankConversation()
        }

        return before != conversations
    }

    private func persistHistory() {
        guard historyWritesAllowed else { return }
        syncCurrentConversation()
        let conversationsToPersist = conversations.filter { conversation in
            !conversation.messages.isEmpty || conversation.id == currentConversationID
        }
        let retainedUserTurnIDs =
            HerculesMemoryBackfillLedger.allUserTurnIDs(in: conversationsToPersist)
        memoryBackfilledUserTurnIDs.formIntersection(retainedUserTurnIDs)
        let hasSavedConversation = conversationsToPersist.contains { !$0.messages.isEmpty }
        let url = historyURLs.encrypted
        historyWriteSequence += 1
        let sequence = historyWriteSequence
        if !hasSavedConversation {
            historyWriteTask = Task(priority: .userInitiated) { [historyWriter] in
                await historyWriter.enqueue(
                    operation: .delete,
                    url: url,
                    sequence: sequence
                )
            }
            return
        }

        let payload = HerculesChatHistoryPayload(
            version: 3,
            savedAt: .now,
            currentConversationID: currentConversationID,
            conversations: conversationsToPersist,
            memoryBackfilledUserTurnIDs: memoryBackfilledUserTurnIDs.sorted {
                $0.uuidString < $1.uuidString
            }
        )
        historyWriteTask = Task(priority: .userInitiated) { [historyWriter] in
            await historyWriter.enqueue(
                operation: .save(payload),
                url: url,
                sequence: sequence
            )
        }
    }

    private func startBlankConversation() {
        let conversation = ChatConversation(title: "Yeni sohbet")
        conversations = [conversation]
        currentConversationID = conversation.id
        messages = []
    }

    private func ensureCurrentConversation() {
        if let currentConversationID,
           conversations.contains(where: { $0.id == currentConversationID }) {
            return
        }

        let conversation = ChatConversation(title: "Yeni sohbet")
        conversations.insert(conversation, at: 0)
        currentConversationID = conversation.id
    }

    private func syncCurrentConversation(titleSeed: String? = nil) {
        ensureCurrentConversation()
        guard let currentConversationID,
              let index = conversations.firstIndex(where: { $0.id == currentConversationID })
        else { return }

        conversations[index].messages = messages
        if let titleSeed, conversations[index].title == "Yeni sohbet" {
            conversations[index].title = Self.makeTitle(from: titleSeed)
        } else if conversations[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conversations[index].title = Self.title(from: messages) ?? "Yeni sohbet"
        }

        if let latest = messages.map(\.createdAt).max() {
            conversations[index].updatedAt = latest
        }
    }

    private static func normalizedConversation(
        _ conversation: ChatConversation,
        cutoff: Date,
        currentID: UUID?
    ) -> ChatConversation {
        var copy = conversation
        copy.messages = cleanMessages(copy.messages, cutoff: cutoff)
        if copy.messages.isEmpty {
            copy.title = copy.id == currentID ? "Yeni sohbet" : copy.title
        } else if copy.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.title = title(from: copy.messages) ?? "Sohbet"
        }
        if let latest = copy.messages.map(\.createdAt).max() {
            copy.updatedAt = latest
        }
        return copy
    }

    private static func cleanMessages(_ messages: [ChatTurn], cutoff: Date? = nil) -> [ChatTurn] {
        let cutoff = cutoff ?? Date().addingTimeInterval(-historyRetention)
        return messages.filter { turn in
            turn.createdAt >= cutoff &&
            !(turn.role == .assistant && turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private static func title(from messages: [ChatTurn]) -> String? {
        guard let firstUserMessage = messages.first(where: { $0.role == .user })?.text else {
            return nil
        }
        return makeTitle(from: firstUserMessage)
    }

    private static func makeTitle(from text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return "Yeni sohbet" }
        let limit = 42
        guard compact.count > limit else { return compact }
        let end = compact.index(compact.startIndex, offsetBy: limit)
        return String(compact[..<end]) + "..."
    }
}
