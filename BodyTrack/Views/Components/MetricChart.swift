import SwiftUI
import Charts

struct TrendChart: View {
    let points: [TrendPoint]
    var goalBand: (start: TrendPoint, end: TrendPoint)? = nil
    var height: CGFloat = 220
    var accent: Color = Palette.accent
    var unit: String = ""

    @State private var selectedDate: Date? = nil

    private var fit: LinearFit? {
        TrendAnalysis.linearFit(points)
    }

    private var yDomain: ClosedRange<Double> {
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

    var body: some View {
        if points.isEmpty {
            EmptyChartState()
                .frame(height: height)
        } else {
            Chart {
                if let band = goalBand {
                    let upper = max(band.start.value, band.end.value) + (yDomain.upperBound - yDomain.lowerBound) * 0.06
                    let lower = min(band.start.value, band.end.value) - (yDomain.upperBound - yDomain.lowerBound) * 0.06

                    AreaMark(
                        x: .value("Date", band.start.date),
                        yStart: .value("Lower", lower),
                        yEnd: .value("Upper", upper)
                    )
                    .foregroundStyle(Palette.chartBand)

                    AreaMark(
                        x: .value("Date", band.end.date),
                        yStart: .value("Lower", lower),
                        yEnd: .value("Upper", upper)
                    )
                    .foregroundStyle(Palette.chartBand)

                    LineMark(
                        x: .value("Date", band.start.date),
                        y: .value("Goal", band.start.value)
                    )
                    .foregroundStyle(Palette.chartBandStrong)
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

                    LineMark(
                        x: .value("Date", band.end.date),
                        y: .value("Goal", band.end.value)
                    )
                    .foregroundStyle(Palette.chartBandStrong)
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }

                if let f = fit,
                   let first = points.first?.date,
                   let last = points.last?.date {
                    // Linear regression + constant stdError => band is a parallelogram.
                    // 2 points per edge is enough; no sampling needed.
                    let yStartFirst = f.value(at: first)
                    let yStartLast = f.value(at: last)

                    AreaMark(
                        x: .value("Date", first),
                        yStart: .value("Lower", yStartFirst - f.stdError),
                        yEnd: .value("Upper", yStartFirst + f.stdError),
                        series: .value("Band", "trend-band")
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    AreaMark(
                        x: .value("Date", last),
                        yStart: .value("Lower", yStartLast - f.stdError),
                        yEnd: .value("Upper", yStartLast + f.stdError),
                        series: .value("Band", "trend-band")
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", first),
                        y: .value("Trend", yStartFirst),
                        series: .value("Line", "trend-line")
                    )
                    .foregroundStyle(Color.white.opacity(0.32))
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))

                    LineMark(
                        x: .value("Date", last),
                        y: .value("Trend", yStartLast),
                        series: .value("Line", "trend-line")
                    )
                    .foregroundStyle(Color.white.opacity(0.32))
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }

                ForEach(points) { p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Value", p.value),
                        series: .value("Line", "data-line")
                    )
                    .foregroundStyle(accent.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                ForEach(points) { p in
                    PointMark(
                        x: .value("Date", p.date),
                        y: .value("Value", p.value)
                    )
                    .foregroundStyle(accent)
                    .symbolSize(selectedPoint?.id == p.id ? 120 : 36)
                }

                if let sel = selectedPoint {
                    RuleMark(x: .value("Date", sel.date))
                        .foregroundStyle(Palette.textTertiary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .annotation(
                            position: .top,
                            alignment: .center,
                            spacing: 8,
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
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                        .foregroundStyle(Palette.chartGrid)
                    AxisValueLabel()
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(height: height)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.dateFormatter.string(from: point.date))
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(Fmt.num(point.value))
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 0.5)
        )
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
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.dots.scatter")
                .font(.system(size: 22))
                .foregroundStyle(Palette.textQuaternary)
            Text("Henüz veri yok")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.white.opacity(0.015))
        )
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

                Path { path in
                    for (i, p) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let normalized = (p.value - mn) / range
                        let y = h - CGFloat(normalized) * h
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    let normalized = (last.value - mn) / range
                    let y = h - CGFloat(normalized) * h
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .position(x: w, y: y)
                }
            }
        }
    }
}
