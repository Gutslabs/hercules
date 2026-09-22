import Foundation
import Observation
import SwiftData
import SwiftUI

/// Telefonun sohbet deposu — Mac'teki `ChatStore` ile AYNI veri modelini kullanır
/// (`ChatConversation`: kök mesaj + yanıtlar). Fark yalnız taşımada: Mac doğrudan
/// modele bağlanır, telefon `RemoteAIClient` üzerinden Mac'e sorar.
///
/// Kanal/thread ayrımı buradan gelir: her konuşma bir kanal satırı (kök mesaj),
/// içindeki yanıtlar thread'i oluşturur.
@Observable
@MainActor
final class MobileChatStore {
    static let shared = MobileChatStore()

    private(set) var conversations: [ChatConversation] = []
    private(set) var isSending = false
    var currentConversationID: UUID?
    var errorText: String?
    var health: RemoteAIHealthResponse?
    var healthError: String?

    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var didLoad = false
    /// Yerel konuşma id'si → Mac'teki konuşma id'si.
    @ObservationIgnored private var macIDs: [UUID: UUID] = [:]

    private init() {}

    // MARK: - Okuma

    /// Kanal akışı: kronolojik (eski üstte), boş taslaklar çizilmez — Mac'teki
    /// `channelConversations` ile aynı kural.
    var channelConversations: [ChatConversation] {
        conversations
            .filter { !$0.messages.isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var currentConversation: ChatConversation? {
        guard let currentConversationID else { return nil }
        return conversations.first { $0.id == currentConversationID }
    }

    /// Açık thread'in mesajları.
    var messages: [ChatTurn] { currentConversation?.messages ?? [] }

    func conversation(_ id: UUID) -> ChatConversation? {
        conversations.first { $0.id == id }
    }

    // MARK: - Yaşam döngüsü

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        conversations = MobileChatHistory.load()
        currentConversationID = MobileChatHistory.loadCurrentID()
            ?? channelConversations.last?.id
    }

    // MARK: - Gönderim

    /// Kanal composer'ından yazmak YENİ konuşma başlatır (Mac'teki
    /// `startConversationFromChannel` ile aynı davranış) ve thread'i açar.
    @discardableResult
    func startConversation(
        text: String,
        images: [Data] = [],
        userContext: String
    ) -> UUID? {
        guard !isSending else { return nil }
        let convo = ChatConversation(title: Self.title(from: text), messages: [])
        conversations.append(convo)
        currentConversationID = convo.id
        send(text: text, images: images, userContext: userContext)
        return convo.id
    }

    /// Açık thread'e yanıt ekler. Konuşma yoksa yeni bir tane açar.
    func send(text: String, images: [Data] = [], userContext: String) {
        guard !isSending else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Görsel-yalnız mesajda modele/UI'a anlamlı bir metin ver.
        let outgoing = (trimmed.isEmpty && !images.isEmpty) ? "Bu görsele bakar mısın?" : trimmed
        guard !outgoing.isEmpty else { return }

        if currentConversation == nil {
            let convo = ChatConversation(title: Self.title(from: outgoing), messages: [])
            conversations.append(convo)
            currentConversationID = convo.id
        }
        guard let idx = conversationIndex else { return }

        // Görseller diske arka planda yazılır; tur yalnız id'leri taşır.
        let imageIDs = images.map { _ in UUID().uuidString }
        if !imageIDs.isEmpty {
            let pairs = Array(zip(imageIDs, images))
            Task.detached(priority: .utility) {
                for (id, data) in pairs { ChatImageStore.save(data, id: id) }
            }
        }

        let history = conversations[idx].messages
        conversations[idx].messages.append(
            ChatTurn(role: .user, text: outgoing, imageIDs: imageIDs.isEmpty ? nil : imageIDs)
        )
        conversations[idx].updatedAt = .now
        if conversations[idx].title.isEmpty {
            conversations[idx].title = Self.title(from: outgoing)
        }
        persist()
        beginRequest(text: outgoing, images: images, history: history, userContext: userContext)
    }

    func retryLast(userContext: String) {
        guard !isSending, let idx = conversationIndex else { return }
        let turns = conversations[idx].messages
        guard let last = turns.lastIndex(where: { $0.role == .user }) else { return }
        let turn = turns[last]
        let images = (turn.imageIDs ?? []).compactMap { ChatImageStore.load($0) }
        beginRequest(
            text: turn.text,
            images: images,
            history: Array(turns.prefix(last)),
            userContext: userContext
        )
    }

    func stop() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }

