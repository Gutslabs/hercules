import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

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
            if store.isSending { store.stop() } else { sendWithContext() }
        } label: {
            Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle((canSendInput || store.isSending) ? ChatChrome.ink : ChatChrome.quaternary)
                .frame(width: 38, height: 38)
                .background(Circle().fill((canSendInput || store.isSending) ? ChatChrome.white : ChatChrome.panelPressed))
                .overlay(Circle().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!store.isSending && !canSendInput)
        .scaleEffect((canSendInput || store.isSending) ? 1 : 0.98)
        .help(store.isSending ? "Durdur" : "Gönder")
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
