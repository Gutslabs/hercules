import SwiftUI
import SwiftData

enum EditorMode {
    case create
    case edit(Measurement)
}

/// Tartı ekle / Tam ölçüm — V1 dili, kompakt (560px).
/// İlkeler: mod seçimi segment (radio kart yok), tarih varsayılan GİZLİ
/// ("Bugün · 15:50" çipi — kaçırılan gün için tıklayıp açılır), sağ özet
/// paneli yok. Tek zorunlu alan: kilo; tam ölçümde detaylar opsiyonel.
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

    @State private var date: Date
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var waist: Double?
    @State private var chest: Double?
    @State private var neck: Double?
    @State private var note: String
    @State private var showExtra: Bool
    @State private var dateOpen = false
    @State private var confirmingDelete = false
    /// US Navy hesabı için boy — profilden gelir, yalnız bu kayıt için düzeltilebilir.
    @State private var heightLocal: Double? = nil
    /// false → yağ oranı bel+boyun+boydan otomatik; true → elle girilmiş değer korunur.
    @State private var bodyFatManual: Bool
    @FocusState private var weightFocused: Bool
    @FocusState private var bodyFatFocused: Bool

    private var fieldFill: Color { Palette.fieldFill }
    private var segPaper: Color { Palette.btnBg }
    private var segInk: Color { Palette.btnFg }

    private static let trLocale = Locale(identifier: "tr_TR")

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
        return showExtra ? "Tam Ölçüm Ekle" : "Tartı Ekle"
    }

    private var modeHint: String {
        showExtra ? "kilo zorunlu, detaylar opsiyonel" : "günlük akış için sadece kilo yeterli"
    }

    private var canSave: Bool {
        weight != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerRow
            dateRow

            numberField(label: "Kilo", unit: "kg", value: $weight, big: true, required: true)
                .focused($weightFocused)

            if showExtra {
                detailFields
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            footer
        }
        .padding(.init(top: 24, leading: 30, bottom: 20, trailing: 30))
        .frame(width: 560)
        .background(ZStack { Palette.background; Palette.surface })
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 40, y: 30)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showExtra)
        .animation(.easeInOut(duration: 0.16), value: dateOpen)
        // ↵ herhangi bir alandayken kaydeder (mockup: "↵ kaydet").
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

    // MARK: - Header (eyebrow + başlık · segment · kapat)

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "Kayıt" : "Yeni Kayıt").eyebrow()
                Text(editorTitle)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer(minLength: Spacing.md)
            modeSegment
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textQuaternary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Kapat (esc)")
        }
    }

    private var modeSegment: some View {
        HStack(spacing: 2) {
            segmentItem("Tartı", selected: !showExtra) { showExtra = false }
            segmentItem("Tam Ölçüm", selected: showExtra) { showExtra = true }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private func segmentItem(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(selected ? segInk : Palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? segPaper : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tarih (varsayılan gizli çip — tıklayınca gün gezgini)

    private var dateRow: some View {
        HStack(alignment: .center, spacing: 10) {
            if dateOpen {
                openDateChip
                Text(relativeDayHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            } else {
                collapsedDateChip
            }
            Spacer(minLength: Spacing.md)
            Text(modeHint)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var collapsedDateChip: some View {
        Button {
            dateOpen = true
        } label: {
            HStack(spacing: 7) {
                Text(shortDayLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Text(Fmt.timeShort.string(from: date))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Tarihi değiştir")
    }

    /// ‹ 9 Haziran › | saat — kaçırılan günü girmek için. Çip içerik boyunda
    /// sabittir (.fixedSize) — dar düzende metin asla harf harf kırılmaz.
    private var openDateChip: some View {
        HStack(spacing: 9) {
            Button { stepDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 14, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { dateOpen = false } label: {
                Text(Fmt.dayMonth.string(from: date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tarihi gizle")

            Button { stepDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(canStepForward ? Palette.textTertiary : Palette.textQuaternary.opacity(0.4))
                    .frame(width: 14, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canStepForward)

            Rectangle().fill(Palette.border).frame(width: 1, height: 12)

            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .controlSize(.small)
                .environment(\.locale, Self.trLocale)   // 24 saat (AM/PM değil)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.accent.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1)
        )
        .fixedSize()
    }

    private var shortDayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        return Fmt.dayMonth.string(from: date)
    }

    private var relativeDayHint: String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0:  return "bugünü giriyorsun"
        case 1:  return "dünü giriyorsun"
        default: return "\(days) gün öncesini giriyorsun"
        }
    }

    private var canStepForward: Bool {
        !Calendar.current.isDateInToday(date) && date < .now
    }

    private func stepDay(_ delta: Int) {
        guard let stepped = Calendar.current.date(byAdding: .day, value: delta, to: date) else { return }
        date = min(stepped, .now)
    }

    // MARK: - Alanlar

    private func numberField(
        label: String,
        unit: String,
        value: Binding<Double?>,
        big: Bool = false,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(label).eyebrow()
                if required {
                    Circle().fill(Palette.accent).frame(width: 4, height: 4)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                TextField(
                    "0,0",
                    value: value,
                    format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))
                )
                .textFieldStyle(.plain)
                .font(.system(size: big ? 22 : 14, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.leading)

                Text(unit)
                    .font(.system(size: big ? 12 : 10.5))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.horizontal, big ? 16 : 14)
            .padding(.vertical, big ? 12 : 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(required ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 1)
            )
        }
    }

    private var detailFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                numberField(label: "Bel", unit: "cm", value: $waist)
                numberField(label: "Boyun", unit: "cm", value: $neck)
                numberField(label: "Göğüs", unit: "cm", value: $chest)
                numberField(label: "Boy", unit: "cm", value: $heightLocal)
            }
            .onChange(of: waist) { _, _ in syncAutoBodyFat() }
            .onChange(of: neck) { _, _ in syncAutoBodyFat() }
            .onChange(of: heightLocal) { _, _ in syncAutoBodyFat() }

            bodyFatRow

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Not").eyebrow()
                TextField("ör: sabah aç karnına, antrenman sonrası", text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Yağ oranı (US Navy'den otomatik; kalemle manuel moda geçilir)

    private var bodyFatRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Yağ Oranı").eyebrow()
                if !bodyFatManual {
                    Text("oto · US Navy")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Palette.macroCarbs)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if bodyFatManual {
                    TextField(
                        "0,0",
                        value: $bodyFat,
                        format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .focused($bodyFatFocused)
                } else {
                    Text(bodyFat.map { Fmt.num($0, digits: 1) } ?? "0,0")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(bodyFat == nil ? Palette.textQuaternary : Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("%")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textQuaternary)
                Button {
                    toggleBodyFatMode()
                } label: {
                    Image(systemName: bodyFatManual ? "arrow.uturn.backward" : "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(bodyFatManual ? "Otomatik hesaba dön" : "Elle düzenle")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        !bodyFatManual && bodyFat != nil ? Palette.macroCarbs.opacity(0.3) : Palette.border,
                        lineWidth: 1
                    )
            )
            Text("bel + boyun + boy girilince US Navy formülüyle otomatik hesaplanır")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
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

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 12) {
                Text("↵ kaydet · esc vazgeç")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: Spacing.md)

                if isEditing, onDelete != nil {
                    Button {
                        confirmingDelete = true
                    } label: {
                        Text("Sil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.negative)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Ölçümü sil")
                }

                Button {
                    dismiss()
                } label: {
                    Text("Vazgeç")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    guard canSave else { return }
                    save()
                    dismiss()
                } label: {
                    Text(saveButtonTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.btnFg)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.accent))
                        .opacity(canSave ? 1 : 0.5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MeasurementPressButtonStyle())
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
    }

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
