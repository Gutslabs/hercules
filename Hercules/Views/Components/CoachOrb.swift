import SwiftUI

/// Koç asistanının avatarı — kırık beyaz→gri orb (uygulamanın monokrom sohbet dili).
/// Renkler parametreli.
///
/// Perf: `idle` DONUK tek karedir — `TimelineView` yalnız gerçekten akan durumlarda kurulur.
/// Sohbette onlarca avatar aynı anda görünebiliyor; hepsini sürekli yeniden çizmek kasardı.
enum CoachOrbState { case idle, thinking, talking }

struct CoachOrb: View {
    var colors: [Color] = [
        Color(red: 0.960, green: 0.960, blue: 0.968),
        Color(red: 0.706, green: 0.714, blue: 0.745)
    ]
    var state: CoachOrbState = .idle
    var seed: Double = 0

    private var animated: Bool { if case .idle = state { return false } else { return true } }

    var body: some View {
        if animated {
            TimelineView(.animation) { tl in
                canvas(t: tl.date.timeIntervalSinceReferenceDate + seed)
            }
        } else {
            // Sabit bir "an": her avatar seed'e göre farklı ama kendi içinde durağan görünür.
            canvas(t: 8.37 + seed)
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas { ctx, size in
            Self.render(&ctx, size, t: t, colors: colors, state: state, seed: seed)
        }
    }

    private static func render(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double,
                               colors: [Color], state: CoachOrbState, seed: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let r = min(size.width, size.height) / 2
        let cx = size.width / 2, cy = size.height / 2
        let c0 = colors.first ?? .white
        let c1 = colors.last ?? c0

        ctx.clip(to: Path(ellipseIn: rect))

        let energy: Double, speed: Double
        switch state {
        case .idle:     energy = 0.32; speed = 0.0
        case .thinking: energy = 0.95; speed = 1.7
        case .talking:  energy = 0.60; speed = 1.2
        }
        let tt = t * speed

        ctx.fill(Path(ellipseIn: rect), with: .linearGradient(
            Gradient(colors: [c0, c1]),
            startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))

        ctx.blendMode = .plusLighter
        for i in 0..<3 {
            let ph = tt + Double(i) * 2.1 + seed
            let orbit = r * (0.30 + 0.18 * energy)
            let bx = cx + CGFloat(cos(ph * 0.9 + Double(i))) * orbit
            let by = cy + CGFloat(sin(ph * 1.1 + Double(i) * 1.7)) * orbit
            let br = r * (0.65 + 0.30 * (0.5 + 0.5 * sin(ph * 0.7)))
            let c = colors[i % max(colors.count, 1)]
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [c.opacity(0.30 + 0.40 * energy), .clear]),
                center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: br))
        }

        // Sol-üstten gelen ışık: küreye hacim veren şey bu.
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.40), .clear]),
            center: CGPoint(x: cx - r * 0.35, y: cy - r * 0.45), startRadius: 0, endRadius: r * 0.95))

        ctx.blendMode = .multiply
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.06, dy: r * 0.06)),
                   with: .color(c1.opacity(0.35)), lineWidth: max(r * 0.14, 0.5))
    }
}
