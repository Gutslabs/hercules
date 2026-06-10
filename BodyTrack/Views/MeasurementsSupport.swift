import SwiftUI
import SwiftData

// MARK: - Shared (also used by MeasurementEditor)

struct MeasurementActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var prominent: Bool
    var compact: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 7 : 9) {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(prominent ? Palette.background.opacity(0.16) : Palette.fieldFill)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(compact ? Typography.captionBold : Typography.bodyBold)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if !compact {
                        Text(subtitle)
                            .font(Typography.caption)
                            .opacity(0.62)
                    }
                }
            }
            .foregroundStyle(prominent ? Palette.background.opacity(0.92) : Palette.textPrimary)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(height: compact ? 34 : 46)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(prominent ? Palette.accent : Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(prominent ? Palette.borderStrong : Palette.borderStrong, lineWidth: 0.5)
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

// MARK: - V1 "Tek Akış" building blocks

/// Weekly rhythm rail — thin uniform bars; today highlighted, the full-check-in
/// weekday (Saturday) accented.
struct RhythmWeekStrip: View {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEE"
        return f
    }()

    private var days: [Date] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? cal.startOfDay(for: .now)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                let isFull = Calendar.current.component(.weekday, from: day) == MeasurementCadence.fullCheckInWeekday
                VStack(spacing: 5) {
                    Text(Self.dayFormatter.string(from: day))
                        .font(.system(size: 10, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Palette.textPrimary : Palette.textQuaternary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isFull ? Palette.accent : (isToday ? Palette.textTertiary : Palette.track))
                        .frame(height: 5)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Yağ / Bel mini card — readout on the left, wide sparkline on the right.
struct MeasureMiniCard: View {
    let name: String
    let value: String
    let unit: String
    let delta: Double?
    let lowerIsBetter: Bool
    let points: [TrendPoint]
    let tint: Color

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name).eyebrow()
                    DeltaBadge(delta: delta, lowerIsBetter: lowerIsBetter)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 27, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            .frame(minWidth: 130, alignment: .leading)

            Sparkline(points: points, accent: tint)
                .frame(height: 54)
                .opacity(points.count >= 2 ? 0.9 : 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .dashboardCard()
    }
}

struct MeasurementHistoryMetric: Identifiable {
    let label: String
    let value: String
    let unit: String
    let tint: Color

    var id: String { label }
}

/// One row of the record ledger. Daily weigh-ins read quietly; full check-ins
/// get a tinted, rounded background and spell out fat/lean/waist/chest/neck.
struct MeasurementTableRow: View {
    let measurement: Measurement
    var isLatest: Bool = false
    var compact: Bool = false
    var topDivider: Bool = false
    var onEdit: () -> Void
    @State private var hovering = false

    private var isFull: Bool { measurement.isFullCheckIn }

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
        VStack(alignment: .leading, spacing: 0) {
            if topDivider { Hairline() }
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isFull ? Palette.accent.opacity(0.05) : (hovering ? Palette.fieldFill : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isFull ? Palette.accent.opacity(0.16) : .clear, lineWidth: 0.6)
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)
                .onHover { hovering = $0 }
        }
    }

    @ViewBuilder
    private var content: some View {
        if compact {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    dateCol
                    Spacer(minLength: 8)
                    weightCol
                    editButton
                }
                HStack(alignment: .top, spacing: 14) {
                    typeCol
                    if !metrics.isEmpty { measuresGrid }
                }
            }
        } else {
            HStack(alignment: .center, spacing: 18) {
                dateCol.frame(width: 230, alignment: .leading)
                typeCol.frame(width: 130, alignment: .leading)
                weightCol.frame(width: 150, alignment: .leading)
                if metrics.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    measuresGrid.frame(maxWidth: .infinity, alignment: .leading)
                }
                editButton.frame(width: 34)
            }
        }
    }

    private var dateCol: some View {
        HStack(alignment: .center, spacing: 9) {
            Circle()
                .fill(isLatest ? Palette.positive : Color.clear)
                .frame(width: 5, height: 5)
            Text(Fmt.dateLong.string(from: measurement.date))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(Fmt.timeShort.string(from: measurement.date))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.textQuaternary)
        }
    }

    private var typeCol: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isFull {
                Text("Tam ölçüm")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.accent)
                Text("Haftalık check-in")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Palette.accent.opacity(0.7))
            } else {
                Text("Tartı")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var weightCol: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Fmt.numOpt(measurement.weight, digits: 1))
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(measurement.weight == nil ? Palette.textQuaternary : Palette.textPrimary)
            Text("kg")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Palette.textQuaternary)
        }
    }

    private var measuresGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 14)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(metrics) { m in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(m.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.textQuaternary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(m.value)
                            .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Text(m.unit)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Palette.textQuaternary)
                    }
                    .fixedSize()
                }
            }
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Palette.textSecondary : Palette.textQuaternary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovering ? Palette.fieldFill : Color.clear))
        }
        .buttonStyle(.plain)
        .help("Ölçümü düzenle")
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
        .dashboardCard()
    }
}
