import SwiftUI
import SwiftData

// MARK: - Root view

struct MealPlanView: View {
    @Query(sort: \MealPlanOverride.createdAt) private var mealOverrides: [MealPlanOverride]
    @AppStorage("mealplan.deficit") private var deficitRaw: String = DeficitLevel.maintain.rawValue
    @AppStorage("mealplan.selectedWeekday") private var selectedWeekdayRaw: Int = Weekday.today.rawValue

    private var deficit: DeficitLevel {
        get { DeficitLevel(rawValue: deficitRaw) ?? .maintain }
    }

    private var selectedWeekday: Weekday {
        Weekday(rawValue: selectedWeekdayRaw) ?? .today
    }

    private var dayType: MealDayType {
        dayType(for: selectedWeekday.rawValue)
    }

    private var template: DayTemplate {
        MealLibrary.template(for: dayType)
    }

    private var totals: Macros {
        template.totals(deficit: deficit.factor) + customTotals
    }

    private var selectedOverrides: [MealPlanOverride] {
        mealOverrides.filter { $0.weekday == selectedWeekday.rawValue }
    }

    private var customTotals: Macros {
        selectedOverrides
            .filter { $0.operation == .addItem }
            .reduce(.zero) { $0 + $1.macros }
    }

    private func dayType(for weekday: Int) -> MealDayType {
        MealPlanOverride.dayTypeOverride(for: weekday, in: mealOverrides) ?? MealLibrary.dayType(for: weekday)
    }

    private func customItems(for slot: MealSlot) -> [MealPlanOverride] {
        selectedOverrides.filter { $0.operation == .addItem && $0.slot == slot }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header
                weeklyStrip
                summaryRow
                mealsGrid
                deficitPanel
                rotationNote
                Spacer(minLength: 24)
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .background(Palette.background.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Diyet").eyebrow()
                Text("Yemek Takvimi")
                    .font(Typography.display(40))
                    .foregroundStyle(Palette.textPrimary)
                Text("3 günlük döngü · ~2000-2150 kcal · 165 g+ protein hedefi")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            DeficitSegmented(selection: Binding(
                get: { deficit },
                set: { deficitRaw = $0.rawValue }
            ))
        }
    }

    // MARK: Weekly strip

