import SwiftUI
import SwiftData
import AppKit

private enum ChatChrome {
    static let background = Color(red: 0.045, green: 0.045, blue: 0.050)
    static let panel = Color(red: 0.075, green: 0.075, blue: 0.082)
    static let panelRaised = Color(red: 0.115, green: 0.115, blue: 0.125)
    static let panelPressed = Color(red: 0.155, green: 0.155, blue: 0.165)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.16)
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.68)
    static let tertiary = Color.white.opacity(0.46)
    static let quaternary = Color.white.opacity(0.28)
    static let ink = Color.black.opacity(0.90)
    static let white = Color.white.opacity(0.92)
    static let whiteSoft = Color.white.opacity(0.12)
    static let userBubble = Color.white.opacity(0.115)
    static let assistantBubble = Color(red: 0.092, green: 0.092, blue: 0.102)
}

struct ChatSidebar: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var store: ChatStore
    @Binding var width: CGFloat
    var onClose: () -> Void

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

    /// Streaming sırasında scrollTo'yu throttle etmek için kullanılan tick.
    /// `store.messages.last?.text.count` her ~50 karakterde değiştiğinde artar.
    private var streamingScrollTick: Int {
        ((store.messages.last?.text.count ?? 0) / 50)
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

    private let minWidth: CGFloat = 320
    private let maxWidth: CGFloat = 720
    private static let chatBottomID = "chat-bottom-anchor"
    private static let chatScrollSpace = "chat-scroll-space"

    var body: some View {
        HStack(spacing: 0) {
            resizeHandle
            VStack(spacing: 0) {
                header
                Hairline()
                messagesScroll
                Hairline()
                inputBar
            }
            .frame(maxWidth: .infinity)
            .background(ChatChrome.background)
        }
        .frame(width: width)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ChatChrome.border)
                .frame(width: 0.5)
        }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        let new = width - v.translation.width
                        width = min(maxWidth, max(minWidth, new))
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ChatChrome.whiteSoft)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChatChrome.white)
            }

            modelPicker

            Spacer()

            historyMenu

            Button {
                store.newChat()
                inputFocused = true
            } label: {
                headerIcon("square.and.pencil")
            }
            .buttonStyle(.plain)
            .disabled(store.isSending)
            .opacity(store.isSending ? 0.45 : 1)
            .help("Yeni sohbet")

            Button {
                store.clear()
            } label: {
                headerIcon("trash")
            }
            .buttonStyle(.plain)
            .disabled(!canDeleteConversation || store.isSending)
            .opacity((!canDeleteConversation || store.isSending) ? 0.4 : 1)
            .help("Bu sohbeti sil")

            Button(action: onClose) {
                headerIcon("xmark")
            }
            .buttonStyle(.plain)
            .help("Kapat")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(ChatChrome.background)
        .onReceive(NotificationCenter.default.publisher(for: .aiClientChanged)) { _ in
            currentProvider = AIKeyStore.shared.provider
            currentModel = AIKeyStore.shared.model
        }
    }

    private var historyMenu: some View {
        Menu {
            Button {
                store.newChat()
                inputFocused = true
            } label: {
                Label("Yeni sohbet", systemImage: "square.and.pencil")
            }
            .disabled(store.isSending)

            Divider()

            Section("Son sohbetler") {
                ForEach(store.conversationList) { conversation in
                    Button {
                        store.selectConversation(conversation.id)
                        inputFocused = true
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
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(ChatChrome.tertiary)
                Text("Yediklerini yaz, kalorisini söyleyeyim")
                    .font(Typography.body)
                    .foregroundStyle(ChatChrome.secondary)
                Text("ör: \"300g pişmiş tavuk göğsü\"")
                    .font(Typography.caption)
                    .foregroundStyle(ChatChrome.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                GeometryReader { viewport in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
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
                                            key: ChatBottomDistanceKey.self,
                                            value: bottomGeo.frame(in: .named(Self.chatScrollSpace)).maxY - viewport.size.height
                                        )
                                    }
                                )
                        }
                        .padding(Spacing.lg)
                    }
                    .coordinateSpace(name: Self.chatScrollSpace)
                    .onPreferenceChange(ChatBottomDistanceKey.self) { distance in
                        let nearBottom = distance < 90
                        if nearBottom {
                            setAutoFollowMessages(true)
                        } else if Date() > suppressAutoFollowUntil {
                            setAutoFollowMessages(false)
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
    /// — @-mention varsa ilgili veri bölümleri de eklenir
    /// — İkisi de boşsa nil
    private func sendWithContext() {
        let mentions = UserContextSnapshot.parseMentions(store.input)
        let snapshot = UserContextSnapshot.combined(tags: mentions, ctx: ctx)
        Task { await store.send(userContext: snapshot, ctx: ctx) }
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
        let allMentions = chatMentions.union(aboutMentions)

        if !allMentions.isEmpty || aboutActive {
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
        VStack(spacing: 6) {
            // Autocomplete popup — input bar'ın hemen üstünde
            if let query = activeMentionQuery {
                mentionPopup(query: query)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            mentionHint
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

            HStack(spacing: Spacing.sm) {
                chatInputEditor
                Button {
                    sendWithContext()
                } label: {
                    Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(canSendInput ? ChatChrome.ink : ChatChrome.quaternary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(canSendInput ? ChatChrome.white : ChatChrome.panelPressed)
                        )
                        .overlay(Circle().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(!canSendInput || store.isSending)
            }
            .padding(Spacing.md)
        }
    }

    private var chatInputEditor: some View {
        ZStack(alignment: .topLeading) {
            if store.input.isEmpty {
                Text("ör: 200g pirinç pilavı")
                    .font(Typography.body)
                    .foregroundStyle(ChatChrome.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $store.input)
                .scrollContentBackground(.hidden)
                .font(Typography.body)
                .foregroundStyle(ChatChrome.primary)
                .focused($inputFocused)
                .onAppear { inputFocused = true }
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
                    if NSEvent.modifierFlags.contains(.shift) {
                        return .ignored
                    }

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
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(ChatChrome.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(inputFocused ? ChatChrome.borderStrong : ChatChrome.border, lineWidth: 0.5)
        )
    }
}

private struct ChatBottomDistanceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
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
                // Assistant avatar — küçük accent sparkle
                ZStack {
                    Circle()
                        .fill(ChatChrome.whiteSoft)
                        .frame(width: 22, height: 22)
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ChatChrome.white)
                }
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
                    Text("\(turn.text) ▍")
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
            .shadow(color: .black.opacity(turn.role == .user ? 0.18 : 0.10), radius: 10, y: 3)

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
            case .updateMealPlan: return "fork.knife"
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
