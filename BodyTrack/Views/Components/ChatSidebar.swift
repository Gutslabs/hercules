import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

private enum ChatChrome {
    static let background = Color(red: 0.052, green: 0.052, blue: 0.058)
    static let panel = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let panelRaised = Color(red: 0.118, green: 0.118, blue: 0.128)
    static let panelPressed = Color(red: 0.158, green: 0.158, blue: 0.168)
    static let border = Color.white.opacity(0.075)
    static let borderStrong = Color.white.opacity(0.145)
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.68)
    static let tertiary = Color.white.opacity(0.46)
    static let quaternary = Color.white.opacity(0.28)
    static let accent = Palette.accent
    static let accentSoft = Palette.accent.opacity(0.14)
    static let positive = Color(red: 0.54, green: 0.82, blue: 0.68)
    static let ink = Color.black.opacity(0.90)
    static let white = Color.white.opacity(0.92)
    static let whiteSoft = Color.white.opacity(0.12)
    static let userBubble = Color.white.opacity(0.13)
    static let assistantBubble = Color(red: 0.095, green: 0.095, blue: 0.105)
}

extension Notification.Name {
    static let aiChatShouldResignInputFocus = Notification.Name("hercules.ai.chat.resign.input.focus")
}

struct ChatSidebar: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FoodPreset.sortOrder) private var foodPresets: [FoodPreset]
    @Bindable var store: ChatStore
    @Binding var width: CGFloat
    var minWidth: CGFloat = 320
    var maxWidth: CGFloat = 560
    var onClose: () -> Void
    var onSwitchToDock: () -> Void = {}

    @State private var currentProvider: AIProvider = AIKeyStore.shared.provider
    @State private var currentModel: String = AIKeyStore.shared.model
    @State private var currentIntelligence: IntelligenceLevel = AIKeyStore.shared.intelligence

    // Mention popup keyboard navigation state
    @State private var selectedMentionIndex: Int = 0
    /// Esc ile kapatıldıysa input metni değişene kadar bir daha açılmasın.
    @State private var dismissedAt: String? = nil
    /// Chat input focus — popup keyboard handling güvenilir olsun.
    @FocusState private var inputFocused: Bool
    /// Kullanıcı chat'in dibindeyse typewriter follow eder; yukarı çıktıysa rahat bırakır.
    @State private var autoFollowMessages = true
    @State private var suppressAutoFollowUntil = Date.distantPast
    @State private var showingPresetWidget = false
    @State private var presetQuery = ""
    @State private var presetFeedback: String? = nil
    @State private var collapseHandleHovering = false
    @State private var resizeCursorActive = false
    @State private var resizeStartWidth: CGFloat? = nil
    @State private var resizeStartLocationX: CGFloat? = nil

    /// Streaming sırasında scrollTo'yu throttle etmek için kullanılan tick.
    /// Uzun cevaplarda scrollTo da layout maliyeti yarattığı için daha seyrek tetiklenir.
    private var streamingScrollTick: Int {
        ((store.messages.last?.text.count ?? 0) / 320)
    }

    private var canSendInput: Bool {
        !store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canDeleteConversation: Bool {
        !store.messages.isEmpty || store.conversationList.count > 1
    }

    private var inputEditorHeight: CGFloat {
        let explicitLines = store.input.components(separatedBy: .newlines).count
        return min(118, max(38, CGFloat(explicitLines) * 20 + 24))
    }

    private static let chatBottomID = "chat-bottom-anchor"
    private static let chatScrollSpace = "chat-scroll-space"

    private var resolvedMinWidth: CGFloat {
        min(minWidth, maxWidth)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                header
                Hairline()
                messagesScroll
                Hairline()
                inputBar
            }
            .frame(maxWidth: .infinity)
            .background(ChatChrome.background)

            Rectangle()
                .fill(ChatChrome.border)
                .frame(width: 0.5)
                .allowsHitTesting(false)

            resizeHandle
        }
        .frame(width: width)
        .onReceive(NotificationCenter.default.publisher(for: .aiChatShouldResignInputFocus)) { _ in
            inputFocused = false
        }
    }

    private var resizeHandle: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { v in
                            if resizeStartWidth == nil {
                                resizeStartWidth = width
                                resizeStartLocationX = v.startLocation.x
                            }
                            let base = resizeStartWidth ?? width
                            let startX = resizeStartLocationX ?? v.startLocation.x
                            let delta = startX - v.location.x
                            let new = min(maxWidth, max(resolvedMinWidth, base + delta))
                            guard abs(width - new) >= 0.5 else { return }
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                width = new
                            }
                        }
                        .onEnded { _ in
                            resizeStartWidth = nil
                            resizeStartLocationX = nil
                        }
                )

            VStack(spacing: 8) {
                Capsule()
                    .fill(collapseHandleHovering ? ChatChrome.borderStrong : ChatChrome.border)
                    .frame(width: 4, height: 46)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
                    )

                Button(action: closeFromHandle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ChatChrome.primary)
                        .frame(width: 26, height: 38)
                        .background(
                            Capsule()
                                .fill(collapseHandleHovering ? ChatChrome.panelPressed : ChatChrome.panelRaised)
                                .shadow(color: .black.opacity(0.32), radius: 10, y: 3)
                        )
                        .overlay(Capsule().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Chat'i kapat")
            }
            .offset(x: -4)
            .padding(.bottom, 34)
        }
        .frame(width: 44)
        .frame(maxHeight: .infinity)
        .offset(x: -34)
        .onHover { hovering in
            collapseHandleHovering = hovering
            setResizeCursor(hovering)
        }
        .onDisappear {
            setResizeCursor(false)
        }
    }

    private func closeFromHandle() {
        setResizeCursor(false)
        collapseHandleHovering = false
        onClose()
    }

    private func setResizeCursor(_ active: Bool) {
        guard resizeCursorActive != active else { return }
        resizeCursorActive = active
        #if os(macOS)
        if active {
            NSCursor.resizeLeftRight.push()
        } else {
            NSCursor.pop()
        }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AssistantMark(size: 30, cornerRadius: 9)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("Codex")
                            .font(Typography.bodyBold)
                            .foregroundStyle(ChatChrome.primary)
                            .lineLimit(1)
                        Circle()
                            .fill(ChatChrome.positive)
                            .frame(width: 5, height: 5)
                    }
                    HStack(spacing: 4) {
                        Text(currentModel)
                        if currentProvider.supportsIntelligence {
                            Text("· \(currentIntelligence.label)")
                        }
                    }
                    .font(Typography.caption)
                    .foregroundStyle(ChatChrome.tertiary)
                    .lineLimit(1)
                }

                Spacer()

                Button(action: onSwitchToDock) {
                    headerIcon("arrow.down")
                }
                .buttonStyle(.plain)
                .help("Alt chat moduna geç")

                chatOptionsMenu
            }

            if !store.currentConversationTitle.isEmpty {
                Text(store.currentConversationTitle)
                    .font(Typography.caption)
                    .foregroundStyle(ChatChrome.quaternary)
                    .lineLimit(1)
                    .padding(.leading, 40)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .padding(.bottom, 10)
        .background(ChatChrome.background)
        .onReceive(NotificationCenter.default.publisher(for: .aiClientChanged)) { _ in
            currentProvider = AIKeyStore.shared.provider
            currentModel = AIKeyStore.shared.model
            currentIntelligence = AIKeyStore.shared.intelligence
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiChatShouldResignInputFocus)) { _ in
            inputFocused = false
        }
    }

    private var chatOptionsMenu: some View {
        Menu {
            Section("Sohbet") {
	                Button {
	                    store.newChat()
	                } label: {
                    Label("Yeni sohbet", systemImage: "square.and.pencil")
                }
                .disabled(store.isSending)

                if !store.conversationList.isEmpty {
                    Menu {
                        ForEach(store.conversationList) { conversation in
	                            Button {
	                                store.selectConversation(conversation.id)
	                            } label: {
                                Label(
                                    conversation.title,
                                    systemImage: conversation.id == store.currentConversationID ? "checkmark.circle.fill" : "message"
                                )
                            }
                            .disabled(store.isSending)
                        }
                    } label: {
                        Label("Geçmiş sohbetler", systemImage: "clock")
                    }
                }
            }

            Section("Model") {
                Menu {
                    ForEach(AIProvider.selectable) { provider in
                        Button {
                            AIKeyStore.shared.provider = provider
                            currentProvider = provider
                            currentModel = AIKeyStore.shared.model
                            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                        } label: {
                            Label(provider.label, systemImage: provider == currentProvider ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label("Sağlayıcı", systemImage: "cpu")
                }

                Menu {
                    ForEach(currentProvider.availableModels, id: \.self) { model in
                        Button {
                            AIKeyStore.shared.model = model
                            currentModel = model
                            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                        } label: {
                            Label(model, systemImage: model == currentModel ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label("Model", systemImage: "switch.2")
                }

                if currentProvider.supportsIntelligence {
                    Menu {
                        ForEach(IntelligenceLevel.allCases) { level in
                            Button {
                                AIKeyStore.shared.intelligence = level
                                currentIntelligence = level
                                NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                            } label: {
                                Label(level.label, systemImage: level == currentIntelligence ? "checkmark" : "circle")
                            }
                        }
                    } label: {
                        Label("Düşünme seviyesi", systemImage: "slider.horizontal.3")
                    }
                }
            }

            Section("Panel") {
                Button {
                    store.clear()
                } label: {
                    Label("Bu sohbeti sil", systemImage: "trash")
                }
                .disabled(!canDeleteConversation || store.isSending)
            }
        } label: {
            headerIcon("ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("Chat ayarları")
    }

    private var historyMenu: some View {
        Menu {
	            Button {
	                store.newChat()
	            } label: {
                Label("Yeni sohbet", systemImage: "square.and.pencil")
            }
            .disabled(store.isSending)

            Divider()

            Section("Son sohbetler") {
                ForEach(store.conversationList) { conversation in
	                    Button {
	                        store.selectConversation(conversation.id)
	                    } label: {
                        Label(
                            conversation.title,
                            systemImage: conversation.id == store.currentConversationID ? "checkmark.circle.fill" : "message"
                        )
                    }
                    .disabled(store.isSending)
                }
            }
        } label: {
            headerIcon("clock")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(store.conversationList.isEmpty)
        .opacity(store.conversationList.isEmpty ? 0.45 : 1)
        .help("Sohbet geçmişi")
    }

    private func headerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ChatChrome.secondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(ChatChrome.panelRaised))
            .overlay(Circle().strokeBorder(ChatChrome.border, lineWidth: 0.5))
    }

    private var modelPicker: some View {
        Menu {
            Section("Sağlayıcı") {
                ForEach(AIProvider.selectable) { p in
                    Button {
                        AIKeyStore.shared.provider = p
                        currentProvider = p
                        currentModel = AIKeyStore.shared.model
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    } label: {
                        if p == currentProvider {
                            Label(p.label, systemImage: "checkmark")
                        } else {
                            Text(p.label)
                        }
                    }
                }
            }
            Section("Model") {
                ForEach(currentProvider.availableModels, id: \.self) { m in
                    Button {
                        AIKeyStore.shared.model = m
                        currentModel = m
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    } label: {
                        if m == currentModel {
                            Label(m, systemImage: "checkmark")
                        } else {
                            Text(m)
                        }
                    }
                }
            }
            if currentProvider.supportsIntelligence {
                Section("Intelligence") {
                    ForEach(IntelligenceLevel.allCases) { e in
                        Button {
                            AIKeyStore.shared.intelligence = e
                            currentIntelligence = e
                            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                        } label: {
                            if e == currentIntelligence {
                                Label(e.label, systemImage: "checkmark")
                            } else {
                                Text(e.label)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(currentProvider.label)
                            .font(Typography.bodyBold)
                            .foregroundStyle(ChatChrome.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(ChatChrome.tertiary)
                    }
                    HStack(spacing: 4) {
                        Text(currentModel)
                            .font(Typography.caption)
                            .foregroundStyle(ChatChrome.tertiary)
                            .lineLimit(1)
                        if currentProvider.supportsIntelligence {
                            Text("· \(currentIntelligence.label)")
                                .font(Typography.caption)
                            .foregroundStyle(ChatChrome.secondary)
                        }
                    }
                    Text(store.currentConversationTitle)
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.quaternary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(ChatChrome.panel))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(ChatChrome.border, lineWidth: 0.5))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var messagesScroll: some View {
        if store.messages.isEmpty {
            VStack(spacing: Spacing.lg) {
                Spacer()
                VStack(spacing: 12) {
                    AssistantMark(size: 42, cornerRadius: 13)
                    VStack(spacing: 5) {
                        Text("Bugün ne yedin?")
                            .font(Typography.titleSmall)
                            .foregroundStyle(ChatChrome.primary)
                        Text("Yemeği, ölçüyü veya antrenman notunu tek cümleyle yaz.")
                            .font(Typography.caption)
                            .foregroundStyle(ChatChrome.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }

                VStack(spacing: 7) {
                    starterLine("300g pişmiş tavuk göğsü")
                    starterLine("@Takvim dün ne yemişim?")
                    starterLine("@Antrenman salı planına bak")
                }
                .frame(maxWidth: 260)
                Spacer()
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                GeometryReader { viewport in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(store.messages) { turn in
                                MessageBubble(
                                    turn: turn,
                                    isStreaming: store.isSending && turn.id == store.messages.last?.id && turn.role == .assistant
                                ) {
                                    store.saveFood(in: turn, ctx: ctx)
                                } onConfirmAction: { action in
                                    store.confirmAction(turnID: turn.id, actionID: action.id, ctx: ctx)
                                } onRejectAction: { action in
                                    store.rejectAction(turnID: turn.id, actionID: action.id)
                                }
                                .id(turn.id)
                                .transaction { transaction in
                                    transaction.animation = nil
                                    transaction.disablesAnimations = true
                                }
                            }
                            // Boş assistant turn varsa typing indicator gizlenir
                            if store.isSending,
                               let lastAssistant = store.messages.last,
                               lastAssistant.role == .assistant,
                               lastAssistant.text.isEmpty {
                                TypingIndicator(searchQuery: store.searchingFor)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(Self.chatBottomID)
                                .background(
                                    GeometryReader { bottomGeo in
                                        Color.clear.preference(
                                            key: ChatNearBottomKey.self,
                                            value: bottomGeo.frame(in: .named(Self.chatScrollSpace)).maxY - viewport.size.height < 90
                                        )
                                    }
                                )
                        }
                        .padding(Spacing.lg)
                    }
                    .coordinateSpace(name: Self.chatScrollSpace)
                    .onPreferenceChange(ChatNearBottomKey.self) { nearBottom in
                        if nearBottom {
                            DispatchQueue.main.async {
                                setAutoFollowMessages(true)
                            }
                        } else if Date() > suppressAutoFollowUntil {
                            DispatchQueue.main.async {
                                setAutoFollowMessages(false)
                            }
                        }
                    }
                    .onChange(of: store.messages.count) { _, _ in
                        setAutoFollowMessages(true)
                        scrollToChatBottom(proxy, animated: true)
                    }
                    // Streaming sırasında yalnızca kullanıcı bottom'da kaldıysa takip et.
                    // Yukarı scroll atıp okumaya başladıysa typewriter onu geri çekmez.
                    .onChange(of: streamingScrollTick) { _, _ in
                        if store.isSending, autoFollowMessages {
                            scrollToChatBottom(proxy, animated: false)
                        }
                    }
                    .onChange(of: store.isSending) { _, isSending in
                        if !isSending, autoFollowMessages {
                            scrollToChatBottom(proxy, animated: false)
                        }
                    }
                }
            }
        }
    }

    private func starterLine(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(ChatChrome.tertiary)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(ChatChrome.panel.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(ChatChrome.border, lineWidth: 0.5)
            )
    }

    private func scrollToChatBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        suppressAutoFollowUntil = Date().addingTimeInterval(0.35)
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.chatBottomID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.chatBottomID, anchor: .bottom)
        }
    }

    private func setAutoFollowMessages(_ value: Bool) {
        if autoFollowMessages != value {
            autoFollowMessages = value
        }
    }

    /// AI'ya gönderilecek context:
    /// — "Hakkında" metni daima inject edilir (kullanıcının kim olduğunu AI bilsin)
    /// — V4 coach mode'da @-mention olmasa bile alakalı veri bölümleri eklenir
    /// — İkisi de boşsa nil
    private func sendWithContext() {
        let mentions = UserContextSnapshot.parseMentions(store.input)
        let allMentions = mentions.union(UserContextSnapshot.aboutMentionTags(ctx: ctx))
        let snapshot = UserContextSnapshot.coachContext(for: store.input, explicitTags: mentions, ctx: ctx)
        let skillScope = AgentDataScope.infer(query: store.input, explicitTags: allMentions)
        let skillData = AgentDataSnapshot.make(ctx: ctx, scope: skillScope)
        inputFocused = false
        Task { await store.send(userContext: snapshot, skillData: skillData, ctx: ctx) }
    }

    private func addPresetToToday(_ preset: FoodPreset, servings: Double) {
        let entry = preset.makeFoodEntry(servings: servings)
        ctx.insert(entry)
        do {
            try ctx.save()
	            let message = "\(entry.name) bugüne eklendi"
	            presetFeedback = message
	            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if presetFeedback == message {
                    presetFeedback = nil
                }
            }
        } catch {
            presetFeedback = "Eklenemedi: \(error.localizedDescription)"
        }
    }

    // MARK: - Mention autocomplete

    /// Input'un SON kelimesi `@` ile başlıyor mu?
    /// Başlıyorsa `@` sonrası query string döner; yoksa nil.
    /// Esc ile dismiss edildiyse input değişene kadar nil döner.
    private var activeMentionQuery: String? {
        let text = store.input
        if let dismissed = dismissedAt, dismissed == text { return nil }
        // Trailing whitespace varsa son "kelime" boş demektir → popup kapalı
        if let last = text.last, last.isWhitespace || last.isNewline { return nil }
        // Aksi halde, son boşluğa kadar olan kısmı al
        let parts = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard let lastWord = parts.last, lastWord.hasPrefix("@") else { return nil }
        return String(lastWord.dropFirst())
    }

    /// Aktif query'ye göre filtrelenmiş tag listesi.
    private func filteredMentions(query: String) -> [MentionTag] {
        MentionTag.allCases.filter { $0.matches(prefix: query) }
    }

    /// Popup içeriği — query'ye göre filtrelenmiş tag listesi.
    @ViewBuilder
    private func mentionPopup(query: String) -> some View {
        let matches = filteredMentions(query: query)
        if !matches.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { idx, tag in
                    let isSelected = idx == clampedSelection(in: matches.count)
                    Button {
                        selectedMentionIndex = idx  // explicit set so insert uses correct tag
                        insert(tag: tag)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: tag))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSelected ? ChatChrome.primary : ChatChrome.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("@\(tag.displayName)")
                                    .font(Typography.bodyBold)
                                    .foregroundStyle(ChatChrome.primary)
                                Text(tag.hintAlias)
                                    .font(Typography.caption)
                                    .foregroundStyle(isSelected ? ChatChrome.secondary : ChatChrome.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "return")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(ChatChrome.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? ChatChrome.whiteSoft : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { selectedMentionIndex = idx }
                    }
                    if tag != matches.last {
                        Divider().opacity(0.4)
                    }
                }
                // Footer — kullanım ipucu
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    Label("Enter veya tıkla", systemImage: "return")
                        .font(.system(size: 9, weight: .medium))
                    Text("·")
                    Label("↑↓ ile gez", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 9, weight: .medium))
                    Text("·")
                    Label("Esc kapat", systemImage: "escape")
                        .font(.system(size: 9, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ChatChrome.quaternary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(ChatChrome.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .padding(.horizontal, Spacing.md)
        }
    }

    /// selectedMentionIndex'i geçerli aralığa kıs.
    private func clampedSelection(in count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((selectedMentionIndex % count) + count) % count
    }

    private func icon(for tag: MentionTag) -> String {
        switch tag {
        case .genelBakis: return "square.grid.2x2"
        case .olcumler:   return "list.bullet"
        case .grafikler:  return "chart.xyaxis.line"
        case .antrenman:  return "dumbbell"
        case .takvim:     return "calendar"
        case .kalori:     return "flame"
        case .yemekPlani: return "menucard"
        case .tarifler:   return "fork.knife"
        case .profil:     return "person.crop.circle"
        case .hepsi:      return "sparkles"
        }
    }

    /// "@partial" yerine "@DisplayName " yerleştir.
    private func insert(tag: MentionTag) {
        let text = store.input
        guard let atIndex = text.lastIndex(of: "@") else { return }
        let before = text[..<atIndex]
        store.input = String(before) + "@\(tag.displayName) "
        // Tıklamadan sonra focus TextField'a dönsün — sonraki tuşlar yazıya gitsin
        inputFocused = true
    }

    /// Input bar üstündeki ipucu — neyin AI'ya gideceğini gerçek zamanlı gösterir.
    @ViewBuilder
    private var mentionHint: some View {
        let chatMentions = UserContextSnapshot.parseMentions(store.input)
        let aboutMentions = UserContextSnapshot.aboutMentionTags(ctx: ctx)
        let aboutActive = UserContextSnapshot.aboutSection(ctx: ctx) != nil
        let supplementsActive = UserContextSnapshot.supplementsSection(ctx: ctx) != nil
        let allMentions = chatMentions.union(aboutMentions)

        if !allMentions.isEmpty || aboutActive || supplementsActive {
            // Aktif gönderim — kullanıcı görüyor neyin gittiğini
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 9, weight: .medium))
                    Text("Gönderilecek")
                        .font(Typography.captionBold)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(allMentions.isEmpty ? ChatChrome.tertiary : ChatChrome.primary)

                ChatHintFlow(spacing: 5) {
                    if aboutActive {
                        contextChip("Hakkında", icon: "person.crop.circle", tint: ChatChrome.primary)
                    }
                    if supplementsActive {
                        contextChip("Supplements", icon: "pills.fill", tint: ChatChrome.primary)
                    }
                    ForEach(allMentions.map(\.displayName).sorted(), id: \.self) { name in
                        contextChip(name, icon: nil, tint: ChatChrome.primary)
                    }
                    if !aboutMentions.isEmpty {
                        contextChip("bio'dan", icon: "link", tint: ChatChrome.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        } else {
            ChatHintFlow(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "at")
                        .font(.system(size: 9, weight: .medium))
                    Text("@ yaz seç")
                        .font(Typography.caption)
                }
                HStack(spacing: 0) {
                    Text("@all")
                        .font(Typography.captionBold)
                    Text(" tüm veri")
                        .font(Typography.caption)
                }
                HStack(spacing: 0) {
                    Text("Profil → Hakkında")
                        .font(Typography.captionBold)
                    Text(" yaz")
                        .font(Typography.caption)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(ChatChrome.quaternary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var presetLauncher: some View {
        Button {
            showingPresetWidget.toggle()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ChatChrome.whiteSoft)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ChatChrome.border, lineWidth: 0.5))
                    Image(systemName: "takeoutbag.and.cup.and.straw")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ChatChrome.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Presetler")
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.primary)
                    Text(presetFeedback ?? "Sık kullandıklarını ekle")
                        .font(Typography.caption)
                        .foregroundStyle(presetFeedback == nil ? ChatChrome.tertiary : ChatChrome.positive)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("\(foodPresets.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ChatChrome.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(ChatChrome.white))

                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ChatChrome.tertiary)
                    .rotationEffect(.degrees(showingPresetWidget ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(showingPresetWidget ? ChatChrome.panelPressed : ChatChrome.panelRaised.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(showingPresetWidget ? ChatChrome.borderStrong : ChatChrome.border, lineWidth: 0.55)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: showingPresetWidget)
        .popover(isPresented: $showingPresetWidget, arrowEdge: .bottom) {
            FoodPresetWidget(
                presets: foodPresets,
                query: $presetQuery,
                feedback: presetFeedback,
                onAdd: addPresetToToday
            )
            .frame(width: min(max(width - 32, 340), 460))
            .frame(maxHeight: 520)
        }
        .help("Presetler")
    }

    private func contextChip(_ text: String, icon: String?, tint: Color) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(Typography.captionBold)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            // Autocomplete popup — input bar'ın hemen üstünde
            if let query = activeMentionQuery {
                mentionPopup(query: query)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(spacing: 8) {
                mentionHint
                presetLauncher

                HStack(alignment: .bottom, spacing: Spacing.sm) {
                    chatInputEditor
                    Button {
                        sendWithContext()
                    } label: {
                        Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(canSendInput ? ChatChrome.ink : ChatChrome.quaternary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(canSendInput ? ChatChrome.white : ChatChrome.panelPressed)
                            )
                            .overlay(Circle().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSendInput || store.isSending)
                    .scaleEffect(canSendInput ? 1 : 0.98)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(ChatChrome.panel.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(ChatChrome.border, lineWidth: 0.55)
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
            .padding(.top, 2)
        }
        .background(ChatChrome.background)
    }

    private var chatInputEditor: some View {
        ZStack(alignment: .topLeading) {
            if store.input.isEmpty {
                Text("ör: 200g pirinç pilavı")
                    .font(Typography.body)
                    .foregroundStyle(ChatChrome.tertiary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $store.input)
                .scrollContentBackground(.hidden)
                .font(Typography.body)
                .foregroundStyle(ChatChrome.primary)
                .focused($inputFocused)
                .tint(ChatChrome.secondary.opacity(0.45))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(height: inputEditorHeight)
                // Esc → popup'ı kapat (input metnine dokunma)
                .onKeyPress(.escape) {
                    if activeMentionQuery != nil {
                        dismissedAt = store.input
                        return .handled
                    }
                    return .ignored
                }
                // ↓ — sonraki tag
                .onKeyPress(.downArrow) {
                    guard let q = activeMentionQuery else { return .ignored }
                    let matches = filteredMentions(query: q)
                    guard !matches.isEmpty else { return .ignored }
                    selectedMentionIndex = (clampedSelection(in: matches.count) + 1) % matches.count
                    return .handled
                }
                // ↑ — önceki tag
                .onKeyPress(.upArrow) {
                    guard let q = activeMentionQuery else { return .ignored }
                    let matches = filteredMentions(query: q)
                    guard !matches.isEmpty else { return .ignored }
                    selectedMentionIndex = (clampedSelection(in: matches.count) - 1 + matches.count) % matches.count
                    return .handled
                }
                // ⇧↩ native yeni satır; ↩ popup açıksa tag seçer, değilse gönderir.
                .onKeyPress(.return) {
                    #if os(macOS)
                    if NSEvent.modifierFlags.contains(.shift) {
                        return .ignored
                    }
                    #endif

                    if let q = activeMentionQuery {
                        let matches = filteredMentions(query: q)
                        guard !matches.isEmpty else { return .ignored }
                        insert(tag: matches[clampedSelection(in: matches.count)])
                        return .handled
                    }

                    if canSendInput {
                        sendWithContext()
                    }
                    return .handled
                }
                // Tab → seçili tag'i insert (Enter alternatifi)
                .onKeyPress(.tab) {
                    if let q = activeMentionQuery {
                        let matches = filteredMentions(query: q)
                        guard !matches.isEmpty else { return .ignored }
                        insert(tag: matches[clampedSelection(in: matches.count)])
                        return .handled
                    }
                    return .ignored
                }
                // Popup ilk açıldığında / query değiştiğinde index'i sıfırla
                .onChange(of: activeMentionQuery) { _, newQuery in
                    if newQuery != nil {
                        selectedMentionIndex = 0
                    }
                }
                // Kullanıcı yeni karakter girince Esc dismiss'i temizle
                .onChange(of: store.input) { _, newValue in
                    if let d = dismissedAt, d != newValue {
                        dismissedAt = nil
                    }
                }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(ChatChrome.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(inputFocused ? ChatChrome.borderStrong : ChatChrome.border, lineWidth: 0.55)
        )
    }
}

struct BottomCenterChatDock: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FoodPreset.sortOrder) private var foodPresets: [FoodPreset]
    @Bindable var store: ChatStore
    var onClose: () -> Void
    var onSwitchToSidebar: () -> Void

    @State private var currentProvider: AIProvider = AIKeyStore.shared.provider
    @State private var currentModel: String = AIKeyStore.shared.model
    @State private var currentIntelligence: IntelligenceLevel = AIKeyStore.shared.intelligence
    @State private var selectedMentionIndex: Int = 0
    @State private var dismissedAt: String? = nil
    @State private var autoFollowMessages = true
    @State private var suppressAutoFollowUntil = Date.distantPast
    @State private var showingPresetWidget = false
    @State private var messagesCollapsed = false
    @State private var messagePanelHeight: CGFloat = 300
    @State private var messageResizeStartHeight: CGFloat? = nil
    @State private var messageResizeHovering = false
    @State private var presetQuery = ""
    @State private var presetFeedback: String? = nil
    @FocusState private var inputFocused: Bool

    private static let dockBottomID = "bottom-dock-chat-bottom-anchor"
    private static let dockScrollSpace = "bottom-dock-chat-scroll-space"
    private static let messagePanelMinHeight: CGFloat = 150
    private static let messagePanelMaxHeight: CGFloat = 560

    private var canSendInput: Bool {
        !store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canDeleteConversation: Bool {
        !store.messages.isEmpty || store.conversationList.count > 1
    }

    private var hasDockMessages: Bool {
        !store.messages.isEmpty || store.isSending
    }

    private var inputEditorHeight: CGFloat {
        let explicitLines = store.input.components(separatedBy: .newlines).count
        return min(94, max(44, CGFloat(explicitLines) * 20 + 24))
    }

    private var clampedMessagePanelHeight: CGFloat {
        min(Self.messagePanelMaxHeight, max(Self.messagePanelMinHeight, messagePanelHeight))
    }

    private var streamingScrollTick: Int {
        ((store.messages.last?.text.count ?? 0) / 320)
    }

    var body: some View {
        VStack(spacing: 10) {
            if hasDockMessages && !messagesCollapsed {
                dockMessages
                    .frame(height: clampedMessagePanelHeight)
                    .overlay(alignment: .bottom) {
                        messageResizeHandle
                    }
                    .overlay(alignment: .bottomTrailing) {
                        messageCollapseButton
                            .padding(.trailing, 10)
                            .padding(.bottom, 10)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if hasDockMessages && messagesCollapsed {
                HStack {
                    Spacer(minLength: 0)
                    messageExpandButton
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(spacing: 8) {
                if let query = activeMentionQuery {
                    mentionPopup(query: query)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                composer
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ChatChrome.background.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(ChatChrome.borderStrong, lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.38), radius: 22, y: 10)
        }
        .frame(maxWidth: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .aiClientChanged)) { _ in
            currentProvider = AIKeyStore.shared.provider
            currentModel = AIKeyStore.shared.model
            currentIntelligence = AIKeyStore.shared.intelligence
        }
    }

    private var dockMessages: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(store.messages) { turn in
                            MessageBubble(
                                turn: turn,
                                isStreaming: store.isSending && turn.id == store.messages.last?.id && turn.role == .assistant
                            ) {
                                store.saveFood(in: turn, ctx: ctx)
                            } onConfirmAction: { action in
                                store.confirmAction(turnID: turn.id, actionID: action.id, ctx: ctx)
                            } onRejectAction: { action in
                                store.rejectAction(turnID: turn.id, actionID: action.id)
                            }
                            .id(turn.id)
                            .transaction { transaction in
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                        }

                        if store.isSending,
                           let lastAssistant = store.messages.last,
                           lastAssistant.role == .assistant,
                           lastAssistant.text.isEmpty {
                            TypingIndicator(searchQuery: store.searchingFor)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.dockBottomID)
                            .background(
                                GeometryReader { bottomGeo in
                                    Color.clear.preference(
                                        key: ChatNearBottomKey.self,
                                        value: bottomGeo.frame(in: .named(Self.dockScrollSpace)).maxY - viewport.size.height < 90
                                    )
                                }
                            )
                    }
                    .padding(12)
                }
                .coordinateSpace(name: Self.dockScrollSpace)
                .onPreferenceChange(ChatNearBottomKey.self) { nearBottom in
                    if nearBottom {
                        DispatchQueue.main.async {
                            setAutoFollowMessages(true)
                        }
                    } else if Date() > suppressAutoFollowUntil {
                        DispatchQueue.main.async {
                            setAutoFollowMessages(false)
                        }
                    }
                }
                .onChange(of: store.messages.count) { _, _ in
                    setAutoFollowMessages(true)
                    scrollToDockBottom(proxy, animated: true)
                }
                .onChange(of: streamingScrollTick) { _, _ in
                    if store.isSending, autoFollowMessages {
                        scrollToDockBottom(proxy, animated: false)
                    }
                }
                .onChange(of: store.isSending) { _, isSending in
                    if !isSending, autoFollowMessages {
                        scrollToDockBottom(proxy, animated: false)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ChatChrome.background.opacity(0.60))
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded {
            inputFocused = false
        })
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ChatChrome.border, lineWidth: 0.55)
        )
        .shadow(color: .black.opacity(0.26), radius: 18, y: 8)
    }

    private var messageResizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 24)
                .contentShape(Rectangle())

            Capsule()
                .fill(messageResizeHovering ? ChatChrome.borderStrong : ChatChrome.border)
                .frame(width: 68, height: 5)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.28), lineWidth: 0.5)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if messageResizeStartHeight == nil {
                        messageResizeStartHeight = clampedMessagePanelHeight
                    }
                    let start = messageResizeStartHeight ?? clampedMessagePanelHeight
                    let proposed = start - value.translation.height
                    resizeMessagePanel(to: proposed)
                }
                .onEnded { _ in
                    messageResizeStartHeight = nil
                }
        )
        .onHover { hovering in
            messageResizeHovering = hovering
        }
        .help("Chat yüksekliğini değiştir")
    }

    private var messageCollapseButton: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                messagesCollapsed = true
            }
            inputFocused = false
        } label: {
            chatAreaToggleIcon("chevron.down")
        }
        .buttonStyle(.plain)
        .help("Chat'i gizle")
    }

    private var messageExpandButton: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                messagesCollapsed = false
            }
            inputFocused = false
        } label: {
            chatAreaToggleIcon("chevron.up")
        }
        .buttonStyle(.plain)
        .padding(.trailing, 10)
        .help("Chat'i aç")
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            dockInputEditor
                .layoutPriority(1)
            controlCluster
            sendButton
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(inputFocused ? ChatChrome.borderStrong : ChatChrome.border, lineWidth: 0.6)
        )
    }

    private var controlCluster: some View {
        HStack(spacing: 4) {
            Button {
                store.newChat()
                inputFocused = false
            } label: {
                dockIcon("square.and.pencil")
            }
            .buttonStyle(.plain)
            .disabled(store.isSending)
            .help("Yeni sohbet")

            dockOptionsMenu

            Button(action: onClose) {
                dockIcon("xmark")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                inputFocused = false
            })
            .help("Chat'i kapat")
        }
        .frame(height: 42)
    }

    private var dockHistoryMenu: some View {
        Menu {
            Button {
                store.newChat()
                inputFocused = false
            } label: {
                Label("Yeni sohbet", systemImage: "square.and.pencil")
            }
            .disabled(store.isSending)

            Divider()

            Section("Son sohbetler") {
                ForEach(store.conversationList) { conversation in
                    Button {
                        store.selectConversation(conversation.id)
                        inputFocused = false
                    } label: {
                        Label(
                            conversation.title,
                            systemImage: conversation.id == store.currentConversationID ? "checkmark.circle.fill" : "message"
                        )
                    }
                    .disabled(store.isSending)
                }
            }
        } label: {
            dockIcon("clock")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(store.conversationList.isEmpty)
        .opacity(store.conversationList.isEmpty ? 0.45 : 1)
        .help("Sohbet geçmişi")
    }

    private var dockPresetButton: some View {
        Button {
            showingPresetWidget.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                dockIcon("takeoutbag.and.cup.and.straw")
                if foodPresets.count > 0 {
                    Text("\(foodPresets.count)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ChatChrome.ink)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(ChatChrome.white))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPresetWidget, arrowEdge: .bottom) {
            FoodPresetWidget(
                presets: foodPresets,
                query: $presetQuery,
                feedback: presetFeedback,
                onAdd: addPresetToToday
            )
            .frame(width: 430)
            .frame(maxHeight: 520)
        }
        .help(presetFeedback ?? "Presetler")
    }

    private var dockOptionsMenu: some View {
        Menu {
            Section("Sohbet") {
                if !store.conversationList.isEmpty {
                    Menu {
                        ForEach(store.conversationList) { conversation in
                            Button {
                                store.selectConversation(conversation.id)
                                inputFocused = false
                            } label: {
                                Label(
                                    conversation.title,
                                    systemImage: conversation.id == store.currentConversationID ? "checkmark.circle.fill" : "message"
                                )
                            }
                            .disabled(store.isSending)
                        }
                    } label: {
                        Label("Geçmiş sohbetler", systemImage: "clock")
                    }
                }

                Button {
                    showingPresetWidget = true
                    inputFocused = false
                } label: {
                    Label("Presetler (\(foodPresets.count))", systemImage: "takeoutbag.and.cup.and.straw")
                }

                Button(action: onSwitchToSidebar) {
                    Label("Sidebar moduna geç", systemImage: "arrow.right")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    inputFocused = false
                })
            }

            Section("Model") {
                Menu {
                    ForEach(AIProvider.selectable) { provider in
                        Button {
                            AIKeyStore.shared.provider = provider
                            currentProvider = provider
                            currentModel = AIKeyStore.shared.model
                            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                        } label: {
                            Label(provider.label, systemImage: provider == currentProvider ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label("Sağlayıcı", systemImage: "cpu")
                }

                Menu {
                    ForEach(currentProvider.availableModels, id: \.self) { model in
                        Button {
                            AIKeyStore.shared.model = model
                            currentModel = model
                            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                        } label: {
                            Label(model, systemImage: model == currentModel ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label("Model", systemImage: "switch.2")
                }

                if currentProvider.supportsIntelligence {
                    Menu {
                        ForEach(IntelligenceLevel.allCases) { level in
                            Button {
                                AIKeyStore.shared.intelligence = level
                                currentIntelligence = level
                                NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                            } label: {
                                Label(level.label, systemImage: level == currentIntelligence ? "checkmark" : "circle")
                            }
                        }
                    } label: {
                        Label("Düşünme seviyesi", systemImage: "slider.horizontal.3")
                    }
                }
            }

            Section("Panel") {
                Button {
                    store.clear()
                    inputFocused = false
                } label: {
                    Label("Bu sohbeti sil", systemImage: "trash")
                }
                .disabled(!canDeleteConversation || store.isSending)
            }
        } label: {
            dockIcon("ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            inputFocused = false
        })
        .popover(isPresented: $showingPresetWidget, arrowEdge: .bottom) {
            FoodPresetWidget(
                presets: foodPresets,
                query: $presetQuery,
                feedback: presetFeedback,
                onAdd: addPresetToToday
            )
            .frame(width: 430)
            .frame(maxHeight: 520)
        }
        .help("Chat ayarları")
    }

    private var sendButton: some View {
        Button {
            sendWithContext()
        } label: {
            Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(canSendInput ? ChatChrome.ink : ChatChrome.quaternary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(canSendInput ? ChatChrome.white : ChatChrome.panelPressed))
                .overlay(Circle().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!canSendInput || store.isSending)
        .scaleEffect(canSendInput ? 1 : 0.98)
        .help("Gönder")
    }

    private var dockInputEditor: some View {
        ZStack(alignment: .topLeading) {
            if store.input.isEmpty {
                Text("AI'ya sor...")
                    .font(Typography.body)
                    .foregroundStyle(ChatChrome.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 13)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $store.input)
                .scrollContentBackground(.hidden)
                .font(Typography.body)
                .foregroundStyle(ChatChrome.primary)
                .focused($inputFocused)
                .tint(ChatChrome.secondary.opacity(0.45))
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
                .frame(height: inputEditorHeight)
                .onKeyPress(.escape) {
                    if activeMentionQuery != nil {
                        dismissedAt = store.input
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.downArrow) {
                    guard let q = activeMentionQuery else { return .ignored }
                    let matches = filteredMentions(query: q)
                    guard !matches.isEmpty else { return .ignored }
                    selectedMentionIndex = (clampedSelection(in: matches.count) + 1) % matches.count
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard let q = activeMentionQuery else { return .ignored }
                    let matches = filteredMentions(query: q)
                    guard !matches.isEmpty else { return .ignored }
                    selectedMentionIndex = (clampedSelection(in: matches.count) - 1 + matches.count) % matches.count
                    return .handled
                }
                .onKeyPress(.return) {
                    #if os(macOS)
                    if NSEvent.modifierFlags.contains(.shift) {
                        return .ignored
                    }
                    #endif

                    if let q = activeMentionQuery {
                        let matches = filteredMentions(query: q)
                        guard !matches.isEmpty else { return .ignored }
                        insert(tag: matches[clampedSelection(in: matches.count)])
                        return .handled
                    }

                    if canSendInput {
                        sendWithContext()
                    }
                    return .handled
                }
                .onKeyPress(.tab) {
                    if let q = activeMentionQuery {
                        let matches = filteredMentions(query: q)
                        guard !matches.isEmpty else { return .ignored }
                        insert(tag: matches[clampedSelection(in: matches.count)])
                        return .handled
                    }
                    return .ignored
                }
                .onChange(of: activeMentionQuery) { _, newQuery in
                    if newQuery != nil {
                        selectedMentionIndex = 0
                    }
                }
                .onChange(of: store.input) { _, newValue in
                    if let d = dismissedAt, d != newValue {
                        dismissedAt = nil
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func dockIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ChatChrome.secondary)
            .frame(width: 30, height: 30)
            .background(Circle().fill(ChatChrome.panelRaised.opacity(0.88)))
            .overlay(Circle().strokeBorder(ChatChrome.border, lineWidth: 0.5))
    }

    private func chatAreaToggleIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(ChatChrome.primary)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(ChatChrome.panelRaised.opacity(0.94))
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            )
            .overlay(Circle().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.55))
    }

    private func scrollToDockBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        suppressAutoFollowUntil = Date().addingTimeInterval(0.35)
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.dockBottomID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.dockBottomID, anchor: .bottom)
        }
    }

    private func setAutoFollowMessages(_ value: Bool) {
        if autoFollowMessages != value {
            autoFollowMessages = value
        }
    }

    private func resizeMessagePanel(to proposedHeight: CGFloat) {
        let clamped = min(Self.messagePanelMaxHeight, max(Self.messagePanelMinHeight, proposedHeight))
        guard abs(messagePanelHeight - clamped) >= 0.5 else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            messagePanelHeight = clamped
        }
    }

    private func sendWithContext() {
        if messagesCollapsed {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                messagesCollapsed = false
            }
        }
        let mentions = UserContextSnapshot.parseMentions(store.input)
        let allMentions = mentions.union(UserContextSnapshot.aboutMentionTags(ctx: ctx))
        let snapshot = UserContextSnapshot.coachContext(for: store.input, explicitTags: mentions, ctx: ctx)
        let skillScope = AgentDataScope.infer(query: store.input, explicitTags: allMentions)
        let skillData = AgentDataSnapshot.make(ctx: ctx, scope: skillScope)
        inputFocused = false
        Task { await store.send(userContext: snapshot, skillData: skillData, ctx: ctx) }
    }

    private func addPresetToToday(_ preset: FoodPreset, servings: Double) {
        let entry = preset.makeFoodEntry(servings: servings)
        ctx.insert(entry)
        do {
            try ctx.save()
            let message = "\(entry.name) bugüne eklendi"
            presetFeedback = message
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if presetFeedback == message {
                    presetFeedback = nil
                }
            }
        } catch {
            presetFeedback = "Eklenemedi: \(error.localizedDescription)"
        }
    }

    private var activeMentionQuery: String? {
        let text = store.input
        if let dismissed = dismissedAt, dismissed == text { return nil }
        if let last = text.last, last.isWhitespace || last.isNewline { return nil }
        let parts = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard let lastWord = parts.last, lastWord.hasPrefix("@") else { return nil }
        return String(lastWord.dropFirst())
    }

    private func filteredMentions(query: String) -> [MentionTag] {
        MentionTag.allCases.filter { $0.matches(prefix: query) }
    }

    @ViewBuilder
    private func mentionPopup(query: String) -> some View {
        let matches = filteredMentions(query: query)
        if !matches.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { idx, tag in
                    let isSelected = idx == clampedSelection(in: matches.count)
                    Button {
                        selectedMentionIndex = idx
                        insert(tag: tag)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: tag))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSelected ? ChatChrome.primary : ChatChrome.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("@\(tag.displayName)")
                                    .font(Typography.bodyBold)
                                    .foregroundStyle(ChatChrome.primary)
                                Text(tag.hintAlias)
                                    .font(Typography.caption)
                                    .foregroundStyle(isSelected ? ChatChrome.secondary : ChatChrome.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "return")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(ChatChrome.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? ChatChrome.whiteSoft : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { selectedMentionIndex = idx }
                    }
                    if tag != matches.last {
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(ChatChrome.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func clampedSelection(in count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((selectedMentionIndex % count) + count) % count
    }

    private func insert(tag: MentionTag) {
        let text = store.input
        guard let atIndex = text.lastIndex(of: "@") else { return }
        let before = text[..<atIndex]
        store.input = String(before) + "@\(tag.displayName) "
        inputFocused = true
    }

    private func icon(for tag: MentionTag) -> String {
        switch tag {
        case .genelBakis: return "square.grid.2x2"
        case .olcumler:   return "list.bullet"
        case .grafikler:  return "chart.xyaxis.line"
        case .antrenman:  return "dumbbell"
        case .takvim:     return "calendar"
        case .kalori:     return "flame"
        case .yemekPlani: return "menucard"
        case .tarifler:   return "fork.knife"
        case .profil:     return "person.crop.circle"
        case .hepsi:      return "sparkles"
        }
    }
}

private struct AssistantMark: View {
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ChatChrome.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(ChatChrome.borderStrong, lineWidth: 0.6)
                )
            Image(systemName: "sparkles")
                .font(.system(size: max(10, size * 0.38), weight: .semibold))
                .foregroundStyle(ChatChrome.primary)
        }
        .frame(width: size, height: size)
    }
}

private struct FoodPresetWidget: View {
    let presets: [FoodPreset]
    @Binding var query: String
    let feedback: String?
    var onAdd: (FoodPreset, Double) -> Void

    private var filteredPresets: [FoodPreset] {
        let q = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return presets }
        return presets.filter { preset in
            normalized([preset.brand, preset.name, preset.category, preset.note, preset.searchText].joined(separator: " "))
                .contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ChatChrome.panelRaised)
                            .frame(width: 34, height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
                        Image(systemName: "takeoutbag.and.cup.and.straw")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ChatChrome.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Presetler")
                            .font(Typography.bodyBold)
                            .foregroundStyle(ChatChrome.primary)
                        Text("Sık kullandıklarını bugüne ekle")
                            .font(Typography.caption)
                            .foregroundStyle(ChatChrome.tertiary)
                    }

                    Spacer(minLength: 0)

                    Text("\(filteredPresets.count)")
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(ChatChrome.whiteSoft))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ARA")
                        .font(Typography.label)
                        .tracking(0.8)
                        .foregroundStyle(ChatChrome.quaternary)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ChatChrome.tertiary)
                        TextField("Protein, marka, ürün ara", text: $query)
                            .textFieldStyle(.plain)
                            .font(Typography.body)
                            .foregroundStyle(ChatChrome.primary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(ChatChrome.panelRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(ChatChrome.border, lineWidth: 0.5)
                    )
                }

                if let feedback {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.positive)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(ChatChrome.positive.opacity(0.12))
                        )
                }
            }
            .padding(14)

            Hairline()

            if filteredPresets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(ChatChrome.quaternary)
                    Text("Preset bulunamadı")
                        .font(Typography.bodyBold)
                        .foregroundStyle(ChatChrome.secondary)
                    Text("Aramayı biraz kısaltmayı dene.")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredPresets) { preset in
                            FoodPresetRow(preset: preset, onAdd: onAdd)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(ChatChrome.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(ChatChrome.borderStrong, lineWidth: 0.6)
        )
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased(with: Locale(identifier: "tr_TR"))
    }
}

