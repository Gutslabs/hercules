import SwiftUI
import SwiftData

struct MeasurementsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

    @State private var showingNew = false
    @State private var editingMeasurement: Measurement? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header
                summaryStrip
                measurementList
                Spacer(minLength: 24)
            }
            .padding(Spacing.xxl)
        }
        .background(Palette.background.ignoresSafeArea())
        .sheet(isPresented: $showingNew) {
            MeasurementEditor(mode: .create) { m in
                ctx.insert(m)
                try? ctx.save()
            }
        }
        .sheet(item: $editingMeasurement) { m in
            MeasurementEditor(mode: .edit(m)) { _ in
                try? ctx.save()
            } onDelete: {
                ctx.delete(m)
                try? ctx.save()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ölçümler").eyebrow()
                Text("Vücut Ölçümleri")
                    .font(Typography.display(40))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            HStack(spacing: 8) {
                GhostButton(title: "Tümünü Dışa Aktar", systemImage: "square.and.arrow.up") {}
                    .frame(width: 180)
                PrimaryButton(title: "Yeni Ölçüm", systemImage: "plus") {
                    showingNew = true
                }
                .frame(width: 150)
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: Spacing.md) {
            SummaryStat(label: "Toplam Ölçüm", value: "\(measurements.count)")
            SummaryStat(label: "İlk Ölçüm", value: measurements.last.map { Fmt.date.string(from: $0.date) } ?? "—")
            SummaryStat(label: "Son Ölçüm", value: measurements.first.map { Fmt.date.string(from: $0.date) } ?? "—")
            SummaryStat(label: "Bu Ay", value: "\(measurementsThisMonth)")
        }
    }

    private var measurementsThisMonth: Int {
        let cal = Calendar.current
        let now = Date()
        return measurements.filter {
            cal.isDate($0.date, equalTo: now, toGranularity: .month)
        }.count
    }

    @ViewBuilder
    private var measurementList: some View {
        if measurements.isEmpty {
            EmptyMeasurementState { showingNew = true }
        } else {
            VStack(spacing: 0) {
                listHeader
                Hairline()
                ForEach(measurements) { m in
                    MeasurementRow(measurement: m)
                        .contentShape(Rectangle())
                        .onTapGesture { editingMeasurement = m }
                    if m.id != measurements.last?.id {
                        Hairline()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
        }
    }

    private var listHeader: some View {
        HStack(spacing: 0) {
            cell("Tarih", width: 130, align: .leading)
            cell("Ağırlık", align: .trailing)
            cell("Yağ %", align: .trailing)
            cell("Yağsız", align: .trailing)
            cell("Bel", align: .trailing)
            cell("Göğüs", align: .trailing)
            cell("Boyun", align: .trailing)
            cell(" ", width: 28, align: .trailing)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
    }

    private func cell(_ text: String, width: CGFloat? = nil, align: Alignment) -> some View {
        Text(text)
            .font(Typography.label)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: width ?? .infinity, alignment: align)
    }
}

struct SummaryStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow()
            Text(value)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
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

struct MeasurementRow: View {
    let measurement: Measurement
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.dateLong.string(from: measurement.date))
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Text(timeString)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(width: 130, alignment: .leading)
            valueCell(measurement.weight, unit: "kg")
            valueCell(measurement.bodyFat, unit: "%")
            valueCell(measurement.leanMass, unit: "kg")
            valueCell(measurement.waist, unit: "cm")
            valueCell(measurement.chest, unit: "cm")
            valueCell(measurement.neck, unit: "cm")
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? Palette.textSecondary : Palette.textQuaternary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .background(hovering ? Color.white.opacity(0.025) : Color.clear)
        .onHover { hovering = $0 }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f.string(from: measurement.date)
    }

    private func valueCell(_ value: Double?, unit: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(Fmt.numOpt(value, digits: 1))
                .font(Typography.mono)
                .foregroundStyle(value == nil ? Palette.textQuaternary : Palette.textPrimary)
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
                .opacity(value == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct EmptyMeasurementState: View {
    var action: () -> Void
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "ruler")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("Henüz ölçüm yok")
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
            PrimaryButton(title: "İlk ölçümü ekle", systemImage: "plus", action: action)
                .frame(width: 220)
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

enum EditorMode {
    case create
    case edit(Measurement)
}

struct MeasurementEditor: View {
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

    init(mode: EditorMode, onSave: @escaping (Measurement) -> Void, onDelete: (() -> Void)? = nil) {
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
        case .edit(let m):
            _date = State(initialValue: m.date)
            _weight = State(initialValue: m.weight)
            _bodyFat = State(initialValue: m.bodyFat)
            _waist = State(initialValue: m.waist)
            _chest = State(initialValue: m.chest)
            _neck = State(initialValue: m.neck)
            _note = State(initialValue: m.note ?? "")
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                editorHeader
                dateCard
                section(title: "Vücut Kompozisyonu") {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        grid {
                            LabeledNumberField(label: "Ağırlık", unit: "kg", value: $weight)
                            LabeledNumberField(label: "Yağ Oranı", unit: "%", value: $bodyFat)
                        }
                        Link(destination: URL(string: "https://www.agirsaglam.com/vucut-yag-orani-hesaplama/")!) {
                            HStack(spacing: 5) {
                                Image(systemName: "ruler").font(.system(size: 10))
                                Text("Yağ oranı hesapla").font(Typography.caption)
                                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                section(title: "Gövde Çevreleri") {
                    grid {
                        LabeledNumberField(label: "Bel", unit: "cm", value: $waist)
                        LabeledNumberField(label: "Göğüs", unit: "cm", value: $chest)
                        LabeledNumberField(label: "Boyun", unit: "cm", value: $neck)
                    }
                }
                noteCard
                actionRow
            }
            .padding(Spacing.xxl)
        }
        .frame(width: 720, height: 760)
        .background(Palette.background.ignoresSafeArea())
        .onAppear {
            if case .create = mode {
                date = .now
            }
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isEditing ? "Düzenle" : "Yeni Ölçüm").eyebrow()
                Text(isEditing ? "Ölçümü Güncelle" : "Yeni Ölçüm Ekle")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.surfaceElevated))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var dateCard: some View {
        Card(padding: Spacing.lg) {
            StyledDateField(label: "Tarih", date: $date)
        }
    }

    private var noteCard: some View {
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not (opsiyonel)").eyebrow()
                TextEditor(text: $note)
                    .scrollContentBackground(.hidden)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(minHeight: 70)
                    .padding(8)
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
    }

    private var actionRow: some View {
        HStack(spacing: Spacing.md) {
            if isEditing, let onDelete {
                Button {
                    onDelete()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Sil")
                            .font(Typography.bodyBold)
                    }
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Palette.negative)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(Palette.negative.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .strokeBorder(Palette.negative.opacity(0.20), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            GhostButton(title: "İptal", action: { dismiss() })
            PrimaryButton(title: isEditing ? "Kaydet" : "Ekle", systemImage: "checkmark") {
                save()
                dismiss()
            }
        }
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .create:
            let m = Measurement(
                date: date, weight: weight, bodyFat: bodyFat,
                waist: waist, chest: chest, neck: neck,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            onSave(m)
        case .edit(let m):
            m.date = date
            m.weight = weight
            m.bodyFat = bodyFat
            m.waist = waist
            m.chest = chest
            m.neck = neck
            m.note = trimmedNote.isEmpty ? nil : trimmedNote
            onSave(m)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(title).eyebrow()
                content()
            }
        }
    }

    @ViewBuilder
    private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
            spacing: Spacing.md
        ) {
            content()
        }
    }
}
