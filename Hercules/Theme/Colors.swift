import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Tema ayarları (Settings ▸ Görünüm)

/// Açık/koyu görünüm tercihi. Varsayılan koyu (mevcut his korunur).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Sistem"
        case .dark:   return "Koyu"
        case .light:  return "Açık"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }
}

/// Semantik şema: olumlu/olumsuz yön renkleri.
/// B "Adaçayı/Bordo": iyi=yeşil, kötü=bordo. C "Sessiz/Pirinç": iyi=nötr gri, dikkat=pirinç.
enum SemanticScheme: String, CaseIterable, Identifiable {
    case adacayiBordo, sessizPirinc
    var id: String { rawValue }

    var label: String {
        switch self {
        case .adacayiBordo: return "Adaçayı/Pirinç"
        case .sessizPirinc: return "Sessiz/Pirinç"
        }
    }
}

/// Grafik rengi — tema semantiğinden bağımsız kullanıcı seçeneği.
enum ChartTint: String, CaseIterable, Identifiable {
    case bordo, adacayi, murekkep, petrol, celik, murdum, tutun
    var id: String { rawValue }

    var label: String {
        switch self {
        case .bordo:    return "Bordo"
        case .adacayi:  return "Adaçayı"
        case .murekkep: return "Mürekkep"
        case .petrol:   return "Petrol"
        case .celik:    return "Çelik"
        case .murdum:   return "Mürdüm"
        case .tutun:    return "Tütün"
        }
    }

    /// Aynı doygunluk bandında (oklch C≈0.05–0.08) açık/koyu çiftleri.
    /// inkL/paperD nötr "mürekkep" için Palette'te çözülür (bu fonksiyon o ikisini almaz).
    func hex(dark: Bool) -> UInt32 {
        switch self {
        case .bordo:    return dark ? 0xB0564E : 0x8E3F39
        case .adacayi:  return dark ? 0x6F9D83 : 0x4E7A60
        case .murekkep: return dark ? 0xECE9E2 : 0x26241F
        case .petrol:   return dark ? 0x6B97A3 : 0x44707C
        case .celik:    return dark ? 0x7E93AD : 0x50677F
        case .murdum:   return dark ? 0xA8788F : 0x7D5267
        case .tutun:    return dark ? 0xA98D6B : 0x7A5C40
        }
    }
}

/// UserDefaults-destekli tema durumu. Semantik/grafik değişince `.herculesThemeChanged`
/// post edilir; ContentView ağacı tazeler (renkler çizim anında defaults'tan okunur).
enum ThemeSettings {
    static let appearanceKey = "hercules.theme.appearance"
    static let semanticKey   = "hercules.theme.semantic"
    static let chartKey      = "hercules.theme.chart"

    static var appearance: AppAppearance {
        get { AppAppearance(rawValue: UserDefaults.standard.string(forKey: appearanceKey) ?? "") ?? .dark }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey)
            NotificationCenter.default.post(name: .herculesThemeChanged, object: nil)
        }
    }

    static var semantic: SemanticScheme {
        get { SemanticScheme(rawValue: UserDefaults.standard.string(forKey: semanticKey) ?? "") ?? .adacayiBordo }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: semanticKey)
            NotificationCenter.default.post(name: .herculesThemeChanged, object: nil)
        }
    }

    static var chart: ChartTint {
        get { ChartTint(rawValue: UserDefaults.standard.string(forKey: chartKey) ?? "") ?? .adacayi }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: chartKey)
            NotificationCenter.default.post(name: .herculesThemeChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let herculesThemeChanged = Notification.Name("hercules.theme.changed")
}

// MARK: - Dinamik renk altyapısı

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Görünüme göre çizim anında çözülen renk. Closure'lar resolve sırasında çalışır —
/// semantik/grafik token'ları içeride ThemeSettings okuyabilir.
private func dyn(light: @autoclosure @escaping () -> Color, dark: @autoclosure @escaping () -> Color) -> Color {
    #if canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(isDark ? dark() : light())
    })
    #else
    return Color(uiColor: UIColor { traits in
        UIColor(traits.userInterfaceStyle == .dark ? dark() : light())
    })
    #endif
}

// MARK: - Kömür rampası (koç yüzeyinin kromu = uygulamanın koyu teması)

