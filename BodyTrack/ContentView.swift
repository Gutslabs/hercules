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

private enum ChatPresentationMode: String {
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

private enum SidebarChrome {
    static let background = Color(red: 0.060, green: 0.060, blue: 0.068)
    static let backgroundRaised = Color(red: 0.086, green: 0.086, blue: 0.096)
    static let rowHover = Color.white.opacity(0.040)
    static let rowSelected = Color.white.opacity(0.095)
    static let border = Color.white.opacity(0.075)
    static let borderStrong = Color.white.opacity(0.14)
    static let primary = Palette.textPrimary
    static let secondary = Palette.textSecondary
    static let tertiary = Palette.textTertiary
    static let quiet = Palette.textQuaternary
    static let ink = Color(red: 0.060, green: 0.045, blue: 0.040)
}

struct HerculesSidebar: View {
    @Binding var selection: NavTab?
    let onShowPromptTips: () -> Void
    @State private var hoveredTab: NavTab?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(NavCategory.allCases) { category in
                        SidebarSection(
                            category: category,
                            selection: $selection,
                            hoveredTab: $hoveredTab
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 18)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            sidebarBackground
                .ignoresSafeArea(.container, edges: [.top, .bottom])
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SidebarChrome.border)
                .frame(width: 0.5)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.065))
                    Image("HerculesLogo")
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                }
                .frame(width: 38, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(SidebarChrome.borderStrong, lineWidth: 0.75)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hercules")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(SidebarChrome.primary)
                        .lineLimit(1)
                    Text("BodyTrack")
                        .font(Typography.caption)
                        .foregroundStyle(SidebarChrome.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(SidebarChrome.border)
                .frame(height: 0.5)

            PromptTipsButton(action: onShowPromptTips)
                .padding(.horizontal, 12)

            ProfileFooter(
                isSelected: selection == .profile,
                onTap: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selection = .profile
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            LinearGradient(
                colors: [
                    SidebarChrome.background.opacity(0.72),
                    SidebarChrome.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var sidebarBackground: some View {
        ZStack(alignment: .topLeading) {
            SidebarChrome.background
            LinearGradient(
                colors: [
                    Color.white.opacity(0.070),
                    Color.white.opacity(0.025),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .frame(height: 210)
            .allowsHitTesting(false)
        }
    }
}

private struct SidebarSection: View {
    let category: NavCategory
    @Binding var selection: NavTab?
    @Binding var hoveredTab: NavTab?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.label)
                        .font(Typography.label)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(SidebarChrome.quiet)
                    Text(category.subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(SidebarChrome.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(String(format: "%02d", category.tabs.count))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(SidebarChrome.quiet)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 4) {
                ForEach(category.tabs) { tab in
                    SidebarItemButton(
                        tab: tab,
                        isSelected: selection == tab,
                        isHovered: hoveredTab == tab
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selection = tab
                        }
                    }
                    .onHover { hovering in
                        hoveredTab = hovering ? tab : nil
                    }
                }
            }
        }
    }
}

private struct SidebarItemButton: View {
    let tab: NavTab
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconBackground)
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 28, height: 28)

                Text(tab.label)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.78))
                        .frame(width: 3, height: 18)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(isSelected ? SidebarChrome.primary : SidebarChrome.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(rowBackground)
            .overlay(rowBorder)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .help(tab.label)
    }

    private var iconBackground: Color {
        if isSelected {
            return Color.white.opacity(0.115)
        }
        if isHovered {
            return Color.white.opacity(0.065)
        }
        return Color.white.opacity(0.035)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(isSelected ? SidebarChrome.rowSelected : (isHovered ? SidebarChrome.rowHover : Color.clear))
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSelected)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isHovered)
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(
                isSelected ? Color.white.opacity(0.18) : Color.white.opacity(isHovered ? 0.09 : 0.0),
                lineWidth: 0.75
            )
    }
}

private struct SidebarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - AI prompt tips

private struct PromptTipsButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(hovering ? 0.095 : 0.050))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI ipuçları")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Hangi veriyi ne zaman çağıracağını gör")
                        .font(Typography.caption)
                        .foregroundStyle(SidebarChrome.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SidebarChrome.quiet)
            }
            .foregroundStyle(SidebarChrome.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(hovering ? SidebarChrome.rowHover : Color.white.opacity(0.022))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(hovering ? SidebarChrome.borderStrong : SidebarChrome.border, lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .onHover { hovering = $0 }
        .help("AI sorgu örnekleri")
    }
}

