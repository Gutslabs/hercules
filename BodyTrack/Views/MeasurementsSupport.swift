import SwiftUI
import SwiftData

struct SummaryStat: View {
    let label: String
    let value: String
    var detail: String? = nil
    var systemImage: String = "chart.bar"

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(label).eyebrow()
                Text(value)
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .measurementPanel(cornerRadius: Radius.md, fill: Palette.surface.opacity(0.72))
    }
}

struct MeasurementActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var prominent: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(prominent ? Palette.background.opacity(0.16) : Color.white.opacity(0.055))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.bodyBold)
                    Text(subtitle)
                        .font(Typography.caption)
                        .opacity(0.62)
                }
            }
            .foregroundStyle(prominent ? Palette.background.opacity(0.92) : Palette.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(prominent ? Palette.accent : Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(prominent ? Color.white.opacity(0.18) : Palette.borderStrong, lineWidth: 0.5)
            )
            .scaleEffect(hovering ? 1.012 : 1)
        }
        .buttonStyle(MeasurementPressButtonStyle())
        .onHover { isHovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                hovering = isHovering
            }
        }
    }
}

struct MeasurementPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct BreathingStatusDot: View {
    let color: Color
    @State private var active = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(active ? 0.22 : 0.08))
                .frame(width: 22, height: 22)
                .scaleEffect(active ? 1.08 : 0.82)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.65).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

struct MetricChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow()
            Text(value)
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

struct WeekCadenceRail: View {
    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                WeekDayMark(date: day)
            }
        }
    }
}

struct WeekDayMark: View {
    let date: Date

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEE"
        return f
    }()

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var isFullDay: Bool {
        Calendar.current.component(.weekday, from: date) == MeasurementCadence.fullCheckInWeekday
    }

    var body: some View {
        VStack(spacing: 7) {
            Text(Self.formatter.string(from: date))
                .font(Typography.captionBold)
                .foregroundStyle(isToday ? Palette.textPrimary : Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Capsule(style: .continuous)
                .fill(isFullDay ? Palette.accent : (isToday ? Palette.textSecondary : Palette.borderStrong))
                .frame(height: isFullDay || isToday ? 16 : 8)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isToday ? Color.white.opacity(0.22) : Color.clear, lineWidth: 0.5)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

struct MeasurementDeltaPill: View {
    let delta: Double?
    var lowerIsBetter: Bool
    var unit: String

    private var tint: Color {
        guard let delta else { return Palette.textTertiary }
        let increased = delta > 0
        let isGood = lowerIsBetter ? !increased : increased
        return isGood ? Palette.positive : Palette.negative
    }

    private var text: String {
        guard let delta else { return "tek veri" }
        if abs(delta) < 0.005 { return "sabit" }
        return "\(Fmt.signed(delta, digits: 1)) \(unit)"
    }

    var body: some View {
        Text(text)
            .font(Typography.captionBold)
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

struct MetricBrief: View {
    let title: String
    let value: String
    let unit: String
    let delta: Double?
    var lowerIsBetter: Bool
    let points: [TrendPoint]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).eyebrow()
                Spacer(minLength: 8)
                MeasurementDeltaPill(delta: delta, lowerIsBetter: lowerIsBetter, unit: unit)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.hero(26))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 4)
            }

            Sparkline(points: points, accent: tint)
                .frame(height: 24)
                .opacity(points.count >= 2 ? 1 : 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)
        }
    }
}

struct MeasurementChartBackdrop: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                Rectangle()
                    .fill(Palette.chartGrid)
                    .frame(height: 0.5)
                Spacer(minLength: 0)
            }
            Rectangle()
                .fill(Palette.chartGrid)
                .frame(height: 0.5)
        }
    }
}

struct MeasurementPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var fill: Color
    var accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(accent, lineWidth: 0.6)
            )
            .shadow(color: Palette.background.opacity(0.28), radius: 28, x: 0, y: 18)
    }
}

extension View {
    func measurementPanel(
        cornerRadius: CGFloat = Radius.lg,
        fill: Color = Palette.surface,
        accent: Color = Palette.border
    ) -> some View {
        modifier(MeasurementPanelModifier(cornerRadius: cornerRadius, fill: fill, accent: accent))
    }
}

struct MeasurementTypeBadge: View {
    let isFull: Bool

    var body: some View {
        Label(isFull ? "Tam ölçüm" : "Tartı", systemImage: isFull ? "ruler" : "scalemass")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isFull ? Palette.accent : Palette.textTertiary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill((isFull ? Palette.accent : Color.white).opacity(isFull ? 0.14 : 0.07))
            )
    }
}

struct MeasurementHistoryCard: View {
    let measurement: Measurement
    let isLatest: Bool
    var onEdit: () -> Void
    @State private var hovering = false

    private var accent: Color {
        measurement.isFullCheckIn ? Palette.accent : Palette.textSecondary
    }

    private var isFull: Bool {
        measurement.isFullCheckIn
    }