    private var conversationIndex: Int? {
        guard let currentConversationID else { return nil }
        return conversations.firstIndex { $0.id == currentConversationID }
    }

    private func beginRequest(
        text: String,
        images: [Data],
        history: [ChatTurn],
        userContext: String
    ) {
        errorText = nil
        isSending = true
        let targetID = currentConversationID
        sendTask = Task { [weak self] in
            do {
                let client = RemoteAIClient()
                let live = try await client.health()
                try Task.checkCancellation()
                // Kanal senkronlu gönderim: Mac turu KENDİ geçmişine yazar.
                let (result, searchEvidence, macConversationID) = try await client.sendInChannel(
                    conversationID: self?.macConversationID(for: targetID),
                    history: history,
                    newUserText: text,
                    userContext: userContext,
                    images: images
                )
                try Task.checkCancellation()
                guard let self else { return }
                self.health = live
                self.healthError = nil
                let answer = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
                let turn = ChatTurn(
                    role: .assistant,
                    text: answer.isEmpty ? (result.name ?? "Yanıt boş geldi.") : answer,
                    food: result.isFood ? result : nil,
                    actions: result.actionList,
                    searchedFor: (
                        searchEvidence?.completedSuccessfully == true
                        && searchEvidence?.sourceURLs.isEmpty == false
                    ) ? searchEvidence?.query : nil
                )
                // Yanıt geldiğinde kullanıcı başka thread'e geçmiş olabilir:
                // tur her zaman İSTEĞİ AÇAN konuşmaya yazılır.
                if let idx = self.conversations.firstIndex(where: { $0.id == targetID }) {
                    self.conversations[idx].messages.append(turn)
                    self.conversations[idx].updatedAt = .now
                    // Mac hangi konuşmaya yazdıysa yerel kaydı ona bağla; bir
                    // sonraki mesaj aynı thread'e düşsün.
                    if let macConversationID {
                        self.macIDs[targetID ?? macConversationID] = macConversationID
                    }
                }
                self.persist()
                // Mac tek kaynak: yazımdan hemen sonra aynala.
                await self.syncFromMac()
            } catch is CancellationError {
                self?.errorText = nil
            } catch {
                guard let self else { return }
                self.errorText = MobileChatHistory.friendlyError(error)
                self.health = nil
                self.healthError = "\(CoachIdentity.name) çevrimdışı"
            }
            self?.isSending = false
            self?.sendTask = nil
        }
    }

    // MARK: - Mac ile ortak kanal

    /// Telefon kendi geçmişini BİRİKTİRMEZ; Mac'in kanalını aynalar. Böylece iki
    /// cihaz aynı konuşmaları, aynı sırada, aynı içerikle gösterir.
    ///
    /// Mac ulaşılamıyorsa son ayna yerinde kalır (çevrimdışı okuma) — yalnız
    /// yeni mesaj gönderilemez, ki bu zaten telefonun sohbet için ön koşulu.
    func syncFromMac() async {
        guard !isSending else { return }
        do {
            let snapshot = try await RemoteAIClient().chatHistory()
            applyMirror(snapshot)
            healthError = nil
        } catch {
            // Sessiz: bağlantı durumu zaten başlıkta gösteriliyor.
        }
    }

    /// Koç adı ve avatarlar da Mac'ten gelir — telefonda ayrı özelleştirme YOK.
    /// İmza değişmediyse diske dokunulmaz (her açılışta gereksiz yazım olmasın).
    func syncIdentityFromMac() async {
        do {
            let identity = try await RemoteAIClient().identity()
            let key = "hercules.mobile.identity.signature"
            guard UserDefaults.standard.string(forKey: key) != identity.signature else { return }

            CoachIdentity.setName(identity.coachName)
            apply(identity.profileAvatar, to: ProfileAvatarStore.store)
            apply(identity.coachAvatar, to: CoachAvatarStore.store)
            UserDefaults.standard.set(identity.signature, forKey: key)
        } catch {
            // Sessiz: Mac ulaşılamıyorsa son bilinen kimlik yerinde kalır.
        }
    }

    private func apply(_ data: Data?, to store: AvatarFileStore) {
        guard let data, let image = PlatformImage(data: data) else {
            store.clear()
            return
        }
        store.set(image)
    }

