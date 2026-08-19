import SwiftUI

/// Ajan "düşünüyor" glyph'i — dairesel maske içinde yatay çizgi alanı; üstünde
/// farklı hız ve fazlarda kayan parlak bloklar ("veriyi tarıyor" hissi).
///
/// State yok: tek `Canvas` + `TimelineView`, konumlar doğrudan zamandan türetilir →
/// her karede view ağacı yeniden kurulmaz ve ritim her açılışta aynıdır.
///
/// Mac koç ve mobil koç sohbeti bunu paylaşır.
struct AgentThinkingGlyph: View {
    var size: CGFloat = 28
    /// Kayan blokların rengi (yüksek kontrast).
    var tint: Color
    /// Taban çizgilerinin rengi (sessiz).
    var dim: Color

    private static let lineCount = 11
    /// (satır, genişlik×, tur/sn, faz, opaklık) — sabit tablo, rastgelelik yok.
    private static let blocks: [(line: Int, width: Double, speed: Double, phase: Double, alpha: Double)] = [
        (2,  0.30, 0.42, 0.00, 1.00),
        (4,  0.17, 0.66, 0.55, 0.72),
        (6,  0.44, 0.33, 0.21, 0.90),
        (8,  0.22, 0.55, 0.78, 0.62),
        (10, 0.34, 0.47, 0.37, 0.85),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, canvas in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let step = canvas.height / CGFloat(Self.lineCount + 1)
                let thickness = max(1, canvas.height / 26)

                // Taban: tam genişlik çizgiler — dairesel maske uçlarını kısaltır.
                for i in 1...Self.lineCount {
                    let y = step * CGFloat(i)
                    ctx.fill(
                        Path(CGRect(x: 0, y: y - thickness / 2, width: canvas.width, height: thickness)),
                        with: .color(dim)
                    )
                }

                // Kayan bloklar: soldan girer, sağdan çıkar, sarmalanır.
                let barHeight = thickness * 1.5
                for b in Self.blocks {
                    let w = canvas.width * CGFloat(b.width)
                    let span = canvas.width + w
                    let progress = (t * b.speed + b.phase).truncatingRemainder(dividingBy: 1)
                    let x = CGFloat(progress) * span - w
                    let y = step * CGFloat(b.line)
                    ctx.fill(
                        Path(
                            roundedRect: CGRect(x: x, y: y - barHeight / 2, width: w, height: barHeight),
                            cornerRadius: barHeight / 2
                        ),
                        with: .color(tint.opacity(b.alpha))
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // anlamı yandaki etiket taşır
    }
}
