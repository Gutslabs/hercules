import SwiftUI

struct MetricTile: View {
    let label: String
    let value: String
    let unit: String
    var delta: Double? = nil
    var lowerIsBetter: Bool = false
    var sparkline: [TrendPoint] = []
    var accent: Color = Palette.accent

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
                    }
                    .foregroundStyle(deltaColor)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.hero(34))
                    .foregroundStyle(Palette.textPrimary)
                Text(unit)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
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
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
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
        }
    }
}
