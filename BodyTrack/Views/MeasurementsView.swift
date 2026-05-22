import SwiftUI
import SwiftData

struct MeasurementsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

    @State private var showingNew = false
    @State private var editingMeasurement: Measurement? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            header
            summaryStrip
            measurementList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        HStack(alignment: .bottom, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ölçümler").eyebrow()
                Text("Vücut Ölçümleri")
                    .font(Typography.display(40))
                    .foregroundStyle(Palette.textPrimary)
            }

            Spacer(minLength: Spacing.lg)

            HStack(spacing: Spacing.sm) {
                Button { /* future: export */ } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 34, height: 34)
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
                .help("Tüm ölçümleri JSON olarak dışa aktar")

                Button {
                    showingNew = true
                } label: {
                    Label("Yeni Ölçüm", systemImage: "plus")
                        .font(Typography.bodyBold)
                        .foregroundStyle(.black.opacity(0.88))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                .help("Yeni ölçüm ekle (⌘N)")
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            measurementsTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// Native macOS Table — sortable columns, multi-select, native row chrome.
    /// Double-click açar düzenleme sheet'ini.
    /// Sütun genişlikleri esnek — pencere geniş olduğunda büyürler.
    private var measurementsTable: some View {
        Table(measurements) {
            TableColumn("Tarih") { m in
                VStack(alignment: .leading, spacing: 1) {
                    Text(Fmt.dateLong.string(from: m.date))
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text(Self.timeFmt.string(from: m.date))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .width(min: 150, ideal: 200, max: 280)

            TableColumn("Ağırlık") { m in
                tableNumber(m.weight, unit: "kg")
            }
            .width(min: 80, ideal: 120)

            TableColumn("Yağ %") { m in
                tableNumber(m.bodyFat, unit: "%")
            }
            .width(min: 70, ideal: 100)

            TableColumn("Yağsız") { m in
                tableNumber(m.leanMass, unit: "kg")
            }
            .width(min: 80, ideal: 120)

            TableColumn("Bel") { m in
                tableNumber(m.waist, unit: "cm")
            }
            .width(min: 70, ideal: 100)

            TableColumn("Göğüs") { m in
                tableNumber(m.chest, unit: "cm")
            }
            .width(min: 70, ideal: 100)

            TableColumn("Boyun") { m in
                tableNumber(m.neck, unit: "cm")
            }
            .width(min: 70, ideal: 100)

            TableColumn("") { m in
                Button {
                    editingMeasurement = m
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.borderless)
            }
            .width(40)
        }
    }

    private func tableNumber(_ value: Double?, unit: String) -> some View {
        HStack(spacing: 3) {
            if let v = value {
                Text(Fmt.num(v, digits: 1))
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
            } else {
                Text("—")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f
    }()
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
        Fmt.timeShort.string(from: measurement.date)
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
    @State private var showExtra: Bool

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
            _showExtra = State(initialValue: false)
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
        return showExtra ? "Ölçüm Ekle" : "Tartı Ekle"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tarih") {
                    DatePicker("Ne zaman", selection: $date)
                }

                Section("Ağırlık") {
                    LabeledContent("Kilo (kg)") {
                        TextField("", value: $weight, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    if !showExtra {
                        Text("Vücut analizini (yağ %, çevreler) haftada bir kez ekleyebilirsin.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                if showExtra {
                    Section("Vücut Kompozisyonu") {
                        LabeledContent("Yağ oranı (%)") {
                            TextField("opsiyonel", value: $bodyFat, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        Link(destination: URL(string: "https://www.agirsaglam.com/vucut-yag-orani-hesaplama/")!) {
                            Label("Yağ oranı hesapla", systemImage: "ruler")
                                .font(Typography.caption)
                        }
                        .foregroundStyle(Palette.textSecondary)
                    }

                    Section("Gövde Çevreleri") {
                        LabeledContent("Bel (cm)") {
                            TextField("", value: $waist, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        LabeledContent("Göğüs (cm)") {
                            TextField("", value: $chest, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        LabeledContent("Boyun (cm)") {
                            TextField("", value: $neck, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showExtra.toggle()
                        }
                    } label: {
                        Label(
                            showExtra ? "Sadeleştir — sadece ağırlık" : "Vücut analizi ekle",
                            systemImage: showExtra ? "minus.circle" : "plus.circle"
                        )
                    }
                }

                Section("Not (opsiyonel)") {
                    TextField("ör: cardio sonrası, sabah aç karnına", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if isEditing, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Ölçümü Sil", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Ölçümü Düzenle" : (showExtra ? "Yeni Ölçüm" : "Hızlı Tartı"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        save()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 540, height: showExtra ? 700 : 460)
        .onAppear {
            if case .create = mode {
                date = .now
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
