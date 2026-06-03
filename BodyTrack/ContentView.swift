import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Navigation tabs

enum NavTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard, measurements, charts, workout, analysis, calendar, recipes, coach, chat, memory, system, profile
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:    return "Genel Bakış"
        case .measurements: return "Ölçümler"
        case .charts:       return "Grafikler"
        case .workout:      return "Antrenman"
        case .analysis:     return "Analiz"
        case .calendar:     return "Takvim"
        case .recipes:      return "Tarifler"
        case .coach:        return "Koç"
        case .chat:         return "Sohbet"
        case .memory:       return "Hafıza"
        case .system:       return "System"
        case .profile:      return "Profil"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:    return "square.grid.2x2"
        case .measurements: return "list.bullet"
        case .charts:       return "chart.xyaxis.line"
        case .workout:      return "dumbbell"
        case .analysis:     return "gauge.medium"
        case .calendar:     return "calendar"
        case .recipes:      return "fork.knife"
        case .coach:        return "sparkles"
        case .chat:         return "bubble.left.and.text.bubble.right"
        case .memory:       return "brain"
        case .system:       return "chevron.left.forwardslash.chevron.right"
        case .profile:      return "person.crop.circle"
        }
    }
}

/// Sidebar kategorileri.
enum NavCategory: String, CaseIterable, Identifiable, Hashable {
    case takip, beslenme, ai, admin

    var id: String { rawValue }

    var label: String {
        switch self {
        case .takip:    return "Takip"
        case .beslenme: return "Beslenme"
        case .ai:       return "AI"
        case .admin:    return "Admin"
        }
    }

    var subtitle: String {
        switch self {
        case .takip:    return "Ölçüm ve performans"
        case .beslenme: return "Plan, kayıt ve tarif"
        case .ai:       return "Koç ve sohbet"
        case .admin:    return "Hafıza ve sistem promptları"
        }
    }

    var tabs: [NavTab] {
        switch self {
        case .takip:    return [.dashboard, .measurements, .charts, .workout, .analysis]
        case .beslenme: return [.calendar, .recipes]
        case .ai:       return [.coach, .chat]
        case .admin:    return [.memory, .system]
        }
    }
}

enum ChatPresentationMode: String {
    case sidebar
    case dock
}

// MARK: - Root view

