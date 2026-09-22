import Foundation

// MARK: - Hesaplanan göstergeler

/// Tek başına ölçülmeyen ama iki değerden çıkan gösterge (HOMA-IR, Trigliserid/HDL …).
/// Bunlar raporda YOKTUR; panelden hesaplanır ve sayfada ayrı bir şeritte durur.
struct LabDerivedMetric: Identifiable, Hashable {
    let id: String
    let name: String
    let value: Double
    let decimals: Int
    let unit: String?
    let optimal: LabRange
    let direction: LabDirection
    let note: String

    var display: String { Fmt.num(value, digits: decimals) }

    var status: LabStatus {
        optimal.contains(value) ? .optimal : .watch
    }

    var optimalText: String { "hedef \(optimal.display)" }
}

// MARK: - Panel özeti

/// Sayfanın üst şeridi ve AI özeti aynı sayıları kullansın diye tek yerde hesaplanır.
struct LabPanelSummary {
    var total: Int = 0
    var outOfRange: Int = 0
    var watch: Int = 0
    var optimal: Int = 0
    var normal: Int = 0

    /// Değerlendirilebilen (durumu bilinen) parametre sayısı.
    var evaluated: Int { outOfRange + watch + optimal + normal }

    var headline: String {
        if total == 0 { return "Sonuç yok" }
        if outOfRange > 0 && watch > 0 { return "\(outOfRange) değer referans dışı, \(watch) değer sınırda" }
        if outOfRange > 0 { return "\(outOfRange) değer referans dışı" }
        if watch > 0 { return "Hepsi referans içinde, \(watch) değer hedef bandın dışında" }
        return "Tüm değerler hedef bantta"
    }
}

// MARK: - Analiz

enum LabInsights {

    // MARK: Özet

    static func summary(for panel: LabPanel) -> LabPanelSummary {
        var s = LabPanelSummary()
        for item in panel.items {
            s.total += 1
            switch item.status {
            case .low, .high: s.outOfRange += 1
            case .watch:      s.watch += 1
            case .optimal:    s.optimal += 1
            case .normal:     s.normal += 1
            case .unknown:    break
            }
        }
        return s
    }

    /// Dikkat isteyenler: önce referans dışı, sonra hedef bandın dışındakiler.
    static func flagged(_ panel: LabPanel) -> [LabResult] {
        panel.items
            .filter { $0.status.needsAttention }
            .sorted { a, b in
                let sa = a.status.severity, sb = b.status.severity
                if sa != sb { return sa < sb }
                return LabCatalog.sortRank(code: a.code, name: a.name) < LabCatalog.sortRank(code: b.code, name: b.name)
            }
    }

    /// Kategorilere ayrılmış sonuçlar — sayfadaki bölümler bu sırayla çizilir.
    static func grouped(_ panel: LabPanel) -> [(category: LabCategory, items: [LabResult])] {
        Dictionary(grouping: panel.orderedItems, by: { $0.category })
            .map { (category: $0.key, items: $0.value) }
            .sorted { $0.category.order < $1.category.order }
    }

    // MARK: Hesaplananlar

    static func derived(for panel: LabPanel) -> [LabDerivedMetric] {
        var out: [LabDerivedMetric] = []

        if let glucose = panel.value("glucose"), let insulin = panel.value("insulin"), glucose > 0 {
            out.append(LabDerivedMetric(
                id: "homaIR", name: "HOMA-IR",
                value: glucose * insulin / 405, decimals: 2, unit: nil,
                optimal: LabRange(nil, 2.0), direction: .lowerBetter,
                note: "İnsülin direnci göstergesi (açlık glukoz × insülin ÷ 405)."
            ))
        }
        if let tg = panel.value("triglyceride"), let hdl = panel.value("hdl"), hdl > 0 {
            out.append(LabDerivedMetric(
                id: "tgHdl", name: "Trigliserid / HDL",
                value: tg / hdl, decimals: 2, unit: nil,
                optimal: LabRange(nil, 2.0), direction: .lowerBetter,
                note: "Metabolik sağlığın tek sayıdaki en iyi lipid oranı."
            ))
        }
        if let total = panel.value("cholesterol"), let hdl = panel.value("hdl"), hdl > 0 {
            out.append(LabDerivedMetric(
                id: "totalHdl", name: "Total / HDL",
                value: total / hdl, decimals: 2, unit: nil,
                optimal: LabRange(nil, 3.5), direction: .lowerBetter,
                note: "Kolesterolü tek başına değil oranıyla okumanın yolu."
            ))
        }
        // TDBK raporda yoksa demir + serbest bağlama kapasitesinden çıkar.
        let tibc = panel.value("tibc") ?? {
            guard let iron = panel.value("iron"), let uibc = panel.value("uibc") else { return nil }
            return iron + uibc
        }()
        if let iron = panel.value("iron"), let tibc, tibc > 0 {
            out.append(LabDerivedMetric(
                id: "transferrinSat", name: "Transferrin Satürasyonu",
                value: iron / tibc * 100, decimals: 0, unit: "%",
                optimal: LabRange(20, 45), direction: .band,
                note: "Ferritinden bağımsız demir doluluk göstergesi."
            ))
        }
        if let ast = panel.value("ast"), let alt = panel.value("alt"), alt > 0 {
            out.append(LabDerivedMetric(
                id: "astAlt", name: "AST / ALT",
                value: ast / alt, decimals: 2, unit: nil,
                optimal: LabRange(0.7, 1.5), direction: .band,
                note: "Karaciğer mi kas mı — oran ayırt etmeye yardım eder."
            ))
        }
        return out
    }

