import SwiftUI
import LucideKit
import Charts

private struct SelectionCallout: View {
    let point: TrendPoint
    let unit: String
    let accent: Color

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(Self.dateFormatter.string(from: point.date))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(Fmt.num(point.value))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.5), accent.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: accent.opacity(0.2), radius: 12, x: 0, y: 6)
    }
}

/// Weight-flow sparkline that leads with a trailing N-day moving average
/// (bold) drawn over the raw series (faint), on one shared y-domain. The
/// daily noise stays visible as the thin line, but the eye follows the
/// smoothed trend — so a single heavy/light day doesn't "break the balance".
struct SmoothedSparkline: View {
    let raw: [TrendPoint]
    var windowDays: Double = 7
    var accent: Color = Palette.chart
    var unit: String = ""
    @State private var hoverX: CGFloat? = nil

    var body: some View {
        // Geometriden bağımsız işler (sıralama + hareketli ortalama + min/max)
        // GeometryReader dışında — yalnızca girdiler değişince hesaplanır,
        // her layout/resize karesinde değil.
        let sorted = raw.sorted { $0.date < $1.date }
        let smooth = TrendAnalysis.movingAverage(sorted, windowDays: windowDays)
        let values = sorted.map(\.value) + smooth.map(\.value)
        let bounds: (mn: Double, mx: Double)? = values.isEmpty
            ? nil
            : (values.min()!, values.max()!)
        return GeometryReader { geo in
            if sorted.count >= 2, let bounds {
                let mn = bounds.mn
                let mx = bounds.mx
                let range = max(0.001, mx - mn)
                let w = geo.size.width
                let h = geo.size.height
                let inset: CGFloat = 5
                let plotH = max(1, h - inset * 2)
                let stepX = w / CGFloat(max(1, sorted.count - 1))

                // Smoothed area fill (down to the baseline)
                sparkPath(smooth, stepX: stepX, mn: mn, range: range, inset: inset, plotH: plotH, closeAt: h, w: w)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.16), accent.opacity(0.02), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                // Raw line — faint, the daily noise
                sparkPath(sorted, stepX: stepX, mn: mn, range: range, inset: inset, plotH: plotH)
                    .stroke(accent.opacity(0.24), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

                // Smoothed line — bold, the trend the user should read
                sparkPath(smooth, stepX: stepX, mn: mn, range: range, inset: inset, plotH: plotH)
                    .stroke(
                        LinearGradient(colors: [accent.opacity(0.7), accent], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                // End dot on the smoothed series — hidden while scrubbing.
                if hoverX == nil, let last = smooth.last {
                    let norm = (last.value - mn) / range
                    let y = inset + (1 - CGFloat(norm)) * plotH
                    ZStack {
                        Circle().fill(accent.opacity(0.25)).frame(width: 11, height: 11)
                        Circle().fill(accent).frame(width: 5.5, height: 5.5)
                    }
                    .position(x: w, y: y)
                }

                // ── Hover scrub — crosshair + highlighted raw weigh-in + callout ──
                if let hx = hoverX {
                    let i = min(max(0, Int((hx / stepX).rounded())), sorted.count - 1)
                    let p = sorted[i]
                    let px = CGFloat(i) * stepX
                    let py = inset + (1 - CGFloat((p.value - mn) / range)) * plotH

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.5), accent.opacity(0.08), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 1, height: h)
                        .position(x: px, y: h / 2)

                    ZStack {
                        Circle().fill(accent.opacity(0.2)).frame(width: 22, height: 22)
                        Circle().fill(accent.opacity(0.45)).frame(width: 12, height: 12)
                        Circle().fill(.white).frame(width: 6, height: 6)
                    }
                    .position(x: px, y: py)

                    SelectionCallout(point: p, unit: unit, accent: accent)
                        .fixedSize()
                        .position(x: min(max(px, 54), w - 54), y: max(20, py - 30))
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hoverX = location.x
            case .ended: hoverX = nil
            }
        }
    }

    private func sparkPath(
        _ pts: [TrendPoint], stepX: CGFloat, mn: Double, range: Double,
        inset: CGFloat, plotH: CGFloat, closeAt: CGFloat? = nil, w: CGFloat = 0
    ) -> Path {
        Path { path in
            for (i, p) in pts.enumerated() {
                let x = CGFloat(i) * stepX
                let norm = (p.value - mn) / range
                let y = inset + (1 - CGFloat(norm)) * plotH
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            if let closeAt {
                path.addLine(to: CGPoint(x: w, y: closeAt))
                path.addLine(to: CGPoint(x: 0, y: closeAt))
                path.closeSubpath()
            }
        }
    }
}

/// Tiny line-swatch + label, used to explain which line is which under a
/// smoothed sparkline (bold = moving average, faint = raw weigh-ins).
struct TrendLegendMark: View {
    let label: String
    let color: Color
    var bold: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(color)
                .frame(width: bold ? 16 : 12, height: bold ? 2.4 : 1.4)
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

struct Sparkline: View {
    let points: [TrendPoint]
    var accent: Color = Palette.chart
    var lowerIsBetter: Bool = false
    var body: some View {
        GeometryReader { geo in
            if points.count >= 2 {
                let values = points.map(\.value)
                let mn = values.min() ?? 0
                let mx = values.max() ?? 1
                let range = max(0.001, mx - mn)
                let w = geo.size.width
                let h = geo.size.height
                let stepX = w / CGFloat(max(1, points.count - 1))

                // Gradient fill under sparkline
                Path { path in
                    for (i, p) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let normalized = (p.value - mn) / range
                        let y = h - CGFloat(normalized) * h
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.18), accent.opacity(0.02), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line
                Path { path in
                    for (i, p) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let normalized = (p.value - mn) / range
                        let y = h - CGFloat(normalized) * h
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.6), accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )

                // End dot with glow
                if let last = points.last {
                    let normalized = (last.value - mn) / range
                    let y = h - CGFloat(normalized) * h
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.25))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(accent)
                            .frame(width: 5, height: 5)
                    }
                    .position(x: w, y: y)
                }
            }
        }
    }
}

