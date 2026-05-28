import SwiftUI
import Charts

struct TrendChart: View {
    let points: [TrendPoint]
    var goalBand: (start: TrendPoint, end: TrendPoint)? = nil
    var height: CGFloat = 220
    var accent: Color = Palette.accent
    var unit: String = ""

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
                .frame(height: height)
        } else {
            let fit = TrendAnalysis.linearFit(points)
            let domain = yDomain(for: fit)
            chartBody(fit: fit, yDomain: domain)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .frame(height: height)
        }
    }

    private func chartBody(fit: LinearFit?, yDomain: ClosedRange<Double>) -> some View {
        Chart {
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
                .foregroundStyle(Palette.accent.opacity(0.06))

                AreaMark(
                    x: .value("Date", band.end.date),
                    yStart: .value("Lower", lower),
                    yEnd: .value("Upper", upper)
                )
                .foregroundStyle(Palette.accent.opacity(0.06))

                // Goal line (dashed)
                LineMark(
                    x: .value("Date", band.start.date),
                    y: .value("Goal", band.start.value),
                    series: .value("Line", "goal-line")
                )
                .foregroundStyle(Palette.accent.opacity(0.28))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                LineMark(
                    x: .value("Date", band.end.date),
                    y: .value("Goal", band.end.value),
                    series: .value("Line", "goal-line")
                )
                .foregroundStyle(Palette.accent.opacity(0.28))
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
                .foregroundStyle(Color.white.opacity(0.18))
                .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round, dash: [6, 4]))

                LineMark(
                    x: .value("Date", last),
                    y: .value("Trend", yLast),
                    series: .value("Line", "trend-line")
                )
                .foregroundStyle(Color.white.opacity(0.18))
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
                let isSelected = selectedPoint?.id == p.id
                PointMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.value)
                )
                .foregroundStyle(isSelected ? .white : accent)
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
            if let sel = selectedPoint {
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
                    .foregroundStyle(Color.white.opacity(0.04))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                    .foregroundStyle(Color.white.opacity(0.04))
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
                .border(Color.white.opacity(0.03), width: 0.5)
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
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
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
    var accent: Color = Palette.accent

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
                    .fill(Palette.accent.opacity(0.06))
                    .frame(width: 56, height: 56)
                    .scaleEffect(animating ? 1.15 : 0.85)
                    .opacity(animating ? 0.3 : 0.8)
                Image(systemName: "chart.dots.scatter")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.textQuaternary)
            }
            Text("Henüz veri yok")
                .font(.system(size: 12, weight: .medium, design: .rounded))
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

struct Sparkline: View {
    let points: [TrendPoint]
    var accent: Color = Palette.accent
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
