import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

/// Tam sayfa AI sohbeti (sidebar nav'da "Sohbet"). Mevcut sidebar + bottom-dock
/// chat ile AYNI `ChatStore`'u paylaşır → konuşmalar her üç yüzeyde de senkron.
/// Üç sütun: konuşma listesi rail · ortalı konuşma kolonu · şık composer.
struct ChatPageView: View {
    @Bindable var store: ChatStore
    @Environment(\.modelContext) private var ctx
    @FocusState private var inputFocused: Bool

    @State private var provider: AIProvider = AIKeyStore.shared.provider
    @State private var model: String = AIKeyStore.shared.model
    @State private var intelligence: IntelligenceLevel = AIKeyStore.shared.intelligence
    @State private var selectedMentionIndex: Int = 0
    @State private var dismissedAt: String? = nil

    // Mesaj etkileşimleri: hover'da kopyala / telefona gönder + zaman damgası
    @State private var hoveredMessageID: UUID? = nil
    @State private var copiedMessageID: UUID? = nil
    @State private var sharedMessageID: UUID? = nil
    // Akıllı oto-takip: kullanıcı yukarı kaydırıp okuyorsa typewriter onu geri çekmez
    @State private var autoFollow = true
    @State private var nearBottom = true
    @State private var suppressAutoFollowUntil = Date.distantPast
    // Rail'de hover-ile-sil
    @State private var hoveredConversationID: UUID? = nil
    @State private var confirmingDeleteID: UUID? = nil

    private static let bottomID = "chatpage-bottom"
    private static let scrollSpace = "chatpage-scroll-space"

    var body: some View {
        HStack(spacing: 0) {
            conversationRail
                .frame(width: 264)
            Rectangle().fill(ChatChrome.border).frame(width: 0.5)
            mainColumn
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChatChrome.background.ignoresSafeArea())
        .onAppear {
            provider = AIKeyStore.shared.provider
            model = AIKeyStore.shared.model
            intelligence = AIKeyStore.shared.intelligence
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { inputFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiClientChanged)) { _ in
            provider = AIKeyStore.shared.provider
            model = AIKeyStore.shared.model
            intelligence = AIKeyStore.shared.intelligence
        }
    }

    // MARK: - Conversation rail

