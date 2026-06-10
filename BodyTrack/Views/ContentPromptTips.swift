import SwiftUI
import SwiftData

// MARK: - Profile footer

/// V1 alt profil satırı — kutusuz: mercan daire baş harf + ad + dişli.
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
        return name.first.map { String($0).lowercased(with: Locale(identifier: "tr_TR")) } ?? "h"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Palette.accent.opacity(0.13))
                    Text(initial)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1)
                )

                Text(displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SidebarChrome.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected || hovering ? SidebarChrome.secondary : SidebarChrome.quiet)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? SidebarChrome.rowSelected : (hovering ? SidebarChrome.rowHover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable(false)
        .onHover { hovering = $0 }
        .help("Profil ve ayarlar")
    }
}
