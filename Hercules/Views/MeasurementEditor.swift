import SwiftUI
import LucideKit
import SwiftData

enum EditorMode {
    case create
    case edit(Measurement)
}

/// Tartı ekle / Tam ölçüm — tasarım: tuval ▸ Pencereler · Veriler (az yazı). Üstte mod + tarih
/// (‹ gün ›, saat); Tartı'da büyük kilo girişi (−/+ 0,1), düne göre fark ve son 30 günün Grafikler
/// dilindeki eğrisi (yazılan değer ucunda); Tam ölçümde kilo, çevreler, US Navy yağ oranı ve not.
/// Tek zorunlu alan: kilo.
struct MeasurementEditor: View {
    enum CreateKind {
        case smart
        case quick
        case full
    }

    let mode: EditorMode
    var onSave: (Measurement) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

    @State private var date: Date
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var waist: Double?
    @State private var chest: Double?
    @State private var neck: Double?
    @State private var note: String
    @State private var showExtra: Bool
    @State private var pickingDay = false
    @State private var pickingTime = false
    @State private var confirmingDelete = false
    @State private var chartHover: TrendPoint?
    /// US Navy hesabı için boy — profilden gelir, yalnız bu kayıt için düzeltilebilir.
    @State private var heightLocal: Double? = nil
    /// false → yağ oranı bel+boyun+boydan otomatik; true → elle girilmiş değer korunur.
    @State private var bodyFatManual: Bool
    @FocusState private var weightFocused: Bool
    @FocusState private var bodyFatFocused: Bool

