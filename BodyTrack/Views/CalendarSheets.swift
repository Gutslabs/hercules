import SwiftUI
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
        NavigationStack {
            Form {
                Section {
                    DatePicker("Başlangıç tarihi", selection: $startDate, displayedComponents: .date)
                    LabeledContent("Başlangıç (kg)") {
                        TextField("", value: $startWeightInput, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    LabeledContent("Final hedef (kg)") {
                        TextField("", value: $endWeightInput, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                } header: {
                    Text("Plan")
                } footer: {
                    Text("Başlangıç ve final kilonu gir; ayları doğrusal böler, sonradan tek tek düzenleyebilirsin.")
                        .font(Typography.caption)
                }

                Section("Süre") {
                    Stepper(value: $monthsInput, in: 1...36) {
                        LabeledContent("Ay sayısı") {
                            Text("\(monthsInput)")
                                .font(Typography.mono)
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach([3, 6, 12], id: \.self) { m in
                            Button("\(m) ay") { monthsInput = m }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(monthsInput == m ? Palette.accent : Palette.textSecondary)
                        }
                        Spacer()
                    }
                }

                Section("Tempo") {
                    Picker("Mod", selection: $paceMode) {
                        ForEach(PaceMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(paceMode.detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)

                    if paceMode == .customFirst {
                        LabeledContent("İlk ay sonu (kg)") {
                            TextField("", value: Binding(
                                get: { firstMonthTarget },
                                set: { firstMonthTarget = $0; firstMonthTargetEdited = true }
                            ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                Section("Önizleme") {
                    LabeledContent("Toplam değişim") {
                        Text("\(Fmt.signed(totalDelta, digits: 1)) kg")
                            .font(Typography.mono)
                    }
                    if paceMode == .customFirst {
                        LabeledContent("İlk ay") {
                            Text("\(Fmt.signed(firstMonthDelta, digits: 1)) kg")
                                .font(Typography.mono)
                        }
                        LabeledContent("Sonraki aylar") {
                            Text("\(Fmt.signed(subsequentMonthDelta, digits: 2)) kg / ay")
                                .font(Typography.mono)
                        }
                    } else {
                        LabeledContent("Aylık tempo") {
                            Text("\(Fmt.signed(perMonth, digits: 2)) kg")
                                .font(Typography.mono)
                        }
                        LabeledContent("Haftalık tempo") {
                            Text("\(Fmt.signed(perWeek, digits: 2)) kg")
                                .font(Typography.mono)
                        }
                    }
                    if let warning = paceWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.warning)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Plan Oluştur")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Planı Oluştur") {
                        onCreate(Plan(
                            startDate: startDate,
                            startWeight: startWeightInput,
                            endWeight: endWeightInput,
                            months: monthsInput,
                            firstMonthTarget: paceMode == .customFirst ? firstMonthTarget : nil
                        ))
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 560, height: 680)
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
                            .fill(paceMode == mode ? Color.white.opacity(0.07) : Palette.surfaceElevated)
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
                                    .fill(monthsInput == m ? Color.white.opacity(0.07) : Palette.surfaceElevated)
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
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
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
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
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
        NavigationStack {
            Form {
                Section("Yemek") {
                    LabeledContent("Kayıt") {
                        Text(food.name)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                    LabeledContent("Kalori") {
                        Text("\(Fmt.int(food.calories)) kcal")
                    }
                }

                Section("Tarih") {
                    DatePicker(
                        "Tarih ve saat",
                        selection: $dateInput,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Hızlı düzeltme") {
                    Button("Seçili güne taşı: \(CalendarView.fullDayFormatter.string(from: selectedDay))") {
                        dateInput = Self.merged(day: selectedDay, time: dateInput)
                    }
                    Button("1 gün geri al") {
                        shiftDay(-1)
                    }
                    Button("1 gün ileri al") {
                        shiftDay(1)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Yemek Tarihi")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        onSave(dateInput)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 460, height: 360)
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
        NavigationStack {
            Form {
                Section("Hedef") {
                    DatePicker("Tarih", selection: $dateInput, displayedComponents: .date)
                    LabeledContent("Hedef kilo (kg)") {
                        TextField("", value: $weightInput, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                Section("Not") {
                    TextField("ör: yaza hazır", text: $noteInput, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Aylık Hedef")
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        goal.targetWeight = weightInput
                        goal.anchorDate = dateInput
                        let trimmed = noteInput.trimmingCharacters(in: .whitespaces)
                        goal.note = trimmed.isEmpty ? nil : trimmed
                        onSave()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 460, height: 380)
        .alert("Hedefi sil?", isPresented: $showDeleteConfirm) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) { onDelete() }
        }
    }
}