    private func applyMirror(_ snapshot: RemoteAIChatHistoryResponse) {
        // Mac kanonik: aynı konuşma iki yerdeyse Mac'inki geçerlidir.
        //
        // Ama yerel kopyayı KÖRÜ KÖRÜNE değiştirmiyoruz: Mac akıştayken yazılan
        // bir tur Mac'in kanalına giremez (appendRemoteExchange nil döner) ve
        // yalnız telefonda yaşar. Doğrudan atama o konuşmayı sessizce silerdi.
        // Mac'te karşılığı olmayan yerel konuşmalar korunur ve bir sonraki
        // gönderimde Mac'e taşınır.
        let macIDSet = Set(snapshot.conversations.map(\.id))
        let localOnly = conversations.filter { convo in
            !macIDSet.contains(convo.id)
                && macIDs[convo.id].map { !macIDSet.contains($0) } ?? true
                && !convo.messages.isEmpty
        }
        conversations = snapshot.conversations + localOnly
        macIDs = Dictionary(uniqueKeysWithValues: snapshot.conversations.map { ($0.id, $0.id) })
        if let current = currentConversationID,
           !conversations.contains(where: { $0.id == current }) {
            currentConversationID = snapshot.currentConversationID ?? channelConversations.last?.id
        }
        persist()
    }

    /// Yerel konuşma → Mac'teki karşılığı. Ayna sonrası ikisi aynı id olur;
    /// ilk mesajda (henüz Mac'te yokken) nil döner ve Mac yeni konuşma açar.
    private func macConversationID(for localID: UUID?) -> UUID? {
        guard let localID else { return nil }
        return macIDs[localID]
    }

    // MARK: - Konuşma yönetimi

    func selectConversation(_ id: UUID) {
        currentConversationID = id
        MobileChatHistory.saveCurrentID(id)
    }

    /// NOT: Silme yalnız telefonun aynasından kaldırır. Mac tek kaynak olduğu
    /// için bir sonraki senkronda konuşma geri gelir — kalıcı silme Mac'ten
    /// yapılır. (Aynayı sessizce kaynağın önüne geçirmek istemedik.)
    func delete(_ id: UUID) {
        guard let convo = conversation(id) else { return }
        let orphaned = convo.messages.flatMap { $0.imageIDs ?? [] }
        if !orphaned.isEmpty {
            Task.detached(priority: .utility) {
                for imageID in orphaned { ChatImageStore.delete(imageID) }
            }
        }
        conversations.removeAll { $0.id == id }
        if currentConversationID == id { currentConversationID = channelConversations.last?.id }
        persist()
    }

    /// Kanalı sıfırla — Mac'teki "arşivle ve sıfırdan başla" karşılığı.
    func archiveAll() {
        stop()
        let orphaned = conversations.flatMap { $0.messages.flatMap { $0.imageIDs ?? [] } }
        if !orphaned.isEmpty {
            Task.detached(priority: .utility) {
                for id in orphaned { ChatImageStore.delete(id) }
            }
        }
        conversations = []
        currentConversationID = nil
        errorText = nil
        persist()
    }

    // MARK: - Öğün kaydı

