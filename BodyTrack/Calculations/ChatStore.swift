import Foundation
import SwiftData
import Observation

private enum AppToolError: LocalizedError {
    case missing(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missing(let detail): return detail
        case .unsupported(let detail): return detail
        }
    }
}

struct ChatConversation: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatTurn]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatTurn] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

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
    @ObservationIgnored private let historyURL: URL = ChatStore.makeHistoryURL()
    @ObservationIgnored private let agentRouter: AgentRouter = .shared

    private static let historyRetention: TimeInterval = 7 * 24 * 60 * 60

    private struct HistoryPayload: Codable {
        var version: Int
        var savedAt: Date
        var currentConversationID: UUID?
        var conversations: [ChatConversation]
    }

    private struct LegacyHistoryPayload: Codable {
        var version: Int
        var savedAt: Date
        var messages: [ChatTurn]
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
    }

    /// Sağlayıcı/model değişti, istemciyi yeniden kur.
    func reloadClient() {
        client = AIKeyStore.shared.makeClient()
    }

    func reloadHistoryFromDisk() {
        guard !isSending else { return }
        loadHistory()
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

    func send(userContext: String? = nil, ctx: ModelContext? = nil) async {
        if pruneExpiredConversations() {
            persistHistory()
        }

        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
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
            history: historyBeforeSend
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

        do {
            let (result, searchQuery) = try await client.send(
                history: messages.dropLast(2), // hem user hem empty assistant turn'ünü çıkar
                newUserText: text,
                userContext: effectiveContext,
                onSearchStart: { [weak self] q in
                    self?.searchingFor = q
                },
                onMessageUpdate: { [weak self] partial in
                    guard let self else { return }
                    if let idx = assistantIdx() {
                        self.messages[idx].text = partial
                    }
                }
            )
            let assistantText = result.message.isEmpty
                ? (result.name ?? "—")
                : result.message
            if let idx = assistantIdx() {
                messages[idx].text = assistantText
                messages[idx].food = result.isFood ? result : nil
                messages[idx].actions = result.actionList
                messages[idx].searchedFor = searchQuery
                if let ctx {
                    applyAutomaticActions(in: idx, ctx: ctx)
                }
            }
            syncCurrentConversation(titleSeed: text)
            agentRouter.absorbConversation(userText: text, assistantText: assistantText)
        } catch {
            lastError = error.localizedDescription
            if let idx = assistantIdx() {
                messages[idx].text = "❌ Hata: \(error.localizedDescription)"
            }
            syncCurrentConversation(titleSeed: text)
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
        try? ctx.save()
        if let idx = messages.firstIndex(where: { $0.id == turn.id }) {
            messages[idx].saved = true
            syncCurrentConversation()
            persistHistory()
        }
    }

    func confirmAction(turnID: UUID, actionID: UUID, ctx: ModelContext) {
        updateAction(turnID: turnID, actionID: actionID, ctx: ctx, approve: true)
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
            messages.append(ChatTurn(
                role: .assistant,
                text: "Tamam kanka, \(result ?? "onayladığın işlemi uyguladım")."
            ))
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
        let normalized = normalizedKey(text)
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
        case .updateWorkoutPlan, .updateMealPlan:
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
            let result = try executeAction(messages[turnIdx].actions[actionIdx], ctx: ctx)
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
                let result = try executeAction(action, ctx: ctx)
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

    @discardableResult
    private func executeAction(_ action: AIAppAction, ctx: ModelContext) throws -> String {
        switch action.tool {
        case .logFood:
            let name = nonEmpty(action.name ?? action.itemName, fallback: "Yemek")
            guard let calories = action.calories else {
                throw AppToolError.missing("Kalori değeri yok")
            }
            ctx.insert(FoodEntry(
                date: .now,
                name: name,
                grams: action.grams ?? action.amount,
                calories: calories,
                protein: action.proteinG,
                carbs: action.carbsG,
                fat: action.fatG
            ))
            try ctx.save()
            return "\(name) bugüne eklendi"

        case .addRecipe:
            let title = nonEmpty(action.title ?? action.name, fallback: "")
            guard !title.isEmpty else {
                throw AppToolError.missing("Tarif başlığı yok")
            }
            let rawCategory = action.category ?? RecipeCategory.dinner.rawValue
            let category = RecipeCategory(rawValue: rawCategory) ?? .dinner
            let recipes = (try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []
            if let existing = recipes.first(where: {
                $0.category == category && normalizedKey($0.title) == normalizedKey(title)
            }) {
                existing.title = title
                existing.category = category
                applyRecipeDetails(from: action, title: title, to: existing)
                existing.createdAt = .now
                try ctx.save()
                return "\(title) zaten vardı, tarif güncellendi"
            }

            let recipe = Recipe(title: title, urlString: "", category: category)
            applyRecipeDetails(from: action, title: title, to: recipe)
            ctx.insert(recipe)
            try ctx.save()
            return "\(title) tariflere eklendi"

        case .updateWorkoutPlan:
            let weekday = try validWeekday(action.weekday)
            let workoutOperation = action.workoutOperation ?? (action.exerciseName == nil ? "set_session" : "add_exercise")
            if workoutOperation == "add_exercise" {
                let exerciseName = nonEmpty(action.exerciseName ?? action.name, fallback: "")
                guard !exerciseName.isEmpty else {
                    throw AppToolError.missing("Eklenecek hareket adı yok")
                }
                let overrides = (try? ctx.fetch(FetchDescriptor<WorkoutPlanOverride>())) ?? []
                if let existing = overrides.first(where: {
                    $0.weekday == weekday && normalizedKey($0.exerciseName) == normalizedKey(exerciseName)
                }) {
                    existing.sets = action.sets ?? existing.sets
                    existing.reps = action.reps ?? existing.reps
                    existing.weight = action.weight ?? existing.weight
                    existing.note = action.summary ?? existing.note
                    existing.source = "ai"
                    existing.createdAt = .now
                } else {
                    ctx.insert(WorkoutPlanOverride(
                        weekday: weekday,
                        exerciseName: exerciseName,
                        sets: action.sets,
                        reps: action.reps,
                        weight: action.weight,
                        note: action.summary,
                        source: "ai"
                    ))
                }
                try ctx.save()
                return "\(WorkoutSession.weekdayNames[weekday]) planına \(exerciseName) eklendi"
            }

            let name = nonEmpty(action.name, fallback: "")
            guard !name.isEmpty else {
                throw AppToolError.missing("Antrenman adı yok")
            }
            let workouts = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
            if let existing = workouts.first(where: { $0.weekday == weekday }) {
                existing.name = name
                if let kcal = action.estimatedCalories {
                    existing.estimatedCalories = kcal
                }
            } else {
                ctx.insert(WorkoutSession(
                    weekday: weekday,
                    name: name,
                    estimatedCalories: action.estimatedCalories ?? 300
                ))
            }
            try ctx.save()
            return "\(WorkoutSession.weekdayNames[weekday]) antrenmanı güncellendi"

        case .updateMealPlan:
            let weekday = try validWeekday(action.weekday)
            let operation = action.mealOperation ?? "add_item"
            switch operation {
            case "set_day_type":
                guard let raw = action.dayType,
                      let dayType = MealDayType(rawValue: raw)
                else {
                    throw AppToolError.missing("Yemek günü tipi yok")
                }
                let overrides = (try? ctx.fetch(FetchDescriptor<MealPlanOverride>())) ?? []
                for old in overrides where old.weekday == weekday && old.operation == .setDayType {
                    ctx.delete(old)
                }
                ctx.insert(MealPlanOverride(
                    weekday: weekday,
                    operation: .setDayType,
                    dayType: dayType,
                    note: action.summary,
                    source: "ai"
                ))
                try ctx.save()
                return "\(WorkoutSession.weekdayNames[weekday]) yemek günü \(dayType.label) oldu"

            case "add_item":
                guard let rawSlot = action.mealSlot,
                      let slot = MealSlot(rawValue: rawSlot)
                else {
                    throw AppToolError.missing("Öğün bilgisi yok")
                }
                let itemName = nonEmpty(action.itemName ?? action.name, fallback: "")
                guard !itemName.isEmpty else {
                    throw AppToolError.missing("Eklenecek yemek adı yok")
                }
                let amount = action.amount ?? action.grams
                let unit = action.unit ?? (amount == nil ? nil : "g")
                let overrides = (try? ctx.fetch(FetchDescriptor<MealPlanOverride>())) ?? []
                if let existing = overrides.first(where: {
                    $0.weekday == weekday
                    && $0.operation == .addItem
                    && $0.slot == slot
                    && normalizedKey($0.displayName) == normalizedKey(itemName)
                }) {
                    existing.amount = amount ?? existing.amount
                    existing.unit = unit ?? existing.unit
                    existing.calories = action.calories ?? existing.calories
                    existing.protein = action.proteinG ?? existing.protein
                    existing.carbs = action.carbsG ?? existing.carbs
                    existing.fat = action.fatG ?? existing.fat
                    existing.note = action.summary ?? existing.note
                    existing.source = "ai"
                    existing.createdAt = .now
                } else {
                    ctx.insert(MealPlanOverride(
                        weekday: weekday,
                        operation: .addItem,
                        slot: slot,
                        itemName: itemName,
                        amount: amount,
                        unit: unit,
                        calories: action.calories,
                        protein: action.proteinG,
                        carbs: action.carbsG,
                        fat: action.fatG,
                        note: action.summary,
                        source: "ai"
                    ))
                }
                try ctx.save()
                return "\(WorkoutSession.weekdayNames[weekday]) \(slot.label.lowercased()) öğününe \(itemName) eklendi"

            default:
                throw AppToolError.unsupported("Yemek planı işlemi desteklenmiyor: \(operation)")
            }
        }
    }

    private func validWeekday(_ value: Int?) throws -> Int {
        guard let value, (1...7).contains(value) else {
            throw AppToolError.missing("Geçerli gün yok")
        }
        return value
    }

    private func nonEmpty(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applyRecipeDetails(from action: AIAppAction, title: String, to recipe: Recipe) {
        let url = normalizedRecipeURL(action.url, title: title)
        if !url.isEmpty {
            recipe.urlString = url
        }
        if let summary = cleaned(action.recipeSummary) ?? cleaned(action.summary) {
            recipe.summary = summary
        }
        if let ingredients = cleaned(action.ingredients) {
            recipe.ingredientsText = ingredients
        }
        if let instructions = cleaned(action.instructions) {
            recipe.instructionsText = instructions
        }
        if let servings = action.servings {
            recipe.servings = servings
        }
        if let prepMinutes = action.prepMinutes {
            recipe.prepMinutes = prepMinutes
        }
        if let calories = action.calories {
            recipe.calories = calories
        }
        if let protein = action.proteinG {
            recipe.protein = protein
        }
        if let carbs = action.carbsG {
            recipe.carbs = carbs
        }
        if let fat = action.fatG {
            recipe.fat = fat
        }
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func normalizedRecipeURL(_ raw: String?, title: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return ""
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
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
        if !hasSavedConversation {
            try? FileManager.default.removeItem(at: historyURL)
            return
        }

        let payload = HistoryPayload(
            version: 2,
            savedAt: .now,
            currentConversationID: currentConversationID,
            conversations: conversationsToPersist
        )
        guard let data = try? Self.encoder.encode(payload) else { return }
        try? data.write(to: historyURL, options: [.atomic])
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
