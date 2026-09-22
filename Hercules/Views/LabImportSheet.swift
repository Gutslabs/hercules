import SwiftUI
import LucideKit
import UniformTypeIdentifiers

/// e-Nabız PDF'i (ya da aynı düzendeki yapıştırılmış metin) içe aktarma penceresi. Tasarım: tuval ▸
/// Pencereler · Veriler (az yazı). Ayrıştırma ÖNİZLEMELİ: hangi satırın hangi parametreye bağlandığı,
/// referansa göre nerede durduğu, tanınmayanlar ve mevcut bir panelin üzerine yazılıp yazılmayacağı
/// onaydan önce görünür — sessizce yanlış veri yazmak, hiç yazmamaktan kötüdür.
struct LabImportSheet: View {
    var initialURL: URL?
    var existingPanels: [LabPanel]
    var onImport: ([ParsedLabPanel]) -> Void
    /// Önizleme/test kancası: pencere bu ayrıştırılmış panellerle açılır.
    var previewParsed: [ParsedLabPanel]? = nil

    @Environment(\.dismiss) private var dismiss

    private enum Source: String, CaseIterable {
        case file, text
        var label: String { self == .file ? "PDF" : "Metin" }
    }

    @State private var source: Source = .file
    @State private var parsed: [ParsedLabPanel] = []
    @State private var rawText = ""
    @State private var fileName: String?
    @State private var showFilePicker = false
    @State private var message: String?

    private var totalRows: Int { parsed.reduce(0) { $0 + $1.results.count } }
    private var matchedRows: Int {
        parsed.reduce(0) { sum, panel in
            sum + panel.results.filter { code(for: $0) != nil }.count
        }
    }
    private var overwriting: [Date] {
        parsed.compactMap { item in
            existingPanels.first { Calendar.current.isDate($0.date, inSameDayAs: item.date) }?.date
        }
    }

