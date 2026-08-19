import SwiftUI
import LucideKit
import SwiftData

struct PlanSetupSheet: View {
    struct Plan {
        var startDate: Date
        var startWeight: Double
        var endWeight: Double
        var months: Int
        /// nil ise eşit dağıtım. Doluysa: ilk ay bu kiloya iner, sonraki aylar firstMonthTarget→endWeight arası eşit dağıtılır.
        var firstMonthTarget: Double?
    }

    enum PaceMode: String, CaseIterable {
        case even, customFirst
        var label: String {
            switch self {
            case .even: return "Eşit Dağıt"
            case .customFirst: return "İlk Ay Özel"
            }
        }
        var detail: String {
            switch self {
            case .even: return "Her ay aynı miktar"
            case .customFirst: return "İlk ay farklı, sonrası eşit"
            }
        }
    }

    let startWeight: Double
    let onCreate: (Plan) -> Void
    let onCancel: () -> Void

    @State private var startDate: Date = .now
    @State private var startWeightInput: Double
    @State private var endWeightInput: Double
    @State private var monthsInput: Int = 12
    @State private var paceMode: PaceMode = .even
    @State private var firstMonthTarget: Double = 0
    @State private var firstMonthTargetEdited: Bool = false

    init(startWeight: Double, onCreate: @escaping (Plan) -> Void, onCancel: @escaping () -> Void) {
        self.startWeight = startWeight
        self.onCreate = onCreate
        self.onCancel = onCancel
        _startWeightInput = State(initialValue: startWeight)
        _endWeightInput = State(initialValue: max(50, startWeight - 12))
    }

    private var totalDelta: Double { endWeightInput - startWeightInput }
    private var perMonth: Double { totalDelta / Double(max(1, monthsInput)) }
    private var perWeek: Double { perMonth / 4.345 }

    /// Linear projection ile ilk ayın varsayılan hedef kilosu.
    private var defaultFirstMonthTarget: Double {
        startWeightInput + totalDelta / Double(max(1, monthsInput))
    }

    private var firstMonthDelta: Double {
        if paceMode == .customFirst {
            return firstMonthTarget - startWeightInput
        }
        return perMonth
    }

    private var subsequentMonthDelta: Double {
        if paceMode == .customFirst, monthsInput > 1 {
            let remaining = endWeightInput - firstMonthTarget
            return remaining / Double(monthsInput - 1)
        }
        return perMonth
    }

    private var subsequentPerWeek: Double { subsequentMonthDelta / 4.345 }