private struct FoodPresetRow: View {
    let preset: FoodPreset
    var onAdd: (FoodPreset, Double) -> Void

    private var defaultServings: Double {
        max(1, preset.defaultServings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ChatChrome.whiteSoft)
                        .frame(width: 34, height: 34)
                    Image(systemName: "bolt.heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ChatChrome.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.brand)
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.tertiary)
                    Text(preset.name)
                        .font(Typography.bodyBold)
                        .foregroundStyle(ChatChrome.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Fmt.int(preset.servingGrams)) g / \(preset.servingLabel)")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.int(preset.calories(for: defaultServings)))
                        .font(Typography.monoLarge)
                        .foregroundStyle(ChatChrome.primary)
                    Text("kcal")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                }
            }

            Text(preset.note)
                .font(Typography.caption)
                .foregroundStyle(ChatChrome.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                presetMacroChip("P", preset.protein(for: defaultServings))
                presetMacroChip("K", preset.carbs(for: defaultServings))
                presetMacroChip("Y", preset.fat(for: defaultServings))
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    onAdd(preset, defaultServings)
                } label: {
                    Label(preset.servingCountText(defaultServings), systemImage: "plus")
                        .font(Typography.captionBold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ChatChrome.ink)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.white))

                Button {
                    onAdd(preset, 1)
                } label: {
                    Text(preset.servingCountText(1))
                        .font(Typography.captionBold)
                        .frame(width: 82)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ChatChrome.secondary)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.whiteSoft))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(ChatChrome.assistantBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(ChatChrome.border, lineWidth: 0.5)
        )
    }

    private func presetMacroChip(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Typography.captionBold)
                .foregroundStyle(ChatChrome.tertiary)
            Text(value.map { "\(Fmt.num($0, digits: 1))g" } ?? "—")
                .font(Typography.captionBold)
                .foregroundStyle(ChatChrome.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(ChatChrome.whiteSoft))
    }
}

