import SwiftUI
import LucideKit

// MARK: - Sade pencere dili
//
// Tasarım: "Hercules Mac Tasarımı" tuvali ▸ Antrenman · Yeni seans V2 Odak. Başlık (20 yarı kalın)
// + soluk alt satır + sağda kare kapat; gövde; altta ince çizgi, solda özet ya da yıkıcı eylem,
// sağda İptal + birincil. Alanlar: üstte 11,5 soluk etiket, altında 38pt yuvarlak kutu.
// Uygulamanın bütün pencereleri bu kabuğu kullanır (eski SheetChrome'un yerini aldı).

struct SadeSheet<Content: View, Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let onClose: () -> Void
    /// Başlığın sağında, kapat düğmesinden önce (ör. favori kalbi).
    var accessory: AnyView? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footerLeading: () -> Leading
    @ViewBuilder let footerTrailing: () -> Trailing

    /// İki yanı da EmptyView olan pencere (salt görüntüleme) alt şerit çizmez.
    private var hasFooter: Bool { !(Leading.self == EmptyView.self && Trailing.self == EmptyView.self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if let accessory { accessory }
                SadeIconButton(sf: "xmark", help: "Kapat (Esc)", action: onClose)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)

            // Tek kök: içerik birden çok görünüm verirse çerçeve her birine ayrı uygulanıp alanı bölmesin.
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if hasFooter {
                SadeRule()
                HStack(spacing: 8) {
                    footerLeading()
                    Spacer(minLength: 12)
                    footerTrailing()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
            }
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Palette.textPrimary.opacity(0.08), lineWidth: 1))
    }
}

/// 1pt ince ayraç (beyaz %6).
struct SadeRule: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Palette.textPrimary.opacity(0.06))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// Etiketli alan: üstte 11,5 soluk etiket, altında 38pt yuvarlak kutu.
struct SadeField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)
            .sadeBox(radius: 10)
        }
    }
}

extension View {
    /// Alan kutusu: beyaz %5 zemin, %6 çizgi.
    func sadeBox(radius: CGFloat) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.textPrimary.opacity(0.06), lineWidth: 1))
    }
}

/// Pencere düğmeleri: birincil (btnBg, Return), ikincil (beyaz %5, Esc), yıkıcı (kırmızı yazı).
struct SadeButton: View {
    enum Role { case primary, secondary, destructive }

    let title: String
    var icon: String? = nil
    var role: Role = .secondary
    var enabled = true
    /// false → birincil Return'e, ikincil Esc'e bağlanmaz (yanlışlıkla tetiklenmesi riskli eylemler).
    var bindsKey = true
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Lucide(sf: icon, size: 13) }
                Text(title)
                    .font(.system(size: 13, weight: role == .primary ? .semibold : .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, role == .primary ? 16 : 12)
            .padding(.vertical, role == .primary ? 9 : 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(background))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SheetPressStyle())
        .disabled(!enabled)

        switch (role, bindsKey) {
        case (.primary, true): button.keyboardShortcut(.defaultAction)
        case (.secondary, true): button.keyboardShortcut(.cancelAction)
        default: button
        }
    }

    private var foreground: Color {
        guard enabled else { return Palette.textQuaternary }
        switch role {
        case .primary: return Palette.btnFg
        case .secondary: return Palette.textSecondary
        case .destructive: return Palette.negative
        }
    }

    private var background: Color {
        switch role {
        case .primary: return enabled ? Palette.btnBg : Palette.textPrimary.opacity(0.06)
        case .secondary: return Palette.textPrimary.opacity(0.05)
        case .destructive: return .clear
        }
    }
}

/// Kare ikon düğmesi (30pt, beyaz %5).
struct SadeIconButton: View {
    let sf: String
    var help: String = ""
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Lucide(sf: sf, size: 13)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Pencerenin sol listesindeki satır: numara (ya da ikon) halkası + ad + soluk alt satır;
/// seçiliyken hafif zemin.
struct SadeRailRow: View {
    var index: Int? = nil
    var icon: String? = nil
    let title: String
    var placeholder = "Yeni hareket"
    let meta: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if let icon {
                        Lucide(sf: icon, size: 11)
                    } else {
                        Text("\((index ?? 0) + 1)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                }
                .foregroundStyle(selected ? Palette.textSecondary : Palette.textTertiary)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Palette.textPrimary.opacity(selected ? 0.3 : 0.16), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.isEmpty ? placeholder : title)
                        .font(.system(size: 14, weight: selected ? .semibold : .medium))
                        .foregroundStyle(title.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                    Text(meta)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Palette.textPrimary.opacity(selected ? 0.07 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Kesik çizgili ekleme düğmesi (listenin sonunda "Hareket ekle").
struct SadeDashedButton: View {
    let title: String
    var icon = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Lucide(sf: icon, size: 13)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.textPrimary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "…" seçenekler menüsü (30pt kare). macOS'ta borderless Menu yalnız ikonu çizer; zemin arkada.
struct SadeMenuButton<Items: View>: View {
    var help = "Seçenekler"
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            Lucide(sf: "ellipsis", size: 15)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
        .help(help)
    }
}

/// Etiketli çok satırlı metin kutusu (notlar).
struct SadeTextArea: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var lines: ClosedRange<Int> = 2...3
    var minHeight: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Palette.textTertiary), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(lines)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                .sadeBox(radius: 10)
        }
    }
}

/// −/+ düğmeli sayı kutusu; ortadaki değer yazılarak da değişir.
struct SadeStepper<Field: View>: View {
    var unit: String? = nil
    var width: CGFloat = 132
    let decrement: () -> Void
    let increment: () -> Void
    @ViewBuilder let field: () -> Field

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", help: "Azalt", action: decrement)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                field()
                if let unit {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            stepButton("plus", help: "Artır", action: increment)
        }
        .frame(width: width, height: 40)
        .sadeBox(radius: 11)
    }

    private func stepButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Lucide(sf: icon, size: 13)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 34, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Basılınca hafif kararıp küçülen düğme stili (pencere düğmeleri).
struct SheetPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
    }
}
