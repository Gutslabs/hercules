import SwiftUI

/// Buzz kartı (card.tsx): rounded-xl (12), 1px border/70, shadow-xs.
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.xl
    var cornerRadius: CGFloat = Radius.md
    let content: Content

    init(padding: CGFloat = Spacing.xl, cornerRadius: CGFloat = Radius.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.surface)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.border.opacity(0.7), lineWidth: 1)
            )
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
    }
}


// MARK: - Seçim / odak vurgusu (sidebar dili)

/// Sidebar'daki seçili satırın AYNI DİLİ: kenarlık yok, yalnız yumuşak peçe
/// dolgu (koyuda beyaz %16, açıkta siyah %7) ve hover'da daha soluk peçe.
/// Sert aksan çizgileri yerine tüm uygulamada bu dil kullanılır.
///
/// DİKKAT: peçe SAYDAM. Kendi opak zemini olan kart/fayanslarda zemini `base`
/// olarak buraya verin — yoksa peçe zeminin ARKASINDA kalır ve görünmez
/// (sidebar satırlarının zemini olmadığı için orada sorun çıkmıyordu).
struct SelectionRing: ViewModifier {
    let isActive: Bool
    var cornerRadius: CGFloat = 12
    /// Sidebar peçesi yerine özel bir renk isteyen çağıranlar için.
    var tint: Color? = nil
    /// Hover peçesi (satır/kart kendi hover'ını çizmiyorsa).
    var isHovered: Bool = false
    /// Çağıranın kendi zemini; verilirse peçe bunun ÜSTÜNE bindirilir.
    var base: Color? = nil
    /// Zemin gölgesi (kart dili: shadow-xs) — base ile birlikte çizilir.
    var baseShadow: Bool = false

    private var veil: Color {
        if isActive { return tint ?? Palette.selectionVeil }
        if isHovered { return Palette.selectionVeilHover }
        return .clear
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    if let base {
                        shape.fill(base)
                            .shadow(color: baseShadow ? Color.black.opacity(0.05) : .clear,
                                    radius: baseShadow ? 2 : 0,
                                    y: baseShadow ? 1 : 0)
                    }
                    shape.fill(veil)
                }
            )
            .animation(.easeOut(duration: 0.14), value: isActive)
    }
}

extension View {
    /// Seçili/odaklı durum vurgusu — sidebar satırıyla aynı peçe.
    /// Kendi zemini olan kartlar zemini `base` ile geçmeli (bkz. SelectionRing).
    func selectionRing(_ isActive: Bool,
                       cornerRadius: CGFloat = 12,
                       tint: Color? = nil,
                       isHovered: Bool = false,
                       base: Color? = nil,
                       baseShadow: Bool = false) -> some View {
        modifier(SelectionRing(isActive: isActive,
                               cornerRadius: cornerRadius,
                               tint: tint,
                               isHovered: isHovered,
                               base: base,
                               baseShadow: baseShadow))
    }
}


// MARK: - Düz buton kromu (sidebar dili)

/// Uygulamadaki ikincil butonların ortak yüzeyi: kenarlık ve dolu kart zemini
/// yerine sidebar satırındaki peçe. Hover'da peçe koyulaşır, basılıyken biraz daha.
struct FlatButtonChrome: ViewModifier {
    var cornerRadius: CGFloat = 10
    var isHovered: Bool = false
    var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isActive ? Palette.selectionVeil
                          : (isHovered ? Palette.selectionVeilHover : Palette.selectionVeilHover.opacity(0.55)))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    func flatButtonChrome(cornerRadius: CGFloat = 10,
                          isHovered: Bool = false,
                          isActive: Bool = false) -> some View {
        modifier(FlatButtonChrome(cornerRadius: cornerRadius, isHovered: isHovered, isActive: isActive))
    }
}

/// `.buttonStyle(.flat)` — düz krom + basılma geri bildirimi tek yerde.
struct FlatButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .flatButtonChrome(cornerRadius: cornerRadius,
                              isHovered: hovering,
                              isActive: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == FlatButtonStyle {
    static var flat: FlatButtonStyle { FlatButtonStyle() }
}
