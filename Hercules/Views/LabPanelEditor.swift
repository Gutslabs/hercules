import SwiftUI
import SwiftData
import LucideKit

/// Elle panel girişi / düzenleme — tasarım: tuval ▸ Pencereler · Veriler (az yazı). PDF akışının
/// yedeği: tek bir değeri düzeltmek, eksik bir parametre eklemek ya da PDF'i olmayan bir tahlili
/// girmek için. Her satırda katalog seçici, değer, birim, referans ve değerin referanstaki yeri.
struct LabPanelEditor: View {
    let panel: LabPanel?
    var onSave: (LabPanelDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: LabPanelDraft

    init(panel: LabPanel?, onSave: @escaping (LabPanelDraft) -> Void) {
        self.panel = panel
        self.onSave = onSave
        _draft = State(initialValue: LabPanelDraft(panel: panel))
    }

    private var isEditing: Bool { panel != nil }

    private var canSave: Bool {
        draft.rows.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !$0.valueText.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        SadeSheet(title: isEditing ? "Paneli düzenle" : "Panel ekle", onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                metaRow
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                columnHeader
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, 8)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach($draft.rows) { $row in
                            rowView($row)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
                SadeDashedButton(title: "Satır ekle") {
                    draft.rows.append(LabPanelDraft.Row())
                }
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
        } footerLeading: {
            EmptyView()
        } footerTrailing: {
            SadeButton(title: "Vazgeç") { dismiss() }
            SadeButton(title: isEditing ? "Kaydet" : "Panel ekle", role: .primary, enabled: canSave) {
                onSave(draft.cleaned)
                dismiss()
            }
        }
        .frame(width: 900, height: 760)
    }

    // MARK: Panel bilgisi

    private var metaRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            SadeDateField(label: "Tarih", date: $draft.date)
                .frame(width: 200)
            SadeField(label: "Saat") {
                TextField("", text: $draft.timeLabel, prompt: Text("10:14").foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14).monospacedDigit())
            }
            .frame(width: 110)
            SadeField(label: "Laboratuvar") {
                TextField("", text: $draft.source, prompt: Text("ör. Haydarpaşa Numune EAH").foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 38, height: 1)
            caption("PARAMETRE").frame(maxWidth: .infinity, alignment: .leading)
            caption("SONUÇ").frame(width: 96, alignment: .leading)
            caption("BİRİM").frame(width: 96, alignment: .leading)
            caption("REFERANS").frame(width: 130, alignment: .leading)
            Color.clear.frame(width: 80 + 12 + 30, height: 1)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.textTertiary)
    }

    private func rowView(_ row: Binding<LabPanelDraft.Row>) -> some View {
        let r = row.wrappedValue
        let value = LabRange.number(r.valueText)
        let range = LabRange.parse(r.refText)
        let code = r.code.isEmpty ? LabCatalog.match(name: r.name) : r.code
        let status = LabPreviewStatus.status(value: value, range: range, code: code)
        return HStack(spacing: 12) {
            catalogMenu(for: row)
            box(row.name, prompt: "Parametre adı")
            box(row.valueText, prompt: "0", mono: true).frame(width: 96)
            box(row.unit, prompt: "birim", secondary: true).frame(width: 96)
            box(row.refText, prompt: "30 - 100", secondary: true, mono: true).frame(width: 130)
            Group {
                if let value, let range, let status {
                    SadeBandGauge(value: value, low: range.low, high: range.high, color: status.ringColor, width: 80)
                } else {
                    Color.clear
                }
            }
            .frame(width: 80, height: 14)
            Button {
                draft.rows.removeAll { $0.id == r.id }
            } label: {
                Lucide(sf: "trash", size: 13)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Satırı sil")
        }
    }

    private func box(_ text: Binding<String>, prompt: String, secondary: Bool = false, mono: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(Palette.textTertiary))
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 14).monospacedDigit() : .system(size: 14))
            .foregroundStyle(secondary ? Palette.textSecondary : Palette.textPrimary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)
            .sadeBox(radius: 10)
    }

    /// Katalogdan seçince ad ve (boşsa) birim otomatik dolar.
    private func catalogMenu(for row: Binding<LabPanelDraft.Row>) -> some View {
        Menu {
            ForEach(LabCategory.allCases.sorted { $0.order < $1.order }) { category in
                let items = LabCatalog.all.filter { $0.category == category }
                if !items.isEmpty {
                    Menu(category.label) {
                        ForEach(items) { analyte in
                            Button(analyte.name) {
                                row.wrappedValue.code = analyte.code
                                row.wrappedValue.name = analyte.name
                                if row.wrappedValue.unit.isEmpty { row.wrappedValue.unit = analyte.unit ?? "" }
                            }
                        }
                    }
                }
            }
        } label: {
            Lucide(sf: "list.bullet", size: 14)
                .foregroundStyle(Palette.textTertiary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 38, height: 38)
        .sadeBox(radius: 10)
        .help("Katalogdan parametre seç")
    }
}

