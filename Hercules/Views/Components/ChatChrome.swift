import SwiftUI

/// Koç yüzeyinin monokrom kromu.
///
/// Değerler artık `Charcoal` rampasından gelir — aynı rampa `Palette`'in KOYU
/// tarafını da besler, yani koyu temada uygulama geneli koç sayfasıyla birebir
/// aynı zemin/katman/metin kademelerini kullanır. Fark tek yerde: koç yüzeyi
/// görünüm seçicisinden bağımsızdır, açık temada da kömür kalır.
enum ChatChrome {
    static let background = Charcoal.bg
    static let panel = Charcoal.panel
    static let panelRaised = Charcoal.raised
    static let panelPressed = Charcoal.pressed
    static let border = Charcoal.line
    static let borderStrong = Charcoal.lineStrong
    static let primary = Charcoal.paper
    static let secondary = Charcoal.text2
    static let tertiary = Charcoal.text3
    static let quaternary = Charcoal.text4
    static let accent = Charcoal.paper
    static let accentSoft = Color.white.opacity(0.08)
    static let positive = BuzzTheme.statusAdded
    /// Kağıt-beyazı eylem üstündeki mürekkep.
    static let ink = Charcoal.ink
    /// Referanstaki tek yüksek-kontrast vurgu.
    static let white = Charcoal.paper
    static let whiteSoft = Color.white.opacity(0.055)
    static let userBubble = Charcoal.raised
    static let assistantBubble = Color.clear
    static let card = Charcoal.card

    // MARK: Mesaj tipografisi
    /// Sohbet baloncuğu gövde metni — app geneli `Typography.body`'den (13pt) bir tık
    /// büyük; SADECE chat konuşmalarında kullanılır (sidebar/kart token'larını etkilemez).
    static let messageBody = Font.system(size: 14.5, weight: .regular)
}

/// Input DIŞINDA bir yere tıklanınca sohbet yazma alanının focus'unu bıraktırır.
/// `ContentView` post eder (sidebar ve detay kolonu tap'lerinde), `ChatPageView` dinler.
extension Notification.Name {
    static let aiChatShouldResignInputFocus = Notification.Name("hercules.ai.chat.resign.input.focus")
}