    private var weeklyStrip: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.orderedTrWeek) { wd in
                WeekdayChip(
                    weekday: wd,
                    dayType: dayType(for: wd.rawValue),
                    isSelected: wd == selectedWeekday,
                    isToday: wd == Weekday.today
                ) {
                    selectedWeekdayRaw = wd.rawValue
                }
            }
        }
    }

    // MARK: Summary row (day header + macros)

    private var summaryRow: some View {
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    DayBadge(type: dayType)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(selectedWeekday.long) · \(dayType.label)")
                            .font(Typography.title)
                            .foregroundStyle(Palette.textPrimary)
                        Text(dayType.headline)
                            .font(Typography.body)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    if !selectedOverrides.isEmpty {
                        PillTag(text: "AI DÜZENLENDİ", tint: Palette.positive)
                    }
                    if deficit != .maintain {
                        PillTag(text: "DEFICIT · \(deficit.label.uppercased()) (\(deficit.deltaKcal) kcal)", tint: Palette.accent)
                    }
                }

                Hairline()

                MacroSummary(totals: totals, deficit: deficit)
            }
        }
    }

    // MARK: Meals grid

    private var mealsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: Spacing.md),
            GridItem(.flexible(), spacing: Spacing.md),
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.md) {
            ForEach(template.meals) { meal in
                MealCard(meal: meal, deficit: deficit.factor, customItems: customItems(for: meal.slot))
            }
        }
    }

    // MARK: Deficit panel

    private var deficitPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SectionHeader(
                    eyebrow: "PLATEAU",
                    title: "Kalori Defisiti",
                    subtitle: "Plato kırmak için porsiyonları gerçek zamanlı küçült. Protein sabit, karbonhidrat ve yağ önce kısılır."
                )

                DeficitGrid(selection: Binding(
                    get: { deficit },
                    set: { deficitRaw = $0.rawValue }
                ))

                Hairline()

                deficitExplanation
            }
        }
    }

    private var deficitExplanation: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("NASIL KISILIYOR").eyebrow()
            HStack(alignment: .top, spacing: Spacing.lg) {
                trimRow(color: Palette.macroProtein, text: "Protein (et, yumurta, peynir, yoğurt) — dokunulmuyor")
                trimRow(color: Palette.macroFat, text: "Yağ (zeytinyağı) — önce sıfıra iniyor")
            }
            HStack(alignment: .top, spacing: Spacing.lg) {
                trimRow(color: Palette.macroCarbs, text: "Karbonhidrat (bulgur, pirinç, patates) — önce buradan kesiyor")
                trimRow(color: Color(red: 0.90, green: 0.62, blue: 0.78), text: "Meyve (muz, elma) — orta düzeyde küçülür")
            }
        }
    }

    private func trimRow(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Rotation note

    private var rotationNote: some View {
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("HAFTALIK ROTASYON").eyebrow()
                Text("Önerilen dağılım: haftanın 3-4 günü tavuk göğsü, 2 günü derisiz but, 1 günü pirzola. Yağ hedefini tutmak için but ve pirzola günlerinde zeytinyağı kullanma. Tüm gramlar çiğ ağırlık üzerinden — tavuk, bulgur, pirinç, patates hepsi pişmeden tartılır.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - Weekday chip

private struct WeekdayChip: View {
    let weekday: Weekday
    let dayType: MealDayType
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Text(weekday.short)
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textTertiary)
                    if isToday {
                        Circle().fill(Palette.accent).frame(width: 3.5, height: 3.5)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(dayType.accent)
                        .frame(width: 5, height: 5)
                    Text(dayType.short)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? Palette.surfaceElevated : (hover ? Palette.surface.opacity(0.7) : Palette.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(isSelected ? Palette.borderStrong : Palette.border, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Day badge

private struct DayBadge: View {
    let type: MealDayType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surfaceElevated)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
            Image(systemName: "fork.knife")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(type.accent)
        }
        .frame(width: 40, height: 40)
    }
}

// MARK: - Deficit segmented (header version)

private struct DeficitSegmented: View {
    @Binding var selection: DeficitLevel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DeficitLevel.allCases) { level in
                Button { selection = level } label: {
                    Text(level.label)
                        .font(Typography.captionBold)
                        .foregroundStyle(selection == level ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                .fill(selection == level ? Color.white.opacity(0.08) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Deficit big grid (panel version)

private struct DeficitGrid: View {
    @Binding var selection: DeficitLevel

    var body: some View {
        let cols = [GridItem(.flexible(), spacing: Spacing.md),
                    GridItem(.flexible(), spacing: Spacing.md),
                    GridItem(.flexible(), spacing: Spacing.md),
                    GridItem(.flexible(), spacing: Spacing.md)]
        LazyVGrid(columns: cols, spacing: Spacing.md) {
            ForEach(DeficitLevel.allCases) { level in
                DeficitTile(level: level, isSelected: level == selection) {
                    selection = level
                }
            }
        }
    }
}

private struct DeficitTile: View {
    let level: DeficitLevel
    let isSelected: Bool
    let action: () -> Void
    @State private var hover = false

    private var accent: Color {
        switch level {
        case .maintain: return Palette.textSecondary
        case .light:    return Palette.positive
        case .medium:   return Palette.warning
        case .hard:     return Palette.accent
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(level.label)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
                Text(level.deltaKcal == 0 ? "±0 kcal" : "\(level.deltaKcal) kcal")
                    .font(Typography.monoLarge)
                    .foregroundStyle(accent)
                Text(level.subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? Palette.surfaceElevated : (hover ? Palette.surface.opacity(0.7) : Palette.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? Palette.borderStrong : Palette.border, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Macro summary

private struct MacroSummary: View {
    let totals: Macros
    let deficit: DeficitLevel

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            macroBig(value: Int(totals.kcal.rounded()), unit: "kcal", label: "Toplam", tint: Palette.textPrimary)
            Divider().frame(height: 44).background(Palette.border)
            macroBig(value: Int(totals.p.rounded()), unit: "g", label: "Protein", tint: Palette.macroProtein)
            macroBig(value: Int(totals.c.rounded()), unit: "g", label: "Karbonhidrat", tint: Palette.macroCarbs)
            macroBig(value: Int(totals.f.rounded()), unit: "g", label: "Yağ", tint: Palette.macroFat)
            Spacer()
        }
    }

    private func macroBig(value: Int, unit: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Typography.label)
                .tracking(0.8)
                .foregroundStyle(Palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(Typography.hero(30))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.snappy, value: value)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

// MARK: - Meal card

private struct MealCard: View {
    let meal: PlannedMeal
    let deficit: Double
    let customItems: [MealPlanOverride]

    private var totals: Macros {
        meal.totals(deficit: deficit) + customItems.reduce(.zero) { $0 + $1.macros }
    }

    var body: some View {
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: 8) {
                    Image(systemName: meal.slot.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Text(meal.slot.label.uppercased())
                        .font(Typography.captionBold)
                        .tracking(0.8)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("\(Int(totals.kcal.rounded())) kcal")
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textTertiary)
                }

                Hairline()

                VStack(spacing: 7) {
                    ForEach(meal.items) { item in
                        ItemRow(item: item, deficit: deficit)
                    }
                    ForEach(customItems) { item in
                        CustomMealItemRow(item: item)
                    }
                }
            }
        }
    }
}

private struct CustomMealItemRow: View {
    @Environment(\.modelContext) private var ctx
    let item: MealPlanOverride

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(Palette.positive.opacity(0.9))
                .frame(width: 6, height: 6)

            Text(item.amountText.isEmpty ? "+" : "+ \(item.amountText)")
                .font(Typography.mono)
                .foregroundStyle(Palette.positive)
                .frame(width: 130, alignment: .leading)

            Text(item.displayName)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if item.calories != nil || item.protein != nil {
                Text(customMacroText)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }

            Button {
                ctx.delete(item)
                try? ctx.save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help("AI eklemesini sil")
        }
    }

    private var customMacroText: String {
        var parts: [String] = []
        if let kcal = item.calories { parts.append("\(Fmt.int(kcal)) kcal") }
        if let p = item.protein { parts.append("P \(Fmt.int(p))g") }
        return parts.joined(separator: " · ")
    }
}

private struct ItemRow: View {
    let item: PlannedItem
    let deficit: Double

    private var scaledAmount: Double { item.amount(deficit: deficit) }
    private var changed: Bool { deficit > 0 && item.trimFactor > 0 && abs(scaledAmount - item.baseAmount) > 0.5 }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Kind dot
            Circle()
                .fill(item.kind.tint.opacity(0.85))
                .frame(width: 6, height: 6)

            // Amount column (fixed-ish width)
            HStack(spacing: 4) {
                if changed {
                    Text(formatAmount(item.baseAmount, unit: item.unit))
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textQuaternary)
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text(formatAmount(scaledAmount, unit: item.unit))
                        .font(Typography.mono)
                        .foregroundStyle(Palette.accent)
                } else {
                    Text(formatAmount(item.baseAmount, unit: item.unit))
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(width: 130, alignment: .leading)

            // Name
            Text(item.name)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private func formatAmount(_ value: Double, unit: String) -> String {
        // Whole-number units for "adet" and "tabak", round to int.
        // Grams: show as integer (round to nearest 5g if scaled).
        if unit == "adet" || unit == "tabak" {
            let rounded = Int(value.rounded())
            return "\(rounded) \(unit)"
        } else {
            // Round to nearest 5 for cleaner numbers
            let rounded = (value / 5.0).rounded() * 5.0
            return "\(Int(rounded)) \(unit)"
        }
    }
}

// MARK: - Preview

#Preview {
    MealPlanView()
        .frame(width: 1100, height: 900)
        .preferredColorScheme(.dark)
}
