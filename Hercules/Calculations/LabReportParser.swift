import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - Ayrıştırma çıktısı

/// Rapordan çıkarılan tek satır — henüz katalogla eşleşmemiş ham hâli.
struct ParsedLabResult: Hashable {
    var name: String
    /// Sonucun ham metni ("11.5", "<0.4", "Negatif").
    var rawValue: String
    var value: Double?
    var unit: String?
    var refText: String?
    /// Rapordaki bölüm başlığı ("Tam Kan (Hemogram)", "İdrar tetkiki …").
    var section: String?

    var isNumeric: Bool { value != nil }
}

/// Bir güne ait ayrıştırılmış panel.
struct ParsedLabPanel: Hashable {
    var date: Date
    var timeLabel: String?
    var source: String?
    var results: [ParsedLabResult]
}

// MARK: - Ayrıştırıcı

/// e-Nabız "Tahlillerim" PDF çıktısını (ve aynı düzendeki düz metni) satır satır
/// çözer. Sütunlar PDF'te sabit değil — bazı satırlarda referans aralığı ALT SATIRA
/// taşar, isimler iki satıra bölünür — bu yüzden ayrıştırma SAĞDAN SOLA çalışır:
/// önce referans, sonra birim, sonra sonuç ayrılır; artan kısım addır.
enum LabReportParser {

    // MARK: Girişler

