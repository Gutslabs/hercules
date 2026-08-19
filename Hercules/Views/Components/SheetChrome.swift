import SwiftUI
import LucideKit

/// Uygulamadaki tüm sheet'lerin ortak kabuğu.
///
/// NEDEN: 24 sheet vardı ve her biri kendi kurallarını uyduruyordu — boyutlar 420×260'tan
/// 900×660'a yedi ayrı değer, köşe yarıçapı bir yerde elle 20 bir yerde `Radius.lg`, zemin
/// bir yerde `ZStack { background; surface }` bir yerde düz `surface`. En kötüsü birincil
/// buton: `MeasurementEditor` köşeli + `Palette.accent`, `RecipeEditor` kapsül +
/// `Palette.textPrimary` idi. Aynı rol, iki ayrı tasarım.
///
/// Buradan sonra sheet'ler yalnızca İÇERİĞİNİ yazar; başlık, ayraçlar, footer ve buton
/// tasarımı tek yerden gelir.
///
/// Kullanım:
/// ```
/// SheetChrome(eyebrow: "Tarifler", title: "Yeni Tarif", size: .standard) {
///     ...içerik...
/// } footer: {
///     SheetSecondaryButton("Vazgeç") { dismiss() }
///     SheetPrimaryButton("Kaydet", enabled: canSave) { save() }
/// }
/// ```
struct SheetChrome<Content: View, Footer: View>: View {
    /// Serbest ölçü yerine sınırlı bir ölçek. Yeni bir sheet "560 mi 580 mi" diye
    /// karar vermek zorunda kalmasın.
    enum Size {
        case compact   // kısa onay / tek alan
        case standard  // tipik düzenleyici
        case wide      // iki kolon / tablo
        case full      // gömülü tarayıcı, uzun liste

        var width: CGFloat {
            switch self {
            case .compact:  return 460
            case .standard: return 560
            case .wide:     return 760
            case .full:     return 900
            }
        }

        var height: CGFloat? {
            switch self {
            case .compact:  return 380
            case .standard: return 640
            case .wide:     return 660
            case .full:     return 680
            }
        }
    }

    let eyebrow: String?
    let title: String
    let subtitle: String?
    /// Başlığın solunda renkli ikon kutusu (kategori/tür göstergesi). İsteğe bağlı.
    let icon: String?
    let iconTint: Color
    let size: Size
    /// İçerik kendi kaydırmasını yönetiyorsa (liste, tarayıcı) kapat.
    let scrollsContent: Bool
    /// Yükseklik içeriğe göre büyüsün. Ölçüm düzenleyicisi gibi alanları açılıp kapanan
    /// sheet'lerde sabit yükseklik animasyonu öldürüyor; orada preset yükseklik dayatmıyoruz.
    let fitsHeightToContent: Bool
    /// Başlığın sağında, kapat düğmesinden önce duran ek kontrol (segment, filtre vb.).
    /// `AnyView`: üçüncü bir generic parametre eklemek `Footer == EmptyView` kısayollarını
    /// kombinatoryal olarak çoğaltırdı, buradaki maliyet ihmal edilebilir.
    let headerAccessory: AnyView?
    let onClose: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconTint: Color = Palette.accent,
        size: Size = .standard,
        scrollsContent: Bool = true,
        fitsHeightToContent: Bool = false,
        headerAccessory: AnyView? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTint = iconTint
        self.size = size
        self.scrollsContent = scrollsContent
        self.fitsHeightToContent = fitsHeightToContent
        self.headerAccessory = headerAccessory
        self.onClose = onClose
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.border)

            Group {
                // ScrollView açgözlüdür: sabit yükseklik yokken ya sıfıra çöker ya ebeveyni
                // şişirir. Otomatik yükseklikte kaydırmayı bileşen kendisi devre dışı
                // bırakıyor ki çağıran bu kombinasyonu yanlışlıkla seçemesin.
                if scrollsContent && !fitsHeightToContent {
                    ScrollView(showsIndicators: false) { paddedContent }
                } else {
                    paddedContent
                }
            }
            .frame(maxWidth: .infinity,
                   maxHeight: fitsHeightToContent ? nil : .infinity,
                   alignment: .topLeading)

            footerBar
        }
        .frame(width: size.width, height: fitsHeightToContent ? nil : size.height)
        // Tek zemin — eskiden bir sheet iki katman üst üste basıyordu.
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            // Koyu zeminde kenar tanımı olmadan sheet arka planla eriyor.
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    private var paddedContent: some View {
        content()
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(iconTint.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Lucide(sf: icon, size: 14)
                        .foregroundStyle(iconTint)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow { Text(eyebrow).eyebrow() }
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textQuaternary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.sm)
            if let headerAccessory { headerAccessory }
            if let onClose {
                SheetCloseButton(action: onClose)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footerBar: some View {
        // Footer boşsa ayraç da çizilmesin — görüntüleme sheet'lerinde alta boş şerit kalırdı.
        if Footer.self != EmptyView.self {
            Divider().overlay(Palette.border)
            // Hizalamayı çağıran belirler: `Spacer()` koyarak sağa iter, silme gibi
            // yıkıcı bir eylemi solda bırakabilir. Otomatik spacer koysak yıkıcı butonu
            // onay butonunun yanına sıkıştırırdı.
            HStack(spacing: Spacing.sm) {
                footer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
        }
    }
}

extension SheetChrome where Footer == EmptyView {
    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconTint: Color = Palette.accent,
        size: Size = .standard,
        scrollsContent: Bool = true,
        fitsHeightToContent: Bool = false,
        headerAccessory: AnyView? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle,
                  icon: icon, iconTint: iconTint, size: size,
                  scrollsContent: scrollsContent, fitsHeightToContent: fitsHeightToContent,
                  headerAccessory: headerAccessory, onClose: onClose,
                  content: content, footer: { EmptyView() })
    }
}

