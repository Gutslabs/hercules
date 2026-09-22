import SwiftUI
import SwiftData
import LucideKit
import PhotosUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Koç sekmesi · kanal

/// Telefondaki koç, Mac'teki `ChatPageView` ile AYNI mimaride: bir KANAL
/// (konuşmaların kök mesajları + yanıt hapları) ve içine giren THREAD'ler.
/// Mesaj anatomisi de birebir aynı — `MessageBubble` iki platformda ortak
/// bileşendir, yani öğün kartı, aksiyon kartı ve avatarlar tek yerden gelir.
/// Fark yalnız gezinmede: Mac'te thread yandan açılır, telefonda üstüne kayar.
struct MobileAIChatView: View {
    let userContext: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var store: MobileChatStore { .shared }

    @State private var openThreadID: UUID?
    @State private var draft = ""
    @State private var pendingImages: [MobilePendingImage] = []
    @State private var attachStage: MobileAttachStage = .composer
    @State private var isLoadingAttachments = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var confirmingArchive = false
    @State private var deletingID: UUID?
    @FocusState private var composerFocused: Bool

    private var userName: String {
        let name = profiles.first?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Sen" : name
    }

    var body: some View {
        ZStack {
            channel
            if let openThreadID, let convo = store.conversation(openThreadID) {
                MobileChatThreadView(
                    conversationID: convo.id,
                    userContext: userContext,
                    userName: userName,
                    onClose: { closeThread() }
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: openThreadID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Koç yüzeyi görünüm seçicisinden bağımsız: Mac'te olduğu gibi burada da kömür.
        .background(ChatChrome.background.ignoresSafeArea())
        .task {
            store.loadIfNeeded()
            await store.refreshHealth()
            // Mac tek kaynak — sekmeye her girişte kanalı ve kimliği aynala.
            await store.syncIdentityFromMac()
            await store.syncFromMac()
        }
    }

    // MARK: Kanal

    private var channel: some View {
        VStack(spacing: 0) {
            MobileChatHeader(
                title: CoachIdentity.name,
                isSending: store.isSending,
                health: store.health,
                healthError: store.healthError,
                onRefresh: { Task { await store.refreshHealth() } },
                trailing: {
                    Button { confirmingArchive = true } label: {
                        Lucide(sf: "square.and.pencil", size: 15)
                            .foregroundStyle(ChatChrome.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.channelConversations.isEmpty)
                    .accessibilityLabel("Kanalı arşivle")
                }
            )
            Rectangle().fill(ChatChrome.border).frame(height: 0.5)

            if store.channelConversations.isEmpty {
                emptyState
            } else {
                timeline
            }

            MobileChatComposer(
                text: $draft,
                pendingImages: $pendingImages,
                attachStage: $attachStage,
                isLoadingAttachments: $isLoadingAttachments,
                isSending: store.isSending,
                placeholder: "\(CoachIdentity.dative) yeni bir soru başlat…",
                focused: $composerFocused,
                onSend: startConversation,
                onStop: { store.stop() },
                onCamera: { showCamera = true },
                onFiles: { showFiles = true },
                onAllPhotos: { showPhotoLibrary = true }
            )
        }
        .confirmationDialog("Kanalı arşivle", isPresented: $confirmingArchive, titleVisibility: .visible) {
            Button("Arşivle ve sıfırdan başla", role: .destructive) { store.archiveAll() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu kanaldaki tüm konuşmalar ve ekli görseller silinir. Geri alınamaz.")
        }
        .confirmationDialog(
            "Sohbeti sil",
            isPresented: Binding(get: { deletingID != nil }, set: { if !$0 { deletingID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                if let deletingID { store.delete(deletingID) }
                deletingID = nil
            }
            Button("Vazgeç", role: .cancel) { deletingID = nil }
        }
        .modifier(MobileChatAttachModifier(
            showFiles: $showFiles,
            showPhotoLibrary: $showPhotoLibrary,
            showCamera: $showCamera,
            pickerItems: $pickerItems,
            pendingImages: $pendingImages,
            isLoadingAttachments: $isLoadingAttachments
        ))
    }

    /// Kanal akışı: gün ayracı + konuşmanın kök mesajı + yanıt hapı.
    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(store.channelConversations.enumerated()), id: \.element.id) { index, convo in
                    if showsDaySeparator(at: index) {
                        MobileChatDaySeparator(date: convo.createdAt)
                    }
                    rootRow(convo)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 16)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
    }

    private func showsDaySeparator(at index: Int) -> Bool {
        let list = store.channelConversations
        guard list.indices.contains(index) else { return false }
        if index == 0 { return true }
        return !Calendar.current.isDate(list[index].createdAt, inSameDayAs: list[index - 1].createdAt)
    }

    /// Kanal satırı — Mac'teki `conversationRootRow` ile aynı: kök mesaj + yanıt hapı.
    /// Telefonda hover yok, o yüzden aksiyon çubuğu uzun basma menüsüne taşındı.
    private func rootRow(_ convo: ChatConversation) -> some View {
        let root = convo.messages.first
        let replyCount = max(0, convo.messages.count - 1)
        let streaming = convo.id == store.currentConversationID && store.isSending
        return VStack(alignment: .leading, spacing: 4) {
            if let root {
                MessageBubble(turn: root, isStreaming: false, userName: userName) { _ in
                } onConfirmAction: { _ in
                } onRejectAction: { _ in
                }
            } else {
                Text(convo.title.isEmpty ? "Yeni sohbet" : convo.title)
                    .font(ChatChrome.messageBody)
                    .foregroundStyle(ChatChrome.secondary)
            }
            // Günün thread'i (Mac açar, telefon aynalar) yanıtsızken de hapını gösterir.
            if replyCount > 0 || streaming || ChatDailyThread.isDaily(convo) {
                replyPill(convo, replyCount: streaming ? max(replyCount, 1) : replyCount, streaming: streaming)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { openThread(convo.id) }
        .contextMenu {
            Button { openThread(convo.id) } label: { Label("Thread'i aç", systemImage: "text.bubble") }
            Button {
                UIPasteboard.general.string = convo.messages.first?.text ?? convo.title
            } label: { Label("Kök mesajı kopyala", systemImage: "doc.on.doc") }
            Button(role: .destructive) { deletingID = convo.id } label: {
                Label("Sohbeti sil", systemImage: "trash")
            }
        }
    }

    /// Buzz yanıt hapı: facepile + "N yanıt · son yanıt X".
    private func replyPill(_ convo: ChatConversation, replyCount: Int, streaming: Bool) -> some View {
        Button { openThread(convo.id) } label: {
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    ChatUserAvatar(name: userName, size: 20)
                    AssistantMark(size: 20, cornerRadius: 10)
                }
                HStack(spacing: 4) {
                    Text(replyCount == 0 ? ChatDailyThread.emptyReplyLabel(for: convo) : "\(replyCount) yanıt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ChatChrome.secondary)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(ChatChrome.quaternary)
                    Text(streaming ? "yazıyor…" : (replyCount == 0 ? "Thread'i aç" : "son yanıt \(Fmt.relative(convo.updatedAt))"))
                        .font(.system(size: 12))
                        .foregroundStyle(streaming ? ChatChrome.positive : ChatChrome.tertiary)
                }
                .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Gövde hizası: avatar (32) + boşluk (10).
        .padding(.leading, 42)
    }

    private var emptyState: some View {
        MobileChatEmptyState { prompt in
            draft = prompt
            startConversation()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Eylemler

    private func startConversation() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages.map(\.data)
        guard !text.isEmpty || !images.isEmpty, !store.isSending, !isLoadingAttachments else { return }
        composerFocused = false
        draft = ""
        pendingImages = []
        if let id = store.startConversation(text: text, images: images, userContext: userContext) {
            openThread(id)
        }
    }

    private func openThread(_ id: UUID) {
        store.selectConversation(id)
        composerFocused = false
        openThreadID = id
    }

    private func closeThread() {
        openThreadID = nil
    }
}

// MARK: - Thread ekranı

/// Mac'teki thread paneli — telefonda tam ekran. Başlık + transkript + composer.
struct MobileChatThreadView: View {
    let conversationID: UUID
    let userContext: String
    let userName: String
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext

    private var store: MobileChatStore { .shared }

    @State private var draft = ""
    @State private var pendingImages: [MobilePendingImage] = []
    @State private var attachStage: MobileAttachStage = .composer
    @State private var isLoadingAttachments = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var nearBottom = true
    @FocusState private var composerFocused: Bool

    /// Masaüstündeki `followUpPrompts` ile aynı liste.
    static let followUpPrompts = [
        "Bugünkü özeti çıkar",
        "Protein açığını tamamla",
        "Son haftayla karşılaştır",
        "Yarın için plan oluştur"
    ]

    private var conversation: ChatConversation? { store.conversation(conversationID) }
    private var messages: [ChatTurn] { conversation?.messages ?? [] }
    private var isCurrent: Bool { store.currentConversationID == conversationID }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ChatChrome.border).frame(height: 0.5)
            transcript
            MobileChatComposer(
                text: $draft,
                pendingImages: $pendingImages,
                attachStage: $attachStage,
                isLoadingAttachments: $isLoadingAttachments,
                isSending: store.isSending,
                placeholder: "\(CoachIdentity.dative) yaz…",
                focused: $composerFocused,
                onSend: send,
                onStop: { store.stop() },
                onCamera: { showCamera = true },
                onFiles: { showFiles = true },
                onAllPhotos: { showPhotoLibrary = true },
                followUps: messages.isEmpty ? [] : Self.followUpPrompts,
                onPickFollowUp: { draft = $0; composerFocused = true }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChatChrome.background.ignoresSafeArea())
        .modifier(MobileChatAttachModifier(
            showFiles: $showFiles,
            showPhotoLibrary: $showPhotoLibrary,
            showCamera: $showCamera,
            pickerItems: $pickerItems,
            pendingImages: $pendingImages,
            isLoadingAttachments: $isLoadingAttachments
        ))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Lucide(sf: "chevron.left", size: 15)
                    .foregroundStyle(ChatChrome.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kanala dön")

            VStack(alignment: .leading, spacing: 1) {
                Text("Thread")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(ChatChrome.quaternary)
                Text(conversation?.title.nilIfBlank ?? "Yeni sohbet")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(ChatChrome.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(max(0, messages.count - 1)) yanıt")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(ChatChrome.quaternary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 54)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { turn in
                        MessageBubble(
                            turn: turn,
                            isStreaming: false,
                            userName: userName,
                            // Geçmiş bir günün thread'inde kart o güne ayarlı açılır.
                            defaultDayOffset: ChatDailyThread.logDayOffset(for: conversation),
                            onSave: { date in store.saveFood(in: turn, ctx: modelContext, on: date) },
                            onConfirmAction: { action in
                                store.confirmAction(turnID: turn.id, actionID: action.id, ctx: modelContext)
                            },
                            onRejectAction: { action in
                                store.rejectAction(turnID: turn.id, actionID: action.id)
                            }
                        )
                        .id(turn.id)
                    }
                    if isCurrent && store.isSending {
                        thinkingRow.id("thinking")
                    }
                    if isCurrent, let error = store.errorText, !error.isEmpty {
                        errorRow(error).id("error")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.isSending) { _, sending in
                if sending { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private var thinkingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentThinkingGlyph(tint: ChatChrome.primary, dim: ChatChrome.quaternary)
            MobileCoachShimmerText(text: "Düşünüyor…")
                .frame(minHeight: 28, alignment: .center)
            Spacer()
        }
    }

    private func errorRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Lucide("wifi-off", size: 14)
                .foregroundStyle(Palette.negative)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(ChatChrome.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if messages.last?.role == .user {
                    Button("Tekrar dene") { store.retryLast(userContext: userContext) }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(ChatChrome.accent)
                        .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages.map(\.data)
        guard !text.isEmpty || !images.isEmpty, !store.isSending, !isLoadingAttachments else { return }
        composerFocused = false
        draft = ""
        pendingImages = []
        store.selectConversation(conversationID)
        store.send(text: text, images: images, userContext: userContext)
    }
}

// MARK: - Ortak parçalar

/// Kanal ve thread aynı başlığı kullanır: avatar + ad + bağlantı durumu.
struct MobileChatHeader<Trailing: View>: View {
    let title: String
    let isSending: Bool
    let health: RemoteAIHealthResponse?
    let healthError: String?
    let onRefresh: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    private var connectionColor: Color {
        if health != nil { return ChatChrome.positive }
        if healthError != nil { return Palette.negative }
        return ChatChrome.quaternary
    }

    var body: some View {
        HStack(spacing: 10) {
            AssistantMark(size: 24, cornerRadius: 6, state: isSending ? .talking : .idle)
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(ChatChrome.primary)
            Spacer()
            Button(action: onRefresh) {
                HStack(spacing: 7) {
                    Circle().fill(connectionColor).frame(width: 5, height: 5)
                    Text(isSending ? "çalışıyor" : (health != nil ? "hazır" : "bağlı değil"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(ChatChrome.tertiary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(health == nil ? "Bağlantıyı yenile" : "Bağlı")
            trailing()
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 54)
    }
}

/// Gün ayracı — Mac'teki `daySeparator` ile aynı: ortada tarih, iki yanda çizgi.
struct MobileChatDaySeparator: View {
    let date: Date

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        return Fmt.dayMonth.string(from: date)
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(ChatChrome.border).frame(height: 0.5)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(ChatChrome.quaternary)
                .fixedSize()
            Rectangle().fill(ChatChrome.border).frame(height: 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

/// Kanal boşken karşılama + hazır sorular.
struct MobileChatEmptyState: View {
    let onPick: (String) -> Void

    private let suggestions: [(title: String, prompt: String)] = [
        ("Bugün", "Bugünkü verilerime göre kısa bir değerlendirme yap."),
        ("Beslenme", "Bu hafta beslenmede en çok neyi düzeltmeliyim?"),
        ("Antrenman", "Son ölçümlerime göre antrenman öner.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                MobileCoachShimmerText(
                    text: "Ne sormak istersin?",
                    font: .system(size: 24, weight: .semibold),
                    base: ChatChrome.primary,
                    shimmer: ChatChrome.quaternary,
                    cycleLimit: 3
                )
                Text("Hedeflerin, ölçümlerin, öğünlerin ve antrenmanların üzerinden birlikte ilerleyelim.")
                    .font(.system(size: 13))
                    .foregroundStyle(ChatChrome.quaternary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 28)

            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                HStack(spacing: 7) {
                    Circle().fill(ChatChrome.accent).frame(width: 5, height: 5)
                    Text(suggestion.title.uppercased(with: Locale(identifier: "tr_TR")))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(ChatChrome.tertiary)
                }
                Button { onPick(suggestion.prompt) } label: {
                    HStack(spacing: 10) {
                        Text(suggestion.prompt)
                            .font(.system(size: 13))
                            .foregroundStyle(ChatChrome.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Lucide(sf: "arrow.up.right", size: 11)
                            .foregroundStyle(ChatChrome.quaternary)
                    }
                    .padding(.vertical, 12)
                    .overlay(Rectangle().fill(ChatChrome.border).frame(height: 1), alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 18)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }
}

// MARK: - Composer

/// Kanal ve thread AYNI composer'ı kullanır: yazı alanı üstte, eylemler altta,
/// kap büyüyerek ek menüsüne dönüşüyor (MobileAttachSurface).
struct MobileChatComposer: View {
    @Binding var text: String
    @Binding var pendingImages: [MobilePendingImage]
    @Binding var attachStage: MobileAttachStage
    @Binding var isLoadingAttachments: Bool
    let isSending: Bool
    let placeholder: String
    @FocusState.Binding var focused: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCamera: () -> Void
    let onFiles: () -> Void
    let onAllPhotos: () -> Void
    /// Masaüstündeki şerit: sohbet başladıysa ve yanıt akmıyorsa composer'ın üstünde.
    var followUps: [String] = []
    var onPickFollowUp: (String) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
            && !isSending && !isLoadingAttachments
    }

    var body: some View {
        VStack(spacing: 8) {
            if !followUps.isEmpty && !isSending && attachStage == .composer {
                followUpStrip
            }
            if !pendingImages.isEmpty || isLoadingAttachments {
                pendingStrip
                    .padding(.horizontal, 16)
            }
            surface
        }
        .padding(.top, 8)
        .padding(.bottom, MobileChrome.composerClearance)
        // Transkript composer'ın altına doğru sessizce siliniyor.
        .background(
            LinearGradient(
                colors: [ChatChrome.background.opacity(0), ChatChrome.background, ChatChrome.background],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.28)
            )
            .allowsHitTesting(false)
        )
    }

    private var surface: some View {
        MobileAttachSurface(
            stage: $attachStage,
            onCamera: onCamera,
            onFiles: onFiles,
            onAllPhotos: onAllPhotos,
            onPick: { data in
                isLoadingAttachments = true
                Task {
                    if let pending = await MobileChatImagePipeline.preparePending(raw: data) {
                        append([pending])
                    }
                    isLoadingAttachments = false
                }
            },
            composerFocused: focused,
            composer: { field }
        )
        .background {
            MobileCoachComposerGlow(active: isSending && !reduceMotion, cornerRadius: 15)
                .padding(-4)
        }
        .padding(.horizontal, 16)
    }

    /// Masaüstündeki `suggestionStrip` — yatay kaydıran kompakt çipler.
    private var followUpStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(followUps, id: \.self) { prompt in
                    Button { onPickFollowUp(prompt) } label: {
                        Text(prompt)
                            .font(.system(size: 11))
                            .foregroundStyle(ChatChrome.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(ChatChrome.background)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(ChatChrome.borderStrong.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }

    private var field: some View {
        VStack(spacing: 0) {
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(ChatChrome.quaternary),
                axis: .vertical
            )
            .font(.system(size: 13.5))
            .foregroundStyle(ChatChrome.primary)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .tint(ChatChrome.accent.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 32, alignment: .top)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .focused($focused)
            .submitLabel(.send)
            .onSubmit(onSend)

            HStack(spacing: 4) {
                attachButton
                Spacer(minLength: 8)
                sendButton
            }
            .padding(.leading, 4)
            .padding(.trailing, 2)
        }
        .padding(5)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: canSend)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: isSending)
    }

    /// Video referansındaki "+" — menüyü açarken 45° dönüp kapatma jestine dönüşür.
    private var attachButton: some View {
        Button {
            focused = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                attachStage = attachStage.isOpen ? .composer : .menu
            }
        } label: {
            Lucide(sf: "plus", size: 16)
                .foregroundStyle(isSending ? ChatChrome.quaternary : ChatChrome.secondary)
                .rotationEffect(.degrees(attachStage.isOpen ? 45 : 0))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .accessibilityLabel(attachStage.isOpen ? "Ek panelini kapat" : "Ek ekle")
    }

    /// Daire değil, 3pt köşeli kağıt-beyazı kare.
    private var sendButton: some View {
        Button { isSending ? onStop() : onSend() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(canSend || isSending ? ChatChrome.white : ChatChrome.whiteSoft)
                if isSending {
                    Lucide(sf: "stop.fill", size: 12.5)
                        .foregroundStyle(ChatChrome.ink)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    Lucide(sf: "arrow.up", size: 12.5)
                        .foregroundStyle(canSend ? ChatChrome.ink : ChatChrome.quaternary)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(MobileCoachSendButtonStyle())
        .disabled(!canSend && !isSending)
        .accessibilityLabel(isSending ? "Yanıtı durdur" : "Gönder")
    }

    private var pendingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { item in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: item.thumb)
                            .resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                                pendingImages.removeAll { $0.id == item.id }
                            }
                        } label: {
                            Lucide(sf: "xmark.circle.fill", size: 16)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                    }
                }
                if isLoadingAttachments {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ChatChrome.panelRaised)
                        .frame(width: 56, height: 56)
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func append(_ items: [MobilePendingImage]) {
        guard !items.isEmpty else { return }
        let room = max(0, 4 - pendingImages.count)
        guard room > 0 else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            pendingImages.append(contentsOf: items.prefix(room))
        }
    }
}

/// Fotoğraf kütüphanesi / kamera / Dosyalar sunumları — kanal ve thread ortak.
struct MobileChatAttachModifier: ViewModifier {
    @Binding var showFiles: Bool
    @Binding var showPhotoLibrary: Bool
    @Binding var showCamera: Bool
    @Binding var pickerItems: [PhotosPickerItem]
    @Binding var pendingImages: [MobilePendingImage]
    @Binding var isLoadingAttachments: Bool

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showFiles,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in loadImportedFiles(result) }
            .photosPicker(
                isPresented: $showPhotoLibrary,
                selection: $pickerItems,
                maxSelectionCount: 4,
                matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: pickerItems) { _, items in loadPicked(items) }
            .fullScreenCover(isPresented: $showCamera) {
                MobileCameraPicker { image in
                    showCamera = false
                    guard let image else { return }
                    isLoadingAttachments = true
                    Task {
                        if let pending = await MobileChatImagePipeline.preparePending(camera: image) {
                            append([pending])
                        }
                        isLoadingAttachments = false
                    }
                }
                .ignoresSafeArea()
            }
    }

    /// Dosyalar uygulamasından gelen görseller (security-scoped okuma).
    private func loadImportedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        isLoadingAttachments = true
        Task {
            var prepared: [MobilePendingImage] = []
            for url in urls.prefix(4) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let raw = try? Data(contentsOf: url),
                      let pending = await MobileChatImagePipeline.preparePending(raw: raw) else { continue }
                prepared.append(pending)
            }
            append(prepared)
            isLoadingAttachments = false
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isLoadingAttachments = true
        Task {
            var loaded: [MobilePendingImage] = []
            for item in items {
                guard let raw = await MobileChatImagePipeline.loadPickerData(item, timeout: 25) else { continue }
                if let pending = await MobileChatImagePipeline.preparePending(raw: raw) { loaded.append(pending) }
            }
            append(loaded)
            pickerItems = []
            isLoadingAttachments = false
        }
    }

    private func append(_ items: [MobilePendingImage]) {
        guard !items.isEmpty else { return }
        let room = max(0, 4 - pendingImages.count)
        guard room > 0 else { return }
        pendingImages.append(contentsOf: items.prefix(room))
    }
}

/// Görsel hazırlama — kanal, thread ve ek paneli tek yoldan geçer.
enum MobileChatImagePipeline {
    /// Ham kütüphane verisini arka planda 1280px JPEG'e küçültür + strip için küçük decode üretir.
    /// pendingImages'ta hep KÜÇÜK veri durur; tam çözünürlük asla UI state'ine girmez.
    static func preparePending(raw: Data) async -> MobilePendingImage? {
        let small = ChatImageStore.downscaledJPEG(from: raw) ?? raw
        guard let thumb = decodedChatThumb(from: small, maxPixel: 320) else { return nil }
        return MobilePendingImage(data: small, thumb: thumb)
    }

    /// Kamera çekimini arka planda küçültüp JPEG'e çevirir (tam çözünürlük encode main'i kilitliyordu).
    static func preparePending(camera image: UIImage) async -> MobilePendingImage? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let scale = min(1, 1280 / max(pixelWidth, pixelHeight, 1))
        let target = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)
        let small = await image.byPreparingThumbnail(ofSize: target) ?? image
        guard let data = small.jpegData(compressionQuality: 0.78),
              let thumb = decodedChatThumb(from: data, maxPixel: 320) else { return nil }
        return MobilePendingImage(data: data, thumb: thumb)
    }

    /// loadTransferable, iCloud indirmesi/transcode yüzünden çok uzayabiliyor ya da hiç dönmüyor —
    /// spinner'ın sonsuza kadar dönmemesi için süre sınırıyla yarıştırılır.
    static func loadPickerData(_ item: PhotosPickerItem, timeout seconds: Double) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                if let data = try? await item.loadTransferable(type: Data.self) { return data }
                // Picker ilk denemede boş dönebiliyor — bir kez daha dene.
                return try? await item.loadTransferable(type: Data.self)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Composer'da bekleyen görsel: modele gidecek küçültülmüş JPEG + strip için hazır decode edilmiş thumbnail.
struct MobilePendingImage: Identifiable {
    let id = UUID()
    let data: Data
    let thumb: UIImage
}

/// Veriyi hedef piksel boyutunda decode eder — tam çözünürlük decode etmekten çok daha ucuz.
private func decodedChatThumb(from data: Data, maxPixel: CGFloat) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel
    ]
    guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: thumb)
}

/// Transkript görselleri için decode önbelleği — her body yenilenişinde (örn. her tuş vuruşu)
/// diskten okuyup tam boy decode etmeyi engeller.
@MainActor
private enum MobileChatThumbCache {
    /// NSCache: düz sözlük hiç boşalmıyordu — oturum boyunca görülen her 360 px
    /// decode'u kalıcı tutuyordu. NSCache bellek baskısında kendini boşaltır.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        return c
    }()

    static func image(for id: String) async -> UIImage? {
        if let hit = cache.object(forKey: id as NSString) { return hit }
        guard let decoded = await decode(id) else { return nil }
        cache.setObject(decoded, forKey: id as NSString)
        return decoded
    }

    nonisolated private static func decode(_ id: String) async -> UIImage? {
        guard let data = ChatImageStore.load(id) else { return nil }
        return decodedChatThumb(from: data, maxPixel: 360)
    }
}

/// Mesaja bağlı tek görsel karesi — decode'u task'ta yapıp state'te tutar.
struct MobileStoredThumb: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.surface)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: 112, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .task(id: id) {
            if image == nil { image = await MobileChatThumbCache.image(for: id) }
        }
    }
}

/// Kamera ile tek çekim → UIImage (nil = iptal). PhotosPicker kamerayı açamadığı için UIKit köprüsü.
/// Kapanma çağıranın state'iyle yapılır (@Environment(\.dismiss) coordinator kopyasında güvenilir değil).
struct MobileCameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

struct MobileCoachSendButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.76),
                value: configuration.isPressed
            )
    }
}

/// Masaüstü Koç composer'ındaki dönen renk akışının mobil karşılığı.
struct MobileCoachComposerGlow: View {
    let active: Bool
    let cornerRadius: CGFloat

