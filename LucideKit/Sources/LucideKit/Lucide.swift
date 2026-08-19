import SwiftUI
import CoreText

/// Bundle'lanmış Lucide fontu. Tek ağırlık (Lucide'ın tutarlı 2px stroke'u); renk parent
/// `foregroundStyle`'dan miras alınır, tıpkı bir SF Symbol gibi.
public enum LucideFont {
    /// `Font.custom(_:size:)` için aile adı (TTF name tablosundan doğrulandı).
    public static let name = "lucide"

    private static var didRegister = false

    /// Fontu süreç geneline kaydeder. Idempotent. Yalnızca main thread'den çağır
    /// (view init / app launch). Süreç-geneli olduğu için app bir kez kaydedince
    /// Tüm modüller `Font.custom("lucide", …)` kullanabilir.
    public static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        guard let url = Bundle.module.url(forResource: "lucide", withExtension: "ttf") else {
            assertionFailure("LucideKit: lucide.ttf bundle'da bulunamadı")
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// SF Symbols `Image(systemName:)`'in Lucide karşılığı: `Lucide("brain", size: 16)`.
/// İsim Lucide ikon adıdır (lucide.dev). Boyut SF Symbol'deki `.font(.system(size:))` ile
/// aynı rolü oynar; ağırlık yok (Lucide tek stroke). Renk dışarıdan `.foregroundStyle`.
public struct Lucide: View {
    private let glyph: String
    private let size: CGFloat

    public init(_ name: String, size: CGFloat = 17) {
        LucideFont.registerIfNeeded()
        self.glyph = LucideCodepoints.map[name]
            ?? LucideCodepoints.map["circle-help"]
            ?? ""
        self.size = size
    }

    /// SF Symbols adından Lucide karşılığını render eder (migration köprüsü).
    /// `Image(systemName: X)` → `Lucide(sf: X, size: N)`. Enum prop'ları / ternary'ler
    /// değişmeden çalışır; eşleme `LucideSF` tablosundadır.
    public init(sf: String, size: CGFloat = 17) {
        self.init(LucideSF.lucideName(forSF: sf), size: size)
    }

    public var body: some View {
        Text(verbatim: glyph)
            // fixedSize → Dynamic Type'la ölçeklenmez (eski `.system(size:)` davranışıyla eş).
            .font(.custom(LucideFont.name, fixedSize: size))
    }
}

/// Birden çok yerde geçen semantik ikonlar — tek noktadan tutarlılık.
/// Özellikle AI/koç ikonu: eskiden `sparkles`/`wand.and.stars`/`brain.head.profile` karışıktı.
public enum LIcon {
    public static let ai = "sparkles"        // tüm AI/koç/asistan vurgusu
    public static let memory = "brain"       // hafıza/episodik
    public static let distill = "sparkles"   // "AI ile damıt"
}
