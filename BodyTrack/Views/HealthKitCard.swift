import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct HealthKitCard: View {
    @Environment(\.modelContext) private var ctx
    private var sync = ShortcutHealthSyncService.shared
    @Query(sort: \StepEntry.date, order: .reverse) private var allSteps: [StepEntry]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @State private var stepInput: Int = 0
    @FocusState private var inputFocused: Bool

    private var todaysEntry: StepEntry? {
        let cal = Calendar.current
        return allSteps.first { cal.isDateInToday($0.date) }
    }

    private var weight: Double {
        measurements.first?.weight ?? 80
    }

    private var todaysCalorieBurn: Double {
        guard let entry = todaysEntry else { return 0 }
        return StepEntry.calorieBurn(for: entry, weightKg: weight)
    }

    private var weekEntries: [StepEntry] { entries(days: 7) }
    private var monthEntries: [StepEntry] { entries(days: 30) }

    private var weekSteps: Int { weekEntries.reduce(0) { $0 + $1.steps } }
    private var monthSteps: Int { monthEntries.reduce(0) { $0 + $1.steps } }
    private var weekDistance: Double { weekEntries.compactMap(\.distanceMeters).reduce(0, +) }
    private var monthDistance: Double { monthEntries.compactMap(\.distanceMeters).reduce(0, +) }
    private var weekCalories: Double { weekEntries.reduce(0) { $0 + StepEntry.calorieBurn(for: $1, weightKg: weight) } }
    private var monthCalories: Double { monthEntries.reduce(0) { $0 + StepEntry.calorieBurn(for: $1, weightKg: weight) } }

    private var weeklyAverageSteps: Int {
        Int((Double(weekSteps) / 7.0).rounded())
    }

    private var monthlyAverageSteps: Int {
        Int((Double(monthSteps) / 30.0).rounded())
    }

    private var syncBadgeText: String {
        sync.syncFileExists ? "Shortcuts sync aktif" : "Dosya bekleniyor"
    }

    private var syncBadgeIcon: String {
        sync.syncFileExists ? "checkmark.icloud" : "icloud.and.arrow.down"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("Adım & Aktivite").eyebrow()
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: syncBadgeIcon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(syncBadgeText)
                        .font(Typography.captionBold)
                }
                .foregroundStyle(sync.syncFileExists ? Palette.positive : Palette.textTertiary)
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: Spacing.lg, alignment: .leading)
            ], alignment: .leading, spacing: Spacing.md) {
                activityMetric(
                    label: "Bugün",
                    value: Fmt.int(Double(todaysEntry?.steps ?? 0)),
                    unit: "adım",
                    detail: "\(Fmt.int(todaysCalorieBurn)) kcal · \(formatDistance(todaysEntry?.distanceMeters ?? 0))"
                )
                activityMetric(
                    label: "7 gün",
                    value: Fmt.int(Double(weekSteps)),
                    unit: "adım",
                    detail: "\(Fmt.int(Double(weeklyAverageSteps))) / gün · \(formatDistance(weekDistance))"
                )
                activityMetric(
                    label: "30 gün",
                    value: Fmt.int(Double(monthSteps)),
                    unit: "adım",
                    detail: "\(Fmt.int(Double(monthlyAverageSteps))) / gün · \(formatDistance(monthDistance))"
                )
                activityMetric(
                    label: "Yakım",
                    value: Fmt.int(monthCalories),
                    unit: "kcal",
                    detail: "30 gün · 7 gün \(Fmt.int(weekCalories)) kcal"
                )
            }

            syncStatusRow
            manualEntryView
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .task {
            sync.importIfAvailable(into: ctx)
            stepInput = todaysEntry?.steps ?? 0
        }
        .onChange(of: todaysEntry?.steps) { _, new in
            if !inputFocused, let n = new { stepInput = n }
        }
    }

    private var syncStatusRow: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)

            VStack(alignment: .leading, spacing: 3) {
                Text(sync.displayPath)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sync.lastMessage)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                sync.importIfAvailable(into: ctx)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.surfaceElevated))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Shortcut sync dosyasını şimdi oku")
        }
    }

    private var manualEntryView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bugünün adımı").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        TextField("0", value: $stepInput, format: .number)
                            .textFieldStyle(.plain)
                            .font(Typography.hero(28))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: 140)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .focused($inputFocused)
                            .onSubmit { saveSteps() }
                        Text("adım")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Divider().frame(height: 40).background(Palette.border)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yakım").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(Fmt.int(StepEntry.calorieBurn(steps: stepInput, weightKg: weight)))
                            .font(Typography.hero(28))
                            .foregroundStyle(Palette.accent)
                        Text("kcal")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                Spacer()
                Button(action: saveSteps) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Kaydet")
                            .font(Typography.bodyBold)
                    }
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.accent))
                }
                .buttonStyle(.plain)
                .disabled(stepInput == (todaysEntry?.steps ?? 0))
                .opacity(stepInput == (todaysEntry?.steps ?? 0) ? 0.5 : 1)
            }
            Text("iPhone Shortcuts her gün \(sync.displayPath) dosyasını günceller. Mac app açıkken dosyayı otomatik içeri alır; burası acil durum manuel giriş.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func saveSteps() {
        if let entry = todaysEntry {
            entry.steps = stepInput
            entry.source = "manual"
            entry.distanceMeters = nil
            entry.activeEnergyKcal = nil
            entry.syncedAt = nil
        } else {
            let new = StepEntry(date: .now, steps: stepInput, source: "manual")
            ctx.insert(new)
        }
        ctx.saveOrReport()
    }

    private func activityMetric(label: String, value: String, unit: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(Typography.hero(22))
                    .foregroundStyle(Palette.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func entries(days: Int) -> [StepEntry] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? .now

        var byDay: [Date: StepEntry] = [:]
        for entry in allSteps where entry.date >= start && entry.date < end {
            let day = calendar.startOfDay(for: entry.date)
            if let existing = byDay[day] {
                if entry.date > existing.date {
                    byDay[day] = entry
                }
            } else {
                byDay[day] = entry
            }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters <= 0 { return "0 km" }
        return "\(Fmt.num(meters / 1000, digits: 1)) km"
    }
}

// MARK: - AI Provider Card
