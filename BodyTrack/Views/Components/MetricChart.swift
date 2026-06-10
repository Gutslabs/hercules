import SwiftUI
import Charts

struct TrendChart: View {
    let points: [TrendPoint]
    var goalBand: (start: TrendPoint, end: TrendPoint)? = nil
    var height: CGFloat = 220
    var accent: Color = Palette.chart
    var unit: String = ""
    /// When true, the chart grows to fill the available vertical space (min
    /// `height`) instead of locking to a fixed height — lets the card stay snug
    /// (no empty gap above the footer).
    var fills: Bool = false

    @State private var selectedDate: Date? = nil

    private func yDomain(for fit: LinearFit?) -> ClosedRange<Double> {
        var values = points.map(\.value)
        if let g = goalBand { values += [g.start.value, g.end.value] }
        if let f = fit, let first = points.first?.date, let last = points.last?.date {
            values += [f.value(at: first) + f.stdError, f.value(at: first) - f.stdError,
                       f.value(at: last) + f.stdError, f.value(at: last) - f.stdError]
        }
        guard let mn = values.min(), let mx = values.max() else {
            return 0...1
        }
        let pad = max(0.5, (mx - mn) * 0.18)
        return (mn - pad)...(mx + pad)
    }

    private var selectedPoint: TrendPoint? {
        guard let target = selectedDate, !points.isEmpty else { return nil }
        return points.min(by: {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        })
    }

    /// A lighter, brighter version of the accent for gradients.
    private var accentBright: Color {
        accent.opacity(0.92)
    }

    var body: some View {
        if points.isEmpty {
            EmptyChartState()
                .frame(minHeight: fills ? 200 : height, maxHeight: fills ? .infinity : height)
        } else {
            let fit = TrendAnalysis.linearFit(points)
            let domain = yDomain(for: fit)
            chartBody(fit: fit, yDomain: domain)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .frame(minHeight: fills ? 200 : height, maxHeight: fills ? .infinity : height)
        }
    }

