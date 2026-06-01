import SwiftUI
import SwiftData

struct MetricSeriesSnapshot {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?
}

struct FocusChartPanel: View {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?
    let compact: Bool
    var chartHeight: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        BreathingDot(color: points.isEmpty ? Palette.textQuaternary : Palette.accent, size: 6)
                        Text(points.isEmpty ? "veri bekliyor" : "\(points.count) nokta")
                            .font(Typography.captionBold)
                            .foregroundStyle(points.isEmpty ? Palette.textTertiary : Palette.accent)
                    }

                    Text(kind.label)
                        .font(Typography.display(compact ? 32 : 38))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Güncel").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(Fmt.numOpt(stats.current))
                            .font(Typography.hero(compact ? 28 : 34))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Text(kind.unit)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            TrendChart(points: points, goalBand: goalBand, height: resolvedChartHeight, accent: Palette.accent, unit: kind.unit)
                .padding(.top, 2)

        ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    FocusMetric(label: "Haftalık", value: stats.weeklyChange.map { Fmt.signed($0, digits: 2) } ?? "—", unit: "\(kind.unit)/hafta", tint: weeklyTint)
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1, height: 32)
                        .padding(.horizontal, Spacing.md)
                    FocusMetric(label: "Aralık", value: rangeText, unit: kind.unit, tint: Palette.textSecondary)
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1, height: 32)
                        .padding(.horizontal, Spacing.md)
                    FocusMetric(label: "Ortalama", value: Fmt.numOpt(stats.average), unit: kind.unit, tint: Palette.textSecondary)
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    FocusMetric(label: "Haftalık", value: stats.weeklyChange.map { Fmt.signed($0, digits: 2) } ?? "—", unit: "\(kind.unit)/hafta", tint: weeklyTint)
                    FocusMetric(label: "Aralık", value: rangeText, unit: kind.unit, tint: Palette.textSecondary)
                    FocusMetric(label: "Ortalama", value: Fmt.numOpt(stats.average), unit: kind.unit, tint: Palette.textSecondary)
                }
            }
        }
        .padding(compact ? Spacing.lg : Spacing.xl)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Palette.surfaceElevated.opacity(0.98),
                                Palette.surface.opacity(0.94),
                                Palette.surface.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                // Subtle accent tint at top-left corner
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Palette.accent.opacity(0.04), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 400
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        )
        .shadow(color: Palette.accent.opacity(0.06), radius: 48, x: 0, y: 24)
        .shadow(color: Palette.background.opacity(0.35), radius: 36, x: 0, y: 22)
    }

    private var rangeText: String {
        "\(Fmt.numOpt(stats.min)) - \(Fmt.numOpt(stats.max))"
    }

    private var resolvedChartHeight: CGFloat {
        chartHeight ?? (compact ? 270 : 350)
    }

    private var weeklyTint: Color {
        guard let weekly = stats.weeklyChange else { return Palette.textTertiary }
        guard abs(weekly) >= 0.01 else { return Palette.textSecondary }
        let positive = weekly > 0
        let isGood = kind.lowerIsBetter ? !positive : positive
        return isGood ? Palette.positive : Palette.negative
    }
}

struct TrendBriefPanel: View {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.accentSoft)
                        .frame(width: 34, height: 34)
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Okuma").eyebrow()
                    Text(narrative.title)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(narrative.detail)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Hairline()

            VStack(spacing: Spacing.sm) {
                SignalRow(label: "Veri yoğunluğu", value: "\(stats.pointCount) ölçüm", tint: densityTint)
                SignalRow(label: "Son kayıt", value: points.last.map { Fmt.dateLong.string(from: $0.date) } ?? "Yok", tint: Palette.textSecondary)
                SignalRow(label: "Hedef bandı", value: goalBand == nil ? "Kapalı" : "Açık", tint: goalBand == nil ? Palette.textTertiary : Palette.accent)
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var narrative: (title: String, detail: String) {
        guard stats.hasData else {
            return (
                "Bu seri sessiz",
                "\(kind.label) için ölçüm eklenince eğim, aralık ve hedef bandı burada okunur."
            )
        }

        guard stats.pointCount >= 3 else {
            return (
                "İlk izler oluşuyor",
                "\(stats.pointCount) ölçüm var. Güvenilir eğim için birkaç kayıt daha eklendiğinde regresyon bandı anlam kazanır."
            )
        }

        guard let weekly = stats.weeklyChange else {
            return (
                "Tempo nötr",
                "Veri mevcut, fakat haftalık hız için yeterli tarih aralığı oluşmadı."
            )
        }

        if abs(weekly) < 0.03 {
            return (
                "Çizgi dengede",
                "Haftalık değişim \(Fmt.signed(weekly, digits: 2)) \(kind.unit). Seri şu an bakım temposuna yakın."
            )
        }

        let positive = weekly > 0
        let isGood = kind.lowerIsBetter ? !positive : positive
        let direction = positive ? "yukarı" : "aşağı"
        let tone = isGood ? "hedef yönüyle uyumlu" : "hedefle ters yönde"
        return (
            "Eğim \(direction)",
            "\(Fmt.signed(weekly, digits: 2)) \(kind.unit)/hafta; mevcut hareket \(tone)."
        )
    }

    private var densityTint: Color {
        switch stats.pointCount {
        case 0...1: return Palette.textTertiary
        case 2...4: return Palette.warning
        default: return Palette.positive
        }
    }
}

