import Foundation
import SwiftData
import Observation
import SwiftUI

@MainActor
@Observable
final class ChatStore {
    var messages: [ChatTurn] = []
    var conversations: [ChatConversation] = []
    var currentConversationID: UUID?
    var input: String = ""
    var isSending: Bool = false
    var searchingFor: String? = nil
    var lastError: String? = nil
    var lastUsedUserData: Bool = false

    @ObservationIgnored private var client: AIClient = AIKeyStore.shared.makeClient()
    @ObservationIgnored private var notificationToken: NSObjectProtocol?
    @ObservationIgnored private var supportRestoreToken: NSObjectProtocol?
    @ObservationIgnored private var historyWriteTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private let historyWriter = HistoryWriter()
    @ObservationIgnored private var historyWriteSequence = 0
    @ObservationIgnored private let historyURL: URL = ChatStore.makeHistoryURL()
    @ObservationIgnored private let agentRouter: AgentRouter = .shared

    private static let historyRetention: TimeInterval = 7 * 24 * 60 * 60
    private static let memoryBackfillKey = "hercules.memory.backfill.v3.signature"

    private struct HistoryPayload: Codable, Sendable {
        var version: Int
        var savedAt: Date
        var currentConversationID: UUID?
        var conversations: [ChatConversation]
    }

    private struct LegacyHistoryPayload: Codable, Sendable {
        var version: Int
        var savedAt: Date
        var messages: [ChatTurn]
    }

    private actor HistoryWriter {
        private var latestSequence = 0

        func persist(payload: HistoryPayload?, url: URL, sequence: Int) {
            guard sequence >= latestSequence else { return }
            latestSequence = sequence

            guard let payload else {
                try? FileManager.default.removeItem(at: url)
                return
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(payload) else { return }
            try? data.write(to: url, options: [.atomic])
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
        supportRestoreToken = NotificationCenter.default.addObserver(
            forName: .herculesSupportFilesRestored,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadHistoryFromDisk() }
        }
    }

    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = supportRestoreToken {
            NotificationCenter.default.removeObserver(token)
        }
        historyWriteTask?.cancel()
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
        guard !isSending else { return }
        sendTask = Task { [weak self] in
            await self?.send(userContext: userContext, skillData: skillData, ctx: ctx)
            self?.sendTask = nil
        }
    }