    private let colors: [Color] = [
        Color(red: 0.031, green: 0.580, blue: 1.000),
        Color(red: 0.788, green: 0.349, blue: 0.867),
        Color(red: 1.000, green: 0.180, blue: 0.329),
        Color(red: 1.000, green: 0.565, blue: 0.016)
    ]

    var body: some View {
        TimelineView(.animation(paused: !active)) { timeline in
            let degrees = (timeline.date.timeIntervalSinceReferenceDate * 55)
                .truncatingRemainder(dividingBy: 360)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: colors + [colors[0]]),
                        center: .center,
                        angle: .degrees(degrees)
                    ),
                    lineWidth: 3
                )
                .blur(radius: 9)
        }
        .opacity(active ? 0.9 : 0)
        .animation(.easeOut(duration: 0.24), value: active)
        .allowsHitTesting(false)
    }
}

/// Koç'un ilk-token öncesi durumuyla aynı, metin boyunca kayan sakin ışık bandı.
struct MobileCoachShimmerText: View {
    let text: String
    /// Boş-ekran başlığı da bunu kullanıyor → font/renkler dışarıdan verilebilir.
    var font: Font = Typography.caption
    var base: Color = Palette.textTertiary
    var shimmer: Color = Palette.textPrimary
    /// Kaç tur döndükten sonra dursun. "Düşünüyor" göstergesi zaten kısa ömürlü
    /// (nil = sınırsız); boş ekran başlığı ise kullanıcı orada okurken sonsuza dek
    /// ekranı 60/120 Hz yeniden çizdiriyordu — birkaç tur sonra donuyor.
    var cycleLimit: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = false