    private var metrics: [MeasurementHistoryMetric] {
        [
            measurement.bodyFat.map { MeasurementHistoryMetric(label: "Yağ", value: Fmt.num($0, digits: 1), unit: "%", tint: Palette.warning) },
            measurement.leanMass.map { MeasurementHistoryMetric(label: "Yağsız", value: Fmt.num($0, digits: 1), unit: "kg", tint: Palette.positive) },
            measurement.waist.map { MeasurementHistoryMetric(label: "Bel", value: Fmt.num($0, digits: 1), unit: "cm", tint: Palette.accent) },
            measurement.chest.map { MeasurementHistoryMetric(label: "Göğüs", value: Fmt.num($0, digits: 1), unit: "cm", tint: Palette.textSecondary) },
            measurement.neck.map { MeasurementHistoryMetric(label: "Boyun", value: Fmt.num($0, digits: 1), unit: "cm", tint: Palette.textSecondary) }
        ].compactMap { $0 }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                dateBlock
                    .frame(width: 178, alignment: .leading)
                weightBlock
                    .frame(width: 150, alignment: .leading)
                metricsBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                editButton
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    dateBlock
                    Spacer(minLength: Spacing.md)
                    editButton
                }
                HStack(alignment: .top, spacing: Spacing.lg) {
                    weightBlock
                    metricsBlock
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, isFull ? Spacing.lg : Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(
                    isFull
                        ? Palette.surfaceElevated.opacity(hovering ? 0.88 : 0.76)
                        : (hovering ? Palette.surfaceElevated.opacity(0.72) : Palette.surface.opacity(0.58))
                )
        )
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(isFull ? Palette.accent.opacity(0.075) : Color.clear)
                .blur(radius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isFull ? Palette.accent.opacity(hovering ? 0.44 : 0.30) : (hovering ? Palette.borderStrong : Palette.border), lineWidth: isFull ? 0.9 : 0.6)
        )
        .overlay(alignment: .top) {
            if isFull {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.045), lineWidth: 1)
                    .blendMode(.plusLighter)
            }
        }
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(accent.opacity(isFull ? 1 : 0.48))
                .frame(width: isFull ? 5 : 3)
                .padding(.vertical, isFull ? 11 : 14)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture(perform: onEdit)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
    }

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(Fmt.dateLong.string(from: measurement.date))
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                if isLatest {
                    Circle()
                        .fill(Palette.positive)
                        .frame(width: 6, height: 6)
                }
            }
            HStack(spacing: 6) {
                Text(Fmt.timeShort.string(from: measurement.date))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                MeasurementTypeBadge(isFull: measurement.isFullCheckIn)
            }
            if isFull {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Haftalık check-in")
                        .font(Typography.captionBold)
                }
                .foregroundStyle(Palette.accent)
            }
        }
    }

    private var weightBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Ağırlık").eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(Fmt.numOpt(measurement.weight, digits: 1))
                    .font(Typography.hero(28))
                    .foregroundStyle(measurement.weight == nil ? Palette.textQuaternary : Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("kg")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 4)
                    .opacity(measurement.weight == nil ? 0 : 1)
            }
        }
    }

    @ViewBuilder
    private var metricsBlock: some View {
        if metrics.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "scalemass")
                    .font(.system(size: 11, weight: .semibold))
                Text("Günlük tartı kaydı")
                    .font(Typography.captionBold)
            }
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: Spacing.sm)],
                alignment: .leading,
                spacing: Spacing.sm
            ) {
                ForEach(metrics) { metric in
                    MeasurementHistoryMetricChip(metric: metric, highlighted: isFull)
                }
            }
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isFull ? Palette.background.opacity(0.92) : (hovering ? Palette.textPrimary : Palette.textTertiary))
                .frame(width: isFull ? 34 : 30, height: isFull ? 34 : 30)
                .background(Circle().fill(isFull ? Palette.accent : Color.white.opacity(hovering ? 0.075 : 0.045)))
                .overlay(Circle().strokeBorder(isFull ? Color.white.opacity(0.18) : Palette.border, lineWidth: 0.5))
        }
        .buttonStyle(MeasurementPressButtonStyle())
        .help("Ölçümü düzenle")
    }
}

struct MeasurementHistoryMetric: Identifiable {
    let label: String
    let value: String
    let unit: String
    let tint: Color

    var id: String { label }
}

struct MeasurementHistoryMetricChip: View {
    let metric: MeasurementHistoryMetric
    var highlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(metric.tint)
                    .frame(width: 5, height: 5)
                Text(metric.label.uppercased())
                    .font(Typography.label)
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(metric.value)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(metric.unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(highlighted ? Color.white.opacity(0.070) : Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(highlighted ? metric.tint.opacity(0.18) : Color.clear, lineWidth: 0.6)
        )
    }
}

struct EmptyMeasurementState: View {
    var quickAction: () -> Void
    var fullAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xxl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(Palette.accent.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "ruler")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Henüz ölçüm yok")
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                    Text("İlk kayıtla trend çizgisi ve haftalık tam ölçüm ritmi burada görünür.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420, alignment: .leading)
                }
            }

            Spacer(minLength: Spacing.lg)

            VStack(alignment: .trailing, spacing: Spacing.sm) {
                MeasurementActionButton(
                    title: "Tartı Ekle",
                    subtitle: "Başlangıç",
                    systemImage: "scalemass",
                    prominent: false,
                    action: quickAction
                )
                MeasurementActionButton(
                    title: "Tam Ölçüm",
                    subtitle: "Detaylı kayıt",
                    systemImage: "ruler",
                    prominent: true,
                    action: fullAction
                )
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
        .measurementPanel(cornerRadius: Radius.xl)
    }
}