    var body: some View {
        SadeSheet(title: "Tahlil içe aktar", onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    SadeSegmented(options: Source.allCases.map { (value: $0, label: $0.label) }, selection: Binding(
                        get: { source },
                        set: { source = $0; parsed = []; message = nil }
                    ))
                    .frame(width: 170)
                    if source == .file { filePicker }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)

                if source == .text {
                    textInput
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                }

                if let message {
                    SadeNote(text: message, color: Palette.negative)
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                }

                if !parsed.isEmpty {
                    summaryStrip
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                    preview
                        .padding(.top, 10)
                } else {
                    Color.clear.frame(height: 22)
                }
            }
        } footerLeading: {
            EmptyView()
        } footerTrailing: {
            SadeButton(title: "Vazgeç") { dismiss() }
            SadeButton(title: "İçe aktar", role: .primary, enabled: !parsed.isEmpty) {
                onImport(parsed)
                dismiss()
            }
        }
        .frame(width: 860, height: parsed.isEmpty ? nil : 720)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): load(url: url)
            case .failure(let error): message = error.localizedDescription
            }
        }
        .onAppear {
            if let initialURL { load(url: initialURL) }
            if let previewParsed {
                parsed = previewParsed
                fileName = "tahlil.pdf"
            }
        }
    }

    // MARK: Kaynak

    private var filePicker: some View {
        HStack(spacing: 10) {
            Lucide("file-text", size: 15)
                .foregroundStyle(Palette.textSecondary)
            Text(fileName ?? "Dosya seçilmedi")
                .font(.system(size: 13.5))
                .foregroundStyle(fileName == nil ? Palette.textTertiary : Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                showFilePicker = true
            } label: {
                Text(fileName == nil ? "PDF seç" : "Değiştir")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.textPrimary.opacity(0.06)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 38)
        .sadeBox(radius: 10)
        .help("e-Nabız ▸ Tahlillerim ▸ PDF indir")
    }

    private var textInput: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextEditor(text: $rawText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 130)
                .sadeBox(radius: 10)
                .overlay(alignment: .topLeading) {
                    if rawText.isEmpty {
                        Text("PDF'ten kopyalanan satırlar")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            SadeButton(title: "Metni oku") { parse(text: rawText) }
        }
    }

    // MARK: Önizleme

    private var summaryStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(parsed, id: \.date) { panel in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Fmt.dateLong.string(from: panel.date))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text([panel.source, panel.timeLabel].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(matchedRows)/\(totalRows)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                        Text("tanındı")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    recognitionBar
                        .help("Tanınmayanlar “Diğer” altında saklanır")
                }
            }
            if !overwriting.isEmpty {
                SadeNote(text: "\(overwriting.map { Fmt.dayMonth.string(from: $0) }.joined(separator: ", ")) paneli üzerine yazılır")
            }
        }
    }

    /// Tanınanlar adaçayı, tanınmayanlar pirinç.
    private var recognitionBar: some View {
        let width: CGFloat = 160
        let fraction = totalRows > 0 ? CGFloat(matchedRows) / CGFloat(totalRows) : 0
        return HStack(spacing: 2) {
            Rectangle().fill(Palette.positive).frame(width: max(0, width * fraction - 1))
            if matchedRows < totalRows {
                Rectangle().fill(Palette.warning)
            }
        }
        .frame(width: width, height: 6)
        .clipShape(Capsule())
    }

    private var preview: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(parsed.flatMap { $0.results }.enumerated()), id: \.offset) { _, row in
                    previewRow(row)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func previewRow(_ row: ParsedLabResult) -> some View {
        let matched = code(for: row)
        let range = LabRange.parse(row.refText)
        let status = LabPreviewStatus.status(value: row.value, range: range, code: matched)
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(row.name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(matched == nil ? Palette.warning : Palette.textPrimary)
                    .lineLimit(1)
                if matched == nil { SadeChip(text: "Diğer") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(row.rawValue)
                    .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                Text(row.unit ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
            .lineLimit(1)
            .frame(width: 130, alignment: .trailing)
            Text(row.refText.map { LabRange.pretty($0) } ?? "—")
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
                .padding(.leading, 12)
            Group {
                if let value = row.value, let range, let status {
                    SadeBandGauge(value: value, low: range.low, high: range.high, color: status.ringColor)
                } else {
                    Color.clear
                }
            }
            .frame(width: 84, height: 14)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .overlay(alignment: .top) { SadeRule().opacity(0.75) }
    }

    // MARK: Yükleme

    private func code(for row: ParsedLabResult) -> String? {
        let preferUrine = (row.section ?? "").lowercased(with: Locale(identifier: "tr_TR")).contains("idrar")
        return LabCatalog.match(name: row.name, preferUrine: preferUrine)
    }

    private func load(url: URL) {
        message = nil
        fileName = url.lastPathComponent
        // Dosya seçici güvenlik kapsamlı URL veriyor; okumadan önce erişimi açmak gerekiyor.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        #if canImport(PDFKit)
        let result = LabReportParser.parse(pdf: url)
        #else
        let result: [ParsedLabPanel] = []
        #endif
        if result.isEmpty {
            message = "PDF okunamadı ya da tanınan sonuç bulunamadı. Metin sekmesinden yapıştırmayı deneyebilirsin."
        }
        parsed = result
    }

    private func parse(text: String) {
        message = nil
        let result = LabReportParser.parse(text: text)
        if result.isEmpty { message = "Metinde tanınan sonuç yok." }
        parsed = result
    }
}

/// Önizleme/düzenleyici satırı için durum: referans dışı (düşük/yüksek), katalogda optimal bandı
/// varsa hedefte/sınırda, yoksa normal. Sayısal değer ya da referans yoksa nil.
enum LabPreviewStatus {
    static func status(value: Double?, range: LabRange?, code: String?) -> LabStatus? {
        guard let value, let range, !range.isEmpty else { return nil }
        if let low = range.low, value < low { return .low }
        if let high = range.high, value > high { return .high }
        if let code, let optimal = LabCatalog.analyte(code: code)?.optimal, !optimal.isEmpty {
            return optimal.contains(value) ? .optimal : .watch
        }
        return .normal
    }
}
