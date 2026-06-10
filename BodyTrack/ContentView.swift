import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Navigation tabs

enum NavTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard, measurements, charts, workout, analysis, calendar, recipes, chat, profile
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:    return "Genel Bakış"
        case .measurements: return "Ölçümler"
        case .charts:       return "Grafikler"
        case .workout:      return "Antrenman"
        case .analysis:     return "Analiz"
        case .calendar:     return "Öğün Takip"
        case .recipes:      return "Tarifler"
        case .chat:         return "Sohbet"
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
        case .chat:         return "bubble.left.and.text.bubble.right"
        case .profile:      return "person.crop.circle"
        }
    }
}

/// Sidebar grupları — V1: GENEL / TAKİP / BESLENME / EGZERSİZ.
/// (Sohbet nav'dan çıktı: "Koç'a sor" butonu chat panelini açar.
///  Hafıza ve sistem promptları Profil'in sekmeleri.)
enum NavCategory: String, CaseIterable, Identifiable, Hashable {
    case genel, takip, beslenme, egzersiz

    var id: String { rawValue }

    var label: String {
        switch self {
        case .genel:    return "Genel"
        case .takip:    return "Takip"
        case .beslenme: return "Beslenme"
        case .egzersiz: return "Egzersiz"
        }
    }

    var tabs: [NavTab] {
        switch self {
        case .genel:    return [.dashboard, .analysis]
        case .takip:    return [.measurements, .charts]
        case .beslenme: return [.calendar, .recipes]
        case .egzersiz: return [.workout]
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @State private var selection: NavTab? = .dashboard
    @State private var chatStore = ChatStore()
    @State private var chatOpen: Bool = false
    @State private var chatWidth: CGFloat = 380
    @State private var saveErrors = SaveErrorReporter.shared
    // Tema: görünüm @AppStorage'tan canlı okunur; semantik/grafik değişiminde
    // ağaç epoch ile tazelenir (renkler çizim anında defaults'tan çözülür).
    @AppStorage(ThemeSettings.appearanceKey) private var appearanceRaw: String = AppAppearance.dark.rawValue
    @State private var themeEpoch = 0
    private let chatMinWidth: CGFloat = 320
    private let chatMaxWidth: CGFloat = 560
    private let detailReserveWidth: CGFloat = 760

    var body: some View {
        // Düz HStack — NavigationSplitView değil. macOS (Tahoe) split view'ı sidebar'ı
        // kendi kromuyla (yuvarlak panel + kenarlık + tıklamada focus halkası) çiziyordu;
        // collapse zaten kullanılmadığı için sistem kromundan tamamen çıkıyoruz.
        HStack(spacing: 0) {
            sidebar
                .frame(width: 252)
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .dark).colorScheme)
        .id(themeEpoch)
        .onReceive(NotificationCenter.default.publisher(for: .herculesThemeChanged)) { _ in
            themeEpoch += 1
        }
        #if os(macOS)
        .toolbarBackground(SidebarChrome.background, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
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
            onAskCoach: {
                // Tam sayfa sohbete götür (widget/dock değil); açık chat panelini kapat.
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    chatOpen = false
                    selection = .chat
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

                    if chatOpen {
                        ChatSidebar(
                            store: chatStore,
                            width: chatWidthBinding(maxWidth: maxAllowedChatWidth),
                            minWidth: chatMinWidth,
                            maxWidth: maxAllowedChatWidth,
                            onClose: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    chatOpen = false
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
                clampStoredChatWidth(maxWidth: maxAllowedChatWidth)
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                clampStoredChatWidth(maxWidth: maxChatWidth(for: newWidth))
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .toolbar(chatOpen ? .hidden : .visible, for: .windowToolbar)
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
        case .chat:         ChatPageView(store: chatStore)
        case .profile:      ProfileView()
        }
    }
}

// MARK: - Custom sidebar
