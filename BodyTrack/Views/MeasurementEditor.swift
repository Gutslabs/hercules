import SwiftUI
import SwiftData

enum EditorMode {
    case create
    case edit(Measurement)
}

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

    @State private var date: Date
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var waist: Double?
    @State private var chest: Double?
    @State private var neck: Double?
    @State private var note: String
    @State private var showExtra: Bool
    @State private var confirmingDelete = false

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
            let hasExtra = m.bodyFat != nil || m.waist != nil || m.chest != nil || m.neck != nil
            _showExtra = State(initialValue: hasExtra)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var saveButtonTitle: String {
        if isEditing { return "Kaydet" }
        return showExtra ? "Tam Ölçüm Ekle" : "Tartı Ekle"
    }

    private var editorTitle: String {
        if isEditing { return "Ölçümü düzenle" }
        return showExtra ? "Tam ölçüm" : "Tartı ekle"
    }

    private var editorSubtitle: String {
        if showExtra {
            return "Kilo, yağ oranı ve çevre ölçülerini tek kayıtta topla."
        }
        return "Günlük akış için sadece kilo yeterli; detay alanları kapalı kalır."
    }

    private var modeHint: String {
        if showExtra {
            return "Haftalık ana kayıt: kilo + yağ % + bel + göğüs + boyun."
        }
        return "Hızlı tartı: kilo gir, devam et."
    }

    private var validationMessage: String? {
        if weight == nil {
            return "Kilo alanı gerekli."
        }

        if showExtra && bodyFat == nil && waist == nil && chest == nil && neck == nil {
            return "Tam ölçüm için en az bir detay alanı gir."
        }

        return nil
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var fatMass: Double? {
        guard let weight, let bodyFat else { return nil }
        return weight * bodyFat / 100
    }

    private var leanMass: Double? {
        guard let weight, let bodyFat else { return nil }
        return weight * (1 - bodyFat / 100)
    }

    private var editorWidth: CGFloat {
        showExtra ? 760 : 700
    }

    private var editorHeight: CGFloat {
        showExtra ? 720 : 620
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            Hairline()

            HStack(alignment: .top, spacing: Spacing.xl) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        modeSection
                        dateSection
                        weightSection

                        if showExtra {
                            fullMeasurementSection
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        noteSection
                    }
                    .padding(Spacing.xl)
                }
                .scrollContentBackground(.hidden)

                editorSummary
                    .frame(width: 230)
                    .padding(.top, Spacing.xl)
                    .padding(.trailing, Spacing.xl)
                    .padding(.bottom, Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Hairline()

            editorFooter
        }
        .frame(width: editorWidth, height: editorHeight)
        .background(editorBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.7)
        )
        .shadow(color: Palette.background.opacity(0.45), radius: 34, x: 0, y: 22)
        .preferredColorScheme(.dark)
        .onAppear {
            if case .create = mode {
                date = .now
            }
        }
        .confirmationDialog("Bu ölçüm silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Ölçümü Sil", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill((showExtra ? Palette.accent : Color.white).opacity(showExtra ? 0.16 : 0.07))
                    .frame(width: 46, height: 46)
                Image(systemName: showExtra ? "ruler" : "scalemass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(showExtra ? Palette.accent : Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isEditing ? "KAYIT" : "YENİ KAYIT")
                    .font(Typography.label)
                    .tracking(1)
                    .foregroundStyle(Palette.textQuaternary)
                Text(editorTitle)
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Text(editorSubtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: Spacing.lg)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(MeasurementPressButtonStyle())
            .foregroundStyle(Palette.textSecondary)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                Circle()
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    private var modeSection: some View {
        MeasurementEditorSection(
            title: "Kayıt modu",
            subtitle: modeHint,
            systemImage: showExtra ? "ruler" : "scalemass"
        ) {
            HStack(spacing: Spacing.sm) {
                MeasurementEditorModeButton(
                    title: "Tartı",
                    subtitle: "Sadece kilo",
                    systemImage: "scalemass",
                    selected: !showExtra
                ) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        showExtra = false
                    }
                }

                MeasurementEditorModeButton(
                    title: "Tam ölçüm",
                    subtitle: "Kilo + detay",
                    systemImage: "ruler",
                    selected: showExtra
                ) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        showExtra = true
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        MeasurementEditorSection(
            title: "Zaman",
            subtitle: "Kaydın tartıya çıktığın ana bağlansın.",
            systemImage: "calendar.badge.clock"
        ) {
            StyledDateField(label: "Tarih ve saat", date: $date)
        }
    }

    private var weightSection: some View {
        MeasurementEditorSection(
            title: "Tartı",
            subtitle: showExtra ? "Tam ölçümün merkez değeri." : "Günlük trend için tek zorunlu alan.",
            systemImage: "scalemass"
        ) {
            MeasurementEditorNumberField(
                label: "Kilo",
                unit: "kg",
                value: $weight,
                placeholder: "0.0",
                required: true
            )

            if !showExtra {
                Text("Yağ oranı ve çevreleri haftalık tam ölçümde aç.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    private var fullMeasurementSection: some View {
        MeasurementEditorSection(
            title: "Tam ölçüm",
            subtitle: "Detay alanları opsiyonel; en az birini doldurman yeterli.",
            systemImage: "ruler"
        ) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.md),
                    GridItem(.flexible(), spacing: Spacing.md)
                ],
                spacing: Spacing.md
            ) {
                MeasurementEditorNumberField(
                    label: "Yağ oranı",
                    unit: "%",
                    value: $bodyFat,
                    placeholder: "0.0"
                )
                MeasurementEditorNumberField(
                    label: "Bel",
                    unit: "cm",
                    value: $waist,
                    placeholder: "0.0"
                )
                MeasurementEditorNumberField(
                    label: "Göğüs",
                    unit: "cm",
                    value: $chest,
                    placeholder: "0.0"
                )
                MeasurementEditorNumberField(
                    label: "Boyun",
                    unit: "cm",
                    value: $neck,
                    placeholder: "0.0"
                )
            }

            Link(destination: URL(string: "https://www.agirsaglam.com/vucut-yag-orani-hesaplama/")!) {
                Label("Yağ oranı hesapla", systemImage: "arrow.up.right")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var noteSection: some View {
        MeasurementEditorSection(
            title: "Not",
            subtitle: "Koşul bilgisi ileride sapmaları okumayı kolaylaştırır.",
            systemImage: "text.alignleft"
        ) {
            TextField("ör: sabah aç karnına, antrenman sonrası", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(3...5)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        }
    }

    private var editorSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: 9) {
                BreathingStatusDot(color: canSave ? Palette.positive : Palette.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(canSave ? "Kayıt hazır" : "Eksik alan")
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text(showExtra ? "Tam ölçüm" : "Hızlı tartı")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                MeasurementEditorStat(label: "Kilo", value: weightText, unit: "kg")
                MeasurementEditorStat(label: "Yağ oranı", value: optionalText(bodyFat), unit: "%")

                if showExtra {
                    MeasurementEditorStat(label: "Yağsız kütle", value: optionalText(leanMass), unit: "kg")
                    MeasurementEditorStat(label: "Yağ kütlesi", value: optionalText(fatMass), unit: "kg")
                }
            }

            Hairline()

            VStack(alignment: .leading, spacing: 8) {
                Text("Alan durumu").eyebrow()
                MeasurementFieldStatus(label: "Tartı", filled: weight != nil)
                if showExtra {
                    MeasurementFieldStatus(label: "Yağ", filled: bodyFat != nil)
                    MeasurementFieldStatus(label: "Bel", filled: waist != nil)
                    MeasurementFieldStatus(label: "Göğüs", filled: chest != nil)
                    MeasurementFieldStatus(label: "Boyun", filled: neck != nil)
                }
            }

            Spacer(minLength: 0)

            Text(Fmt.dateLong.string(from: date))
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var editorFooter: some View {
        HStack(spacing: Spacing.md) {
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.warning)
                    .lineLimit(2)
            } else {
                Label(showExtra ? "Detaylı kayıt kaydedilecek." : "Hızlı tartı kaydedilecek.", systemImage: "checkmark.circle")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.positive)
            }

            Spacer(minLength: Spacing.md)

            if isEditing, onDelete != nil {
                Button {
                    confirmingDelete = true
                } label: {
                    Label("Sil", systemImage: "trash")
                        .font(Typography.bodyBold)
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                }
                .buttonStyle(MeasurementPressButtonStyle())
                .foregroundStyle(Palette.negative)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.negative.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Palette.negative.opacity(0.22), lineWidth: 0.5)
                )
            }

            Button("Vazgeç") {
                dismiss()
            }
            .font(Typography.bodyBold)
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)

            Button {
                guard canSave else { return }
                save()
                dismiss()
            } label: {
                Label(saveButtonTitle, systemImage: showExtra ? "ruler" : "scalemass")
                    .font(Typography.bodyBold)
                    .padding(.horizontal, 15)
                    .frame(height: 38)
            }
            .buttonStyle(MeasurementPressButtonStyle())
            .foregroundStyle(canSave ? Palette.background.opacity(0.92) : Palette.textQuaternary)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(canSave ? Palette.accent : Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(canSave ? Color.white.opacity(0.18) : Palette.border, lineWidth: 0.5)
            )
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    private var editorBackground: some View {
        ZStack(alignment: .topLeading) {
            Palette.surface
            LinearGradient(
                colors: [
                    (showExtra ? Palette.accent : Color.white).opacity(showExtra ? 0.14 : 0.055),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
    }

    private var weightText: String {
        guard let weight else { return "—" }
        return Fmt.num(weight, digits: 1)
    }

    private func optionalText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Fmt.num(value, digits: 1)
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedBodyFat = showExtra ? bodyFat : nil
        let savedWaist = showExtra ? waist : nil
        let savedChest = showExtra ? chest : nil
        let savedNeck = showExtra ? neck : nil

        switch mode {
        case .create:
            let m = Measurement(
                date: date,
                weight: weight,
                bodyFat: savedBodyFat,
                waist: savedWaist,
                chest: savedChest,
                neck: savedNeck,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            onSave(m)
        case .edit(let m):
            m.date = date
            m.weight = weight
            m.bodyFat = savedBodyFat
            m.waist = savedWaist
            m.chest = savedChest
            m.neck = savedNeck
            m.note = trimmedNote.isEmpty ? nil : trimmedNote
            onSave(m)
        }
    }
}

struct MeasurementEditorSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(Spacing.lg)
        .measurementPanel(cornerRadius: Radius.lg, fill: Palette.surface.opacity(0.62))
    }
}

struct MeasurementEditorModeButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? Palette.accent.opacity(0.16) : Color.white.opacity(0.045))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.bodyBold)
                    Text(subtitle)
                        .font(Typography.caption)
                        .opacity(0.7)
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Palette.accent : Palette.textQuaternary)
            }
            .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.055) : Palette.surfaceElevated.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.opacity(0.45) : Palette.border, lineWidth: 0.6)
            )
        }
        .buttonStyle(MeasurementPressButtonStyle())
    }
}

struct MeasurementEditorNumberField: View {
    let label: String
    let unit: String
    @Binding var value: Double?
    var placeholder: String
    var required = false

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(label).eyebrow()
                if required {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 4, height: 4)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                TextField(
                    placeholder,
                    value: $value,
                    format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))
                )
                .textFieldStyle(.plain)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
                .focused($focused)
                .multilineTextAlignment(.leading)

                Text(unit)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(focused ? Palette.accent.opacity(0.45) : Palette.border, lineWidth: 0.6)
            )
        }
    }
}

struct MeasurementEditorStat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.hero(25))
                    .foregroundStyle(value == "—" ? Palette.textQuaternary : Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .opacity(value == "—" ? 0 : 1)
                    .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MeasurementFieldStatus: View {
    let label: String
    let filled: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: filled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? Palette.positive : Palette.textQuaternary)
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(filled ? Palette.textSecondary : Palette.textTertiary)
            Spacer(minLength: 0)
        }
    }
}
