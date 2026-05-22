import SwiftUI
import SwiftData

// MARK: - Navigation tabs

enum NavTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard, measurements, charts, workout, calendar, mealPlan, recipes, memory, profile
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:    return "Genel Bakış"
        case .measurements: return "Ölçümler"
        case .charts:       return "Grafikler"
        case .workout:      return "Antrenman"
        case .calendar:     return "Takvim"
        case .mealPlan:     return "Yemek Planı"
        case .recipes:      return "Tarifler"
        case .memory:       return "Memory"
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
        case .mealPlan:     return "menucard"
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

    var tabs: [NavTab] {
        switch self {
        case .takip:    return [.dashboard, .measurements, .charts, .workout]
        case .beslenme: return [.calendar, .mealPlan, .recipes]
        case .ai:       return [.memory]
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @State private var selection: NavTab? = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var chatStore = ChatStore()
    @State private var chatOpen: Bool = false
    @State private var chatWidth: CGFloat = 380

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
    }

    // MARK: Sidebar (native macOS, translucent)

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(NavCategory.allCases) { category in
                Section(category.label) {
                    ForEach(category.tabs) { tab in
                        Label(tab.label, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Hercules")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ProfileFooter(
                isSelected: selection == .profile,
                onTap: { selection = .profile }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: Detail column (with optional right-side chat)

    private var detailColumn: some View {
        ZStack(alignment: .bottomTrailing) {
            selectedDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, chatOpen ? chatWidth : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: chatOpen)
                .animation(.spring(response: 0.25, dampingFraction: 0.9), value: chatWidth)

            if chatOpen {
                ChatSidebar(
                    store: chatStore,
                    width: $chatWidth,
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            chatOpen = false
                        }
                    }
                )
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }

            if !chatOpen {
                FloatingChatButton(isOpen: chatOpen) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        chatOpen = true
                    }
                }
                .padding(20)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background(Palette.background)
        .toolbar(chatOpen ? .hidden : .visible, for: .windowToolbar)
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch selection ?? .dashboard {
        case .dashboard:    DashboardView()
        case .measurements: MeasurementsView()
        case .charts:       ChartsView()
        case .workout:      WorkoutView()
        case .calendar:     CalendarView()
        case .mealPlan:     MealPlanView()
        case .recipes:      RecipesView()
        case .memory:       MemoryView()
        case .profile:      ProfileView()
        }
    }
}

// MARK: - Profile footer (compact, fits the native sidebar bottom)

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
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Palette.accent, Palette.accent.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)
                    Text(initial)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.85))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : (hovering ? Color.white.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