/// Koç sayfasının monokrom kömür rampası. Tek kaynak burada durur: `Palette`'in
/// KOYU tarafı ve `ChatChrome` ikisi de bunu okur, böylece uygulama genelinde
/// koç sayfasıyla birebir aynı zemin/katman/metin kademeleri kullanılır.
/// (Açık tema fildişi kağıt olarak kalır — koç yüzeyi her görünümde kömürdür.)
enum Charcoal {
    // Basamaklar bilinçli olarak açık: rampa dibe yapışınca (0x09…0x15 arası)
    // katmanlar birbirinden ayırt edilemiyordu. Zemin bir tık kaldırıldı ve her
    // kademe arasına görünür bir fark bırakıldı.
    static let bg      = Color(hex: 0x0D0E0F)   // içerik zemini
    static let panel   = Color(hex: 0x141618)   // yan kolonlar (sidebar, geçmiş rayı)
    static let card    = Color(hex: 0x1A1C1E)   // kart / balon / açılır menü
    static let raised  = Color(hex: 0x232628)   // yükseltilmiş, seçili
    static let pressed = Color(hex: 0x2B2E30)   // basılı

    static let paper = Color(hex: 0xF0F0ED)     // ana metin / kağıt-beyazı eylem
    static let ink   = Color(hex: 0x0B0C0D)     // kağıt-beyazı eylem üstündeki mürekkep
    static let text2 = Color(hex: 0x999A96)
    static let text3 = Color(hex: 0x666763)
    static let text4 = Color(hex: 0x454642)

    static let line       = Color.white.opacity(0.09)
    static let lineStrong = Color.white.opacity(0.14)

    // Etkileşim dolguları: kömür zeminde "siyahla karartma" görünmez —
    // hover/alan/seçili durumları beyazla kaldırılır.
    static let fill       = Color.white.opacity(0.05)    // input alanı, hover
    static let fillStrong = Color.white.opacity(0.09)    // seçili satır, ray
}

// MARK: - Palette (tüm eski token adları korunur; değerler tema spec'inden)

/// Tema-bağımlı token'lar (positive/chart) için ayar-anahtarlı önbellek.
/// Değer bir kez üretilir; aynı ayar için sonraki erişimler bedava.
private final class KeyedColorCache<Key: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Key: Color] = [:]

    func color(for key: Key, make: (Key) -> Color) -> Color {
        lock.lock()
        if let hit = values[key] { lock.unlock(); return hit }
        lock.unlock()
        let made = make(key)
        lock.lock()
        values[key] = made
        lock.unlock()
        return made
    }
}

/// Açık tema: fildişi kağıt + mürekkep. Koyu tema: koç yüzeyinin kömür rampası
/// (bkz. `Charcoal`). Makrolar sabit: P nötr / K adaçayı / Y pirinç.
///
/// Token'lar `static let`: computed var hâli HER erişimde 2 escaping closure +
/// 1 NSColor(provider) + 1 Color kutusu alloc ediyordu — 42 hücrelik takvim tek
/// render'da Palette'e yüzlerce kez dokunur. Dinamik NSColor appearance'ı çizim
/// anında çözdüğü için cache'lenmiş Color açık/koyu geçişine yine otomatik uyar.
enum Palette {
    private static let inkL   = Color(hex: 0x26241F)   // açık tema mürekkep
    private static let paperD = Charcoal.paper         // koyu tema metin

    // Zeminler
    static let background: Color = dyn(light: Color(hex: 0xF2EFE8), dark: Charcoal.bg)
    /// Yan kolon zemini (sidebar, geçmiş rayı). İçerik zemininden bir basamak
    /// ayrılır — aksi halde krom ve içerik tek bir düz yüzeye eriyor.
    static let panel: Color = dyn(light: Color(hex: 0xEDEAE3), dark: Charcoal.panel)
    static let surface: Color = dyn(light: Color(hex: 0xFAF9F5), dark: Charcoal.card)
    static let surfaceElevated: Color = dyn(light: Color(hex: 0xECE9E1), dark: Charcoal.raised)

    // Çizgiler
    static let border: Color = dyn(light: inkL.opacity(0.10), dark: Charcoal.line)
    static let borderStrong: Color = dyn(light: inkL.opacity(0.12), dark: Charcoal.lineStrong)