    #if canImport(PDFKit)
    /// PDF'i metne çevirip ayrıştırır. Dosya okunamazsa boş döner.
    static func parse(pdf url: URL) -> [ParsedLabPanel] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string {
                text += s
                text += "\n"
            }
        }
        return parse(text: text)
    }
    #endif

    static func parse(text: String) -> [ParsedLabPanel] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var facility: String?
        var headerDate: Date?
        var currentDate: Date?
        var currentTime: String?
        var currentSection: String?
        /// Sonucu OLMAYAN son satır. e-Nabız uzun parametre adlarını satıra bölüp
        /// sonucu bir alt satıra atıyor ("Sodyum (Na) (Serum ve vücut" / "sıvılarında,
        /// herbiri)" / "139.2 mmol/L 136 - 145"). Bu yüzden başlıksız bir satırın
        /// bölüm başlığı mı yoksa taşan bir AD mı olduğuna, ardından ne geldiğine
        /// bakarak karar veriyoruz: sonuçla başlayan satır gelirse addı, normal bir
        /// satır gelirse bölüm başlığıydı.
        var pendingName: String?
        var lastFacilityLine = false

        /// Gün → panel. Aynı günün farklı saatlerdeki bölümleri tek panelde toplanır.
        var days: [Date: ParsedLabPanel] = [:]
        var dayOrder: [Date] = []
        var lastKey: (day: Date, index: Int)?

        func appendRow(_ row: ParsedLabResult, day: Date, time: String?) {
            if days[day] == nil {
                days[day] = ParsedLabPanel(date: day, timeLabel: time, source: facility, results: [])
                dayOrder.append(day)
            }
            if days[day]?.timeLabel == nil { days[day]?.timeLabel = time }
            days[day]?.results.append(row)
            lastKey = (day, (days[day]?.results.count ?? 1) - 1)
        }

        func mutateLast(_ change: (inout ParsedLabResult) -> Void) {
            guard let lastKey, var panel = days[lastKey.day],
                  panel.results.indices.contains(lastKey.index) else { return }
            change(&panel.results[lastKey.index])
            days[lastKey.day] = panel
        }

        for line in lines {
            let wasFacilityLine = lastFacilityLine
            lastFacilityLine = false

            // Sağlık tesisi (iki satıra bölünebilir).
            if let value = valueAfterPrefix(line, prefixes: ["Sağlık Tesisi:", "Saglik Tesisi:", "Kurum:"]) {
                facility = tidyFacility(value)
                lastFacilityLine = true
                continue
            }
            if wasFacilityLine, line.rangeOfCharacter(from: .lowercaseLetters) == nil, !line.contains(":") {
                facility = tidyFacility([facility, line].compactMap { $0 }.joined(separator: " "))
                lastFacilityLine = true
                continue
            }

            // Başlıktaki rapor tarihi — blok tarihi yoksa yedek.
            if headerDate == nil, let value = valueAfterPrefix(line, prefixes: ["Tarih:"]),
               let d = firstDate(in: value) {
                headerDate = d
                continue
            }
            if isNoise(line) { continue }

            // Tarih / saat satırları yeni bir bloğu başlatır.
            if let d = wholeDate(line) {
                currentDate = d
                if pendingName == nil { currentSection = nil }
                continue
            }
            if let t = wholeTime(line) {
                currentTime = t
                if pendingName == nil { currentSection = nil }
                continue
            }

            // Sadece referans aralığı taşan satır → bir öncekine iliştir.
            if isPureReference(line) {
                mutateLast { row in
                    if row.refText == nil || row.refText?.isEmpty == true { row.refText = line }
                }
                continue
            }
            // Birim kuyruğu ("m²") → bir öncekinin birimine eklenir.
            if isUnitFragment(line) {
                var attached = false
                mutateLast { row in
                    if let unit = row.unit, !unit.isEmpty {
                        row.unit = unit + " " + line
                        attached = true
                    }
                }
                if attached { continue }
            }

            let day = Calendar.current.startOfDay(for: currentDate ?? headerDate ?? .now)

            // Adı da sonucu da olan tam satır: bekleyen başlık gerçekten BÖLÜM başlığıydı.
            if let row = parseRow(line) {
                if let pending = pendingName {
                    currentSection = pending
                    pendingName = nil
                }
                var enriched = row
                enriched.section = currentSection
                appendRow(enriched, day: day, time: currentTime)
                continue
            }

            // Sonuçla BAŞLAYAN satır: adı bir önceki satır(lar)da kalmış.
            if let pending = pendingName, var row = parseRow(line, allowEmptyName: true) {
                row.name = pending
                row.section = currentSection
                appendRow(row, day: day, time: currentTime)
                pendingName = nil
                continue
            }

            // Sonucu olmayan satır: taşan ad mı, bölüm başlığı mı?
            if let pending = pendingName, isNameContinuation(line, previousName: pending) {
                pendingName = pending + " " + line
                continue
            }
            if pendingName == nil,
               let previous = lastRow(days: days, key: lastKey),
               isNameContinuation(line, previousName: previous.name) {
                mutateLast { row in row.name = row.name + " " + line }
                continue
            }
            pendingName = line
        }

        return dayOrder.compactMap { key in
            guard var panel = days[key], !panel.results.isEmpty else { return nil }
            panel.source = facility
            panel.results = dedupe(panel.results)
            return panel
        }
    }

    // MARK: Satır çözümü

    /// "Alanin aminotransferaz (ALT) 18 U/L < 41" → ad / sonuç / birim / referans.
    /// Sonuç bulunamazsa (bölüm başlığı, tablo başlığı) nil döner.
    static func parseRow(_ line: String, allowEmptyName: Bool = false) -> ParsedLabResult? {
        var work = line
        var refText: String?

        if let (rest, ref) = splitTrailingReference(work) {
            work = rest
            refText = ref
        }

        var tokens = work.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var valueRange = valueTokenRange(tokens)
        // Referans olarak ayırdığımız şey aslında TEK sonuçmuş ("NRBC# <0.4"):
        // geri al, sonucun kendisi olarak kullan.
        if valueRange == nil, let ref = refText {
            work = line
            refText = nil
            tokens = work.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            valueRange = valueTokenRange(tokens)
            if valueRange == nil { _ = ref; return nil }
        }
        guard let range = valueRange else { return nil }
        guard allowEmptyName ? range.lowerBound == 0 : range.lowerBound > 0 else { return nil }

        let name = tokens[0..<range.lowerBound].joined(separator: " ")
        let rawValue = tokens[range].joined(separator: " ")
        let unitTokens = tokens[range.upperBound...]
        let unit = unitTokens.isEmpty ? nil : unitTokens.joined(separator: " ")

        guard allowEmptyName || !name.isEmpty else { return nil }
        return ParsedLabResult(
            name: name,
            rawValue: rawValue,
            value: numericValue(rawValue),
            unit: unit,
            refText: refText
        )
    }

    // MARK: Parçalayıcılar

    /// Satır sonundaki referans aralığını ayırır ("… 30 - 100" / "… < 41" / "… Negatif").
    private static func splitTrailingReference(_ line: String) -> (rest: String, ref: String)? {
        if let m = lastMatch(#"\s((?:<=?|>=?|≤|≥)\s*-?[\d.,]+|-?[\d.,]+\s*-\s*-?[\d.,]+)\s*$"#, in: line) {
            return (String(line[line.startIndex..<m.range.lowerBound]).trimmingCharacters(in: .whitespaces),
                    m.capture.trimmingCharacters(in: .whitespaces))
        }
        if let qualitative = trailingQualitative(line) {
            let rest = String(line.dropLast(qualitative.count)).trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty else { return nil }
            return (rest, qualitative)
        }
        return nil
    }

    /// Sonucu taşıyan token aralığı: sayısal token ya da niteliksel ifade
    /// ("Açık Sarı" iki token'dır).
    private static func valueTokenRange(_ tokens: [String]) -> Range<Int>? {
        if let qualitative = trailingQualitativeTokens(tokens) {
            // Niteliksel sonuçtan SONRA sayısal bir token varsa sayı kazanır.
            if let numeric = lastNumericIndex(tokens), numeric > qualitative.lowerBound {
                return numeric..<(numeric + 1)
            }
            return qualitative
        }
        if let numeric = lastNumericIndex(tokens) { return numeric..<(numeric + 1) }
        return nil
    }

    private static func lastNumericIndex(_ tokens: [String]) -> Int? {
        for i in stride(from: tokens.count - 1, through: 0, by: -1) where isNumericToken(tokens[i]) {
            return i
        }
        return nil
    }

    /// "12.5", "<0.4", "≥90" → sonuç; "10*9/L", "B12", "ml/dk/1.73" → değil.
    private static func isNumericToken(_ token: String) -> Bool {
        guard token.rangeOfCharacter(from: .decimalDigits) != nil else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,<>=≤≥-+")
        return token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Niteliksel sonuçlar — uzun olan önce (eşleşmede en uzunu kazansın).
    private static let qualitativeValues: [String] = [
        "Hafif Bulanık", "Çok Bulanık", "Açık Sarı", "Koyu Sarı", "Bulanık", "Berrak",
        "Negatif", "Pozitif", "Normal", "Görülmedi", "Görülmemiştir", "Sarı", "Eser",
        "Yok", "Bol", "Az", "Şeffaf", "Kırmızı", "Kahverengi"
    ].sorted { $0.count > $1.count }

    private static func trailingQualitative(_ line: String) -> String? {
        for candidate in qualitativeValues {
            if line.count > candidate.count,
               line.lowercased(with: trLocale).hasSuffix(candidate.lowercased(with: trLocale)) {
                return String(line.suffix(candidate.count))
            }
        }
        return nil
    }

    private static func trailingQualitativeTokens(_ tokens: [String]) -> Range<Int>? {
        for width in stride(from: min(2, tokens.count), through: 1, by: -1) {
            let start = tokens.count - width
            guard start >= 0 else { continue }
            let phrase = tokens[start...].joined(separator: " ").lowercased(with: trLocale)
            if qualitativeValues.contains(where: { $0.lowercased(with: trLocale) == phrase }) {
                return start..<tokens.count
            }
        }
        return nil
    }

    // MARK: Satır sınıflandırma

    private static let trLocale = Locale(identifier: "tr_TR")

    private static let noiseExact: Set<String> = [
        "t.c.sağlık bakanlığı", "t.c. sağlık bakanlığı",
        "sağlık bilgi sistemleri genel müdürlüğü",
        "enabiz.gov.tr", "e-nabız", "tarih tahlil sonuç", "sonuç", "birimi",
        "referans", "değeri", "sonuç birimi", "referans değeri", "tahlil", "tarih",
        "sonuç birimi referans değeri"
    ]

    private static func isNoise(_ line: String) -> Bool {
        let lower = line.lowercased(with: trLocale)
        if noiseExact.contains(lower) { return true }
        if matches(#"^sayfa\s+\d+\s*/\s*\d+$"#, lower) { return true }
        // Telefon/sayfa numarası gibi yalnız rakamdan oluşan satırlar.
        if matches(#"^[\d\s]+$"#, line), line.contains(" ") { return true }
        for prefix in ["adı/soyadı:", "adi/soyadi:", "cinsiyet:", "doğum tarihi:",
                       "dogum tarihi:", "protokol", "hasta no", "t.c. kimlik", "tc kimlik"] {
            if lower.hasPrefix(prefix) { return true }
        }
        return false
    }

    /// Yalnız referans aralığından ibaret (alt satıra taşmış) satır.
    private static func isPureReference(_ line: String) -> Bool {
        matches(#"^(?:<=?|>=?|≤|≥)\s*-?[\d.,]+$"#, line)
            || matches(#"^-?[\d.,]+\s*-\s*-?[\d.,]+$"#, line)
    }

    /// "m²" gibi birim kuyruğu.
    private static func isUnitFragment(_ line: String) -> Bool {
        line.count <= 4
            && line.rangeOfCharacter(from: .decimalDigits) == nil
            && line.rangeOfCharacter(from: .whitespaces) == nil
            && line.rangeOfCharacter(from: .letters) != nil
    }

    /// Ada taşan satır mı: küçük harfle başlıyorsa ya da öncekinin adında açık
    /// parantez kaldıysa evet. "İdrar tetkiki (…)" gibi başlıklar için hayır.
    private static func isNameContinuation(_ line: String, previousName: String) -> Bool {
        let open = previousName.filter { $0 == "(" }.count
        let close = previousName.filter { $0 == ")" }.count
        if open > close { return true }
        guard let first = line.first else { return false }
        return first.isLowercase
    }

    private static func lastRow(days: [Date: ParsedLabPanel], key: (day: Date, index: Int)?) -> ParsedLabResult? {
        guard let key, let panel = days[key.day], panel.results.indices.contains(key.index) else { return nil }
        return panel.results[key.index]
    }

    // MARK: Yardımcılar

    private static func dedupe(_ rows: [ParsedLabResult]) -> [ParsedLabResult] {
        var seen: Set<String> = []
        var out: [ParsedLabResult] = []
        for row in rows {
            let key = LabCatalog.normalize(row.name) + "|" + (row.section.map { LabCatalog.normalize($0) } ?? "")
            if seen.insert(key).inserted { out.append(row) }
        }
        return out
    }

    private static func numericValue(_ raw: String) -> Double? {
        // "<0.4" sınırlı okumadır, sayı olarak saklanmaz.
        guard raw.rangeOfCharacter(from: CharacterSet(charactersIn: "<>≤≥")) == nil else { return nil }
        return LabRange.number(raw)
    }

    private static func valueAfterPrefix(_ line: String, prefixes: [String]) -> String? {
        for prefix in prefixes where line.lowercased(with: trLocale).hasPrefix(prefix.lowercased(with: trLocale)) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func tidyFacility(_ raw: String) -> String {
        raw.replacingOccurrences(of: "T.C. SAĞLIK BAKANLIĞI ", with: "")
            .replacingOccurrences(of: "T.C.SAĞLIK BAKANLIĞI ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    private static func wholeDate(_ line: String) -> Date? {
        matches(#"^\d{2}\.\d{2}\.\d{4}$"#, line) ? dateFormatter.date(from: line) : nil
    }

    private static func wholeTime(_ line: String) -> String? {
        matches(#"^\d{2}:\d{2}(:\d{2})?$"#, line) ? String(line.prefix(5)) : nil
    }

    private static func firstDate(in text: String) -> Date? {
        guard let m = lastMatch(#"(\d{2}\.\d{2}\.\d{4})"#, in: text) else { return nil }
        return dateFormatter.date(from: m.capture)
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = text as NSString
        return re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func lastMatch(_ pattern: String, in text: String) -> (range: Range<String.Index>, capture: String)? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let all = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard let m = all.last, m.numberOfRanges >= 2,
              let full = Range(m.range, in: text) else { return nil }
        return (full, ns.substring(with: m.range(at: 1)))
    }
}