// MARK: - Taslak

/// Düzenleyicinin üzerinde çalıştığı değer tipi. SwiftData nesnelerini doğrudan
/// bağlamak yerine taslak kullanıyoruz: "Vazgeç" gerçekten vazgeçsin, yarım
/// yazılmış satırlar store'a sızmasın.
struct LabPanelDraft {
    struct Row: Identifiable, Hashable {
        var id = UUID()
        var code: String = ""
        var name: String = ""
        var valueText: String = ""
        var unit: String = ""
        var refText: String = ""
    }

    var date: Date = .now
    var timeLabel: String = ""
    var source: String = ""
    var note: String = ""
    var rows: [Row] = [Row()]

    init(panel: LabPanel?) {
        guard let panel else { return }
        date = panel.date
        timeLabel = panel.timeLabel ?? ""
        source = panel.source ?? ""
        note = panel.note ?? ""
        rows = panel.orderedItems.map { item in
            Row(
                code: item.code,
                name: item.name,
                valueText: item.value.map { Fmt.num($0, digits: LabCatalog.inferredDecimals($0)) } ?? (item.textValue ?? ""),
                unit: item.unit ?? "",
                refText: item.refText ?? ""
            )
        }
        if rows.isEmpty { rows = [Row()] }
    }

    /// Boş satırları atar ve katalog eşleşmesini tazeler.
    var cleaned: LabPanelDraft {
        var copy = self
        copy.rows = rows.compactMap { row in
            let name = row.name.trimmingCharacters(in: .whitespaces)
            let value = row.valueText.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            var updated = row
            updated.name = name
            updated.valueText = value
            if updated.code.isEmpty { updated.code = LabCatalog.match(name: name) ?? "" }
            return updated
        }
        return copy
    }

    func materialize(into ctx: ModelContext) -> LabPanel {
        let panel = LabPanel(
            date: Calendar.current.startOfDay(for: date),
            timeLabel: timeLabel.isEmpty ? nil : timeLabel,
            source: source.isEmpty ? nil : source,
            note: note.isEmpty ? nil : note
        )
        ctx.insert(panel)
        insertRows(into: panel, ctx: ctx)
        return panel
    }

    func apply(to panel: LabPanel, in ctx: ModelContext) {
        panel.date = Calendar.current.startOfDay(for: date)
        panel.timeLabel = timeLabel.isEmpty ? nil : timeLabel
        panel.source = source.isEmpty ? nil : source
        panel.note = note.isEmpty ? nil : note
        for item in panel.items { ctx.delete(item) }
        panel.resultsStorage = []
        insertRows(into: panel, ctx: ctx)
    }

    private func insertRows(into panel: LabPanel, ctx: ModelContext) {
        for row in rows {
            let numeric = LabRange.number(row.valueText)
            let ref = LabRange.parse(row.refText)
            let result = LabResult(
                code: row.code,
                name: row.name,
                value: numeric,
                textValue: numeric == nil ? row.valueText : nil,
                unit: row.unit.isEmpty ? nil : row.unit,
                refLow: ref?.low,
                refHigh: ref?.high,
                refText: row.refText.isEmpty ? nil : row.refText
            )
            result.panel = panel
            ctx.insert(result)
        }
    }
}