    private func chartBody(fit: LinearFit?, yDomain: ClosedRange<Double>) -> some View {
        // Seçili noktayı render başına bir kez hesapla — her PointMark içinde
        // `selectedPoint` çağırmak O(n) tarama olduğundan döngü O(n²) olurdu.
        let sel = selectedPoint
        return Chart {
            // ── Goal band ──
            if let band = goalBand {
                let range = yDomain.upperBound - yDomain.lowerBound
                let upper = max(band.start.value, band.end.value) + range * 0.06
                let lower = min(band.start.value, band.end.value) - range * 0.06

                AreaMark(
                    x: .value("Date", band.start.date),
                    yStart: .value("Lower", lower),
                    yEnd: .value("Upper", upper)
                )
                .foregroundStyle(Palette.chart.opacity(0.06))

                AreaMark(
                    x: .value("Date", band.end.date),
                    yStart: .value("Lower", lower),
                    yEnd: .value("Upper", upper)
                )
                .foregroundStyle(Palette.chart.opacity(0.06))

                // Goal line (dashed)
                LineMark(
                    x: .value("Date", band.start.date),
                    y: .value("Goal", band.start.value),
                    series: .value("Line", "goal-line")
                )
                .foregroundStyle(Palette.chart.opacity(0.28))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                LineMark(
                    x: .value("Date", band.end.date),
                    y: .value("Goal", band.end.value),
                    series: .value("Line", "goal-line")
                )
                .foregroundStyle(Palette.chart.opacity(0.28))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            // ── Regression band ──
            if let f = fit,
               let first = points.first?.date,
               let last = points.last?.date {
                let yFirst = f.value(at: first)
                let yLast = f.value(at: last)

                AreaMark(
                    x: .value("Date", first),
                    yStart: .value("Lower", yFirst - f.stdError),
                    yEnd: .value("Upper", yFirst + f.stdError),
                    series: .value("Band", "trend-band")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.12), accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                AreaMark(
                    x: .value("Date", last),
                    yStart: .value("Lower", yLast - f.stdError),
                    yEnd: .value("Upper", yLast + f.stdError),
                    series: .value("Band", "trend-band")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.12), accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Regression center line
                LineMark(
                    x: .value("Date", first),
                    y: .value("Trend", yFirst),
                    series: .value("Line", "trend-line")
                )
                .foregroundStyle(Palette.textQuaternary)
                .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round, dash: [6, 4]))

                LineMark(
                    x: .value("Date", last),
                    y: .value("Trend", yLast),
                    series: .value("Line", "trend-line")
                )
                .foregroundStyle(Palette.textQuaternary)
                .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round, dash: [6, 4]))
            }

            // ── Gradient fill under the data line ──
            let fillBase = (points.map(\.value).min() ?? 0)
            ForEach(points) { p in
                AreaMark(
                    x: .value("Date", p.date),
                    yStart: .value("Base", fillBase),
                    yEnd: .value("Value", p.value),
                    series: .value("Area", "data-fill")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.18),
                            accent.opacity(0.04),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }


            // ── Main data line ──
            ForEach(points) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.value),
                    series: .value("Line", "data-line")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentBright, accent.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            // ── Data points ──
            ForEach(points) { p in
                let isSelected = sel?.id == p.id
                PointMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.value)
                )
                .foregroundStyle(isSelected ? Palette.btnFg : accent)
                .symbolSize(isSelected ? 80 : 18)
                .symbol {
                    if isSelected {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.2))
                                .frame(width: 22, height: 22)
                            Circle()
                                .fill(accent.opacity(0.45))
                                .frame(width: 12, height: 12)
                            Circle()
                                .fill(.white)
                                .frame(width: 6, height: 6)
                        }
                    } else {
                        Circle()
                            .fill(accent)
                            .frame(width: 4.5, height: 4.5)
                    }
                }
            }

            // ── Selection rule + callout ──
            if let sel {
                RuleMark(x: .value("Date", sel.date))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent.opacity(0.5), accent.opacity(0.08), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        alignment: .center,
                        spacing: 10,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        SelectionCallout(point: sel, unit: unit, accent: accent)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                    .foregroundStyle(Palette.chartGrid)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                    .foregroundStyle(Palette.chartGrid)
                AxisValueLabel()
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .chartPlotStyle { area in
            area
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.012), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .border(Palette.chartGrid, width: 0.5)
        }
    }
}

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

struct MetricChart: View {
    let title: String
    let unit: String
    let points: [TrendPoint]
    var goalBand: (start: TrendPoint, end: TrendPoint)? = nil
    var height: CGFloat = 220
    var accent: Color = Palette.chart

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            TrendChart(points: points, goalBand: goalBand, height: height, accent: accent, unit: unit)
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

private struct EmptyChartState: View {
    @State private var animating = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Palette.chart.opacity(0.06))
                    .frame(width: 56, height: 56)
                    .scaleEffect(animating ? 1.15 : 0.85)
                    .opacity(animating ? 0.3 : 0.8)
                Image(systemName: "chart.dots.scatter")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.textQuaternary)
            }
            Text("Henüz veri yok")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.012))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
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

/// Compact trailing-average ("trend") readout across several day windows.
/// Each value averages every sample within that many days of the latest
/// reading, so day-to-day swings can't distort the number. The shortest
/// window leads (accent dot) as the primary trend reading.
struct MovingAverageStrip: View {
    let points: [TrendPoint]
    var unit: String = "kg"
    var windows: [Int] = [7, 14, 30]
    var accent: Color = Palette.chart

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(windows.enumerated()), id: \.element) { idx, days in
                if idx > 0 {
                    Capsule()
                        .fill(Palette.track)
                        .frame(width: 1, height: 30)
                        .padding(.horizontal, Spacing.md)
                }
                segment(days: days, isLead: idx == 0)
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func segment(days: Int, isLead: Bool) -> some View {
        let value = TrendAnalysis.movingAverageNow(points, windowDays: Double(days))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if isLead {
                    Circle().fill(accent).frame(width: 5, height: 5)
                }
                Text("\(days) GÜN ORT").eyebrow()
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value.map { Fmt.num($0, digits: 1) } ?? "—")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(isLead ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
/// per-point callout (reuses `SelectionCallout`, the same callout the full
/// `TrendChart` uses). On macOS the callout follows the cursor and snaps to the
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
