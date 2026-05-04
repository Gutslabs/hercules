import SwiftUI
import SwiftData

enum NavTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard, measurements, charts, calorie, recipes, profile
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Genel Bakış"
        case .measurements: return "Ölçümler"
        case .charts: return "Grafikler"
        case .calorie: return "Kalori"
        case .recipes: return "Tarifler"
        case .profile: return "Profil"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .measurements: return "list.bullet"
        case .charts: return "chart.xyaxis.line"
        case .calorie: return "flame"
        case .recipes: return "fork.knife"
        case .profile: return "person.crop.circle"
        }
    }
}

struct ContentView: View {
    @State private var selection: NavTab = .dashboard
    @StateObject private var chatStore = ChatStore()
    @State private var chatOpen: Bool = false
    @State private var chatWidth: CGFloat = 380
    @AppStorage("hercules.sidebar.width") private var sidebarWidth: Double = 220
    @State private var dragStartWidth: Double = 0

    private let minSidebarWidth: Double = 160
    private let maxSidebarWidth: Double = 360

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                Sidebar(selection: $selection)
                    .frame(width: sidebarWidth)
                sidebarResizeHandle
                Divider().background(Palette.border)
                Group {
                    switch selection {
                    case .dashboard: DashboardView()
                    case .measurements: MeasurementsView()
                    case .charts: ChartsView()
                    case .calorie: CalorieView()
                    case .recipes: RecipesView()
                    case .profile: ProfileView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if chatOpen {
                    ChatSidebar(
                        store: chatStore,
                        width: $chatWidth,
                        onClose: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { chatOpen = false } }
                    )
                    .transition(.move(edge: .trailing))
                }
            }

            if !chatOpen {
                FloatingChatButton(isOpen: chatOpen) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        chatOpen = true
                    }
                }
                .padding(20)
            }
        }
        .background(Palette.background)
        .preferredColorScheme(.dark)
    }

    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        if dragStartWidth == 0 { dragStartWidth = sidebarWidth }
                        let new = dragStartWidth + Double(v.translation.width)
                        sidebarWidth = max(minSidebarWidth, min(maxSidebarWidth, new))
                    }
                    .onEnded { _ in
                        dragStartWidth = 0
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
}

struct Sidebar: View {
    @Binding var selection: NavTab
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    private var mainTabs: [NavTab] {
        NavTab.allCases.filter { $0 != .profile }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: brand
            HStack {
                brand
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 44)
            .padding(.bottom, 14)

            Hairline()
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            // Menu section header (static, non-collapsible)
            menuHeader
                .padding(.horizontal, 8)

            VStack(spacing: 0) {
                ForEach(mainTabs) { tab in
                    SidebarItem(
                        label: tab.label,
                        systemImage: tab.systemImage,
                        isSelected: selection == tab
                    ) {
                        selection = tab
                    }
                }
            }
            .padding(.horizontal, 6)

            Spacer()

            // Bottom: hairline + profile + filter-style indicator
            Hairline()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            ProfileFooter(
                profile: profile,
                isSelected: selection == .profile
            ) {
                selection = .profile
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [
                    Palette.background,
                    Palette.background.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Image("HerculesLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("Hercules")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
        }
    }

    private var menuHeader: some View {
        HStack(spacing: 5) {
            Text("MENÜ")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 0)
            Text("\(mainTabs.count)")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.textQuaternary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(Color.white.opacity(0.04))
                )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

struct SidebarItem: View {
    let label: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .frame(width: 14)
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(textColor)
                Spacer(minLength: 0)
                if isSelected {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.leading, 16)  // indent for hierarchy feel
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Palette.accent)
                        .frame(width: 2)
                        .offset(x: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var iconColor: Color {
        if isSelected { return Palette.accent }
        return hovering ? Palette.textPrimary : Palette.textSecondary
    }

    private var textColor: Color {
        if isSelected { return Palette.textPrimary }
        return hovering ? Palette.textPrimary : Palette.textSecondary
    }

    private var backgroundColor: Color {
        if isSelected { return Color.white.opacity(0.05) }
        if hovering { return Color.white.opacity(0.025) }
        return Color.clear
    }
}

struct ProfileFooter: View {
    let profile: UserProfile?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var displayName: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Profil" : name
    }

    private var initial: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        if let first = name.first {
            return String(first).uppercased()
        }
        return "H"
    }

    private var subtitle: String {
        guard let p = profile else { return "Ayarları düzenle" }
        return p.goal.label
    }

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            Button(action: action) {
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
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.06) : (hovering ? Color.white.opacity(0.03) : Color.clear))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