private struct ChatNearBottomKey: PreferenceKey {
    static var defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

private struct ChatHintFlow<Content: View>: View {
    var spacing: CGFloat = 5
    @ViewBuilder var content: Content

    var body: some View {
        ChatHintWrappingHStack(spacing: spacing) {
            content
        }
    }
}

private struct ChatHintWrappingHStack: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        guard maxWidth > 0 else {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(
                width: sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)),
                height: sizes.map(\.height).max() ?? 0
            )
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            measuredWidth = max(measuredWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: measuredWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct MessageBubble: View {
    let turn: ChatTurn
    let isStreaming: Bool
    var onSave: () -> Void
    var onConfirmAction: (AIAppAction) -> Void
    var onRejectAction: (AIAppAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if turn.role == .user {
                Spacer(minLength: 32)
            } else {
                AssistantMark(size: 22, cornerRadius: 7)
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let q = turn.searchedFor {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Web'de arandı: \"\(q)\"")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(ChatChrome.tertiary)
                    .padding(.bottom, 2)
                }
                // Streaming sırasında satır sonunda blinking cursor.
                if isStreaming && !turn.text.isEmpty {
                    Text(turn.text + " ▍")
                        .font(Typography.body)
                        .foregroundStyle(ChatChrome.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(turn.text)
                        .font(Typography.body)
                        .foregroundStyle(ChatChrome.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if let food = turn.food {
                    foodCard(food)
                }
                if !turn.actions.isEmpty {
                    ForEach(turn.actions) { action in
                        actionCard(action)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                bubbleShape
                    .fill(turn.role == .user ? ChatChrome.userBubble : ChatChrome.assistantBubble)
            )
            .overlay(
                bubbleShape
                    .strokeBorder(turn.role == .user ? ChatChrome.borderStrong : ChatChrome.border, lineWidth: 0.5)
            )

            if turn.role == .assistant {
                Spacer(minLength: 32)
            }
        }
    }

    /// Asimetrik bubble köşeleri — chat app pattern'i (mesaj sahibine yakın köşe sivri).
    private var bubbleShape: UnevenRoundedRectangle {
        let r: CGFloat = Radius.md
        let small: CGFloat = 4
        if turn.role == .user {
            return UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: r,
                bottomTrailingRadius: small,
                topTrailingRadius: r,
                style: .continuous
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: small,
                bottomLeadingRadius: r,
                bottomTrailingRadius: r,
                topTrailingRadius: r,
                style: .continuous
            )
        }
    }

    private func foodCard(_ food: AIFoodResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name ?? "Yemek")
                        .font(Typography.bodyBold)
                        .foregroundStyle(ChatChrome.primary)
                    if let g = food.grams {
                        Text("\(Fmt.int(g)) g")
                            .font(Typography.caption)
                            .foregroundStyle(ChatChrome.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(Fmt.int(food.calories ?? 0))
                            .font(Typography.monoLarge)
                            .foregroundStyle(ChatChrome.primary)
                        Text("kcal")
                            .font(Typography.caption)
                            .foregroundStyle(ChatChrome.tertiary)
                    }
                }
            }
            if food.protein_g != nil || food.carbs_g != nil || food.fat_g != nil {
                HStack(spacing: 10) {
                    macroChip("P", food.protein_g)
                    macroChip("K", food.carbs_g)
                    macroChip("Y", food.fat_g)
                }
            }
            Button(action: onSave) {
                HStack(spacing: 5) {
                    Image(systemName: turn.saved ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(turn.saved ? "Eklendi" : "Bugüne ekle")
                        .font(Typography.bodyBold)
                }
                .foregroundStyle(turn.saved ? ChatChrome.secondary : ChatChrome.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                        .fill(turn.saved ? ChatChrome.whiteSoft : ChatChrome.white)
                )
            }
            .buttonStyle(.plain)
            .disabled(turn.saved)
        }
    }

    private func actionCard(_ action: AIAppAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: actionIcon(action))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(actionTint(action))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(actionTint(action).opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(action.displayTitle)
                            .font(Typography.bodyBold)
                            .foregroundStyle(ChatChrome.primary)
                        statusPill(action)
                    }
                    Text(action.displaySummary)
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let result = action.resultMessage, !result.isEmpty {
                        Text(result)
                            .font(Typography.caption)
                            .foregroundStyle(action.status == .failed ? Color.red.opacity(0.85) : ChatChrome.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if action.status == .pending && action.requiresConfirmation {
                HStack(spacing: 8) {
                    Button {
                        onConfirmAction(action)
                    } label: {
                        Label("Onayla", systemImage: "checkmark")
                            .font(Typography.captionBold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChatChrome.ink)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.white))

                    Button {
                        onRejectAction(action)
                    } label: {
                        Text("Vazgeç")
                            .font(Typography.captionBold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChatChrome.secondary)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.whiteSoft))
                }
            }
        }
        .padding(.top, 2)
    }

    private func statusPill(_ action: AIAppAction) -> some View {
        Text(statusText(action.status, requiresConfirmation: action.requiresConfirmation))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(actionTint(action))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(actionTint(action).opacity(0.13)))
    }

    private func statusText(_ status: AIAppActionStatus, requiresConfirmation: Bool) -> String {
        switch status {
        case .pending: return requiresConfirmation ? "ONAY BEKLİYOR" : "BEKLİYOR"
        case .applied: return "UYGULANDI"
        case .rejected: return "VAZGEÇİLDİ"
        case .failed: return "HATA"
        }
    }

    private func actionIcon(_ action: AIAppAction) -> String {
        switch action.status {
        case .applied: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .pending:
            switch action.tool {
            case .logFood: return "plus.circle"
            case .addRecipe: return "book.closed"
            case .updateWorkoutPlan: return "dumbbell"
            }
        }
    }

    private func actionTint(_ action: AIAppAction) -> Color {
        switch action.status {
        case .applied: return Color(red: 0.54, green: 0.82, blue: 0.68)
        case .rejected: return ChatChrome.tertiary
        case .failed: return Color(red: 1.0, green: 0.45, blue: 0.42)
        case .pending: return action.requiresConfirmation ? ChatChrome.white : ChatChrome.secondary
        }
    }

    private func macroChip(_ letter: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Circle().fill(ChatChrome.quaternary).frame(width: 5, height: 5)
            Text(letter).font(Typography.caption).foregroundStyle(ChatChrome.tertiary)
            Text(value.map { "\(Fmt.int($0))g" } ?? "—")
                .font(Typography.caption)
                .foregroundStyle(ChatChrome.secondary)
        }
    }
}

private struct TypingIndicator: View {
    var searchQuery: String? = nil
    @State private var phase = 0
    @State private var timer: Timer? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let q = searchQuery {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ChatChrome.white)
                Text("Web'de aranıyor: \"\(q)\"")
                    .font(Typography.caption)
                    .foregroundStyle(ChatChrome.secondary)
            } else {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(ChatChrome.tertiary)
                        .frame(width: 5, height: 5)
                        .opacity(phase == i ? 1 : 0.3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(ChatChrome.assistantBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(ChatChrome.border, lineWidth: 0.5)
        )
        .onAppear {
            // Timer @State'e bağlı → onDisappear'da invalidate'lenir.
            // Daha önce her appear yeni timer açıyordu, leak yapıyordu.
            timer?.invalidate()
            let t = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                Task { @MainActor in
                    phase = (phase + 1) % 3
                }
            }
            timer = t
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

struct FloatingChatButton: View {
    var isOpen: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.96), Color.white.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
                Image(systemName: isOpen ? "xmark" : "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ChatChrome.ink)
            }
            .scaleEffect(hovering ? 1.06 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Kalori Asistanı")
    }
}