    /// Kart hangi güne ayarlandıysa oraya yazar (Mac'teki `saveFood` ile aynı).
    func saveFood(in turn: ChatTurn, ctx: ModelContext, on date: Date = .now) {
        guard let food = turn.food, let cals = food.calories else { return }
        let entry = FoodEntry(
            date: date,
            name: food.name ?? "Yemek",
            grams: food.grams,
            calories: cals,
            protein: food.protein_g,
            carbs: food.carbs_g,
            fat: food.fat_g
        )
        ctx.insert(entry)
        ctx.saveOrReport("koç öğününü günlüğe ekleme")
        for cIdx in conversations.indices {
            if let tIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == turn.id }) {
                conversations[cIdx].messages[tIdx].saved = true
                conversations[cIdx].messages[tIdx].savedFoodDate = date
                persist()
                return
            }
        }
    }

    // MARK: - Aksiyon kartları

    /// Telefonda YALNIZ öğün kaydı yürütülür — FoodEntry burada da var.
    /// Tarif/program yazımı Mac'in yürütücüsünde yaşıyor; onu telefonda taklit
    /// etmek yerine kartı açıkça oraya yönlendiriyoruz (sessiz no-op değil).
    func confirmAction(turnID: UUID, actionID: UUID, ctx: ModelContext) {
        // Geçmiş bir günün thread'inde öğün o güne yazılır (Mac'teki yürütücüyle aynı kural).
        let logDate = ChatDailyThread.logDate(
            for: conversations.first { $0.messages.contains { $0.id == turnID } }
        )
        mutateAction(turnID: turnID, actionID: actionID) { action in
            switch action.tool {
            case .logFood:
                guard let calories = action.calories, calories.isFinite, calories > 0 else {
                    action.status = .failed
                    action.resultMessage = "Kalori değeri okunamadı."
                    return
                }
                let entry = FoodEntry(
                    date: logDate,
                    name: (action.name ?? action.itemName)?.nilIfBlank ?? "AI yemek",
                    grams: action.grams ?? action.amount,
                    calories: calories,
                    protein: action.proteinG,
                    carbs: action.carbsG,
                    fat: action.fatG
                )
                ctx.insert(entry)
                guard ctx.saveOrReport("koç aksiyonuyla öğün ekleme") else {
                    action.status = .failed
                    action.resultMessage = "Kayıt diske yazılamadı."
                    return
                }
                action.status = .applied
                action.resultMessage = ChatDailyThread.loggedPhrase(on: logDate, sentenceStart: true)
            case .addRecipe, .updateWorkoutPlan:
                action.status = .failed
                action.resultMessage = "Bu işlemi Mac'teki Hercules'ten onaylaman gerekiyor."
            }
        }
    }

    func rejectAction(turnID: UUID, actionID: UUID) {
        mutateAction(turnID: turnID, actionID: actionID) { action in
            guard action.status == .pending else { return }
            action.status = .rejected
            action.resultMessage = "Vazgeçildi"
        }
    }

    private func mutateAction(
        turnID: UUID,
        actionID: UUID,
        _ apply: (inout AIAppAction) -> Void
    ) {
        for cIdx in conversations.indices {
            guard let tIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == turnID }),
                  let aIdx = conversations[cIdx].messages[tIdx].actions.firstIndex(where: { $0.id == actionID })
            else { continue }
            apply(&conversations[cIdx].messages[tIdx].actions[aIdx])
            persist()
            return
        }
    }

    // MARK: - Sağlık

    func refreshHealth() async {
        do {
            health = try await RemoteAIClient().health()
            healthError = nil
        } catch {
            health = nil
            healthError = "\(CoachIdentity.name) çevrimdışı"
        }
    }

    // MARK: - Kalıcılık

    private func persist() {
        MobileChatHistory.save(conversations)
        MobileChatHistory.saveCurrentID(currentConversationID)
    }

    /// Kanal satırında görünen başlık — ilk satır, kısaltılmış.
    private static func title(from text: String) -> String {
        let line = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first.map(String.init) ?? ""
        return String(line.prefix(60))
    }
}

/// Telefon sohbet geçmişi. v1 düz `[ChatTurn]` kaydı tek konuşmaya taşınır —
/// güncelleme sonrası eski sohbet kaybolmasın.
enum MobileChatHistory {
    private static let v1Key = "hercules.mobile.remote-ai.chat.v1"
    private static let key = "hercules.mobile.remote-ai.chat.v2"
    private static let currentKey = "hercules.mobile.remote-ai.chat.current"
    private static let maxConversations = 40

    static func load() -> [ChatConversation] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let list = try? JSONDecoder().decode([ChatConversation].self, from: data) {
            return list
        }
        // v1 göçü: düz tur listesi tek bir konuşmaya sarılır.
        guard let legacy = defaults.data(forKey: v1Key),
              let turns = try? JSONDecoder().decode([ChatTurn].self, from: legacy),
              !turns.isEmpty
        else { return [] }
        let convo = ChatConversation(
            title: String((turns.first?.text ?? "Sohbet").prefix(60)),
            messages: turns,
            createdAt: turns.first?.createdAt ?? .now,
            updatedAt: turns.last?.createdAt ?? .now
        )
        save([convo])
        defaults.removeObject(forKey: v1Key)
        return [convo]
    }

    static func save(_ conversations: [ChatConversation]) {
        let kept = Array(conversations.suffix(maxConversations))
        if kept.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func loadCurrentID() -> UUID? {
        UserDefaults.standard.string(forKey: currentKey).flatMap(UUID.init(uuidString:))
    }

    static func saveCurrentID(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: currentKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentKey)
        }
    }

    static func friendlyError(_ error: Error) -> String {
        if case RemoteAIClientError.server(let status, _) = error {
            if status == 429 { return "\(CoachIdentity.name) şu an önceki isteği tamamlıyor. Birazdan tekrar dene." }
            if status == 403 { return "\(CoachIdentity.name) bağlantısı bu cihaz için yetkili değil." }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut:
                return "\(CoachIdentity.dative) bağlanamadım. Tailscale bağlantını kontrol edip tekrar dene."
            case .cancelled:
                return ""
            default:
                break
            }
        }
        return "\(CoachIdentity.name) yanıt veremedi. Birazdan tekrar dene."
    }
}
