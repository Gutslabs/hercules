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

/// Sidebar (pencere zemini) gradienti — üstten alta iki durak.
/// Buz mavisi ailesi + mevcut zeytin; Ayarlar'dan anında denenebilir.
enum SidebarTint: String, CaseIterable, Identifiable, Sendable {
    // Koyu yüzeyler (koyu temada koyu kalır, yazı beyaz)
    case zeytin        // mevcut: zeytin → gece mavisi (Buzz)
    case buzMavisi     // açık buz mavisi → derin gece
    case kutup         // doygun buz/turkuaz
    case gece          // klasik gece mavisi
    case okyanus       // derin petrol mavisi
    case lavanta       // soğuk mor
    case orman         // koyu yeşil
    case korAtesi      // kızıl-kahve
    case kahve         // sıcak kahve
    case grafit        // nötr grafit

    // AÇIK yüzeyler — koyu temada bile açık kalır (yazı koyuya döner)
    case kar           // saf beyaz → çok açık gri
    case sis           // soğuk açık gri
    case inci          // sıcak kırık beyaz
    case porselen      // mavimsi beyaz
    case kirec         // bej-kireç beyazı

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zeytin:    return "Zeytin"
        case .buzMavisi: return "Buz Mavisi"
        case .kutup:     return "Kutup"
        case .gece:      return "Gece"
        case .okyanus:   return "Okyanus"
        case .lavanta:   return "Lavanta"
        case .orman:     return "Orman"
        case .korAtesi:  return "Kor"
        case .kahve:     return "Kahve"
        case .grafit:    return "Grafit"
        case .kar:       return "Kar"
        case .sis:       return "Sis"
        case .inci:      return "İnci"
        case .porselen:  return "Porselen"
        case .kirec:     return "Kireç"
        }
    }

    /// Beyaz ailesi: her iki temada da AÇIK yüzey (sidebar yazısı koyuya döner).
    var isLightFamily: Bool {
        switch self {
        case .kar, .sis, .inci, .porselen, .kirec: return true
        default: return false
        }
    }

    /// Yüzey açık mı? Açıksa sidebar mürekkebi koyu, peçeler siyah tabanlı olur.
    func hasLightSurface(dark: Bool) -> Bool { isLightFamily || !dark }

    /// (üst, alt) — koyu tema.
    var darkStops: (UInt32, UInt32) {
        switch self {
        case .zeytin:    return (0x4A4616, 0x0A1423)
        case .buzMavisi: return (0x2C5566, 0x0A1423)
        case .kutup:     return (0x1F6B7A, 0x081522)
        case .gece:      return (0x1C3A5E, 0x080F1B)
        case .okyanus:   return (0x14576B, 0x061019)
        case .lavanta:   return (0x4A4470, 0x0C0A16)
        case .orman:     return (0x274A38, 0x080F0B)
        case .korAtesi:  return (0x6B3A2A, 0x1A0D08)
        case .kahve:     return (0x4A3A2C, 0x120C08)
        case .grafit:    return (0x33373C, 0x0B0D10)
        case .kar:       return (0xFFFFFF, 0xDDE3E8)
        case .sis:       return (0xE9EDF0, 0xC6CED5)
        case .inci:      return (0xF6F2EB, 0xDCD5C9)
        case .porselen:  return (0xEDF4F8, 0xCBD8E1)
        case .kirec:     return (0xEDEAE3, 0xCBC7BE)
        }
    }

    /// (üst, alt) — açık tema.
    var lightStops: (UInt32, UInt32) {
        switch self {
        case .zeytin:    return (0xE6E6B6, 0xC4D0DA)
        case .buzMavisi: return (0xD3E7F0, 0xBFD2DE)
        case .kutup:     return (0xC7E6EA, 0xB4CFDB)
        case .gece:      return (0xCFDCEC, 0xB9C7D8)
        case .okyanus:   return (0xC2DFE8, 0xA9C6D4)
        case .lavanta:   return (0xDCD8EE, 0xC3BEDA)
        case .orman:     return (0xD3E4D8, 0xB6CDBE)
        case .korAtesi:  return (0xF0D6C8, 0xD8B7A6)
        case .kahve:     return (0xE8DDD1, 0xCDBEAE)
        case .grafit:    return (0xDCDEE1, 0xC3C7CC)
        case .kar:       return (0xFFFFFF, 0xE9EDF0)
        case .sis:       return (0xEFF2F5, 0xD5DCE2)
        case .inci:      return (0xFAF7F1, 0xE6DFD3)
        case .porselen:  return (0xF4F9FC, 0xDCE6EE)
        case .kirec:     return (0xF3F1EB, 0xDAD6CD)
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

    static let sidebarKey    = "hercules.theme.sidebar"

    static var sidebar: SidebarTint {
        get { SidebarTint(rawValue: UserDefaults.standard.string(forKey: sidebarKey) ?? "") ?? .buzMavisi }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: sidebarKey)
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
func dynColor(light: @autoclosure @escaping () -> Color, dark: @autoclosure @escaping () -> Color) -> Color {
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
/// Koyu rampa artık Buzz Dark'ın birebir portu: Buzz, github-dark Shiki
/// paletinden türetir (adaptive-theme.ts) ve içerik kanvasını #1A1A1A'ya
/// (`--buzz-content-dark`) sabitler. Basamaklar Buzz'ın kendi türetimi:
/// card = github-dark bg, raised = elevate(0.06), pressed = elevate(0.10).
enum Charcoal {
    // shadcn dark kanvas ailesi: zemin near-black, kartlar nötr zinc —
    // kart/zemin kontrastı Buzz'ın düz #1A1A1A'sından belirgin şekilde yüksek.
    static let bg      = Color(hex: 0x0B0B0C)   // içerik zemini (zinc-950 tonu)
    static let panel   = Color(hex: 0x0B0B0C)   // yan kolonlar — ayrım hairline'la
    static let card    = Color(hex: 0x1A1B1E)   // kart / balon / açılır menü (zinc-900)
    static let raised  = Color(hex: 0x27272A)   // yükseltilmiş, seçili (zinc-800)
    static let pressed = Color(hex: 0x323236)   // basılı

    static let paper = Color(hex: 0xE1E4E8)     // ana metin (--foreground)
    static let ink   = Color(hex: 0x24292E)     // kağıt-beyazı eylem üstündeki mürekkep (--primary-foreground)
    // "Soluk" geri bildirimi sonrası bir kademe parlak: ikincil metin muted-fg
    // DEĞİL, foreground'ın ~%65'i (Buzz gövde-yanı metni); muted-fg üçüncü kademeye indi.
    static let text2 = Color(hex: 0x9BA0A6)     // foreground %65 — ikincil metin
    static let text3 = Color(hex: 0x6A737D)     // --muted-foreground (github-dark comment)
    static let text4 = Color(hex: 0x52585F)     // muted-fg %70 — timestamp kademesi

    // Buzz border'ı #40454A'yı %50-80 alfayla kullanır. Token TAM güç durur;
    // alfayı çağrı yeri seçer (kart .opacity(0.7) = Buzz border/70). Eskiden token
    // 0.55 taşıyordu ve kart kenarları 0.55×0.7 ≈ %38'e düşüp görünmez oluyordu.
    static let line       = Color(hex: 0x3F3F46)   // zinc-700
    static let lineStrong = Color(hex: 0x52525B)   // zinc-600

    // Etkileşim dolguları: Buzz'ın beyaz-tül overlay'leri (hover %4, seçili %16'ya
    // sidebar kendi token'ıyla çıkar; içerik yüzeyinde ılımlı kal).
    static let fill       = Color.white.opacity(0.045)   // input alanı, hover
    static let fillStrong = Color.white.opacity(0.09)    // seçili satır, ray
}

// MARK: - Buzz kanvas token'ları (gradient + gradient üstü sidebar kromu)

/// Buzz'ın imza katmanı: pencere kanvasına tek bir dikey gradient boyanır,
/// sidebar ve üst krom şeffaftır, içerik 16px köşeli bir kart olarak üstte yüzer.
/// Değerler Buzz theme.css'ten birebir (`--buzz-gradient-*`, `--buzz-*-surface`).
enum BuzzTheme {
    /// Gradient durakları Ayarlar'daki Sidebar Rengi seçimine bağlı.
    /// ThemeSettings okuması resolve closure'ının DIŞINDA (her çizimde defaults
    /// okumamak için) — semantic/chart ile aynı desen.
    private static let gradientTopCache = KeyedColorCache<SidebarTint>()
    static var gradientTop: Color {
        gradientTopCache.color(for: ThemeSettings.sidebar) { tint in
            dynColor(light: Color(hex: tint.lightStops.0), dark: Color(hex: tint.darkStops.0))
        }
    }

    private static let gradientBottomCache = KeyedColorCache<SidebarTint>()
    static var gradientBottom: Color {
        gradientBottomCache.color(for: ThemeSettings.sidebar) { tint in
            dynColor(light: Color(hex: tint.lightStops.1), dark: Color(hex: tint.darkStops.1))
        }
    }

    /// Gradient üstündeki sidebar metin/etkileşim katmanı. AÇIK yüzeyli tonlarda
    /// (Kar, Sis, İnci…) koyu temada bile mürekkep KOYUYA döner — yoksa beyaz
    /// zeminde beyaz yazı olurdu.
    private static let inkCache = KeyedColorCache<SidebarTint>()
    private static let sidebarInk = Color(hex: 0x24292E)

    /// Yüzeye göre çözülen sidebar token'ı: açık zeminde siyah tabanlı,
    /// koyu zeminde beyaz tabanlı.
    private static func onSurface(_ cache: KeyedColorCache<SidebarTint>,
                                  onLight: @escaping (Bool) -> Color) -> Color {
        cache.color(for: ThemeSettings.sidebar) { tint in
            dynColor(light: onLight(tint.hasLightSurface(dark: false)),
                     dark: onLight(tint.hasLightSurface(dark: true)))
        }
    }

    static var sidebarText: Color {
        onSurface(inkCache) { light in light ? sidebarInk : .white }
    }

    private static let mutedCache = KeyedColorCache<SidebarTint>()
    static var sidebarMuted: Color {
        onSurface(mutedCache) { light in (light ? Color.black : Color.white).opacity(0.40) }
    }

    private static let chromeCache = KeyedColorCache<SidebarTint>()
    static var sidebarChrome: Color {
        onSurface(chromeCache) { light in (light ? Color.black : Color.white).opacity(0.50) }
    }

    private static let hoverCache = KeyedColorCache<SidebarTint>()
    static var rowHover: Color {
        onSurface(hoverCache) { light in (light ? Color.black : Color.white).opacity(0.05) }
    }

    private static let activeCache = KeyedColorCache<SidebarTint>()
    static var rowActive: Color {
        onSurface(activeCache) { light in light ? Color.black.opacity(0.08) : Color.white.opacity(0.16) }
    }

    private static let activeTextCache = KeyedColorCache<SidebarTint>()
    static var rowActiveText: Color {
        onSurface(activeTextCache) { light in light ? Color(hex: 0x1A1A1A) : .white }
    }

    private static let searchCache = KeyedColorCache<SidebarTint>()
    static var searchFill: Color {
        onSurface(searchCache) { light in (light ? Color.black : Color.white).opacity(0.05) }
    }

    /// İçerik yüzeyi de sidebar gibi KADEMELİ: üstte seçili tonun çok soluk bir
    /// izi, altta saf sayfa zemini. Gradient sidebar'la aynı yönde (üst → alt),
    /// böylece iki yüzey aynı ışığı paylaşıyor gibi durur.
    private static let contentTopCache = KeyedColorCache<SidebarTint>()
    static var contentGradientTop: Color {
        contentTopCache.color(for: ThemeSettings.sidebar) { tint in
            dynColor(
                light: Color(hex: blend(0xFFFFFF, tint.lightStops.0, 0.30)),
                dark:  Color(hex: blend(0x0B0B0C, tint.darkStops.0, tint.isLightFamily ? 0.07 : 0.16))
            )
        }
    }

    private static let contentBottomCache = KeyedColorCache<SidebarTint>()
    static var contentGradientBottom: Color {
        contentBottomCache.color(for: ThemeSettings.sidebar) { tint in
            dynColor(
                light: Color(hex: blend(0xFFFFFF, tint.lightStops.1, 0.08)),
                dark:  Color(hex: blend(0x0B0B0C, tint.darkStops.1, 0.35))
            )
        }
    }

    /// İki hex rengi `amount` oranında karıştırır (0 = a, 1 = b).
    private static func blend(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        let t = min(max(amount, 0), 1)
        func ch(_ shift: UInt32) -> UInt32 {
            let ca = Double((a >> shift) & 0xFF)
            let cb = Double((b >> shift) & 0xFF)
            return UInt32((ca + (cb - ca) * t).rounded())
        }
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }

    /// İçerik kartının kenar vurgusu (dark: sidebar-border %45 hairline;
    /// light'ta yumuşak gölge ayrıca eklenir).
    static let contentEdge: Color = dynColor(light: Color.black.opacity(0.10), dark: Color(hex: 0x40454A).opacity(0.45))

    /// Temalar arası sabitler (theme.css: bildirim kırmızısı + mention fosforu).
    static let notification = Color(hex: 0xCA2B4B)
    static let notificationFg = Color(hex: 0xFFF5F7)
    static let mention = Color(hex: 0xFCDF69)
    static let statusAdded = Color(hex: 0x34D058)
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
    private static let inkL   = Color(hex: 0x24292E)   // açık tema mürekkep (github-light fg)
    private static let paperD = Charcoal.paper         // koyu tema metin

    // Zeminler
    static let background: Color = dynColor(light: .white, dark: Charcoal.bg)
    /// Yan kolon zemini (sidebar, geçmiş rayı). İçerik zemininden bir basamak
    /// ayrılır — aksi halde krom ve içerik tek bir düz yüzeye eriyor.
    static let panel: Color = dynColor(light: Color(hex: 0xF6F6F6), dark: Charcoal.panel)
    static let surface: Color = dynColor(light: .white, dark: Charcoal.card)
    static let surfaceElevated: Color = dynColor(light: Color(hex: 0xF0F0F0), dark: Charcoal.raised)

    // Çizgiler
    static let border: Color = dynColor(light: inkL.opacity(0.10), dark: Charcoal.line)
    static let borderStrong: Color = dynColor(light: inkL.opacity(0.12), dark: Charcoal.lineStrong)

    // Metin
    static let textPrimary: Color = dynColor(light: inkL, dark: paperD)
    static let textSecondary: Color = dynColor(light: Color(hex: 0x6A737D), dark: Charcoal.text2)
    static let textTertiary: Color = dynColor(light: Color(hex: 0x979DA4), dark: Charcoal.text3)
    static let textQuaternary: Color = dynColor(light: inkL.opacity(0.35), dark: Charcoal.text4)

    // Marka vurgusu = NÖTR mürekkep/kağıt (seçili durum, nokta işaretleri, CTA).
    // Bordo UI'da kullanılmaz — yalnızca Grafik Rengi seçeneği olarak yaşar.
    static let accent: Color = dynColor(light: inkL, dark: paperD)
    static let accentSoft: Color = accent.opacity(0.14)
    static let accentDim: Color = accent.opacity(0.38)

    // Semantik — B: olumlu adaçayı / C: olumlu nötr gri; olumsuz iki şemada da pirinç.
    // ThemeSettings okuması resolve closure'ının DIŞINDA: eski hali UserDefaults'u
    // her appearance çözümünde (çizim başına) yeniden okuyordu.
    private static let positiveCache = KeyedColorCache<SemanticScheme>()
    static var positive: Color {
        positiveCache.color(for: ThemeSettings.semantic) { scheme in
            dynColor(
                light: scheme == .adacayiBordo ? Color(hex: 0x4E7A60) : Color(hex: 0x8D887C),
                dark: scheme == .adacayiBordo ? Color(hex: 0x6F9D83) : Color(hex: 0x8A867D)
            )
        }
    }
    /// Olumsuz durum (hedef üstü, silme, hata) — pirinç değil GERÇEK kırmızı:
    /// "fazla" gibi uyarılar sarı tonda alarm hissi vermiyordu.
    static let negative: Color = dynColor(light: Color(hex: 0xB3261E), dark: Color(hex: 0xE5565E))
    static var warning: Color { macroFat }   // pirinç — alarm değil, kenar notu

    // Makrolar: P nötr mürekkep · K adaçayı · Y pirinç (bordo yok)
    static let macroProtein: Color = dynColor(light: inkL, dark: paperD)
    static let macroCarbs: Color = dynColor(light: Color(hex: 0x4E7A60), dark: Color(hex: 0x6F9D83))
    static let macroFat: Color = dynColor(light: Color(hex: 0x96763C), dark: Color(hex: 0xC2A36B))

    // Grafik — Settings'teki bağımsız seçenek (halka, ağırlık grafiği, sparkline)
    private static let chartCache = KeyedColorCache<ChartTint>()
    static var chart: Color {
        chartCache.color(for: ThemeSettings.chart) { tint in
            dynColor(
                light: Color(hex: tint.hex(dark: false)),
                dark: Color(hex: tint.hex(dark: true))
            )
        }
    }

    // Dolgulu buton / aktif segment (mürekkep zemin + fildişi yazı; koyuda tersi)
    static let btnBg: Color = dynColor(light: inkL, dark: Charcoal.paper)
    static let btnFg: Color = dynColor(light: .white, dark: Charcoal.ink)

    /// Seçim peçesi — içerik yüzeyinde kullanılır; sidebar tonundan bağımsızdır
    /// (sidebar beyaza dönünce kart seçimi kaybolmasın diye).
    static let selectionVeil: Color      = dynColor(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.16))
    static let selectionVeilHover: Color = dynColor(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.05))

    // Ray/alan dolguları
    static let track: Color = dynColor(light: inkL.opacity(0.08), dark: Charcoal.fillStrong)
    static let fieldFill: Color = dynColor(light: inkL.opacity(0.045), dark: Charcoal.fill)

    // Kart derinliği: yaygın gölge + temas gölgesi + üst kenar ışık rim'i.
    // Rim bilinçli olarak fısıltı seviyesinde — border'dan ancak bir tık parlak.
    static let cardShadow: Color = dynColor(light: inkL.opacity(0.08), dark: Color.black.opacity(0.38))
    static let cardShadowTight: Color = dynColor(light: inkL.opacity(0.05), dark: Color.black.opacity(0.30))
    static let cardRim: Color = dynColor(light: Color.white.opacity(0.30), dark: Color.white.opacity(0.10))

    // Grafik zemin çizgileri
    static let chartGrid: Color = dynColor(light: inkL.opacity(0.05), dark: Color.white.opacity(0.035))
    static let chartBand: Color = dynColor(light: inkL.opacity(0.07), dark: Color.white.opacity(0.055))
    static let chartBandStrong: Color = dynColor(light: inkL.opacity(0.12), dark: Color.white.opacity(0.10))
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
