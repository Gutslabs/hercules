import SwiftUI
import SwiftData

// MARK: - Navigation tabs

enum NavTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard, measurements, charts, workout, calendar, recipes, memory, profile
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:    return "Genel Bakış"
        case .measurements: return "Ölçümler"
        case .charts:       return "Grafikler"
        case .workout:      return "Antrenman"
        case .calendar:     return "Takvim"
        case .recipes:      return "Tarifler"
        case .memory:       return "Hafıza"
        case .profile:      return "Profil"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:    return "square.grid.2x2"
        case .measurements: return "list.bullet"
        case .charts:       return "chart.xyaxis.line"
        case .workout:      return "dumbbell"
        case .calendar:     return "calendar"
        case .recipes:      return "fork.knife"
        case .memory:       return "brain"
        case .profile:      return "person.crop.circle"
        }
    }
}

/// Sidebar kategorileri.
enum NavCategory: String, CaseIterable, Identifiable, Hashable {
    case takip, beslenme, ai

    var id: String { rawValue }

    var label: String {
        switch self {
        case .takip:    return "Takip"
        case .beslenme: return "Beslenme"
        case .ai:       return "AI"
        }
    }

    var subtitle: String {
        switch self {
        case .takip:    return "Ölçüm ve performans"
        case .beslenme: return "Plan, kayıt ve tarif"
        case .ai:       return "Koç hafızası"
        }
    }

    var tabs: [NavTab] {
        switch self {
        case .takip:    return [.dashboard, .measurements, .charts, .workout]
        case .beslenme: return [.calendar, .recipes]
        case .ai:       return [.memory]
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

    @ViewBuilder
    private var selectedDetail: some View {
        switch selection ?? .dashboard {
        case .dashboard:    DashboardView()
        case .measurements: MeasurementsView()
        case .charts:       ChartsView()
        case .workout:      WorkoutView()
        case .calendar:     CalendarView()
        case .recipes:      RecipesView()
        case .memory:       MemoryView()
        case .profile:      ProfileView()
        }
    }
}

// MARK: - Custom sidebar
