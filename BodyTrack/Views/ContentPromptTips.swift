import SwiftUI
import SwiftData

struct PromptTipsButton: View {
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

struct PromptTipsOverlay: View {
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

struct PromptTipSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tips: [String]
}

struct PromptTipCard: View {
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
