import SwiftUI
import SwiftData

struct ChartsView: View {
    @Query(sort: \Measurement.date) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]

    @State private var selectedCategory: MetricCategory = .composition

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header
                categoryPicker
                chartGrid
                Spacer(minLength: 24)
            }
            .padding(Spacing.xxl)
        }
        .background(Palette.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trend").eyebrow()
            Text("Grafikler")
                .font(Typography.display(40))
                .foregroundStyle(Palette.textPrimary)
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 4) {
            ForEach(MetricCategory.allCases) { c in
                Button {
                    selectedCategory = c
                } label: {
                    Text(c.label)
                        .font(Typography.bodyBold)
                        .foregroundStyle(selectedCategory == c ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                .fill(selectedCategory == c ? Color.white.opacity(0.07) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(measurements.count) ölçüm")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var visibleKinds: [MetricKind] {
        MetricKind.allCases.filter { $0.category == selectedCategory }
    }

    private var chartGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
            spacing: Spacing.md
        ) {
            ForEach(visibleKinds, id: \.self) { kind in
                let pts = TrendAnalysis.points(measurements, for: kind)
                let stats = TrendAnalysis.stats(pts)
                ChartTile(kind: kind, points: pts, stats: stats, goalBand: goalBand(for: kind, points: pts))
            }
        }
    }

    private func goalBand(for kind: MetricKind, points: [TrendPoint]) -> (start: TrendPoint, end: TrendPoint)? {
        guard kind == .weight, let target = profile?.targetWeight else { return nil }
        return TrendAnalysis.goalBand(from: points, target: target)
    }
}

struct ChartTile: View {
    let kind: MetricKind
    let points: [TrendPoint]
    let stats: TrendStats
    let goalBand: (start: TrendPoint, end: TrendPoint)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.label)
                            .font(Typography.titleSmall)
                            .foregroundStyle(Palette.textPrimary)
                        Text(kind.unit)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(Fmt.numOpt(stats.current))
                            .font(Typography.hero(28))
                            .foregroundStyle(Palette.textPrimary)
                        Text(kind.unit)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                statSummary
            }
            .padding(Spacing.xl)

            chartArea
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var statSummary: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            changeStat
            rangeStat
            averageStat
            Spacer(minLength: 0)
        }
    }

    private var changeStat: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Değişim").eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if let d = stats.delta {
                    Image(systemName: d > 0 ? "arrow.up" : (d < 0 ? "arrow.down" : "arrow.right"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(deltaColor)
                }
                Text(deltaText)
                    .font(Typography.mono)
                    .foregroundStyle(deltaColor)
                Text(kind.unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            if let w = stats.weeklyChange {
                Text("\(Fmt.signed(w, digits: 2)) \(kind.unit)/hafta")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var rangeStat: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Aralık").eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(Fmt.numOpt(stats.min)) – \(Fmt.numOpt(stats.max))")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                Text(kind.unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            Text("en düşük – en yüksek")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private var averageStat: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ortalama").eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(Fmt.numOpt(stats.average))
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                Text(kind.unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            Text("\(stats.pointCount) ölçüm")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private var deltaText: String {
        guard let d = stats.delta else { return "—" }
        return Fmt.signed(d, digits: 1)
    }

    private var deltaColor: Color {
        guard let d = stats.delta else { return Palette.textTertiary }
        let positive = d > 0
        let isGood = kind.lowerIsBetter ? !positive : positive
        if abs(d) < 0.05 { return Palette.textSecondary }
        return isGood ? Palette.positive : Palette.negative
    }

    private var chartArea: some View {
        TrendChart(points: points, goalBand: goalBand, height: 220, unit: kind.unit)
    }
}
