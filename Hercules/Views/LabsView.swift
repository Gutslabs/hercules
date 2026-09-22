import SwiftUI
import SwiftData
import LucideKit
import UniformTypeIdentifiers

/// Kan tahlilleri sayfası — tasarım: "Hercules Mac Tasarımı" tuvali ▸ Tahliller · V3 Halka.
/// Bir panel = bir tarihteki tüm sonuçlar. Solda halka (her değer bir dilim, ortada kaç değer
/// hedefte, altında sınırdakiler), sağda bütün değerler ve önceki tahlile göre değişim. Kartlar
/// LabsRing.swift'te; burada veri, sheet'ler, içe aktarma ve eylemler. Koça analiz ettirme
/// sayfanın birincil eylemi.
struct LabsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \LabPanel.date, order: .reverse) private var panels: [LabPanel]

    /// Sohbet sayfasına hazır istem gönderir (ContentView bağlar).
    var onAskCoach: (String) -> Void = { _ in }

    @State private var selectedDate: Date?
    @State private var showImport = false
    @State private var importURL: URL?
    @State private var editingPanel: LabPanel?
    @State private var creatingPanel = false
    @State private var panelToDelete: LabPanel?
    @State private var isDropTarget = false

    // MARK: Seçili panel

    private var selectedPanel: LabPanel? {
        guard !panels.isEmpty else { return nil }
        if let selectedDate, let hit = panels.first(where: { $0.date == selectedDate }) { return hit }
        return panels.first
    }

    /// Seçili panelin bir öncekisi — değişim okları buradan çıkar.
    private var previousPanel: LabPanel? {
        guard let selectedPanel, let index = panels.firstIndex(where: { $0.id == selectedPanel.id }) else { return nil }
        return panels.indices.contains(index + 1) ? panels[index + 1] : nil
    }

    // MARK: Gövde

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content(size: proxy.size)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
        .overlay(alignment: .top) { dropHint }
        .onDrop(of: [.fileURL, .pdf], isTargeted: $isDropTarget) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $showImport) {
            LabImportSheet(initialURL: importURL, existingPanels: panels) { parsed in
                importPanels(parsed)
            }
            .onDisappear { importURL = nil }
        }
        .sheet(isPresented: $creatingPanel) {
            LabPanelEditor(panel: nil) { draft in
                let panel = draft.materialize(into: ctx)
                selectedDate = panel.date
                ctx.saveOrReport("tahlil paneli")
            }
        }
        .sheet(item: $editingPanel) { panel in
            LabPanelEditor(panel: panel) { draft in
                draft.apply(to: panel, in: ctx)
                ctx.saveOrReport("tahlil paneli")
            }
        }
        .alert("Panel silinsin mi?", isPresented: Binding(
            get: { panelToDelete != nil },
            set: { if !$0 { panelToDelete = nil } }
        )) {
            Button("Vazgeç", role: .cancel) { panelToDelete = nil }
            Button("Sil", role: .destructive) {
                if let panelToDelete {
                    if selectedDate == panelToDelete.date { selectedDate = nil }
                    ctx.delete(panelToDelete)
                    ctx.saveOrReport("tahlil paneli sil")
                }
                panelToDelete = nil
            }
        } message: {
            Text(panelToDelete.map { "\(Fmt.dateLong.string(from: $0.date)) tarihli panel ve içindeki \($0.items.count) sonuç silinecek." } ?? "")
        }
    }

    /// Geniş pencere: halka | değerler (tasarım ölçüsünde 734 | 735), pencereyi doldurur.
    /// Dar pencere: alt alta.
    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if let panel = selectedPanel {
            let groups = LabInsights.grouped(panel)
            let ring = LabRingCard(panel: panel, groups: groups, summary: LabInsights.summary(for: panel),
                                   flagged: LabInsights.flagged(panel)) {
                ringActions(panel: panel)
            }
            let values = LabValuesCard(groups: groups, previous: previousPanel)
            let innerW = max(0, size.width - 48)
            if innerW >= 900 {
                let first = floor((innerW - 24) / 2)
                HStack(spacing: 24) {
                    ring.frame(width: first)
                    values.frame(width: innerW - 24 - first)
                }
                .frame(width: innerW, height: max(size.height - 36, 760))
            } else {
                VStack(spacing: 18) {
                    ring.frame(height: 760)
                    values.frame(height: 760)
                }
                .frame(width: innerW)
            }
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Eylemler (halka kartının altı)

    private func ringActions(panel: LabPanel) -> some View {
        HStack(spacing: 8) {
            Button {
                onAskCoach(LabInsights.coachPrompt(for: panel))
            } label: {
                HStack(spacing: 6) {
                    Lucide(sf: "sparkles", size: 13)
                    Text("Koça analiz ettir")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Palette.btnFg)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.btnBg))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Bu panelin tamamını koça yorumlat")

            menuButton(sf: "calendar", help: "Tahlil seç") {
                ForEach(panels) { item in
                    Button {
                        selectedDate = item.date
                    } label: {
                        let flags = LabInsights.summary(for: item).outOfRange
                        Text("\(Fmt.date.string(from: item.date)) · \(item.items.count) sonuç\(flags > 0 ? " · \(flags) bayrak" : "")")
                    }
                }
            }
            menuButton(sf: "plus", help: "Tahlil ekle ya da bu paneli düzenle") {
                Button("PDF / metin içe aktar…") { showImport = true }
                Button("Elle panel ekle…") { creatingPanel = true }
                Divider()
                Button("Bu paneli düzenle…") { editingPanel = panel }
                Button("Bu paneli sil", role: .destructive) { panelToDelete = panel }
            }
        }
    }

    /// 34pt kare ikon düğmesi açılır menüyle. macOS borderless Menu yalnız ikonu çizer; zemin arkada.
    private func menuButton<Items: View>(sf: String, help: String, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            Lucide(sf: sf, size: 15)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 34, height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
        .help(help)
    }

    // MARK: - Boş durum

    private var emptyState: some View {
        VStack(spacing: 14) {
            Lucide("flask-conical", size: 26)
                .foregroundStyle(Palette.textQuaternary)
            VStack(spacing: 5) {
                Text("Henüz tahlil yok")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("e-Nabız'dan indirdiğin PDF'i buraya sürükle — tarih, sonuç, birim ve\nreferans aralıkları otomatik okunur ve koç bu değerleri kullanmaya başlar.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textTertiary)
            }
            HStack(spacing: 8) {
                Button {
                    showImport = true
                } label: {
                    HStack(spacing: 6) {
                        Lucide("file-text", size: 13)
                        Text("PDF / metin içe aktar")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(Palette.btnFg)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.btnBg))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    creatingPanel = true
                } label: {
                    HStack(spacing: 6) {
                        Lucide(sf: "plus", size: 13)
                        Text("Elle ekle")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .flatButtonChrome()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(36)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isDropTarget ? Palette.accent.opacity(0.7) : Palette.border,
                    style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                )
        )
    }

    @ViewBuilder
    private var dropHint: some View {
        if isDropTarget, !panels.isEmpty {
            HStack(spacing: 8) {
                Lucide("file-text", size: 13)
                Text("PDF'i bırak — tahliller içe aktarılacak")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Palette.btnFg)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(Palette.btnBg))
            .padding(.top, 12)
            .transition(.opacity)
        }
    }

    // MARK: - İçe aktarma

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
                ?? providers.first
        else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "pdf"
            else { return }
            Task { @MainActor in
                importURL = url
                showImport = true
            }
        }
        return true
    }

    /// Ayrıştırılan panelleri store'a yazar. Aynı GÜNE ait panel varsa üzerine yazılır
    /// (aynı PDF'i iki kere sürüklemek kopya üretmesin).
    private func importPanels(_ parsed: [ParsedLabPanel]) {
        var lastDate: Date?
        for item in parsed {
            let day = Calendar.current.startOfDay(for: item.date)
            if let existing = panels.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                ctx.delete(existing)
            }
            let panel = LabPanel(date: day, timeLabel: item.timeLabel, source: item.source)
            ctx.insert(panel)
            for row in item.results {
                let preferUrine = (row.section ?? "").lowercased(with: Locale(identifier: "tr_TR")).contains("idrar")
                let code = LabCatalog.match(name: row.name, preferUrine: preferUrine) ?? ""
                let ref = LabRange.parse(row.refText)
                let result = LabResult(
                    code: code,
                    name: row.name,
                    value: row.value,
                    textValue: row.value == nil ? row.rawValue : nil,
                    unit: row.unit,
                    refLow: ref?.low,
                    refHigh: ref?.high,
                    refText: row.refText
                )
                result.panel = panel
                ctx.insert(result)
            }
            lastDate = day
        }
        ctx.saveOrReport("tahlil içe aktarma")
        if let lastDate { selectedDate = lastDate }
    }
}
