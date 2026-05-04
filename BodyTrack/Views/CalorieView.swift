import SwiftUI
import SwiftData

struct CalorieView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [UserProfile]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

    @State private var sex: Sex = .male
    @State private var age: Double = 28
    @State private var height: Double = 178
    @State private var weight: Double = 80
    @State private var bodyFat: Double? = 15
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: Goal = .maintain
    @State private var manualOffset: Double = 0

    @State private var hasInitialized = false

    private var result: CalorieResult {
        CalorieCalculator.compute(
            weight: weight,
            height: height,
            age: Int(age),
            sex: sex,
            bodyFat: bodyFat,
            activity: activity,
            goal: goal,
            manualOffset: manualOffset
        )
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: Spacing.xl) {
                inputColumn
                    .frame(maxWidth: 460)
                resultColumn
            }
            .padding(Spacing.xxl)
        }
        .background(Palette.background.ignoresSafeArea())
        .onAppear { initializeFromProfile() }
    }

    private func initializeFromProfile() {
        guard !hasInitialized else { return }
        hasInitialized = true
        if let p = profiles.first {
            sex = p.sex
            age = Double(p.age)
            height = p.height
            activity = p.activity
            goal = p.goal
            manualOffset = p.manualCalorieOffset
        }
        if let last = measurements.first {
            if let w = last.weight { weight = w }
            if let bf = last.bodyFat { bodyFat = bf }
        } else if let manualBF = profiles.first?.manualBodyFat {
            bodyFat = manualBF
        }
    }

    private var inputColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hesaplayıcı").eyebrow()
                Text("Günlük Kalori")
                    .font(Typography.display(36))
                    .foregroundStyle(Palette.textPrimary)
            }

            Card(padding: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Temel Bilgiler").eyebrow()
                    SegmentedChoice(
                        options: Sex.allCases,
                        selection: $sex,
                        label: { $0.label }
                    )
                    HStack(spacing: Spacing.md) {
                        LabeledNumberFieldRequired(label: "Yaş", unit: "yıl", value: $age, range: 14...100)
                        LabeledNumberFieldRequired(label: "Boy", unit: "cm", value: $height, range: 100...230)
                    }
                    HStack(spacing: Spacing.md) {
                        LabeledNumberFieldRequired(label: "Ağırlık", unit: "kg", value: $weight, range: 30...250)
                        LabeledNumberField(label: "Yağ Oranı", unit: "%", value: $bodyFat, range: 3...60)
                    }
                    HStack(spacing: Spacing.md) {
                        Link(destination: URL(string: "https://www.agirsaglam.com/vucut-yag-orani-hesaplama/")!) {
                            HStack(spacing: 5) {
                                Image(systemName: "ruler").font(.system(size: 10))
                                Text("Yağ oranı hesapla").font(Typography.caption)
                                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)

                        if let last = measurements.first, last.weight != nil {
                            Button {
                                if let w = last.weight { weight = w }
                                if let bf = last.bodyFat { bodyFat = bf }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down.circle").font(.system(size: 10))
                                    Text("Son ölçümden çek").font(Typography.caption)
                                }
                                .foregroundStyle(Palette.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Card(padding: Spacing.lg) {
                ChoiceRow(
                    title: "Aktivite",
                    options: ActivityLevel.allCases,
                    selection: $activity,
                    label: { "\($0.label) · ×\(Fmt.num($0.multiplier, digits: 2).replacingOccurrences(of: ",", with: "."))" }
                )
            }

            Card(padding: Spacing.lg) {
                ChoiceRow(
                    title: "Hedef",
                    options: Goal.allCases,
                    selection: $goal,
                    label: { "\($0.label) · \($0.detail)" }
                )
            }

            Card(padding: Spacing.lg) {
                manualOffsetControl
            }

            Button {
                saveToProfile()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Profilime kaydet")
                        .font(Typography.bodyBold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(Palette.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var manualOffsetControl: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ek Düzeltme").eyebrow()
                    Text("Plato kırmak veya ince ayar için")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Text(offsetDisplay)
                    .font(Typography.monoLarge)
                    .foregroundStyle(offsetColor)
            }
            HStack(spacing: Spacing.sm) {
                offsetButton(delta: -100, label: "−100")
                offsetButton(delta: -50, label: "−50")
                offsetButton(delta: +50, label: "+50")
                offsetButton(delta: +100, label: "+100")
                Spacer(minLength: 0)
                Button {
                    manualOffset = 0
                } label: {
                    Text("Sıfırla")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .opacity(manualOffset == 0 ? 0.4 : 1)
                .disabled(manualOffset == 0)
            }
        }
    }

    private var offsetDisplay: String {
        if manualOffset == 0 { return "0 kcal" }
        let prefix = manualOffset > 0 ? "+" : ""
        return "\(prefix)\(Fmt.int(manualOffset)) kcal"
    }

    private var offsetColor: Color {
        if manualOffset == 0 { return Palette.textTertiary }
        return manualOffset < 0 ? Palette.positive : Palette.warning
    }

    private func offsetButton(delta: Double, label: String) -> some View {
        Button {
            let newValue = manualOffset + delta
            manualOffset = min(500, max(-500, newValue))
        } label: {
            Text(label)
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 52)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                        .fill(Palette.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func saveToProfile() {
        let profile = profiles.first ?? {
            let p = UserProfile()
            ctx.insert(p)
            return p
        }()
        profile.sex = sex
        profile.height = height
        profile.activity = activity
        profile.goal = goal
        profile.manualBodyFat = bodyFat
        profile.manualCalorieOffset = manualOffset
        if let birthDate = Calendar.current.date(byAdding: .year, value: -Int(age), to: .now) {
            profile.birthDate = birthDate
        }
        try? ctx.save()
    }

    private var resultColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            heroResult
            macroSplit
            extras
            formulaInfo
        }
    }

    private var heroResult: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hedef").eyebrow()
                    Text("Günlük Kalori İhtiyacın")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                PillTag(text: result.formula, tint: Palette.accent)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(Fmt.int(result.goalCalories))
                    .font(Typography.display(72))
                    .foregroundStyle(Palette.textPrimary)
                Text("kcal/gün")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textTertiary)
            }

            HStack(spacing: Spacing.xl) {
                breakdown(label: "BMR", value: "\(Fmt.int(result.bmr)) kcal")
                breakdown(label: "TDEE", value: "\(Fmt.int(result.tdee)) kcal")
                breakdown(label: "Hedef", value: goalAdjustmentString)
                if manualOffset != 0 {
                    breakdown(label: "Ek", value: offsetDisplay)
                }
            }
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var goalAdjustmentString: String {
        let v = goal.calorieAdjustment
        if v == 0 { return "0 kcal" }
        let prefix = v > 0 ? "+" : ""
        return "\(prefix)\(Fmt.int(v)) kcal"
    }

    private func breakdown(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow()
            Text(value)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var macroSplit: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Makro Dağılımı").eyebrow()
                Spacer()
                Text("Toplam \(Fmt.int(result.goalCalories)) kcal üzerinden")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            MacroBar(macros: result)
            HStack(spacing: Spacing.lg) {
                macroCard(name: "Protein", grams: result.protein.grams, kcal: result.protein.calories, percent: result.protein.percent, tint: Palette.macroProtein)
                macroCard(name: "Karbonhidrat", grams: result.carbs.grams, kcal: result.carbs.calories, percent: result.carbs.percent, tint: Palette.macroCarbs)
                macroCard(name: "Yağ", grams: result.fat.grams, kcal: result.fat.calories, percent: result.fat.percent, tint: Palette.macroFat)
            }
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func macroCard(name: String, grams: Double, kcal: Double, percent: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(name).eyebrow()
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(Fmt.int(grams))
                    .font(Typography.hero(28))
                    .foregroundStyle(Palette.textPrimary)
                Text("g")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            Text("%\(Fmt.int(percent))")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var extras: some View {
        HStack(spacing: Spacing.md) {
            ExtraCard(
                title: "Su",
                value: Fmt.num(result.water, digits: 1),
                unit: "L/gün",
                icon: "drop.fill",
                tint: Color(red: 0.36, green: 0.70, blue: 0.95)
            )
            ExtraCard(
                title: "Lif",
                value: Fmt.int(result.fiber),
                unit: "g/gün",
                icon: "leaf.fill",
                tint: Color(red: 0.55, green: 0.78, blue: 0.40)
            )
            ExtraCard(
                title: "Yağsız Kütle",
                value: Fmt.num(result.leanMass, digits: 1),
                unit: "kg",
                icon: "figure.strengthtraining.traditional",
                tint: Palette.accent
            )
        }
    }

    private var formulaInfo: some View { EmptyView() }
}

struct ExtraCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title).eyebrow()
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.hero(30))
                    .foregroundStyle(Palette.textPrimary)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}
