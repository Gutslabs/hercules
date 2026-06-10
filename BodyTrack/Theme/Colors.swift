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

// MARK: - Palette (tüm eski token adları korunur; değerler tema spec'inden)

/// Açık tema: fildişi kağıt + mürekkep. Koyu tema: #121417 + kağıt metin.
/// Makrolar sabit: P bordo / K adaçayı / Y pirinç. accent = bordo (marka vurgusu).
enum Palette {
    private static let inkL   = Color(hex: 0x26241F)   // açık tema mürekkep
    private static let paperD = Color(hex: 0xECE9E2)   // koyu tema metin

    // Zeminler
    static var background: Color { dyn(light: Color(hex: 0xF2EFE8), dark: Color(hex: 0x121417)) }
    static var surface: Color { dyn(light: Color(hex: 0xFAF9F5), dark: Color.white.opacity(0.035)) }
    static var surfaceElevated: Color { dyn(light: Color(hex: 0xECE9E1), dark: Color.white.opacity(0.07)) }

    // Çizgiler
    static var border: Color { dyn(light: inkL.opacity(0.10), dark: Color.white.opacity(0.08)) }
    static var borderStrong: Color { dyn(light: inkL.opacity(0.12), dark: Color.white.opacity(0.12)) }

    // Metin
    static var textPrimary: Color { dyn(light: inkL, dark: paperD) }
    static var textSecondary: Color { dyn(light: Color(hex: 0x6E6A60), dark: Color(hex: 0x9A968D)) }
    static var textTertiary: Color { dyn(light: Color(hex: 0x98948A), dark: Color(hex: 0x6C6961)) }
    static var textQuaternary: Color { dyn(light: inkL.opacity(0.35), dark: Color.white.opacity(0.28)) }

    // Marka vurgusu = NÖTR mürekkep/kağıt (seçili durum, nokta işaretleri, CTA).
    // Bordo UI'da kullanılmaz — yalnızca Grafik Rengi seçeneği olarak yaşar.
    static var accent: Color { dyn(light: inkL, dark: paperD) }
    static var accentSoft: Color { accent.opacity(0.14) }
    static var accentDim: Color { accent.opacity(0.38) }

    // Semantik — B: olumlu adaçayı / C: olumlu nötr gri; olumsuz iki şemada da pirinç
    static var positive: Color {
        dyn(
            light: ThemeSettings.semantic == .adacayiBordo ? Color(hex: 0x4E7A60) : Color(hex: 0x8D887C),
            dark: ThemeSettings.semantic == .adacayiBordo ? Color(hex: 0x6F9D83) : Color(hex: 0x8A867D)
        )
    }
    static var negative: Color { dyn(light: Color(hex: 0x96763C), dark: Color(hex: 0xC2A36B)) }
    static var warning: Color { macroFat }   // pirinç — alarm değil, kenar notu

    // Makrolar: P nötr mürekkep · K adaçayı · Y pirinç (bordo yok)
    static var macroProtein: Color { dyn(light: inkL, dark: paperD) }
    static var macroCarbs: Color { dyn(light: Color(hex: 0x4E7A60), dark: Color(hex: 0x6F9D83)) }
    static var macroFat: Color { dyn(light: Color(hex: 0x96763C), dark: Color(hex: 0xC2A36B)) }

    // Grafik — Settings'teki bağımsız seçenek (halka, ağırlık grafiği, sparkline)
    static var chart: Color {
        dyn(
            light: Color(hex: ThemeSettings.chart.hex(dark: false)),
            dark: Color(hex: ThemeSettings.chart.hex(dark: true))
        )
    }

    // Dolgulu buton / aktif segment (mürekkep zemin + fildişi yazı; koyuda tersi)
    static var btnBg: Color { dyn(light: inkL, dark: Color(hex: 0xE8E4DA)) }
    static var btnFg: Color { dyn(light: Color(hex: 0xF2EFE8), dark: Color(hex: 0x15181C)) }

    // Ray/alan dolguları
    static var track: Color { dyn(light: inkL.opacity(0.08), dark: Color.white.opacity(0.08)) }
    static var fieldFill: Color { dyn(light: inkL.opacity(0.045), dark: Color.black.opacity(0.20)) }

    // Kart derinliği: yaygın gölge + temas gölgesi + üst kenar ışık rim'i.
    // Rim bilinçli olarak fısıltı seviyesinde — border'dan ancak bir tık parlak.
    static var cardShadow: Color { dyn(light: inkL.opacity(0.08), dark: Color.black.opacity(0.38)) }
    static var cardShadowTight: Color { dyn(light: inkL.opacity(0.05), dark: Color.black.opacity(0.30)) }
    static var cardRim: Color { dyn(light: Color.white.opacity(0.30), dark: Color.white.opacity(0.10)) }

    // Grafik zemin çizgileri
    static var chartGrid: Color { dyn(light: inkL.opacity(0.05), dark: Color.white.opacity(0.035)) }
    static var chartBand: Color { dyn(light: inkL.opacity(0.07), dark: Color.white.opacity(0.055)) }
    static var chartBandStrong: Color { dyn(light: inkL.opacity(0.12), dark: Color.white.opacity(0.10)) }
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
