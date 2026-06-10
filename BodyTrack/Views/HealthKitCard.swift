import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Adım & Aktivite — V1 tek satır şerit: durum + dört dönem kolonu + manuel giriş.
/// Manuel giriş satırı "Manuel giriş" ile açılır; Shortcuts dosya yolu da orada.
struct HealthKitCard: View {
    @Environment(\.modelContext) private var ctx
    private var sync = ShortcutHealthSyncService.shared
    @Query(sort: \StepEntry.date, order: .reverse) private var allSteps: [StepEntry]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @State private var stepInput: Int = 0
    @State private var showManualEntry = false
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

    private var syncStatusText: String {
        if let date = sync.lastImportDate {
            return "Shortcuts · \(Fmt.relative(date))"
        }
        return sync.syncFileExists ? "Shortcuts · dosya hazır" : "Shortcuts · dosya bekleniyor"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                wideStrip
                compactStrip
            }

            if showManualEntry {
                Hairline().padding(.top, 14)
                manualEntryPanel
                    .padding(.top, 13)
            }
        }
        .padding(.init(top: 16, leading: 28, bottom: 16, trailing: 28))
        .dashboardCard()
        .task {
            sync.importIfAvailable(into: ctx)
            stepInput = todaysEntry?.steps ?? 0
        }
        .onChange(of: todaysEntry?.steps) { _, new in
            if !inputFocused, let n = new { stepInput = n }
        }
    }

    private var wideStrip: some View {
        HStack(alignment: .center, spacing: 26) {
            statusBlock
                .frame(minWidth: 118, alignment: .leading)
            metricCol("Bugün",
                      value: Fmt.int(Double(todaysEntry?.steps ?? 0)), unit: "adım",
                      sub: "\(Fmt.int(todaysCalorieBurn)) kcal · \(formatDistance(todaysEntry?.distanceMeters ?? 0))")
            metricCol("7 Gün",
                      value: Fmt.int(Double(weekSteps)), unit: "adım",
                      sub: "\(Fmt.int(Double(weeklyAverageSteps))) / gün · \(formatDistance(weekDistance))")
            metricCol("30 Gün",
                      value: Fmt.int(Double(monthSteps)), unit: "adım",
                      sub: "\(Fmt.int(Double(monthlyAverageSteps))) / gün")
            metricCol("Yakım",
                      value: Fmt.int(monthCalories), unit: "kcal",
                      sub: "30 gün · 7 gün \(Fmt.int(weekCalories))")
            manualToggleButton
        }
    }

    private var compactStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                statusBlock
                Spacer(minLength: Spacing.md)
                manualToggleButton
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.lg, alignment: .topLeading)],
                alignment: .leading,
                spacing: Spacing.md
            ) {
                compactMetric("Bugün", value: Fmt.int(Double(todaysEntry?.steps ?? 0)), unit: "adım",
                              sub: "\(Fmt.int(todaysCalorieBurn)) kcal · \(formatDistance(todaysEntry?.distanceMeters ?? 0))")
                compactMetric("7 Gün", value: Fmt.int(Double(weekSteps)), unit: "adım",
                              sub: "\(Fmt.int(Double(weeklyAverageSteps))) / gün · \(formatDistance(weekDistance))")
                compactMetric("30 Gün", value: Fmt.int(Double(monthSteps)), unit: "adım",
                              sub: "\(Fmt.int(Double(monthlyAverageSteps))) / gün")
                compactMetric("Yakım", value: Fmt.int(monthCalories), unit: "kcal",
                              sub: "30 gün · 7 gün \(Fmt.int(weekCalories))")
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Adım & Aktivite").eyebrow()
            HStack(spacing: 6) {
                Circle()
                    .fill(sync.syncFileExists ? Palette.positive : Palette.textQuaternary)
                    .frame(width: 5, height: 5)
                Text(syncStatusText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func metricCol(_ label: String, value: String, unit: String, sub: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Palette.border).frame(width: 0.5)
                .padding(.trailing, 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).eyebrow()
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text(unit)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
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
                Text(unit)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var manualToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { showManualEntry.toggle() }
        } label: {
            Text(showManualEntry ? "Kapat" : "Manuel giriş")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Bugünün adımını elle gir")
    }

    /// Acil durum manuel girişi + Shortcuts sync dosya durumu.
    private var manualEntryPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bugünün adımı").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        TextField("0", value: $stepInput, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: 120)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .focused($inputFocused)
                            .onSubmit { saveSteps() }
                        Text("adım")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                Rectangle().fill(Palette.border).frame(width: 0.5, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Yakım").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(Fmt.int(StepEntry.calorieBurn(steps: stepInput, weightKg: weight)))
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundStyle(Palette.accent)
                        Text("kcal")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }

                Button(action: saveSteps) {
                    Text("Kaydet")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.btnFg)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(stepInput == (todaysEntry?.steps ?? 0))
                .opacity(stepInput == (todaysEntry?.steps ?? 0) ? 0.5 : 1)

                Spacer(minLength: 0)

                Button {
                    sync.importIfAvailable(into: ctx)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Dosyayı oku")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Shortcuts sync dosyasını şimdi oku")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(sync.displayPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(sync.lastMessage) — iPhone Shortcuts dosyayı her gün günceller; Mac app açıkken otomatik içeri alır. Manuel giriş yalnızca acil durum için.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