    var body: some View {
        if reduceMotion || finished {
            label.foregroundStyle(base)
        } else {
            TimelineView(.animation) { timeline in
                let duration = 2.4
                let progress = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: duration) / duration
                label
                    .foregroundStyle(base)
                    .overlay {
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            LinearGradient(
                                colors: [.clear, shimmer, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: width * 0.55)
                            .offset(x: -width * 0.55 + (width * 1.55 * progress))
                        }
                        .mask(label)
                    }
            }
            .task(id: text) {
                guard let cycleLimit else { return }
                try? await Task.sleep(for: .seconds(2.4 * Double(cycleLimit)))
                finished = true
            }
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum MobileAIChatCoordinateSpace {
    static let name = "hercules.mobile-ai-chat"
}

/// Dibe-yakınlık sinyali (aşağı-in butonu görünürlüğü).
private struct MobileChatNearBottomKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = nextValue() }
}

private struct MobileAIComposerFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private enum MobileAIChatHistory {
    private static let key = "hercules.mobile.remote-ai.chat.v1"
    private static let maxTurns = 40

    static func load() -> [ChatTurn] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let turns = try? JSONDecoder().decode([ChatTurn].self, from: data)
        else { return [] }
        return Array(turns.suffix(maxTurns))
    }

    static func save(_ turns: [ChatTurn]) {
        let kept = Array(turns.suffix(maxTurns))
        if kept.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func friendlyError(_ error: Error) -> String {
        if case RemoteAIClientError.server(let status, _) = error {
            if status == 429 { return "Koç şu an önceki isteği tamamlıyor. Birazdan tekrar dene." }
            if status == 403 { return "Koç bağlantısı bu cihaz için yetkili değil." }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut:
                return "Koç'a bağlanamadım. Tailscale bağlantını kontrol edip tekrar dene."
            case .cancelled:
                return ""
            default:
                break
            }
        }
        return "Koç yanıt veremedi. Birazdan tekrar dene."
    }
}