private struct PromptTipsOverlay: View {
    let onClose: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12, alignment: .top)
    ]

    private let sections: [PromptTipSection] = [
        PromptTipSection(
            title: "Bugün",
            icon: "sun.max",
            tips: [
                "bugünkü makrom ne?",
                "bugün kaç kalori kaldı?",
                "bugün ne yedim?",
                "bugünkü proteinim yeterli mi?"
            ]
        ),
        PromptTipSection(
            title: "Tarih ve Takvim",
            icon: "calendar",
            tips: [
                "dün ne yemişim?",
                "24 Mayıs ne yedim?",
                "geçen hafta yemek günlüğüm",
                "Mayıs yemek özetim"
            ]
        ),
        PromptTipSection(
            title: "Kalori Aralıkları",
            icon: "chart.bar.xaxis",
            tips: [
                "bu hafta kalori ortalamam?",
                "bu ay kalori ortalamam?",
                "son 30 gün kalori açığım nasıl?",
                "son 90 gün özetim"
            ]
        ),
        PromptTipSection(
            title: "Vücut Trendleri",
            icon: "scalemass",
            tips: [
                "kilo trendim nasıl?",
                "son 14 gün kilo hızım?",
                "hedefe ulaşır mıyım?",
                "plato mu yaşıyorum?"
            ]
        ),
        PromptTipSection(
            title: "Antrenman",
            icon: "dumbbell",
            tips: [
                "bugün antrenman var mı?",
                "programım mantıklı mı?",
                "son 30 gün antrenman frekansım?",
                "cut döneminde antrenmanı değiştirmeli miyim?"
            ]
        ),
        PromptTipSection(
            title: "Adım ve Aktivite",
            icon: "figure.walk",
            tips: [
                "bugünkü adımım kaç?",
                "cut için adımım yeterli mi?",
                "adım ortalamam düşük mü?",
                "NEAT artırmak mantıklı mı?"
            ]
        ),
        PromptTipSection(
            title: "Beslenme ve Mikro",
            icon: "leaf",
            tips: [
                "mikro eksiklerim ne?",
                "lifim düşük mü?",
                "protein hedefimi nasıl tamamlarım?",
                "beslenmemde çeşitlilik iyi mi?"
            ]
        ),
        PromptTipSection(
            title: "Tarif ve Preset",
            icon: "fork.knife",
            tips: [
                "protein bowl tarifi öner",
                "whey ile tatlı tarifi bul",
                "kayıtlı tariflerime bak",
                "bugünkü makroya göre öğün öner"
            ]
        ),
        PromptTipSection(
            title: "@ Etiketler",
            icon: "at",
            tips: [
                "@Kalori bu ay ortalamam?",
                "@Takvim dün ne yemişim?",
                "@Antrenman programım mantıklı mı?",
                "@Hepsi tüm veriye bakarak yorumla"
            ]
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.46)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                VStack(alignment: .leading, spacing: 16) {
                    header

                    ScrollView(showsIndicators: true) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(sections) { section in
                                PromptTipCard(section: section)
                            }
                        }
                        .padding(.bottom, 2)
                    }
                }
                .padding(18)
                .frame(
                    width: min(760, max(320, proxy.size.width - 48)),
                    height: min(620, max(420, proxy.size.height - 48))
                )
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(SidebarChrome.backgroundRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(SidebarChrome.borderStrong, lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.34), radius: 26, y: 12)
                .padding(24)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(SidebarChrome.primary)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.080))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("AI ipuçları")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(SidebarChrome.primary)
                Text("Bu kalıplar AI’nın sadece gereken veri aralığını açmasına yardım eder.")
                    .font(Typography.caption)
                    .foregroundStyle(SidebarChrome.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SidebarChrome.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.065)))
                    .overlay(Circle().strokeBorder(SidebarChrome.border, lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .help("Kapat")
        }
    }
}

private struct PromptTipSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tips: [String]
}

private struct PromptTipCard: View {
    let section: PromptTipSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SidebarChrome.primary)
                    .frame(width: 25, height: 25)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.070))
                    )
                Text(section.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SidebarChrome.primary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.tips, id: \.self) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle()
                            .fill(SidebarChrome.quiet)
                            .frame(width: 4, height: 4)
                        Text(tip)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(SidebarChrome.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SidebarChrome.border, lineWidth: 0.75)
        )
    }
}

// MARK: - Profile footer

struct ProfileFooter: View {
    let isSelected: Bool
    let onTap: () -> Void

    @Query private var profiles: [UserProfile]
    @State private var hovering = false

    private var profile: UserProfile? { profiles.first }

    private var displayName: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Profil" : name
    }

    private var initial: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.first.map { String($0).uppercased() } ?? "H"
    }

    private var subtitle: String {
        profile?.goal.label ?? "Ayarları düzenle"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.90),
                                    Color.white.opacity(0.50)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Text(initial)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(SidebarChrome.ink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SidebarChrome.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(SidebarChrome.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : SidebarChrome.quiet)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(hovering ? 0.055 : 0.0))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? SidebarChrome.rowSelected : (hovering ? SidebarChrome.rowHover : Color.white.opacity(0.028)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.18) : SidebarChrome.border, lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .onHover { hovering = $0 }
    }
}