    private var conversationRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sohbetler").eyebrow()
                Spacer()
                Button { store.newChat(); inputFocused = true } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ChatChrome.primary)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ChatChrome.panelRaised))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(ChatChrome.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(store.isSending)
                .help("Yeni sohbet")
            }
            .padding(.horizontal, Spacing.lg).padding(.top, Spacing.lg).padding(.bottom, Spacing.md)

            Button { store.newChat(); inputFocused = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Yeni sohbet").font(Typography.captionBold)
                    Spacer()
                }
                .foregroundStyle(ChatChrome.secondary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(ChatChrome.panel.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(ChatChrome.border, lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isSending)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if store.conversationList.isEmpty {
                        Text("Geçmiş yok. İlk mesajını yaz.")
                            .font(Typography.caption).foregroundStyle(ChatChrome.quaternary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    } else {
                        ForEach(store.conversationList) { conversation in
                            conversationRow(conversation)
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg).padding(.bottom, Spacing.lg)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ChatChrome.background)
        .confirmationDialog(
            "Bu sohbet silinsin mi?",
            isPresented: Binding(
                get: { confirmingDeleteID != nil },
                set: { if !$0 { confirmingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sohbeti sil", role: .destructive) {
                if let id = confirmingDeleteID { store.deleteConversation(id) }
                confirmingDeleteID = nil
            }
            Button("İptal", role: .cancel) { confirmingDeleteID = nil }
        } message: {
            Text("Bu sohbetteki tüm mesajlar kalıcı olarak silinir.")
        }
    }

    private func conversationRow(_ conversation: ChatConversation) -> some View {
        let active = conversation.id == store.currentConversationID
        let hovered = hoveredConversationID == conversation.id
        return ZStack(alignment: .trailing) {
            Button {
                store.selectConversation(conversation.id)
                inputFocused = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: active ? "bubble.left.fill" : "bubble.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? ChatChrome.accent : ChatChrome.tertiary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(conversation.title.isEmpty ? "Yeni sohbet" : conversation.title)
                            .font(Typography.captionBold)
                            .foregroundStyle(active ? ChatChrome.primary : ChatChrome.secondary)
                            .lineLimit(1)
                        Text(Fmt.relative(conversation.updatedAt))
                            .font(Typography.label)
                            .foregroundStyle(ChatChrome.quaternary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: hovered ? 26 : 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(active ? ChatChrome.panelRaised : (hovered ? ChatChrome.panel.opacity(0.5) : Color.clear)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isSending)

            if hovered && !store.isSending {
                Button { confirmingDeleteID = conversation.id } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ChatChrome.tertiary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(ChatChrome.panelPressed))
                        .overlay(Circle().strokeBorder(ChatChrome.border, lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 7)
                .help("Sohbeti sil")
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            if hovering { hoveredConversationID = conversation.id }
            else if hoveredConversationID == conversation.id { hoveredConversationID = nil }
        }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }

    // MARK: - Main column

    private var mainColumn: some View {
        VStack(spacing: 0) {
            chatHeader
            Rectangle().fill(ChatChrome.border).frame(height: 0.5)
            if store.messages.isEmpty {
                emptyState
            } else {
                conversation
            }
            composer
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            AssistantMark(size: 34, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Koç").font(Typography.bodyBold).foregroundStyle(ChatChrome.primary)
                    Circle().fill(ChatChrome.positive).frame(width: 5, height: 5)
                }
                modelMenu
            }
            Spacer()
            if !store.currentConversationTitle.isEmpty {
                Text(store.currentConversationTitle)
                    .font(Typography.caption).foregroundStyle(ChatChrome.quaternary)
                    .lineLimit(1).frame(maxWidth: 280, alignment: .trailing)
            }
        }
        .padding(.horizontal, Spacing.xl).padding(.vertical, Spacing.md)
        .background(ChatChrome.background)
    }

    /// Sağlayıcı / model / düşünme seviyesini header'dan değiştir (sidebar ile aynı mantık,
    /// `.aiClientChanged` post'lar → store istemciyi tazeler, sidebar da güncellenir).
    private var modelMenu: some View {
        Menu {
            Section("Sağlayıcı") {
                ForEach(AIProvider.selectable) { p in
                    Button {
                        AIKeyStore.shared.provider = p
                        provider = p
                        model = AIKeyStore.shared.model
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    } label: {
                        Label(p.label, systemImage: p == provider ? "checkmark" : "circle")
                    }
                }
            }
            Section("Model") {
                ForEach(provider.availableModels, id: \.self) { m in
                    Button {
                        AIKeyStore.shared.model = m
                        model = m
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    } label: {
                        Label(m, systemImage: m == model ? "checkmark" : "circle")
                    }
                }
            }
            if provider.supportsIntelligence {
                Section("Düşünme seviyesi") {
                    ForEach(IntelligenceLevel.allCases) { lvl in
                        Button {
                            AIKeyStore.shared.intelligence = lvl
                            intelligence = lvl
                            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                        } label: {
                            Label(lvl.label, systemImage: lvl == intelligence ? "checkmark" : "circle")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text("\(provider.label) · \(model)")
                    .font(Typography.caption).foregroundStyle(ChatChrome.tertiary).lineLimit(1)
                if provider.supportsIntelligence {
                    Text("· \(intelligence.label)")
                        .font(Typography.caption).foregroundStyle(ChatChrome.secondary).lineLimit(1)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(ChatChrome.quaternary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("Sağlayıcı / model / düşünme seviyesi")
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, turn in
                            if showsDaySeparator(at: index) {
                                daySeparator(turn.createdAt)
                            }
                            messageRow(turn)
                                .id(turn.id)
                        }
                        if store.isSending,
                           let last = store.messages.last,
                           last.role == .assistant, last.text.isEmpty {
                            TypingIndicator(searchQuery: store.searchingFor)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ChatNearBottomKey.self,
                                        value: geo.frame(in: .named(Self.scrollSpace)).maxY - viewport.size.height < 90
                                    )
                                }
                            )
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.xl)
                }
                .coordinateSpace(name: Self.scrollSpace)
                .background(ChatChrome.background)
                .onPreferenceChange(ChatNearBottomKey.self) { value in
                    nearBottom = value
                    if value {
                        autoFollow = true
                    } else if Date() > suppressAutoFollowUntil {
                        autoFollow = false
                    }
                }
                .onChange(of: store.messages.count) { _, _ in
                    autoFollow = true
                    scrollDown(proxy, animated: true)
                }
                .onChange(of: store.messages.last?.text) { _, _ in
                    if store.isSending, autoFollow { scrollDown(proxy, animated: false) }
                }
                .onChange(of: store.isSending) { _, sending in
                    if !sending, autoFollow { scrollDown(proxy, animated: false) }
                }
                .onAppear { scrollDown(proxy, animated: false) }
                .overlay(alignment: .bottomTrailing) {
                    if !nearBottom {
                        Button {
                            suppressAutoFollowUntil = Date().addingTimeInterval(0.15)
                            autoFollow = true
                            scrollDown(proxy, animated: true)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ChatChrome.primary)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(ChatChrome.panelRaised))
                                .overlay(Circle().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, Spacing.xl)
                        .padding(.bottom, 14)
                        .transition(.scale.combined(with: .opacity))
                        .help("En alta in")
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: nearBottom)
            }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    // MARK: - Message row (bubble + zaman damgası + hover kopyala)

    private func messageRow(_ turn: ChatTurn) -> some View {
        let streaming = store.isSending && turn.id == store.messages.last?.id && turn.role == .assistant
        return VStack(alignment: .leading, spacing: 3) {
            MessageBubble(turn: turn, isStreaming: streaming) {
                store.saveFood(in: turn, ctx: ctx)
            } onConfirmAction: { action in
                store.confirmAction(turnID: turn.id, actionID: action.id, ctx: ctx)
            } onRejectAction: { action in
                store.rejectAction(turnID: turn.id, actionID: action.id)
            }
            if !turn.text.isEmpty {
                metaRow(turn)
            }
        }
        .onHover { hovering in
            if hovering { hoveredMessageID = turn.id }
            else if hoveredMessageID == turn.id { hoveredMessageID = nil }
        }
    }

    /// Bubble altında zaman damgası + (hover'da) kopyala butonu — mesaj sahibine göre hizalı.
    private func metaRow(_ turn: ChatTurn) -> some View {
        let isUser = turn.role == .user
        let showActions = hoveredMessageID == turn.id || copiedMessageID == turn.id || sharedMessageID == turn.id
        return HStack(spacing: 10) {
            if isUser { Spacer(minLength: 0) }
            if showActions { shareButton(turn) }
            if showActions { copyButton(turn) }
            Text(Fmt.timeShort.string(from: turn.createdAt))
                .font(Typography.label)
                .foregroundStyle(ChatChrome.quaternary)
            if !isUser { Spacer(minLength: 0) }
        }
        .padding(.leading, isUser ? 0 : 30)
        .padding(.trailing, isUser ? 2 : 0)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.12), value: showActions)
    }

    private func copyButton(_ turn: ChatTurn) -> some View {
        let copied = copiedMessageID == turn.id
        return Button {
            copyToClipboard(turn.text)
            copiedMessageID = turn.id
            let id = turn.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if copiedMessageID == id { copiedMessageID = nil }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                Text(copied ? "Kopyalandı" : "Kopyala")
                    .font(Typography.label)
            }
            .foregroundStyle(copied ? ChatChrome.positive : ChatChrome.tertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mesajı kopyala")
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    // MARK: - Telefona gönder (mobil Akış feed'i)

    private func shareButton(_ turn: ChatTurn) -> some View {
        let shared = sharedMessageID == turn.id
        return Button {
            shareToPhone(turn)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: shared ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                    .font(.system(size: 9, weight: .semibold))
                Text(shared ? "Telefona gönderildi" : "Telefona gönder")
                    .font(Typography.label)
            }
            .foregroundStyle(shared ? ChatChrome.positive : ChatChrome.tertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Telefondaki Hercules Akış sekmesine gönder")
    }

    private func shareToPhone(_ turn: ChatTurn) {
        let convo = store.currentConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasConvo = !convo.isEmpty && convo != "Yeni sohbet"
        let title = hasConvo ? convo : String(turn.text.prefix(48))
        let item = FeedItem(
            title: title,
            body: turn.text,
            kind: turn.food != nil ? "recipe" : "chat",
            source: "Mac",
            conversationTitle: hasConvo ? convo : nil
        )
        FeedStore.shared.add(item)
        // Vault'a it: feed dosyası support snapshot'a girer → mobil pull'da Akış'ta görür.
        BackupService.shared.exportAsync(from: ctx)
        Task { await BackupService.shared.autoSyncWithVault(into: ctx) }
        sharedMessageID = turn.id
        let id = turn.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if sharedMessageID == id { sharedMessageID = nil }
        }
    }

    // MARK: - Gün ayracı (Bugün / Dün / tarih)

    private func showsDaySeparator(at index: Int) -> Bool {
        guard store.messages.indices.contains(index) else { return false }
        if index == 0 { return true }
        return !Calendar.current.isDate(
            store.messages[index].createdAt,
            inSameDayAs: store.messages[index - 1].createdAt
        )
    }

    private func daySeparator(_ date: Date) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(ChatChrome.border).frame(height: 0.5)
            Text(dayLabel(date))
                .font(Typography.label)
                .tracking(0.6)
                .foregroundStyle(ChatChrome.tertiary)
                .fixedSize()
            Rectangle().fill(ChatChrome.border).frame(height: 0.5)
        }
        .padding(.vertical, 4)
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "BUGÜN" }
        if cal.isDateInYesterday(date) { return "DÜN" }
        return Fmt.dateLong.string(from: date).uppercased(with: Locale(identifier: "tr_TR"))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                Spacer(minLength: 40)
                VStack(spacing: 14) {
                    AssistantMark(size: 56, cornerRadius: 17)
                    VStack(spacing: 6) {
                        Text("Koç'a sor")
                            .font(Typography.display(30)).foregroundStyle(ChatChrome.primary)
                        Text("Yemeğini, ölçünü, antrenmanını yaz; verini @ ile etiketle. Tek cümle yeter.")
                            .font(Typography.body).foregroundStyle(ChatChrome.tertiary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 440)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: Spacing.md)], spacing: Spacing.md) {
                    ForEach(Self.starters, id: \.self) { starter(prompt: $0) }
                }
                .frame(maxWidth: 720)
                Spacer(minLength: 40)
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChatChrome.background)
    }

    private static let starters = [
        "Bugün nasıl gidiyorum? @Ölçümler @Beslenme",
        "300g pişmiş tavuk göğsü + 150g pirinç",
        "@Antrenman bu haftaki planımı göster",
        "@Takvim son 7 gün ortalama kalorim ne?",
        "Yüksek proteinli bir akşam yemeği öner",
        "Kilo hedefime göre nasıl gidiyorum?"
    ]

    private func starter(prompt: String) -> some View {
        Button {
            store.input = prompt
            inputFocused = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(ChatChrome.accent)
                Text(prompt).font(Typography.caption).foregroundStyle(ChatChrome.secondary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(ChatChrome.panel.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(ChatChrome.border, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if let query = activeMentionQuery {
                mentionPopup(query: query)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if store.input.isEmpty {
                        Text("Mesaj yaz…  ( @ ile veriyi etiketle )")
                            .font(Typography.body).foregroundStyle(ChatChrome.quaternary)
                            .padding(.horizontal, 6).padding(.vertical, 8).allowsHitTesting(false)
                    }
                    TextEditor(text: $store.input)
                        .focused($inputFocused)
                        .font(Typography.body)
                        .foregroundStyle(ChatChrome.primary)
                        .scrollContentBackground(.hidden)
                        .tint(ChatChrome.accent.opacity(0.6))
                        .frame(minHeight: 24, maxHeight: 168)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2).padding(.vertical, 1)
                        .onKeyPress(.escape) {
                            if activeMentionQuery != nil { dismissedAt = store.input; return .handled }
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
                            if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                            #endif
                            if let q = activeMentionQuery {
                                let matches = filteredMentions(query: q)
                                guard !matches.isEmpty else { return .ignored }
                                insert(tag: matches[clampedSelection(in: matches.count)])
                                return .handled
                            }
                            if canSend && !store.isSending { sendWithContext() }
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
                            if newQuery != nil { selectedMentionIndex = 0 }
                        }
                        .onChange(of: store.input) { _, newValue in
                            if let d = dismissedAt, d != newValue { dismissedAt = nil }
                        }
                }
                sendButton
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(ChatChrome.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(inputFocused ? ChatChrome.accent.opacity(0.55) : ChatChrome.borderStrong, lineWidth: inputFocused ? 1.2 : 0.6))
            .animation(.easeInOut(duration: 0.15), value: inputFocused)

            Text("↩ gönder · ⇧↩ yeni satır · @ ile veri etiketle")
                .font(Typography.label).foregroundStyle(ChatChrome.quaternary)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.lg)
        .background(ChatChrome.background)
    }

    // MARK: - Mention picker (@ ile veri etiketleme)

    /// Input'un SON kelimesi `@` ile başlıyorsa, `@` sonrası query string döner.
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

    private func clampedSelection(in count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((selectedMentionIndex % count) + count) % count
    }

    /// "@partial" yerine "@DisplayName " yerleştir.
    private func insert(tag: MentionTag) {
        let text = store.input
        guard let atIndex = text.lastIndex(of: "@") else { return }
        store.input = String(text[..<atIndex]) + "@\(tag.displayName) "
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
                        HStack(spacing: 9) {
                            Image(systemName: icon(for: tag))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSelected ? ChatChrome.accent : ChatChrome.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("@\(tag.displayName)")
                                    .font(Typography.bodyBold).foregroundStyle(ChatChrome.primary)
                                Text(tag.hintAlias)
                                    .font(Typography.caption)
                                    .foregroundStyle(isSelected ? ChatChrome.secondary : ChatChrome.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "return").font(.system(size: 9, weight: .semibold)).foregroundStyle(ChatChrome.secondary)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isSelected ? ChatChrome.whiteSoft : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in if hovering { selectedMentionIndex = idx } }
                }
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    Label("Enter/Tab seç", systemImage: "return").font(.system(size: 9, weight: .medium))
                    Text("·")
                    Label("↑↓ gez", systemImage: "arrow.up.arrow.down").font(.system(size: 9, weight: .medium))
                    Text("·")
                    Label("Esc kapat", systemImage: "escape").font(.system(size: 9, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ChatChrome.quaternary)
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(ChatChrome.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sendButton: some View {
        Button {
            if store.isSending { store.stop() } else { sendWithContext() }
        } label: {
            Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(store.isSending ? ChatChrome.primary : ChatChrome.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(store.isSending ? ChatChrome.panelPressed : (canSend ? ChatChrome.accent : ChatChrome.panelPressed)))
        }
        .buttonStyle(.plain)
        .disabled(!store.isSending && !canSend)
        .help(store.isSending ? "Durdur" : "Gönder (↩)")
    }

    private var canSend: Bool {
        !store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendWithContext() {
        guard canSend, !store.isSending else { return }
        let mentions = UserContextSnapshot.parseMentions(store.input)
        let allMentions = mentions.union(UserContextSnapshot.aboutMentionTags(ctx: ctx))
        let snapshot = UserContextSnapshot.coachContext(for: store.input, explicitTags: mentions, ctx: ctx)
        let skillScope = AgentDataScope.infer(query: store.input, explicitTags: allMentions)
        let skillData = AgentDataSnapshot.make(ctx: ctx, scope: skillScope)
        store.startSend(userContext: snapshot, skillData: skillData, ctx: ctx)
    }
}