// MARK: - Butonlar

/// Onaylayıcı eylem. Şekil kararı: uygulamanın diğer birincil butonları (Tarifler'deki
/// "+ Yeni Tarif", Instagram içe aktarma) köşeli + `Palette.accent`; kapsül yalnızca
/// `RecipeEditor`'da tekti. Yoğun/veri ağırlıklı bu arayüzde köşeli olan daha oturuyor.
struct SheetPrimaryButton: View {
    let title: String
    var icon: String?
    var enabled: Bool = true
    let action: () -> Void

    init(_ title: String, icon: String? = nil, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 6) {
                if let icon { Lucide(sf: icon, size: 11) }
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(enabled ? Palette.btnFg : Palette.textQuaternary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(enabled ? Palette.accent : Palette.surfaceElevated)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(SheetPressStyle())
        .disabled(!enabled)
        .keyboardShortcut(.defaultAction)   // Return
    }
}

/// Vazgeç / ikincil eylem — dolgusuz, sessiz.
struct SheetSecondaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(SheetPressStyle())
        .keyboardShortcut(.cancelAction)   // Esc
    }
}

/// Silme gibi geri dönüşü olmayan eylem — footer'da SOLDA durur ki onay butonuyla
/// yan yana gelip yanlışlıkla tıklanmasın.
struct SheetDestructiveButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.negative)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(SheetPressStyle())
    }
}

struct SheetCloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Lucide(sf: "xmark", size: 11)
                .foregroundStyle(hovering ? Palette.textPrimary : Palette.textQuaternary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(hovering ? Palette.surfaceElevated : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Kapat (Esc)")
    }
}

/// Ortak basma geri bildirimi — her sheet kendi press style'ını yazmasın.
struct SheetPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

// MARK: - Form parçaları
//
// Dönüştürülen sheet'lerin çoğu `Form { Section { LabeledContent } }` kullanıyordu; bu
// stok Aqua görünümünün kaynağıydı. Aşağıdakiler aynı yapıyı uygulamanın kendi diliyle
// kuruyor, böylece her sheet kendi kart/alan stilini yeniden icat etmiyor.

/// Başlıklı kart. Form'daki `Section` yerine — çağrı biçimi de ona uyuyor:
/// `SheetSection("Başlık") { ... }` veya `SheetSection { ... } header: { ... }`.
struct SheetSection<Content: View, Header: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let header: () -> Header

    init(@ViewBuilder content: @escaping () -> Content,
         @ViewBuilder header: @escaping () -> Header) {
        self.content = content
        self.header = header
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header()
            VStack(alignment: .leading, spacing: 2) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
        }
    }
}

extension SheetSection where Header == AnyView {
    /// Düz metin başlık — en yaygın hâli.
    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, header: {
            AnyView(
                Group {
                    if let title { Text(title).eyebrow() }
                }
            )
        })
    }
}

/// Etiket solda, değer/kontrol sağda. `LabeledContent` yerine.
struct SheetRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: () -> Trailing

    init(_ label: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Spacing.sm)
            trailing()
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Kart içinde tam genişlik eylem satırı — Form'daki çıplak `Button("...")` yerine.
struct SheetActionRow: View {
    let title: String
    var icon: String?
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Lucide(sf: icon, size: 11) }
                Text(title).font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(hovering ? Palette.fieldFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SheetPressStyle())
        .onHover { hovering = $0 }
        .padding(.horizontal, 4)
    }
}

/// Üstte etiket, altında girdi kutusu.
struct SheetField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow()
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
        }
    }
}
