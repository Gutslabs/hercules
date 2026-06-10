import SwiftUI
import SwiftData

struct MetricSeriesSnapshot {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?
}

// MARK: - V1 "Tek Akış" · Okuma panel

/// Reading panel for the focused series — slope narrative + data density / last
/// record / target band. Goal-aware (`lowerIsBetter`) so weight loss reads as
/// "aligned" when cutting.
struct ChartReadingPanel: View {
    let kind: MetricKind
    let stats: TrendStats
    let points: [TrendPoint]
    let goalBand: (start: TrendPoint, end: TrendPoint)?
    let lowerIsBetter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Okuma").eyebrow()
            Text(narrative.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text(narrative.detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)

            Hairline().padding(.top, 13)

            VStack(spacing: 9) {
                readingRow("Veri yoğunluğu", "\(stats.pointCount) ölçüm", tint: Palette.textPrimary)
                readingRow("Son kayıt", points.last.map { Fmt.dateLong.string(from: $0.date) } ?? "Yok", tint: Palette.textPrimary)
                readingRow("Hedef bandı", goalBand == nil ? "Kapalı" : "Açık", tint: goalBand == nil ? Palette.textTertiary : Palette.accent)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .dashboardCard()
    }

    private func readingRow(_ label: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
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
        let isGood = lowerIsBetter ? !positive : positive
        let direction = positive ? "yukarı" : "aşağı"
        let tone = isGood ? "hedef yönüyle uyumlu" : "hedefle ters yönde"
        return (
            "Eğim \(direction)",
            "\(Fmt.signed(weekly, digits: 2)) \(kind.unit)/hafta; mevcut hareket \(tone)."
        )
    }
}

// MARK: - V1 "Tek Akış" · Seri seçici

/// Compact series chip in the selector — name + current value + goal-aware delta.
struct ChartSeriesTile: View {
    let kind: MetricKind
    let stats: TrendStats
    let lowerIsBetter: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(Fmt.numOpt(stats.current))
                        .font(.system(size: 15.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(kind.unit)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(Palette.textQuaternary)
                    Spacer(minLength: 4)
                    DeltaBadge(delta: stats.delta, lowerIsBetter: lowerIsBetter)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Palette.accent.opacity(0.07) : Palette.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent.opacity(0.45) : Palette.border, lineWidth: isSelected ? 1 : 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(PressedButtonStyle())
        .help("\(kind.label) serisini ana grafiğe taşı")
    }
}

struct ChartsEmptyState: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
                .frame(height: 280)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.75)
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

struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
