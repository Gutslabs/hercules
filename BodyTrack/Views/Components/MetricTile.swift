import SwiftUI

struct MetricTile: View {
    let label: String
    let value: String
    let unit: String
    var delta: Double? = nil
    var lowerIsBetter: Bool = false
    var sparkline: [TrendPoint] = []
    var accent: Color = Palette.accent
    @State private var hovering = false

    private var deltaColor: Color {
        guard let d = delta else { return Palette.textTertiary }
        let positiveChange = d > 0
        let isGood = lowerIsBetter ? !positiveChange : positiveChange
        return isGood ? Palette.positive : Palette.negative
    }

    private var deltaSymbol: String {
        guard let d = delta else { return "—" }
        if d > 0 { return "▲" }
        if d < 0 { return "▼" }
        return "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(label).eyebrow()
                Spacer()
                if let d = delta {
                    HStack(spacing: 3) {
                        Text(deltaSymbol)
                            .font(.system(size: 8, weight: .bold))
                        Text(Fmt.num(abs(d), digits: 1))
                            .font(Typography.captionBold)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .foregroundStyle(deltaColor)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.hero(34))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .padding(.bottom, 4)
            }

            Sparkline(points: sparkline, accent: accent)
                .frame(height: 28)
                .opacity(sparkline.count >= 2 ? 1 : 0)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(hovering ? accent.opacity(0.34) : Palette.border, lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(accent.opacity(hovering ? 0.72 : 0.42))
                .frame(width: 42, height: 1)
                .padding(.leading, Spacing.lg)
        }
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var hint: String? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                if let hint {
                    Text(hint)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer()
            Text(value)
                .font(Typography.bodyBold)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