    var body: some View {
        SheetChrome(
            eyebrow: "Öğün Takip",
            title: "Plan Oluştur",
            subtitle: "Başlangıç ve final kilonu gir; ayları doğrusal böler, sonradan tek tek düzenleyebilirsin.",
            size: .standard,
            onClose: onCancel
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SheetField("Başlangıç tarihi") {
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                HStack(spacing: Spacing.md) {
                    SheetField("Başlangıç (kg)") { weightInput($startWeightInput) }
                    SheetField("Final hedef (kg)") { weightInput($endWeightInput) }
                }

                SheetSection("Süre") {
                    SheetRow("Ay sayısı") {
                        Stepper(value: $monthsInput, in: 1...36) {
                            Text("\(monthsInput)").font(Typography.mono)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach([3, 6, 12], id: \.self) { m in
                            quickMonths(m)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }

                SheetSection("Tempo") {
                    Picker("", selection: $paceMode) {
                        ForEach(PaceMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                    Text(paceMode.detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    if paceMode == .customFirst {
                        SheetRow("İlk ay sonu (kg)") {
                            TextField("", value: Binding(
                                get: { firstMonthTarget },
                                set: { firstMonthTarget = $0; firstMonthTargetEdited = true }
                            ), format: .number)
                                .textFieldStyle(.plain)
                                .font(Typography.mono)
                                .frame(width: 70)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                SheetSection("Önizleme") {
                    SheetRow("Toplam değişim") {
                        Text("\(Fmt.signed(totalDelta, digits: 1)) kg").font(Typography.mono)
                    }
                    if paceMode == .customFirst {
                        SheetRow("İlk ay") {
                            Text("\(Fmt.signed(firstMonthDelta, digits: 1)) kg").font(Typography.mono)
                        }
                        SheetRow("Sonraki aylar") {
                            Text("\(Fmt.signed(subsequentMonthDelta, digits: 2)) kg / ay").font(Typography.mono)
                        }
                    } else {
                        SheetRow("Aylık tempo") {
                            Text("\(Fmt.signed(perMonth, digits: 2)) kg").font(Typography.mono)
                        }
                        SheetRow("Haftalık tempo") {
                            Text("\(Fmt.signed(perWeek, digits: 2)) kg").font(Typography.mono)
                        }
                    }
                    if let warning = paceWarning {
                        HStack(spacing: 6) {
                            Lucide(sf: "exclamationmark.triangle.fill", size: 11)
                            Text(warning).font(Typography.caption)
                        }
                        .foregroundStyle(Palette.warning)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
            }
        } footer: {
            Spacer(minLength: 0)
            SheetSecondaryButton("İptal", action: onCancel)
            SheetPrimaryButton("Planı Oluştur") {
                onCreate(Plan(
                    startDate: startDate,
                    startWeight: startWeightInput,
                    endWeight: endWeightInput,
                    months: monthsInput,
                    firstMonthTarget: paceMode == .customFirst ? firstMonthTarget : nil
                ))
            }
        }
        .onChange(of: paceMode) { _, newMode in
            if newMode == .customFirst, !firstMonthTargetEdited {
                firstMonthTarget = roundedHalf(defaultFirstMonthTarget)
            }
        }
        .onChange(of: monthsInput) { _, _ in
            if !firstMonthTargetEdited {
                firstMonthTarget = roundedHalf(defaultFirstMonthTarget)
            }
        }
        .onChange(of: startWeightInput) { _, _ in
            if !firstMonthTargetEdited {
                firstMonthTarget = roundedHalf(defaultFirstMonthTarget)
            }
        }
        .onChange(of: endWeightInput) { _, _ in
            if !firstMonthTargetEdited {
                firstMonthTarget = roundedHalf(defaultFirstMonthTarget)
            }
        }
    }

    private func roundedHalf(_ v: Double) -> Double {
        (v * 2).rounded() / 2
    }

    /// Kilo girdisi — `.roundedBorder` yerine uygulamanın kendi alan stili.
    private func weightInput(_ value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Palette.textPrimary)
    }

    /// 3/6/12 ay kısayolu. Eskiden `.buttonStyle(.bordered)` + `.tint` idi, yani
    /// koyu temanın ortasında Aqua düğmesi.
    private func quickMonths(_ m: Int) -> some View {
        let selected = monthsInput == m
        return Button { monthsInput = m } label: {
            Text("\(m) ay")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(selected ? Palette.btnFg : Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Palette.accent : Palette.fieldFill)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(selected ? Color.clear : Palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(SheetPressStyle())
    }

    private var paceModePicker: some View {
        HStack(spacing: 6) {
            ForEach(PaceMode.allCases, id: \.self) { mode in
                Button {
                    paceMode = mode
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.label)
                            .font(Typography.bodyBold)
                            .foregroundStyle(paceMode == mode ? Palette.textPrimary : Palette.textSecondary)
                        Text(mode.detail)
                            .font(Typography.caption)
                            .foregroundStyle(paceMode == mode ? Palette.textSecondary : Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(paceMode == mode ? Palette.track : Palette.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(paceMode == mode ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monthsPicker: some View {
        HStack(spacing: Spacing.sm) {
            stepperControl
            HStack(spacing: 6) {
                ForEach([3, 6, 12], id: \.self) { m in
                    Button {
                        monthsInput = m
                    } label: {
                        Text("\(m)")
                            .font(Typography.captionBold)
                            .foregroundStyle(monthsInput == m ? Palette.textPrimary : Palette.textSecondary)
                            .frame(width: 32, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                    .fill(monthsInput == m ? Palette.track : Palette.surfaceElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                    .strokeBorder(monthsInput == m ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var stepperControl: some View {
        HStack(spacing: 0) {
            stepperButton(systemImage: "minus", enabled: monthsInput > 1) {
                if monthsInput > 1 { monthsInput -= 1 }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                TextField("", value: Binding(
                    get: { monthsInput },
                    set: { monthsInput = max(1, min(36, $0)) }
                ), format: .number)
                    .textFieldStyle(.plain)
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                Text("ay")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)

            stepperButton(systemImage: "plus", enabled: monthsInput < 36) {
                if monthsInput < 36 { monthsInput += 1 }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func stepperButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Lucide(sf: systemImage, size: 11)
                .foregroundStyle(enabled ? Palette.textPrimary : Palette.textQuaternary)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Önizleme").eyebrow()
            HStack(spacing: Spacing.lg) {
                previewStat(label: "Toplam", value: "\(Fmt.signed(totalDelta, digits: 1)) kg")
                Divider().frame(height: 32).background(Palette.border)
                if paceMode == .customFirst {
                    previewStat(label: "İlk Ay", value: "\(Fmt.signed(firstMonthDelta, digits: 1)) kg")
                    Divider().frame(height: 32).background(Palette.border)
                    previewStat(label: "Sonraki Ay", value: "\(Fmt.signed(subsequentMonthDelta, digits: 2)) kg")
                } else {
                    previewStat(label: "Aylık", value: "\(Fmt.signed(perMonth, digits: 2)) kg")
                    Divider().frame(height: 32).background(Palette.border)
                    previewStat(label: "Haftalık", value: "\(Fmt.signed(perWeek, digits: 2)) kg")
                }
                Spacer()
            }
            if let warning = paceWarning {
                HStack(spacing: 5) {
                    Lucide(sf: "exclamationmark.triangle.fill", size: 10)
                        .foregroundStyle(Palette.warning)
                    Text(warning)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.warning)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.md)
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

    private var paceWarning: String? {
        if paceMode == .customFirst {
            // İlk ay totalDelta'yı geçtiyse / yön ters dönüyorsa uyarı
            if totalDelta != 0, firstMonthDelta != 0,
               firstMonthDelta.sign != totalDelta.sign {
                return "İlk ay yönü genel hedefin tersine. Final hedefe ulaşmak için sonraki aylarda tempo artar."
            }
            if abs(firstMonthDelta) > abs(totalDelta) {
                return "İlk ay değişimi toplam hedefi aşıyor. Sonraki aylar ters yönde ilerler."
            }
            if abs(firstMonthDelta / 4.345) > 1.0 {
                return "İlk hafta 1 kg üstü tempo agresif olabilir."
            }
            if abs(subsequentPerWeek) > 1.0 {
                return "Sonraki haftalarda 1 kg üstü tempo agresif olabilir."
            }
        } else {
            if abs(perWeek) > 1.0 {
                return "Haftalık 1 kg üstü tempo agresif olabilir."
            }
        }
        return nil
    }

    private func previewStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow()
            Text(value)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
        }
    }
}

// MARK: - Food date editor sheet

struct FoodDateEditorSheet: View {
    let food: FoodEntry
    let selectedDay: Date
    let onSave: (Date) -> Void
    let onCancel: () -> Void

    @State private var dateInput: Date

    init(
        food: FoodEntry,
        selectedDay: Date,
        onSave: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.food = food
        self.selectedDay = selectedDay
        self.onSave = onSave
        self.onCancel = onCancel
        _dateInput = State(initialValue: food.date)
    }

    var body: some View {
        SheetChrome(
            eyebrow: "Öğün Takip",
            title: "Yemek Tarihi",
            size: .compact,
            fitsHeightToContent: true,
            onClose: onCancel
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SheetSection("Yemek") {
                    SheetRow("Kayıt") {
                        Text(food.name).lineLimit(2)
                    }
                    SheetRow("Kalori") {
                        Text("\(Fmt.int(food.calories)) kcal")
                            .font(.system(size: 12.5, design: .monospaced))
                    }
                }

                SheetField("Tarih ve saat") {
                    DatePicker("", selection: $dateInput,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                SheetSection("Hızlı düzeltme") {
                    SheetActionRow("Seçili güne taşı: \(CalendarView.fullDayFormatter.string(from: selectedDay))",
                                   icon: "arrow.right") {
                        dateInput = Self.merged(day: selectedDay, time: dateInput)
                    }
                    SheetActionRow("1 gün geri al", icon: "chevron.left") { shiftDay(-1) }
                    SheetActionRow("1 gün ileri al", icon: "chevron.right") { shiftDay(1) }
                }
            }
        } footer: {
            Spacer(minLength: 0)
            SheetSecondaryButton("İptal", action: onCancel)
            SheetPrimaryButton("Kaydet") { onSave(dateInput) }
        }
    }

    private func shiftDay(_ days: Int) {
        dateInput = Calendar.current.date(byAdding: .day, value: days, to: dateInput) ?? dateInput
    }

    static func merged(day: Date, time: Date) -> Date {
        let cal = Calendar.current
        let timeParts = cal.dateComponents([.hour, .minute, .second], from: time)
        let dayStart = cal.startOfDay(for: day)
        return cal.date(
            bySettingHour: timeParts.hour ?? 0,
            minute: timeParts.minute ?? 0,
            second: timeParts.second ?? 0,
            of: dayStart
        ) ?? day
    }
}

// MARK: - Goal editor sheet

struct GoalEditorSheet: View {
    @Bindable var goal: MonthlyGoal
    let onSave: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var weightInput: Double
    @State private var dateInput: Date
    @State private var noteInput: String
    @State private var showDeleteConfirm = false

    init(
        goal: MonthlyGoal,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.goal = goal
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _weightInput = State(initialValue: goal.targetWeight)
        _dateInput = State(initialValue: goal.anchorDate)
        _noteInput = State(initialValue: goal.note ?? "")
    }

    var body: some View {
        SheetChrome(
            eyebrow: "Öğün Takip",
            title: "Aylık Hedef",
            size: .compact,
            fitsHeightToContent: true,
            onClose: onCancel
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SheetField("Tarih") {
                    DatePicker("", selection: $dateInput, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                SheetField("Hedef kilo (kg)") {
                    TextField("", value: $weightInput, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                }
                SheetField("Not") {
                    TextField("ör: yaza hazır", text: $noteInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
        } footer: {
            // Yıkıcı eylem SOLDA — Kaydet'in dibinde olsa yanlışlıkla tıklanırdı.
            SheetDestructiveButton("Sil") { showDeleteConfirm = true }
            Spacer(minLength: 0)
            SheetSecondaryButton("İptal", action: onCancel)
            SheetPrimaryButton("Kaydet") {
                goal.targetWeight = weightInput
                goal.anchorDate = dateInput
                let trimmed = noteInput.trimmingCharacters(in: .whitespaces)
                goal.note = trimmed.isEmpty ? nil : trimmed
                onSave()
            }
        }
        .alert("Hedefi sil?", isPresented: $showDeleteConfirm) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) { onDelete() }
        }
    }
}
