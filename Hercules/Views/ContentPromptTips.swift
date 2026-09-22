import SwiftUI
import LucideKit
import SwiftData
#if os(macOS)
import AppKit
#endif

// MARK: - Sidebar kimlik satırı

/// Buzz kimlik kartı: yuvarlak avatar + durum noktası + ad; dinlenmede kutu yok,
/// hover'da beyaz-tül, 12px köşe. Profil ve koç satırları AYNI kabuğu kullanır —
/// ikisi sidebar'ın dibinde eş görünsün diye tek yerde tanımlı.
struct SidebarIdentityRow<Face: View>: View {
    var name: String
    var isSelected: Bool = false
    var collapsed: Bool = false
    var statusColor: Color = BuzzTheme.statusAdded
    var trailingIcon: String
    var help: String
    /// Büyütme kartındaki alt satır ve "Fotoğrafı değiştir" eylemi.
    var zoomSubtitle: String? = nil
    var onPickPhoto: (() -> Void)? = nil
    var onTap: () -> Void
    @ViewBuilder var face: () -> Face

    @State private var hovering = false
    @State private var zooming = false

    private var avatar: some View {
        face()
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            // Presence: Buzz profil kartındaki yeşil durum noktası.
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                    .offset(x: 1, y: 1)
            }
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if collapsed {
                    avatar
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                } else {
                    HStack(spacing: 10) {
                        avatar

                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? SidebarChrome.selectedText : SidebarChrome.primary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Lucide(sf: trailingIcon, size: 13)
                            .foregroundStyle(SidebarChrome.quiet)
                            .opacity(isSelected || hovering ? 1 : 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? SidebarChrome.rowSelected : (hovering ? SidebarChrome.rowHover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable(false)
        .onHover { hovering = $0 }
        .help(help)
        // Avatar kendi tıklamasını alır: satır gezinir, yüz büyür. Overlay
        // satır butonunun ÜSTÜNDE durduğu için hit-test önce buraya düşer.
        .overlay(alignment: collapsed ? .center : .leading) {
            Button { zooming = true } label: {
                Color.clear
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Fotoğrafı büyüt")
            .padding(.leading, collapsed ? 0 : 8)
            .popover(isPresented: $zooming, arrowEdge: .trailing) {
                AvatarZoomCard(name: name, subtitle: zoomSubtitle, onPickPhoto: onPickPhoto) {
                    face()
                }
            }
        }
    }
}

// MARK: - Profile footer

struct ProfileFooter: View {
    let isSelected: Bool
    var collapsed: Bool = false
    let onTap: () -> Void

    @Query private var profiles: [UserProfile]
    /// Avatar dosyası değişince yüzü tazelemek için sayaç.
    @State private var avatarEpoch = 0

    private var profile: UserProfile? { profiles.first }

    private var displayName: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Profil" : name
    }

    @ViewBuilder
    private var avatarFace: some View {
        #if os(macOS)
        if avatarEpoch >= 0, let img = ProfileAvatarStore.image() {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
        } else {
            InitialFace(name: profile?.name ?? "")
        }
        #else
        InitialFace(name: profile?.name ?? "")
        #endif
    }

    var body: some View {
        SidebarIdentityRow(
            name: displayName,
            isSelected: isSelected,
            collapsed: collapsed,
            trailingIcon: "gearshape",
            help: "Profil ve ayarlar",
            zoomSubtitle: "Profil",
            onPickPhoto: { ProfileAvatarStore.pickImage() },
            onTap: onTap
        ) {
            avatarFace
        }
        #if os(macOS)
        // Minimal profil fotoğrafı yönetimi: avatara sağ tık.
        .contextMenu {
            Button("Profil fotoğrafı seç…") { ProfileAvatarStore.pickImage() }
            if ProfileAvatarStore.image() != nil {
                Button("Fotoğrafı kaldır", role: .destructive) { ProfileAvatarStore.clear() }
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: ProfileAvatarStore.changed)) { _ in
            avatarEpoch += 1
        }
    }
}

// MARK: - Coach footer

/// Sohbete giriş — profil kartıyla BİREBİR aynı kabuk (dolgulu buton değil).
/// Sidebar'ın dibinde ikisi eş bir çift olarak durur.
struct CoachFooter: View {
    var collapsed: Bool = false
    let onTap: () -> Void

    /// Avatar/ad değişince satırı tazeleyen sayaçlar — gövde her çizimde
    /// güncel değeri okur, bu yüzden sayacı artırmak yeterli.
    @State private var avatarEpoch = 0
    @State private var nameEpoch = 0

    @ViewBuilder
    private var avatarFace: some View {
        #if os(macOS)
        if avatarEpoch >= 0, let img = CoachAvatarStore.image() {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
        } else {
            InitialFace(name: CoachIdentity.name, fallbackInitial: "k")
        }
        #else
        InitialFace(name: CoachIdentity.name, fallbackInitial: "k")
        #endif
    }

    var body: some View {
        let name = nameEpoch >= 0 ? CoachIdentity.name : CoachIdentity.defaultName
        SidebarIdentityRow(
            name: name,
            collapsed: collapsed,
            trailingIcon: "sparkles",
            help: "\(CoachIdentity.dative) sor",
            zoomSubtitle: "AI koç",
            onPickPhoto: { CoachAvatarStore.pickImage() },
            onTap: onTap
        ) {
            avatarFace
        }
        #if os(macOS)
        .contextMenu {
            Button("Koç fotoğrafı seç…") { CoachAvatarStore.pickImage() }
            if CoachAvatarStore.image() != nil {
                Button("Fotoğrafı kaldır", role: .destructive) { CoachAvatarStore.clear() }
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: CoachAvatarStore.changed)) { _ in
            avatarEpoch += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: CoachIdentity.changed)) { _ in
            nameEpoch += 1
        }
    }
}