struct MetricSignalButton: View {
    let kind: MetricKind
    let stats: TrendStats
    let icon: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Palette.accent : Palette.textTertiary)
                        .frame(width: 18, height: 18)

                    Text(kind.label)
                        .font(Typography.captionBold)
                        .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 0)
                }

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Fmt.numOpt(stats.current))
                        .font(Typography.monoLarge)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(kind.unit)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }

                Text(deltaLine)
                    .font(Typography.caption)
                    .foregroundStyle(deltaTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? Palette.surfaceElevated : Color.white.opacity(0.018))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent.opacity(0.34) : Palette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressedButtonStyle())
        .help("\(kind.label) serisini ana grafiğe taşı")
    }

    private var deltaLine: String {
        guard let delta = stats.delta else { return "değişim yok" }
        return "\(Fmt.signed(delta, digits: 1)) \(kind.unit) son ölçüm"
    }

    private var deltaTint: Color {
        guard let delta = stats.delta else { return Palette.textTertiary }
        guard abs(delta) >= 0.05 else { return Palette.textSecondary }
        let positive = delta > 0
        let isGood = kind.lowerIsBetter ? !positive : positive
        return isGood ? Palette.positive : Palette.negative
    }
}

struct ChartTile: View {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?
    var isFocused: Bool = false
    var chartHeight: CGFloat = 220
    var onFocus: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        Button(action: onFocus) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(kind.label)
                            .font(Typography.titleSmall)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        HStack(spacing: 7) {
                            BreathingDot(color: points.isEmpty ? Palette.textQuaternary : Palette.accent, size: 5)
                            Text(points.isEmpty ? "veri bekliyor" : "\(points.count) ölçüm")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(Fmt.numOpt(stats.current))
                                .font(Typography.hero(28))
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                            Text(kind.unit)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(1)
                        }

                        Image(systemName: isFocused ? "scope" : "plus.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isFocused ? Palette.accent : Palette.textTertiary)
                            .frame(width: 26, height: 24)
                    }
                }

                statSummary

                TrendChart(points: points, goalBand: goalBand, height: chartHeight, accent: Palette.accent, unit: kind.unit)
            }
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(isFocused ? Palette.surfaceElevated.opacity(0.92) : Palette.surface.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(isFocused ? Palette.accent.opacity(0.38) : Palette.border, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(PressedButtonStyle())
        .shadow(color: Palette.background.opacity(hovering ? 0.28 : 0.18), radius: hovering ? 26 : 14, x: 0, y: hovering ? 18 : 10)
        .scaleEffect(hovering ? 1.006 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: hovering)
        .onHover { hovering = $0 }
    }

    private var statSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ChartMicroStat(label: "Değişim", value: deltaText, unit: kind.unit, tint: deltaColor, detail: weeklyText)
                Divider().background(Palette.border).padding(.horizontal, Spacing.md)
                ChartMicroStat(label: "Aralık", value: rangeText, unit: kind.unit, tint: Palette.textSecondary, detail: "min - max")
                Divider().background(Palette.border).padding(.horizontal, Spacing.md)
                ChartMicroStat(label: "Ortalama", value: Fmt.numOpt(stats.average), unit: kind.unit, tint: Palette.textSecondary, detail: "\(stats.pointCount) ölçüm")
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ChartMicroStat(label: "Değişim", value: deltaText, unit: kind.unit, tint: deltaColor, detail: weeklyText)
                ChartMicroStat(label: "Aralık", value: rangeText, unit: kind.unit, tint: Palette.textSecondary, detail: "min - max")
                ChartMicroStat(label: "Ortalama", value: Fmt.numOpt(stats.average), unit: kind.unit, tint: Palette.textSecondary, detail: "\(stats.pointCount) ölçüm")
            }
        }
    }

    private var deltaText: String {
        guard let delta = stats.delta else { return "—" }
        return Fmt.signed(delta, digits: 1)
    }

    private var rangeText: String {
        "\(Fmt.numOpt(stats.min)) - \(Fmt.numOpt(stats.max))"
    }

    private var weeklyText: String {
        guard let weekly = stats.weeklyChange else { return "haftalık yok" }
        return "\(Fmt.signed(weekly, digits: 2))/hafta"
    }

    private var deltaColor: Color {
        guard let delta = stats.delta else { return Palette.textTertiary }
        guard abs(delta) >= 0.05 else { return Palette.textSecondary }
        let positive = delta > 0
        let isGood = kind.lowerIsBetter ? !positive : positive
        return isGood ? Palette.positive : Palette.negative
    }
}

struct FocusMetric: View {
    let label: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChartMicroStat: View {
    let label: String
    let value: String
    let unit: String
    let tint: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.mono)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SignalRow: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: Spacing.sm)
            Text(value)
                .font(Typography.captionBold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

struct ChartsEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(Palette.surface.opacity(0.78))
                    .frame(height: 280)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Palette.accent)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("İlk çizgi için veri bekleniyor")
                            .font(Typography.title)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Ölçümler sayfasından ağırlık, yağ oranı veya çevre ölçüsü eklediğinde bu ekran otomatik olarak trendleri çizer.")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textSecondary)
                            .lineSpacing(3)
                            .frame(maxWidth: 520, alignment: .leading)
                    }
                }
                .padding(Spacing.xl)
            }
        }
    }
}

struct BreathingDot: View {
    let color: Color
    var size: CGFloat = 6
    @State private var active = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: size * 3.2, height: size * 3.2)
                .scaleEffect(active ? 1.12 : 0.72)
                .opacity(active ? 0.2 : 0.75)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.spring(response: 1.4, dampingFraction: 0.72).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

struct ChartScanLine: View {
    @State private var active = false

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.055), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 42)
                .offset(y: active ? proxy.size.height : -48)
                .opacity(0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 4.2, dampingFraction: 0.96).repeatForever(autoreverses: false)) {
                active = true
            }
        }
    }
}

struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