    private static let trLocale = Locale(identifier: "tr_TR")
    private static let numberFormat = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))

    init(
        mode: EditorMode,
        createKind: CreateKind = .smart,
        onSave: @escaping (Measurement) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .create:
            _date = State(initialValue: .now)
            _weight = State(initialValue: nil)
            _bodyFat = State(initialValue: nil)
            _waist = State(initialValue: nil)
            _chest = State(initialValue: nil)
            _neck = State(initialValue: nil)
            _note = State(initialValue: "")
            _bodyFatManual = State(initialValue: false)
            let shouldShowExtra: Bool
            switch createKind {
            case .smart:
                shouldShowExtra = MeasurementCadence.isFullCheckInDay()
            case .quick:
                shouldShowExtra = false
            case .full:
                shouldShowExtra = true
            }
            _showExtra = State(initialValue: shouldShowExtra)
        case .edit(let m):
            _date = State(initialValue: m.date)
            _weight = State(initialValue: m.weight)
            _bodyFat = State(initialValue: m.bodyFat)
            _waist = State(initialValue: m.waist)
            _chest = State(initialValue: m.chest)
            _neck = State(initialValue: m.neck)
            _note = State(initialValue: m.note ?? "")
            // Kayıtlı yağ oranı varsa otomatik hesap üstüne yazmasın.
            _bodyFatManual = State(initialValue: m.bodyFat != nil)
            // Not da detay alanında yaşıyor — notu olan kayıt tam ölçüm görünümüyle açılsın.
            let hasExtra = m.bodyFat != nil || m.waist != nil || m.chest != nil || m.neck != nil
                || !(m.note ?? "").isEmpty
            _showExtra = State(initialValue: hasExtra)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editorTitle: String {
        if isEditing { return "Ölçümü düzenle" }
        return showExtra ? "Tam ölçüm" : "Tartı ekle"
    }

    private var saveButtonTitle: String {
        if isEditing { return "Kaydet" }
        return showExtra ? "Tam ölçüm ekle" : "Tartı ekle"
    }

    private var canSave: Bool {
        weight != nil
    }

    /// Düzenlenen kayıt hariç, bu kaydın tarihinden önceki ölçümler (yeniden eskiye).
    private var earlier: [Measurement] {
        let editing: Measurement? = { if case .edit(let m) = mode { return m } else { return nil } }()
        return measurements.filter { $0 !== editing && $0.date < date }
    }

    private var lowerIsBetter: Bool { (profiles.first?.goal.calorieAdjustment ?? 0) <= 0 }

    var body: some View {
        SadeSheet(title: editorTitle, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                modeRow
                if showExtra {
                    fullFields
                        .transition(.opacity)
                } else {
                    quickFields
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        } footerLeading: {
            if isEditing, onDelete != nil {
                SadeButton(title: "Sil", role: .destructive) { confirmingDelete = true }
            }
        } footerTrailing: {
            SadeButton(title: "Vazgeç") { dismiss() }
            SadeButton(title: saveButtonTitle, role: .primary, enabled: canSave) {
                save()
                dismiss()
            }
        }
        .frame(width: 660)
        .animation(.easeInOut(duration: 0.18), value: showExtra)
        // ↵ herhangi bir alandayken kaydeder.
        .onSubmit {
            if canSave { save(); dismiss() }
        }
        .onAppear {
            if heightLocal == nil { heightLocal = profiles.first?.height }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { weightFocused = true }
        }
        .confirmationDialog("Bu ölçüm silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Ölçümü Sil", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    // MARK: - Üst: mod + tarih

    private var modeRow: some View {
        HStack(spacing: 12) {
            SadeSegmented(options: [(value: false, label: "Tartı"), (value: true, label: "Tam ölçüm")], selection: $showExtra)
                .frame(width: 220)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                stepButton("chevron.left", help: "Önceki gün", enabled: true) { stepDay(-1) }
                Button { pickingDay = true } label: {
                    HStack(spacing: 8) {
                        Lucide(sf: "calendar", size: 13)
                            .foregroundStyle(Palette.textTertiary)
                        Text(shortDayLabel)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .sadeBox(radius: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Tarihi değiştir")
                .popover(isPresented: $pickingDay, arrowEdge: .bottom) {
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .environment(\.locale, Self.trLocale)
                        .padding(12)
                }
                stepButton("chevron.right", help: "Sonraki gün", enabled: canStepForward) { stepDay(1) }
                Button { pickingTime = true } label: {
                    HStack(spacing: 8) {
                        Text(Fmt.timeShort.string(from: date))
                            .font(.system(size: 14).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                        Lucide(sf: "clock", size: 12)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .sadeBox(radius: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Saati değiştir")
                .padding(.leading, 6)
                .popover(isPresented: $pickingTime, arrowEdge: .bottom) {
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.stepperField)
                        .labelsHidden()
                        .environment(\.locale, Self.trLocale)   // 24 saat (AM/PM değil)
                        .padding(12)
                }
            }
        }
    }

    private func stepButton(_ icon: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Lucide(sf: icon, size: 13)
                .foregroundStyle(enabled ? Palette.textSecondary : Palette.textQuaternary)
                .frame(width: 30, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private var shortDayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        return Fmt.dayMonth.string(from: date)
    }

    private var canStepForward: Bool {
        !Calendar.current.isDateInToday(date) && date < .now
    }

    private func stepDay(_ delta: Int) {
        guard let stepped = Calendar.current.date(byAdding: .day, value: delta, to: date) else { return }
        date = min(stepped, .now)
    }

    // MARK: - Tartı: büyük kilo + eğri

    private var quickFields: some View {
        VStack(spacing: 0) {
            HStack(spacing: 26) {
                SadeRoundButton(icon: "minus", help: "0,1 kg azalt") { nudge(-0.1) }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("", value: $weight, format: Self.numberFormat, prompt: Text("0,0").foregroundStyle(Palette.textQuaternary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 60, weight: .semibold).monospacedDigit())
                        .tracking(-1.5)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize()
                        .frame(minWidth: 90)
                        .focused($weightFocused)
                    Text("kg")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.textTertiary)
                }
                SadeRoundButton(icon: "plus", help: "0,1 kg artır") { nudge(0.1) }
            }
            .padding(.top, 30)
            changeLine
                .padding(.top, 10)
            SadeLineChart(points: chartPoints, tint: chartTint) { chartHover = $0 }
                .frame(height: 92)
                .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
    }

    /// Düne (bir önceki tartıya) göre fark; eğride imleç varsa o günün değeri.
    @ViewBuilder private var changeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let hover = chartHover {
                Text("\(SadeFormat.num(hover.value)) kg")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                Text(Fmt.dateMonthAxis.string(from: hover.date))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
            } else if let weight, let previous = earlier.first(where: { $0.weight != nil }), let prev = previous.weight {
                let delta = weight - prev
                Text("\(SadeFormat.signed(delta)) kg")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(SadeLineChart.tint(change: delta, lowerIsBetter: lowerIsBetter))
                Text(relativeLabel(previous.date))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                Text(" ")
                    .font(.system(size: 13))
            }
        }
        .lineLimit(1)
    }

    private func relativeLabel(_ previous: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: previous), to: cal.startOfDay(for: date)).day ?? 0
        return days == 1 ? "dün" : Fmt.dateMonthAxis.string(from: previous)
    }

    /// Son 30 günün 7 günlük ortalaması (Grafikler kilo eğrisi); yazılan değer ucunda.
    private var chartPoints: [TrendPoint] {
        let cal = Calendar.current
        guard let from = cal.date(byAdding: .day, value: -30, to: date),
              let windowStart = cal.date(byAdding: .day, value: -37, to: date) else { return [] }
        var raw = earlier
            .filter { $0.date >= windowStart }
            .compactMap { m in m.weight.map { TrendPoint(date: m.date, value: $0) } }
            .sorted { $0.date < $1.date }
        if let weight { raw.append(TrendPoint(date: date, value: weight)) }
        return TrendAnalysis.trailingAverage(raw, windowDays: 7).filter { $0.date >= from }
    }

    private var chartTint: Color {
        let pts = chartPoints
        guard let first = pts.first, let last = pts.last else { return Palette.textTertiary }
        return SadeLineChart.tint(change: last.value - first.value, lowerIsBetter: lowerIsBetter)
    }

    private func nudge(_ step: Double) {
        let base = weight ?? earlier.first(where: { $0.weight != nil })?.weight ?? 80
        weight = ((base + step) * 10).rounded() / 10
    }

    // MARK: - Tam ölçüm

    private var fullFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kilo")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                    SadeStepper(unit: "kg", width: 220) { nudge(-0.1) } increment: { nudge(0.1) } field: {
                        TextField("", value: $weight, format: Self.numberFormat, prompt: Text("0,0").foregroundStyle(Palette.textQuaternary))
                            .textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .semibold).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .frame(width: 70)
                            .focused($weightFocused)
                    }
                }
                changeLine
                    .padding(.bottom, 12)
            }
            .padding(.top, 20)

            HStack(spacing: 12) {
                numberField("Bel", unit: "cm", value: $waist)
                numberField("Boyun", unit: "cm", value: $neck)
                numberField("Göğüs", unit: "cm", value: $chest)
                numberField("Boy", unit: "cm", value: $heightLocal)
            }
            .padding(.top, 20)
            .onChange(of: waist) { _, _ in syncAutoBodyFat() }
            .onChange(of: neck) { _, _ in syncAutoBodyFat() }
            .onChange(of: heightLocal) { _, _ in syncAutoBodyFat() }

            bodyFatCard
                .padding(.top, 20)

            SadeField(label: "Not") {
                TextField("", text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
            }
            .padding(.top, 18)
        }
    }

    private func numberField(_ label: String, unit: String, value: Binding<Double?>) -> some View {
        SadeField(label: label) {
            TextField("", value: value, format: Self.numberFormat)
                .textFieldStyle(.plain)
                .font(.system(size: 14).monospacedDigit())
                .fixedSize()
            Text(unit)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Yağ oranı (US Navy'den otomatik; kalemle manuel moda geçilir)

    private var bodyFatCard: some View {
        let previous = earlier.first(where: { $0.bodyFat != nil })?.bodyFat
        let hasAuto = !bodyFatManual && bodyFat != nil
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Yağ oranı")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if bodyFatManual {
                        TextField("", value: $bodyFat, format: Self.numberFormat, prompt: Text("0,0").foregroundStyle(Palette.textQuaternary))
                            .textFieldStyle(.plain)
                            .font(.system(size: 28, weight: .semibold).monospacedDigit())
                            .fixedSize()
                            .frame(minWidth: 40, alignment: .leading)
                            .focused($bodyFatFocused)
                    } else {
                        Text(bodyFat.map { SadeFormat.num($0) } ?? "–")
                            .font(.system(size: 28, weight: .semibold).monospacedDigit())
                            .foregroundStyle(bodyFat == nil ? Palette.textQuaternary : Palette.textPrimary)
                    }
                    Text("%")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textTertiary)
                    if let bodyFat, let previous {
                        let delta = bodyFat - previous
                        Text(SadeFormat.signed(delta))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(SadeLineChart.tint(change: delta, lowerIsBetter: true))
                            .help("Önceki tam ölçüme göre")
                    }
                }
            }
            Spacer(minLength: 8)
            if !bodyFatManual {
                SadeChip(text: "oto")
                    .help("Bel, boyun ve boydan (US Navy)")
            }
            SadeIconButton(sf: bodyFatManual ? "arrow.uturn.backward" : "pencil",
                           help: bodyFatManual ? "Otomatik hesaba dön" : "Elle düzenle", size: 34) {
                toggleBodyFatMode()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(hasAuto ? Palette.positive.opacity(0.07) : Palette.textPrimary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(hasAuto ? Palette.positive.opacity(0.18) : Palette.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private func toggleBodyFatMode() {
        if bodyFatManual {
            bodyFatManual = false
            syncAutoBodyFat()
        } else {
            bodyFatManual = true
            if bodyFat == nil { bodyFat = navyBodyFat }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { bodyFatFocused = true }
        }
    }

    // MARK: - US Navy yağ oranı (erkek formülü; boy profilden gelir)

    private var navyBodyFat: Double? {
        guard let waist, let neck, waist > neck,
              let h = heightLocal ?? profiles.first?.height, h > 0 else { return nil }
        let bf = 495.0 / (1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(h)) - 450.0
        guard bf.isFinite else { return nil }
        return (min(max(bf, 2), 60) * 10).rounded() / 10
    }

    private func syncAutoBodyFat() {
        guard !bodyFatManual else { return }
        bodyFat = navyBodyFat
    }

    // MARK: - Footer

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedBodyFat = showExtra ? bodyFat : nil
        let savedWaist = showExtra ? waist : nil
        let savedChest = showExtra ? chest : nil
        let savedNeck = showExtra ? neck : nil
        // Not her modda korunur — tartı modunda alan gizli ama mevcut not silinmez.
        let savedNote = trimmedNote.isEmpty ? nil : trimmedNote

        switch mode {
        case .create:
            let m = Measurement(
                date: date,
                weight: weight,
                bodyFat: savedBodyFat,
                waist: savedWaist,
                chest: savedChest,
                neck: savedNeck,
                note: savedNote
            )
            onSave(m)
        case .edit(let m):
            m.date = date
            m.weight = weight
            m.bodyFat = savedBodyFat
            m.waist = savedWaist
            m.chest = savedChest
            m.neck = savedNeck
            m.note = savedNote
            onSave(m)
        }
    }
}
