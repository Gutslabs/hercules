import Foundation
import SwiftData
import Combine

@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatTurn] = []
    @Published var input: String = ""
    @Published var isSending: Bool = false
    @Published var searchingFor: String? = nil
    @Published var lastError: String? = nil

    private var client: AIClient = AIKeyStore.shared.makeClient()
    private var notificationToken: NSObjectProtocol?

    init() {
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
    }

    /// Sağlayıcı/model değişti, istemciyi yeniden kur.
    func reloadClient() {
        client = AIKeyStore.shared.makeClient()
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""
        lastError = nil

        let userTurn = ChatTurn(role: .user, text: text)
        messages.append(userTurn)
        isSending = true
        searchingFor = nil

        do {
            let (result, searchQuery) = try await client.send(
                history: messages.dropLast(),
                newUserText: text,
                onSearchStart: { [weak self] q in
                    self?.searchingFor = q
                }
            )
            let assistantText = result.message.isEmpty
                ? (result.name ?? "—")
                : result.message
            let turn = ChatTurn(
                role: .assistant,
                text: assistantText,
                food: result.isFood ? result : nil,
                searchedFor: searchQuery
            )
            messages.append(turn)
        } catch {
            lastError = error.localizedDescription
            messages.append(ChatTurn(role: .assistant, text: "❌ Hata: \(error.localizedDescription)"))
        }

        isSending = false
        searchingFor = nil
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
        }
    }

    func clear() {
        messages.removeAll()
        lastError = nil
    }
}
