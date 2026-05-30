import SwiftUI
import SwiftData

enum SidebarChrome {
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

struct SidebarSection: View {
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

struct SidebarItemButton: View {
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

struct SidebarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - AI prompt tips
