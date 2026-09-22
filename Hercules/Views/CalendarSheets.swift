import SwiftUI
import LucideKit
import SwiftData

// Öğün Takip pencereleri — tasarım: "Hercules Mac Tasarımı" tuvali ▸ Pencereler · Beslenme (az yazı).

// MARK: - Plan oluştur

/// Aylık plan: solda başlangıç, şimdi/hedef kilo, süre ve tempo; sağda Grafikler dilinde ay ay
/// önizleme (üzerine gelince o ayın hedefi) ve aylık/haftalık tempo.
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
            case .even: return "Eşit"
            case .customFirst: return "İlk ay özel"
            }
        }
    }

    let startWeight: Double
    /// Mevcut aylık hedefler var mı — varsa oluşturmak onların yerini alır (altta uyarı).
    var replacesExisting = false
    let onCreate: (Plan) -> Void
    let onCancel: () -> Void

    @State private var startDate: Date = .now
    @State private var startWeightInput: Double
    @State private var endWeightInput: Double
    @State private var monthsInput: Int = 12
    @State private var paceMode: PaceMode = .even
    @State private var firstMonthTarget: Double = 0
    @State private var firstMonthTargetEdited: Bool = false
    @State private var hover: TrendPoint?

    init(startWeight: Double, replacesExisting: Bool = false, onCreate: @escaping (Plan) -> Void, onCancel: @escaping () -> Void) {
        self.startWeight = startWeight
        self.replacesExisting = replacesExisting
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

    /// Başlangıç + her ay sonunun hedefi (önizleme çizgisi).
    private var planPoints: [TrendPoint] {
        let cal = Calendar.current
        var out = [TrendPoint(date: startDate, value: startWeightInput)]
        for m in 1...max(1, monthsInput) {
            let date = cal.date(byAdding: .month, value: m, to: startDate) ?? startDate
            let value = paceMode == .customFirst
                ? firstMonthTarget + subsequentMonthDelta * Double(m - 1)
                : startWeightInput + perMonth * Double(m)
            out.append(TrendPoint(date: date, value: value))
        }
        return out
    }

    var body: some View {
        SadeSheet(title: "Plan oluştur", onClose: onCancel) {
            HStack(alignment: .top, spacing: 0) {
                inputs
                    .frame(width: 360)
                SadeRule(vertical: true)
                preview
            }
            .overlay(alignment: .top) { SadeRule() }
            .padding(.top, 18)
        } footerLeading: {
            if replacesExisting {
                SadeNote(text: "Mevcut plan değişir")
            }
        } footerTrailing: {
            SadeButton(title: "İptal", action: onCancel)
            SadeButton(title: "Planı oluştur", role: .primary) {
                onCreate(Plan(
                    startDate: startDate,
                    startWeight: startWeightInput,
                    endWeight: endWeightInput,
                    months: monthsInput,
                    firstMonthTarget: paceMode == .customFirst ? firstMonthTarget : nil
                ))
            }
        }
        .frame(width: 880)
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

    // MARK: Sol: girişler

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 18) {
            SadeDateField(label: "Başlangıç", date: $startDate)
            HStack(spacing: 12) {
                weightField("Şimdi", $startWeightInput)
                weightField("Hedef", $endWeightInput)
            }
            VStack(alignment: .leading, spacing: 8) {
                label("Süre")
                HStack(spacing: 8) {
                    SadeStepper(unit: "ay", width: 140) {
                        monthsInput = max(1, monthsInput - 1)
                    } increment: {
                        monthsInput = min(36, monthsInput + 1)
                    } field: {
                        TextField("", value: Binding(get: { monthsInput }, set: { monthsInput = max(1, min(36, $0)) }), format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .frame(width: 30)
                    }
                    ForEach([3, 6, 12], id: \.self) { m in
                        SadePill(title: "\(m)", selected: monthsInput == m, help: "\(m) ay") { monthsInput = m }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                label("Tempo")
                SadeSegmented(options: PaceMode.allCases.map { (value: $0, label: $0.label) }, selection: $paceMode)
                if paceMode == .customFirst {
                    weightField("İlk ay sonu", Binding(
                        get: { firstMonthTarget },
                        set: { firstMonthTarget = $0; firstMonthTargetEdited = true }
                    ))
                    .padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    // MARK: Sağ: önizleme (Grafikler dili)

    private var preview: some View {
        let points = planPoints
        let shown = hover ?? points[points.count - 1]
        let change = shown.value - startWeightInput
        let tint = paceWarning == nil ? Palette.positive : Palette.warning
        let parts = SadeFormat.num(shown.value).split(separator: ",", maxSplits: 1).map(String.init)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(parts.first ?? "")
                    .foregroundStyle(Palette.textPrimary)
                Text(parts.count > 1 ? ",\(parts[1])" : "")
                    .foregroundStyle(Palette.textTertiary)
                Text("kg")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.leading, 6)
            }
            .font(.system(size: 34, weight: .semibold).monospacedDigit())
            .tracking(-0.8)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(SadeFormat.signed(change)) kg")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                Text(hover.map { Fmt.dateMonthAxis.string(from: $0.date) } ?? "\(monthsInput) ayda")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.top, 4)

            SadeLineChart(points: points, tint: tint) { hover = $0 }
                .frame(height: 150)
                .padding(.top, 14)

            HStack(alignment: .top, spacing: 12) {
                if paceMode == .customFirst {
                    stat("İlk ay", SadeFormat.signed(firstMonthDelta), "kg")
                    stat("Sonra", SadeFormat.signed(subsequentMonthDelta, digits: 2), "kg/ay")
                } else {
                    stat("Aylık", SadeFormat.signed(perMonth, digits: 2), "kg")
                    stat("Haftalık", SadeFormat.signed(perWeek, digits: 2), "kg")
                }
            }
            .padding(.top, 16)

            if let warning = paceWarning {
                SadeNote(text: warning)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func stat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                Text(unit)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.textTertiary)
    }

    private func weightField(_ title: String, _ value: Binding<Double>) -> some View {
        SadeField(label: title) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 14).monospacedDigit())
                .fixedSize()
            Text("kg")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    private func roundedHalf(_ v: Double) -> Double {
        (v * 2).rounded() / 2
    }

    private var paceWarning: String? {
        if paceMode == .customFirst {
            // İlk ay totalDelta'yı geçtiyse / yön ters dönüyorsa uyarı
            if totalDelta != 0, firstMonthDelta != 0,
               firstMonthDelta.sign != totalDelta.sign {
                return "İlk ay hedefin tersine gidiyor"
            }
            if abs(firstMonthDelta) > abs(totalDelta) {
                return "İlk ay toplam hedefi aşıyor"
            }
            if abs(firstMonthDelta / 4.345) > 1.0 {
                return "İlk ay haftada 1 kg üstü — agresif"
            }
            if abs(subsequentPerWeek) > 1.0 {
                return "Sonraki aylar haftada 1 kg üstü — agresif"
            }
        } else {
            if abs(perWeek) > 1.0 {
                return "Haftada 1 kg üstü — agresif"
            }
        }
        return nil
    }
}

// MARK: - Yemek tarihi

/// Bir yemeğin gününü/saatini değiştirir: üstte eski → yeni, altında tarih ve saat, en altta
/// "‹ 1 gün · seçili gün · 1 gün ›".
struct FoodDateEditorSheet: View {
    let food: FoodEntry
    let selectedDay: Date
    let onSave: (Date) -> Void
    let onCancel: () -> Void

    @State private var dateInput: Date
    private let original: Date

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
        original = food.date
    }

    var body: some View {
        SadeSheet(title: "Yemek tarihi", subtitle: food.name, onClose: onCancel) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    moment(original, active: false)
                    Lucide(sf: "arrow.right", size: 15)
                        .foregroundStyle(Palette.textTertiary)
                    moment(dateInput, active: dateInput != original)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    SadeDateField(label: "Tarih", date: $dateInput)
                    SadeTimeField(label: "Saat", date: $dateInput)
                        .frame(width: 120)
                }
                .padding(.top, 18)
                HStack(spacing: 8) {
                    SadePill(title: "1 gün", leading: "chevron.left", help: "1 gün geri") { shiftDay(-1) }
                    SadePill(title: Self.dayLabel.string(from: selectedDay),
                             selected: Calendar.current.isDate(dateInput, inSameDayAs: selectedDay),
                             help: "Takvimde seçili güne taşı") {
                        dateInput = Self.merged(day: selectedDay, time: dateInput)
                    }
                    SadePill(title: "1 gün", trailing: "chevron.right", help: "1 gün ileri") { shiftDay(1) }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 24)
        } footerLeading: {
            EmptyView()
        } footerTrailing: {
            SadeButton(title: "İptal", action: onCancel)
            SadeButton(title: "Kaydet", role: .primary) { onSave(dateInput) }
        }
        .frame(width: 520)
    }

    /// "21 Eyl Pzt   20:10" kartı; yeni değer değiştiyse yeşil çerçeve.
    private func moment(_ date: Date, active: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.dayLabel.string(from: date))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Palette.textPrimary : Palette.textTertiary)
            Spacer(minLength: 8)
            Text(SadeTimeField.formatter.string(from: date))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(active ? Palette.textSecondary : Palette.textTertiary)
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(active ? Palette.positive.opacity(0.07) : Palette.textPrimary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(active ? Palette.positive.opacity(0.35) : Palette.textPrimary.opacity(0.06), lineWidth: 1))
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

    /// "22 Eyl Sal"
    private static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM EEE"
        return f
    }()
}