/// A `Sparkline` with the resting look untouched, plus a hover crosshair +
/// per-point callout (`SelectionCallout`). On macOS the callout follows the cursor and snaps to the
/// nearest data point; when not hovering it renders exactly like `Sparkline`.
struct InteractiveSparkline: View {
    let points: [TrendPoint]
    var accent: Color = Palette.chart
    var unit: String = ""
    @State private var hoverX: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if points.count >= 2, w > 0, h > 0 {
                let values = points.map(\.value)
                let mn = values.min() ?? 0
                let mx = values.max() ?? 1
                let range = max(0.001, mx - mn)
                let stepX = w / CGFloat(points.count - 1)
                let selIndex: Int? = hoverX.map { hx in
                    min(max(0, Int((hx / stepX).rounded())), points.count - 1)
                }

                ZStack(alignment: .topLeading) {
                    // ── Resting drawing — identical to `Sparkline` ──
                    Path { path in
                        for (i, p) in points.enumerated() {
                            let pt = CGPoint(x: CGFloat(i) * stepX, y: h - CGFloat((p.value - mn) / range) * h)
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.addLine(to: CGPoint(x: 0, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.18), accent.opacity(0.02), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        for (i, p) in points.enumerated() {
                            let pt = CGPoint(x: CGFloat(i) * stepX, y: h - CGFloat((p.value - mn) / range) * h)
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(
                        LinearGradient(colors: [accent.opacity(0.6), accent], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )

                    // End dot — hidden while hovering so we don't show two markers.
                    if selIndex == nil, let last = points.last {
                        ZStack {
                            Circle().fill(accent.opacity(0.25)).frame(width: 10, height: 10)
                            Circle().fill(accent).frame(width: 5, height: 5)
                        }
                        .position(x: w, y: h - CGFloat((last.value - mn) / range) * h)
                    }

                    // ── Hover overlay — crosshair + highlighted point + callout ──
                    if let i = selIndex {
                        let p = points[i]
                        let px = CGFloat(i) * stepX
                        let py = h - CGFloat((p.value - mn) / range) * h

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.5), accent.opacity(0.08), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1, height: h)
                            .position(x: px, y: h / 2)

                        ZStack {
                            Circle().fill(accent.opacity(0.2)).frame(width: 22, height: 22)
                            Circle().fill(accent.opacity(0.45)).frame(width: 12, height: 12)
                            Circle().fill(.white).frame(width: 6, height: 6)
                        }
                        .position(x: px, y: py)

                        SelectionCallout(point: p, unit: unit, accent: accent)
                            .fixedSize()
                            .position(x: min(max(px, 54), w - 54), y: max(20, py - 30))
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hoverX = location.x
                    case .ended: hoverX = nil
                    }
                }
            }
        }
    }
}
