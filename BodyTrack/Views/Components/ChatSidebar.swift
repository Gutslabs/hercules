import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

enum ChatChrome {
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
        store.startSend(userContext: snapshot, skillData: skillData, ctx: ctx)
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
                        if store.isSending { store.stop() } else { sendWithContext() }
                    } label: {
                        Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle((canSendInput || store.isSending) ? ChatChrome.ink : ChatChrome.quaternary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill((canSendInput || store.isSending) ? ChatChrome.white : ChatChrome.panelPressed)
                            )
                            .overlay(Circle().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.isSending && !canSendInput)
                    .scaleEffect((canSendInput || store.isSending) ? 1 : 0.98)
                    .help(store.isSending ? "Durdur" : "Gönder")
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