struct ContentView: View {
    @State private var selection: NavTab? = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var chatStore = ChatStore()
    @State private var chatOpen: Bool = false
    @AppStorage("hercules.chat.presentationMode") private var chatPresentationMode: ChatPresentationMode = .sidebar
    @State private var chatWidth: CGFloat = 380
    @State private var showingPromptTips: Bool = false
    @State private var saveErrors = SaveErrorReporter.shared
    private let chatMinWidth: CGFloat = 320
    private let chatMaxWidth: CGFloat = 560
    private let detailReserveWidth: CGFloat = 760

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 226, ideal: 252, max: 292)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .toolbarBackground(SidebarChrome.background, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        .overlay {
            if showingPromptTips {
                PromptTipsOverlay {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        showingPromptTips = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .alert("Kaydedilemedi", isPresented: Binding(
            get: { saveErrors.message != nil },
            set: { if !$0 { saveErrors.message = nil } }
        )) {
            Button("Tamam", role: .cancel) { saveErrors.message = nil }
        } message: {
            Text(saveErrors.message ?? "")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        HerculesSidebar(
            selection: $selection,
            onShowPromptTips: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    showingPromptTips = true
                }
            }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            resignAIChatInputFocus()
        })
    }

    // MARK: Detail column (with optional right-side chat)

    private var detailColumn: some View {
        GeometryReader { proxy in
            let maxAllowedChatWidth = maxChatWidth(for: proxy.size.width)
            let dockWidth = max(280, min(760, proxy.size.width - 56))
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    selectedDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded {
                            resignAIChatInputFocus()
                        })
                        // Input DIŞINDA bir yere tıklayınca metin alanı focus'unu bırak
                        // (cursor kalmasın) — TÜM detay sayfaları için. Buton/TextField'lar
                        // kendi tıklamasını tüketir; bu yalnızca non-interaktif tıklamada çalışır.
                        .onTapGesture { dismissTextFocus() }

                    if chatOpen && chatPresentationMode == .sidebar {
                        ChatSidebar(
                            store: chatStore,
                            width: chatWidthBinding(maxWidth: maxAllowedChatWidth),
                            minWidth: chatMinWidth,
                            maxWidth: maxAllowedChatWidth,
                            onClose: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    chatOpen = false
                                }
                            },
                            onSwitchToDock: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    chatPresentationMode = .dock
                                }
                            }
                        )
                        .frame(maxHeight: .infinity)
                        .ignoresSafeArea(.container, edges: [.top, .bottom])
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: chatOpen)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: chatPresentationMode)

                if chatOpen && chatPresentationMode == .dock {
                    BottomCenterChatDock(
                        store: chatStore,
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                chatOpen = false
                            }
                        },
                        onSwitchToSidebar: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                chatPresentationMode = .sidebar
                            }
                        }
                    )
                    .frame(width: dockWidth)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
                }

                if !chatOpen {
                    FloatingChatButton(isOpen: chatOpen) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            chatOpen = true
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .onAppear {
                columnVisibility = .all
                clampStoredChatWidth(maxWidth: maxAllowedChatWidth)
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                columnVisibility = .all
                clampStoredChatWidth(maxWidth: maxChatWidth(for: newWidth))
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .toolbar(chatOpen && chatPresentationMode == .sidebar ? .hidden : .visible, for: .windowToolbar)
        #endif
    }

    private func maxChatWidth(for detailWidth: CGFloat) -> CGFloat {
        let reserveLimited = detailWidth - detailReserveWidth
        let fractionLimited = detailWidth * 0.40
        let naturalMax = min(chatMaxWidth, reserveLimited, fractionLimited)
        return max(chatMinWidth, naturalMax)
    }

    private func clampedChatWidth(_ value: CGFloat, maxWidth: CGFloat) -> CGFloat {
        min(maxWidth, max(chatMinWidth, value))
    }

    private func chatWidthBinding(maxWidth: CGFloat) -> Binding<CGFloat> {
        Binding(
            get: {
                clampedChatWidth(chatWidth, maxWidth: maxWidth)
            },
            set: { newWidth in
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    chatWidth = clampedChatWidth(newWidth, maxWidth: maxWidth)
                }
            }
        )
    }

    private func clampStoredChatWidth(maxWidth: CGFloat) {
        let clamped = clampedChatWidth(chatWidth, maxWidth: maxWidth)
        guard abs(chatWidth - clamped) > 0.5 else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            chatWidth = clamped
        }
    }

    private func resignAIChatInputFocus() {
        NotificationCenter.default.post(name: .aiChatShouldResignInputFocus, object: nil)
    }

    /// O an düzenlenen metin alanının (TextField/TextEditor) focus'unu bırakır — böylece
    /// input dışına tıklayınca yanıp sönen cursor kalmaz. macOS first-responder'ı temizler;
    /// her sayfa için tek noktadan, alan başına @FocusState gerektirmeden çalışır.
    private func dismissTextFocus() {
        #if canImport(AppKit)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch selection ?? .dashboard {
        case .dashboard:    DashboardView()
        case .measurements: MeasurementsView()
        case .charts:       ChartsView()
        case .workout:      WorkoutView()
        case .analysis:     AnalysisView()
        case .calendar:     CalendarView()
        case .recipes:      RecipesView()
        case .coach:        CoachView()
        case .chat:         ChatPageView(store: chatStore)
        case .memory:       MemoryView()
        case .system:       SystemPromptsView()
        case .profile:      ProfileView()
        }
    }
}

// MARK: - Admin ▸ System (düzenlenebilir promptlar)

/// Uygulamadaki tüm AI sistem promptlarını listeleyip düzenlemeyi sağlayan admin ekranı.
/// Sol rail'de gruplu prompt listesi, sağda seçili prompt'un editörü. Override'lar
/// `PromptStore`'da (UserDefaults) tutulur; "Varsayılana dön" ile fabrika metni geri gelir.
struct SystemPromptsView: View {
    private let store = PromptStore.shared
    @State private var selected: PromptKey = .chatSystem
    @State private var draft: String = ""
    @State private var showResetConfirm = false
    @State private var savedFlash = false

