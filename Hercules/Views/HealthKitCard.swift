import SwiftData
import SwiftUI

/// Mac'teki aktivite özeti. HealthKit doğrudan Mac'ten okunmaz; iPhone'un HealthKit'ten
/// ürettiği `StepEntry` kayıtları CloudKit üzerinden burada görünür.
struct HealthKitCard: View {
    @Query(sort: \StepEntry.date, order: .reverse) private var allSteps: [StepEntry]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

    private var todaysEntry: StepEntry? {
        StepEntry.preferredToday(from: allSteps)
    }

    private var lastHealthKitUpdate: Date? {
        allSteps
            .filter { $0.source == StepEntry.healthKitSource }
            .compactMap(\.syncedAt)
            .max()
    }

    private var weight: Double { measurements.first?.weight ?? 80 }

    private var todaysCalorieBurn: Double {
        guard let entry = todaysEntry else { return 0 }
        return StepEntry.calorieBurn(for: entry, weightKg: weight)
    }

    private var weekEntries: [StepEntry] { entries(days: 7) }
    private var monthEntries: [StepEntry] { entries(days: 30) }
    private var weekSteps: Int { weekEntries.reduce(0) { $0 + $1.steps } }
    private var monthSteps: Int { monthEntries.reduce(0) { $0 + $1.steps } }
    private var weekDistance: Double { weekEntries.compactMap(\.distanceMeters).reduce(0, +) }
    private var weekCalories: Double { weekEntries.reduce(0) { $0 + StepEntry.calorieBurn(for: $1, weightKg: weight) } }
    private var monthCalories: Double { monthEntries.reduce(0) { $0 + StepEntry.calorieBurn(for: $1, weightKg: weight) } }
    private var weeklyAverageSteps: Int { Int((Double(weekSteps) / 7.0).rounded()) }
    private var monthlyAverageSteps: Int { Int((Double(monthSteps) / 30.0).rounded()) }

    private var statusText: String {
        guard let lastHealthKitUpdate else { return "iPhone HealthKit bekleniyor" }
        return "HealthKit · \(Fmt.relative(lastHealthKitUpdate))"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideStrip
            compactStrip
        }
        .padding(.init(top: 16, leading: 28, bottom: 16, trailing: 28))
        .dashboardCard()
    }

    private var wideStrip: some View {
        HStack(alignment: .center, spacing: 26) {
            statusBlock.frame(minWidth: 138, alignment: .leading)
            metricCol(
                "Bugün",
                value: Fmt.int(Double(todaysEntry?.steps ?? 0)),
                unit: "adım",
                sub: "\(Fmt.int(todaysCalorieBurn)) kalori · \(formatDistance(todaysEntry?.distanceMeters ?? 0))"
            )
            metricCol(
                "7 Gün",
                value: Fmt.int(Double(weekSteps)),
                unit: "adım",
                sub: "\(Fmt.int(Double(weeklyAverageSteps))) / gün · \(formatDistance(weekDistance))"
            )
            metricCol(
                "30 Gün",
                value: Fmt.int(Double(monthSteps)),
                unit: "adım",
                sub: "\(Fmt.int(Double(monthlyAverageSteps))) / gün"
            )
            metricCol(
                "Yakım",
                value: Fmt.int(monthCalories),
                unit: "kalori",
                sub: "30 gün · 7 gün \(Fmt.int(weekCalories))"
            )
        }
    }

    private var compactStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            statusBlock
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.lg, alignment: .topLeading)],
                alignment: .leading,
                spacing: Spacing.md
            ) {
                compactMetric(
                    "Bugün",
                    value: Fmt.int(Double(todaysEntry?.steps ?? 0)),
                    unit: "adım",
                    sub: "\(Fmt.int(todaysCalorieBurn)) kalori · \(formatDistance(todaysEntry?.distanceMeters ?? 0))"
                )
                compactMetric(
                    "7 Gün",
                    value: Fmt.int(Double(weekSteps)),
                    unit: "adım",
                    sub: "\(Fmt.int(Double(weeklyAverageSteps))) / gün · \(formatDistance(weekDistance))"
                )
                compactMetric(
                    "30 Gün",
                    value: Fmt.int(Double(monthSteps)),
                    unit: "adım",
                    sub: "\(Fmt.int(Double(monthlyAverageSteps))) / gün"
                )
                compactMetric(
                    "Yakım",
                    value: Fmt.int(monthCalories),
                    unit: "kalori",
                    sub: "30 gün · 7 gün \(Fmt.int(weekCalories))"
                )
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Adım & Aktivite").eyebrow()
            HStack(spacing: 6) {
                Circle()
                    .fill(lastHealthKitUpdate == nil ? Palette.textQuaternary : Palette.positive)
                    .frame(width: 5, height: 5)
                Text(statusText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func metricCol(_ label: String, value: String, unit: String, sub: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Palette.border).frame(width: 0.5).padding(.trailing, 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).eyebrow()
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text(unit).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                    Text("· \(sub)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func compactMetric(_ label: String, value: String, unit: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                Text(unit).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
            }
            Text(sub)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func entries(days: Int) -> [StepEntry] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? .now
        return StepEntry.preferredEntries(
            from: allSteps.filter { $0.date >= start && $0.date < end },
            calendar: calendar
        )
    }

    private func formatDistance(_ meters: Double) -> String {
        guard meters > 0 else { return "0 km" }
        return "\(Fmt.num(meters / 1000, digits: 1)) km"
    }
}