    // MARK: Karşılaştırma

    /// İki panel arasındaki fark (aynı parametre için).
    static func delta(code: String, from previous: LabPanel?, to current: LabPanel) -> Double? {
        guard let previous,
              let old = previous.value(code), let new = current.value(code)
        else { return nil }
        return new - old
    }

    // MARK: AI bağlamı

    /// Koça verilen metin. Kısa ama TAM: önce bayraklar, sonra hesaplananlar,
    /// sonra kategori kategori tüm değerler.
    static func contextText(panels: [LabPanel], limit: Int = 3) -> String? {
        let sorted = panels.sorted { $0.date > $1.date }
        guard let latest = sorted.first, !latest.items.isEmpty else { return nil }

        var lines: [String] = []
        let head = [Fmt.dateLong.string(from: latest.date), latest.source, "\(latest.items.count) parametre"]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        lines.append("[KAN TAHLİLLERİ — \(head)]")
        lines.append("Referans = laboratuvarın aralığı. Hedef = uygulamadaki optimal bant (tanı değil, yorum çerçevesi).")

        let previous = sorted.dropFirst().first
        let flaggedItems = flagged(latest)
        let outOfRange = flaggedItems.filter { $0.status.isOutOfRange }
        let watching = flaggedItems.filter { $0.status == .watch }

        if !outOfRange.isEmpty {
            lines.append("Referans dışı (\(outOfRange.count)): " + outOfRange.map { line(for: $0, previous: previous) }.joined(separator: " · "))
        }
        if !watching.isEmpty {
            lines.append("Hedef bandın dışında (\(watching.count)): " + watching.map { line(for: $0, previous: previous) }.joined(separator: " · "))
        }

        let derivedMetrics = derived(for: latest)
        if !derivedMetrics.isEmpty {
            lines.append("Hesaplanan: " + derivedMetrics.map {
                "\($0.name) \($0.display)\($0.unit.map { u in u == "%" ? "%" : " \(u)" } ?? "") (\($0.optimalText), \($0.status.label.lowercased(with: trLocale)))"
            }.joined(separator: " · "))
        }

        lines.append("Tüm değerler:")
        for group in grouped(latest) where !group.items.isEmpty {
            let body = group.items.map { line(for: $0, previous: previous, compact: true) }.joined(separator: " · ")
            lines.append("- \(group.category.label): \(body)")
        }

        // Geçmiş paneller: yalnız tarih + bayrak sayısı (bağlamı şişirmesin).
        let older = sorted.dropFirst().prefix(max(0, limit - 1))
        if !older.isEmpty {
            let history = older.map { panel -> String in
                let s = summary(for: panel)
                return "\(Fmt.dateLong.string(from: panel.date)) (\(s.total) parametre, \(s.outOfRange) referans dışı)"
            }.joined(separator: " · ")
            lines.append("Önceki paneller: \(history)")
        }

        return lines.joined(separator: "\n")
    }

    /// "Koça analiz ettir" butonunun sohbete yazdığı istem.
    static func coachPrompt(for panel: LabPanel) -> String {
        let date = Fmt.dateLong.string(from: panel.date)
        return """
        @Tahliller \(date) tarihli kan tahlillerimi değerlendir.

        1) Referans dışı ve hedef bandın dışındaki değerleri önem sırasına koy — hangisi \
        gerçekten önemli, hangisi gürültü?
        2) Bunların antrenman, beslenme ve toparlanmama etkisi ne?
        3) Beslenme, supplement ve antrenman tarafında somut olarak ne değiştirmeliyim?
        4) Hangi değeri ne zaman tekrar ölçmeliyim, hangisi için hekime gitmeliyim?
        """
    }

    // MARK: Satır metni

    private static let trLocale = Locale(identifier: "tr_TR")

    private static func line(for result: LabResult, previous: LabPanel?, compact: Bool = false) -> String {
        var parts = "\(result.displayName) \(result.displayValue)"
        if let unit = result.unit, !unit.isEmpty { parts += " \(unit)" }

        var meta: [String] = []
        if let ref = result.displayReference { meta.append("ref \(ref)") }
        if !compact, let optimal = result.distinctOptimal {
            meta.append("hedef \(optimal.display)")
        }
        if result.status != .normal && result.status != .unknown {
            meta.append(result.status.label.lowercased(with: trLocale))
        }
        if let previous, let now = result.value, !result.code.isEmpty,
           let before = previous.value(result.code), abs(now - before) > 0.0001 {
            meta.append("önceki panele göre \(Fmt.signed(now - before, digits: result.analyte?.decimals ?? 1))")
        }
        if !meta.isEmpty { parts += " (\(meta.joined(separator: ", ")))" }
        return parts
    }

}