    private var groups: [(String, [PromptKey])] {
        var order: [String] = []
        var map: [String: [PromptKey]] = [:]
        for key in PromptKey.allCases {
            if map[key.group] == nil { order.append(key.group); map[key.group] = [] }
            map[key.group]?.append(key)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private var isDirty: Bool { draft != store.text(selected) }
    private var differsFromDefault: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
            != selected.defaultText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail.frame(width: 286)
            Rectangle().fill(Palette.border).frame(width: 0.5)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .onAppear { draft = store.text(selected) }
        .onChange(of: selected) { _, newKey in draft = store.text(newKey) }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SİSTEM").eyebrow()
                Text("Promptlar")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text("Uygulamadaki tüm AI promptları. Düzenle, kaydet; istediğinde varsayılana dön.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.lg).padding(.top, Spacing.lg).padding(.bottom, Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.0) { group, keys in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.uppercased(with: Locale(identifier: "tr_TR")))
                                .font(Typography.label).tracking(0.6)
                                .foregroundStyle(Palette.textTertiary)
                                .padding(.horizontal, 10)
                            ForEach(keys) { key in railRow(key) }
                        }
                    }
                }
                .padding(.horizontal, Spacing.md).padding(.bottom, Spacing.lg)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.surface)
    }

    private func railRow(_ key: PromptKey) -> some View {
        let active = key == selected
        let overridden = store.isOverridden(key)
        return Button { selected = key } label: {
            HStack(spacing: 9) {
                Image(systemName: active ? "doc.text.fill" : "doc.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active ? Palette.accent : Palette.textTertiary)
                    .frame(width: 16)
                Text(key.title)
                    .font(Typography.captionBold)
                    .foregroundStyle(active ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if overridden {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6)
                        .help("Düzenlendi")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(active ? Palette.surfaceElevated : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                detailHeader
                infoCard
                editorCard
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(selected.title)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                if store.isOverridden(selected) {
                    Text("DÜZENLENDİ")
                        .font(.system(size: 9, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.accent.opacity(0.14)))
                }
                Spacer(minLength: 0)
            }
            Text(selected.locationNote)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var infoCard: some View {
        if let note = selected.dynamicNote {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 1)
                Text(note)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.accent.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.accent.opacity(0.18), lineWidth: 0.5))
        }
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PROMPT METNİ")
                    .font(Typography.label).tracking(0.6)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("\(draft.count) karakter")
                    .font(Typography.label)
                    .foregroundStyle(Palette.textTertiary)
            }

            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 420)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))

            actionRow
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { save() } label: {
                Label(savedFlash ? "Kaydedildi" : "Kaydet", systemImage: savedFlash ? "checkmark" : "tray.and.arrow.down")
                    .font(Typography.captionBold)
                    .foregroundStyle(isDirty ? Palette.background : Palette.textTertiary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(isDirty ? Palette.accent : Palette.surfaceElevated))
            }
            .buttonStyle(.plain)
            .disabled(!isDirty)

            Button { copyDraft() } label: {
                Label("Kopyala", systemImage: "doc.on.doc")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Palette.surfaceElevated))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button { showResetConfirm = true } label: {
                Label("Varsayılana dön", systemImage: "arrow.uturn.backward")
                    .font(Typography.captionBold)
                    .foregroundStyle(differsFromDefault ? Palette.negative : Palette.textTertiary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Palette.surfaceElevated))
            }
            .buttonStyle(.plain)
            .disabled(!store.isOverridden(selected) && !differsFromDefault)
            .confirmationDialog("Varsayılana dönülsün mü?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Varsayılana dön", role: .destructive) { resetToDefault() }
                Button("İptal", role: .cancel) {}
            } message: {
                Text("Bu prompttaki değişikliklerin silinir, fabrika metni geri gelir.")
            }
        }
    }

    // MARK: Actions

    private func save() {
        store.setOverride(selected, draft)
        draft = store.text(selected)
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { savedFlash = false }
    }

    private func resetToDefault() {
        store.resetToDefault(selected)
        draft = selected.defaultText
    }

    private func copyDraft() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft, forType: .string)
        #endif
    }
}

// MARK: - Custom sidebar