    /// Devam eden AI gönderimini durdurur (network + sonuç uygulaması iptal edilir).
    func stop() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
        searchingFor = nil
        persistHistory()
    }

    func send(userContext: String? = nil, skillData: AgentDataSnapshot? = nil, ctx: ModelContext? = nil) async {
        if pruneExpiredConversations() {
            persistHistory()
        }

        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let requiresRecipeSource = AIConfig.requiresRecipeWebSearch(text)
        ensureCurrentConversation()
        if let ctx, handleInlineApprovalReply(text, ctx: ctx) {
            input = ""
            lastError = nil
            return
        }
        input = ""
        lastError = nil

        let historyBeforeSend = Array(messages)
        let userTurn = ChatTurn(role: .user, text: text)
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
        isSending = true
        searchingFor = nil

        let skillContext = await agentRouter.buildSkillContext(
            query: text,
            appContext: userContext,
            history: historyBeforeSend,
            dataSnapshot: skillData
        )
        let effectiveContext = Self.joinContext(userContext, skillContext)
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

        var pendingStreamText = ""
        var lastStreamFlush = Date.distantPast
        let streamFlushInterval: TimeInterval = 0.14
        let streamFlushCharacterBudget = 120

        func setAssistantTextWithoutAnimation(_ value: String) {
            guard let idx = assistantIdx(), messages[idx].text != value else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                messages[idx].text = value
            }
        }

        func flushStreamText(force: Bool = false) {
            guard !pendingStreamText.isEmpty, let idx = assistantIdx() else { return }
            let now = Date()
            let currentLength = pendingStreamText.count
            let characterBudget: Int
            let interval: TimeInterval
            if currentLength > 3_000 {
                characterBudget = 260
                interval = 0.24
            } else if currentLength > 1_200 {
                characterBudget = 180
                interval = 0.18
            } else {
                characterBudget = streamFlushCharacterBudget
                interval = streamFlushInterval
            }
            let grewEnough = currentLength - messages[idx].text.count >= characterBudget
            let waitedEnough = now.timeIntervalSince(lastStreamFlush) >= interval
            guard force || grewEnough || waitedEnough else { return }
            setAssistantTextWithoutAnimation(pendingStreamText)
            lastStreamFlush = now
        }

        do {
            let (result, searchQuery) = try await client.send(
                history: messages.dropLast(2), // hem user hem empty assistant turn'ünü çıkar
                newUserText: text,
                userContext: effectiveContext,
                onSearchStart: { [weak self] q in
                    self?.searchingFor = q
                },
                onMessageUpdate: { partial in
                    pendingStreamText = partial
                    flushStreamText()
                }
            )
            try Task.checkCancellation()   // "Dur"a basıldıysa sonucu uygulama
            flushStreamText(force: true)
            let rawAssistantText = result.message.isEmpty
                ? (result.name ?? "—")
                : result.message
            let recipeSearchSatisfied = !requiresRecipeSource || searchQuery != nil
            let assistantText = recipeSearchSatisfied
                ? rawAssistantText
                : "Kanka tarif konusunda kaynaksız cevap vermeyi kapattım. Web araması tetiklenmediği için tarif üretmedim; tekrar denediğinde kaynaklı tarif arayacağım."
            if let idx = assistantIdx() {
                setAssistantTextWithoutAnimation(assistantText)
                messages[idx].food = (recipeSearchSatisfied && result.isFood) ? result : nil
                messages[idx].actions = recipeSearchSatisfied ? result.actionList : []
                messages[idx].searchedFor = searchQuery
                if let ctx, recipeSearchSatisfied {
                    applyAutomaticActions(in: idx, ctx: ctx)
                }
            }
            syncCurrentConversation(titleSeed: text)
            agentRouter.absorbConversation(userText: text, assistantText: assistantText)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                // Kullanıcı "Dur"a bastı — kısmi metni koru, hata gösterme
                flushStreamText(force: true)
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

        isSending = false
        searchingFor = nil
        persistHistory()
    }

    private static func joinContext(_ parts: String?...) -> String? {
        let body = parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return body.isEmpty ? nil : body
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
        guard isApprovalReply(text) else { return false }

        if let pending = latestPendingConfirmationAction() {
            messages.append(ChatTurn(role: .user, text: text))
            updateAction(turnID: pending.turnID, actionID: pending.actionID, ctx: ctx, approve: true)
            let result = latestActionResult(turnID: pending.turnID, actionID: pending.actionID)
            let assistantReply = "Tamam kanka, \(result ?? "onayladığın işlemi uyguladım")."
            messages.append(ChatTurn(
                role: .assistant,
                text: assistantReply
            ))
            agentRouter.absorbConversation(userText: text, assistantText: assistantReply)
            syncCurrentConversation(titleSeed: text)
            persistHistory()
            return true
        }

        if let applied = latestAppliedAutomaticAction() {
            messages.append(ChatTurn(role: .user, text: text))
            messages.append(ChatTurn(role: .assistant, text: alreadyAppliedReply(for: applied)))
            syncCurrentConversation(titleSeed: text)
            persistHistory()
            return true
        }

        return false
    }

    private func isApprovalReply(_ text: String) -> Bool {
        let normalized = ChatActionExecutor.normalizedKey(text)
            .lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: #"[^a-z0-9ğüşöçıİĞÜŞÖÇ ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 42 else { return false }
        let exactMatches: Set<String> = [
            "evet", "tamam", "ok", "okay", "olur", "yap", "uygula", "ekle", "kaydet",
            "onayliyorum", "onaylıyorum", "onay veriyorum", "onayladim", "onayladım",
            "aynen", "tamamdir", "tamamdır"
        ]
        if exactMatches.contains(normalized) { return true }
        return normalized.hasPrefix("onay") || normalized.contains(" onay")
    }

    private func latestPendingConfirmationAction() -> (turnID: UUID, actionID: UUID, action: AIAppAction)? {
        for turn in messages.reversed() where turn.role == .assistant {
            if let action = turn.actions.reversed().first(where: { $0.status == .pending && $0.requiresConfirmation }) {
                return (turn.id, action.id, action)
            }
        }
        return nil
    }

    private func latestAppliedAutomaticAction() -> AIAppAction? {
        let cutoff = Date().addingTimeInterval(-10 * 60)
        for turn in messages.reversed() where turn.role == .assistant && turn.createdAt >= cutoff {
            if let action = turn.actions.reversed().first(where: { $0.status == .applied && !$0.requiresConfirmation }) {
                return action
            }
        }
        return nil
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

    private func applyAutomaticActions(in turnIdx: Int, ctx: ModelContext) {
        guard messages.indices.contains(turnIdx) else { return }
        for actionIdx in messages[turnIdx].actions.indices {
            let action = messages[turnIdx].actions[actionIdx]
            guard action.status == .pending, !action.requiresConfirmation else { continue }
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

    private static func makeHistoryURL() -> URL {
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
        return dir.appendingPathComponent("chat-history.json")
    }

    private func backfillMemoriesFromHistoryIfNeeded() {
        let signature = Self.memoryBackfillSignature(for: conversations)
        guard !signature.isEmpty,
              UserDefaults.standard.string(forKey: Self.memoryBackfillKey) != signature
        else { return }

        var absorbed = 0
        for conversation in conversations {
            for pair in Self.conversationPairs(from: conversation.messages) {
                absorbed += LocalMemoryProvider.shared.absorbConversation(
                    userText: pair.userText,
                    assistantText: pair.assistantText
                )
            }
        }

        if absorbed > 0 {
            LocalMemoryProvider.shared.reloadFromDisk()
        }
        UserDefaults.standard.set(signature, forKey: Self.memoryBackfillKey)
    }

    private static func conversationPairs(from messages: [ChatTurn]) -> [(userText: String, assistantText: String)] {
        var pairs: [(userText: String, assistantText: String)] = []
        var pendingUser: String?
        var assistantParts: [String] = []

        for turn in messages {
            switch turn.role {
            case .user:
                if let pendingUser {
                    pairs.append((pendingUser, assistantParts.joined(separator: "\n")))
                }
                pendingUser = turn.text
                assistantParts = []
            case .assistant:
                if pendingUser != nil {
                    assistantParts.append(turn.text)
                }
            }
        }

        if let pendingUser {
            pairs.append((pendingUser, assistantParts.joined(separator: "\n")))
        }
        return pairs
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
        guard let data = try? Data(contentsOf: historyURL) else {
            startBlankConversation()
            return
        }

        let cutoff = Date().addingTimeInterval(-Self.historyRetention)
        if let payload = try? Self.decoder.decode(HistoryPayload.self, from: data) {
            conversations = payload.conversations
                .map { Self.normalizedConversation($0, cutoff: cutoff, currentID: payload.currentConversationID) }
                .filter { conversation in
                    if conversation.id == payload.currentConversationID {
                        return true
                    }
                    return !conversation.messages.isEmpty && conversation.updatedAt >= cutoff
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
            persistHistory()
            return
        }

        startBlankConversation()
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
        syncCurrentConversation()
        let conversationsToPersist = conversations.filter { conversation in
            !conversation.messages.isEmpty || conversation.id == currentConversationID
        }
        let hasSavedConversation = conversationsToPersist.contains { !$0.messages.isEmpty }
        let url = historyURL
        historyWriteSequence += 1
        let sequence = historyWriteSequence
        historyWriteTask?.cancel()
        if !hasSavedConversation {
            historyWriteTask = Task(priority: .utility) { [historyWriter] in
                guard !Task.isCancelled else { return }
                await historyWriter.persist(payload: nil, url: url, sequence: sequence)
            }
            return
        }

        let payload = HistoryPayload(
            version: 2,
            savedAt: .now,
            currentConversationID: currentConversationID,
            conversations: conversationsToPersist
        )
        historyWriteTask = Task(priority: .utility) { [historyWriter] in
            guard !Task.isCancelled else { return }
            await historyWriter.persist(payload: payload, url: url, sequence: sequence)
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