// MARK: - Aylık hedef

/// Ayın hedef kilosu: tarih, −/+ ile hedef (yanında son tartıya göre fark) ve not.
struct GoalEditorSheet: View {
    @Bindable var goal: MonthlyGoal
    let onSave: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

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
        SadeSheet(title: "Aylık hedef", onClose: onCancel) {
            VStack(alignment: .leading, spacing: 18) {
                SadeDateField(label: "Tarih", date: $dateInput)
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hedef")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.textTertiary)
                        SadeStepper(unit: "kg", width: 220) {
                            weightInput = max(30, weightInput - 0.5)
                        } increment: {
                            weightInput += 0.5
                        } field: {
                            TextField("", value: $weightInput, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                                .multilineTextAlignment(.center)
                                .frame(width: 64)
                        }
                    }
                    if let current = measurements.first?.weight {
                        let delta = weightInput - current
                        Text("\(SadeFormat.signed(delta)) kg")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(delta <= 0 ? Palette.positive : Palette.textTertiary)
                            .help("Son tartıya göre")
                            .padding(.bottom, 12)
                    }
                }
                SadeTextArea(label: "Not", text: $noteInput, lines: 1...3, minHeight: 38)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        } footerLeading: {
            // Yıkıcı eylem SOLDA — Kaydet'in dibinde olsa yanlışlıkla tıklanırdı.
            SadeButton(title: "Sil", role: .destructive) { showDeleteConfirm = true }
        } footerTrailing: {
            SadeButton(title: "İptal", action: onCancel)
            SadeButton(title: "Kaydet", role: .primary) {
                goal.targetWeight = weightInput
                goal.anchorDate = dateInput
                let trimmed = noteInput.trimmingCharacters(in: .whitespaces)
                goal.note = trimmed.isEmpty ? nil : trimmed
                onSave()
            }
        }
        .frame(width: 480)
        .alert("Hedefi sil?", isPresented: $showDeleteConfirm) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) { onDelete() }
        }
    }
}