    // Metin
    static let textPrimary: Color = dyn(light: inkL, dark: paperD)
    static let textSecondary: Color = dyn(light: Color(hex: 0x6E6A60), dark: Charcoal.text2)
    static let textTertiary: Color = dyn(light: Color(hex: 0x98948A), dark: Charcoal.text3)
    static let textQuaternary: Color = dyn(light: inkL.opacity(0.35), dark: Charcoal.text4)

    // Marka vurgusu = NÖTR mürekkep/kağıt (seçili durum, nokta işaretleri, CTA).
    // Bordo UI'da kullanılmaz — yalnızca Grafik Rengi seçeneği olarak yaşar.
    static let accent: Color = dyn(light: inkL, dark: paperD)
    static let accentSoft: Color = accent.opacity(0.14)
    static let accentDim: Color = accent.opacity(0.38)

    // Semantik — B: olumlu adaçayı / C: olumlu nötr gri; olumsuz iki şemada da pirinç.
    // ThemeSettings okuması resolve closure'ının DIŞINDA: eski hali UserDefaults'u
    // her appearance çözümünde (çizim başına) yeniden okuyordu.
    private static let positiveCache = KeyedColorCache<SemanticScheme>()
    static var positive: Color {
        positiveCache.color(for: ThemeSettings.semantic) { scheme in
            dyn(
                light: scheme == .adacayiBordo ? Color(hex: 0x4E7A60) : Color(hex: 0x8D887C),
                dark: scheme == .adacayiBordo ? Color(hex: 0x6F9D83) : Color(hex: 0x8A867D)
            )
        }
    }
    static let negative: Color = dyn(light: Color(hex: 0x96763C), dark: Color(hex: 0xC2A36B))
    static var warning: Color { macroFat }   // pirinç — alarm değil, kenar notu

    // Makrolar: P nötr mürekkep · K adaçayı · Y pirinç (bordo yok)
    static let macroProtein: Color = dyn(light: inkL, dark: paperD)
    static let macroCarbs: Color = dyn(light: Color(hex: 0x4E7A60), dark: Color(hex: 0x6F9D83))
    static let macroFat: Color = dyn(light: Color(hex: 0x96763C), dark: Color(hex: 0xC2A36B))

    // Grafik — Settings'teki bağımsız seçenek (halka, ağırlık grafiği, sparkline)
    private static let chartCache = KeyedColorCache<ChartTint>()
    static var chart: Color {
        chartCache.color(for: ThemeSettings.chart) { tint in
            dyn(
                light: Color(hex: tint.hex(dark: false)),
                dark: Color(hex: tint.hex(dark: true))
            )
        }
    }

    // Dolgulu buton / aktif segment (mürekkep zemin + fildişi yazı; koyuda tersi)
    static let btnBg: Color = dyn(light: inkL, dark: Charcoal.paper)
    static let btnFg: Color = dyn(light: Color(hex: 0xF2EFE8), dark: Charcoal.ink)

    // Ray/alan dolguları
    static let track: Color = dyn(light: inkL.opacity(0.08), dark: Charcoal.fillStrong)
    static let fieldFill: Color = dyn(light: inkL.opacity(0.045), dark: Charcoal.fill)

    // Kart derinliği: yaygın gölge + temas gölgesi + üst kenar ışık rim'i.
    // Rim bilinçli olarak fısıltı seviyesinde — border'dan ancak bir tık parlak.
    static let cardShadow: Color = dyn(light: inkL.opacity(0.08), dark: Color.black.opacity(0.38))
    static let cardShadowTight: Color = dyn(light: inkL.opacity(0.05), dark: Color.black.opacity(0.30))
    static let cardRim: Color = dyn(light: Color.white.opacity(0.30), dark: Color.white.opacity(0.10))

    // Grafik zemin çizgileri
    static let chartGrid: Color = dyn(light: inkL.opacity(0.05), dark: Color.white.opacity(0.035))
    static let chartBand: Color = dyn(light: inkL.opacity(0.07), dark: Color.white.opacity(0.055))
    static let chartBandStrong: Color = dyn(light: inkL.opacity(0.12), dark: Color.white.opacity(0.10))
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}
