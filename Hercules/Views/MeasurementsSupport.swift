import SwiftUI
import LucideKit
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
                Lucide(sf: systemImage, size: compact ? 11 : 12)
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(prominent ? Palette.btnFg.opacity(0.12) : Palette.fieldFill)
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
            .foregroundStyle(prominent ? Palette.btnFg : Palette.textPrimary)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(height: compact ? 34 : 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? Palette.btnBg : Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Palette.border.opacity(0.7), lineWidth: 1)
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
                    .strokeBorder(accent, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func measurementPanel(
        cornerRadius: CGFloat = Radius.md,
        fill: Color = Palette.surface,
        accent: Color = Palette.border.opacity(0.7)
    ) -> some View {
        modifier(MeasurementPanelModifier(cornerRadius: cornerRadius, fill: fill, accent: accent))
    }
}

// MARK: - Board dili yardımcıları

/// Board kart kromu: 16px köşe Palette.surface + shadow-xs, kenarlıksız
/// (BoardChartCard / BoardStatCard kabuğuyla aynı).
extension View {
    func measurementBoardCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.surface)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
            )
    }
}

/// Metrik yönünü gözeten BoardDeltaChip girdisi: kilo/yağ/bel düşüşü yeşil okur.
func measurementBoardDelta(
    _ value: Double?,
    unit: String,
    lowerIsBetter: Bool,
    digits: Int = 1
) -> (text: String, direction: Int)? {
    guard let value else { return nil }
    let direction: Int
    if value == 0 {
        direction = 0
    } else {
        let good = lowerIsBetter ? value < 0 : value > 0
        direction = good ? 1 : -1
    }
    return ("\(Fmt.signed(value, digits: digits)) \(unit)", direction)
}

/// Board küçük stat fayansı: renk noktası + soluk etiket + tabular değer
/// (BoardStageBars'ın özet fayanslarıyla aynı krom: surfaceElevated/60, 10px köşe).
/// Ölçüm sayfası düz MeasurementStatStrip'e geçti; DashboardView hâlâ kullanıyor.
struct MeasurementStatTile: View {
    let label: String
    let value: String
    var sub: String? = nil
    var dot: Color? = nil
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            if let sub {
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surfaceElevated.opacity(0.6)))
    }
}

/// Buzz tarzı düz KPI şeridi girdisi: fayans kromu yok, sadece veri.
struct MeasurementStat: Identifiable {
    let label: String
    let value: String
    var sub: String? = nil
    var dot: Color? = nil
    var unit: String? = nil

    var id: String { label }
}

/// Düz tam-genişlik KPI şeridi: kenarlıksız stat grupları, aralarında 1pt
/// dikey hairline (Buzz özet satırı dili). Sayılar fayans fontlarını korur.
struct MeasurementStatStrip: View {
    let stats: [MeasurementStat]

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.border.opacity(0.5))
                        .frame(width: 1, height: 28)
                }
                group(stat)
                    .padding(.leading, index == 0 ? 0 : 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func group(_ stat: MeasurementStat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let dot = stat.dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(stat.label)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(stat.value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit = stat.unit {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            if let sub = stat.sub {
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
        }
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
/// `chartHeight`, sayfanın dikey esnemesinde ana grafikle birlikte büyür;
/// verilmezse doğal 54pt'de kalır.
struct MeasureMiniCard: View {
    let name: String
    let value: String
    let unit: String
    let delta: Double?
    let lowerIsBetter: Bool
    let points: [TrendPoint]
    let tint: Color
    var chartHeight: CGFloat = 54

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .tracking(-0.3)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                    if let chip = measurementBoardDelta(delta, unit: unit, lowerIsBetter: lowerIsBetter) {
                        BoardDeltaChip(text: chip.text, direction: chip.direction)
                    }
                }
            }
            .frame(minWidth: 130, alignment: .leading)

            // Sparkline kartın düz zemininde durur (kart-içinde-kutu yok).
            Sparkline(points: points, accent: tint)
                .frame(height: chartHeight)
                .opacity(points.count >= 2 ? 0.9 : 0)
                .frame(maxWidth: .infinity)
        }
        // Düz zemin: kart kabuğu yok (Genel Bakış dili).
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Lucide(sf: "ruler", size: 24)
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
        .measurementBoardCard()
    }
}
