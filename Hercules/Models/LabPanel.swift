import Foundation
import SwiftData

/// Tek bir tahlil çıktısı (bir tarihteki kan/idrar paneli). e-Nabız PDF'inden içe
/// aktarılır ya da elle girilir; aynı GÜNE ait bölümler (farklı saatlerde çıkan
/// LDL, TDBK gibi) tek panelde toplanır — kullanıcı "haziran tahlilim" diye tek
/// bir şey düşünür, sistem de öyle saklar.
@Model
final class LabPanel {
    /// Numunenin alındığı gün (saat bilgisi `timeLabel`'da metin olarak durur).
    var date: Date = Date.now
    /// "10:14" gibi ilk numune saati — panelin kendisi güne bağlıdır.
    var timeLabel: String?
    /// Laboratuvar / sağlık tesisi adı.
    var source: String?
    var note: String?
    var createdAt: Date = Date.now
    /// Kaydın son değişiklik zamanı (CloudKit dedup'u bunu okur).
    var updatedAt: Date = Date.now

    /// CloudKit to-many'nin OPTIONAL olmasını şart koşar → stored optional; dışa
    /// dönük okuma `items` üzerinden non-optional.
    @Relationship(deleteRule: .cascade, inverse: \LabResult.panel)
    var resultsStorage: [LabResult]? = []

    var items: [LabResult] {
        get { resultsStorage ?? [] }
        set { resultsStorage = newValue }
    }

    init(date: Date = .now, timeLabel: String? = nil, source: String? = nil, note: String? = nil) {
        self.date = date
        self.timeLabel = timeLabel
        self.source = source
        self.note = note
    }

    /// Katalog sırasına göre (kategori → katalogdaki sıra → ad) dizilmiş sonuçlar.
    var orderedItems: [LabResult] {
        items.sorted { a, b in
            let ra = LabCatalog.sortRank(code: a.code, name: a.name)
            let rb = LabCatalog.sortRank(code: b.code, name: b.name)
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Panel içindeki bir parametreyi kanonik koduyla bulur.
    func result(code: String) -> LabResult? {
        guard !code.isEmpty else { return nil }
        return items.first { $0.code == code }
    }

    /// Sayısal değeri olan parametrenin değeri.
    func value(_ code: String) -> Double? { result(code: code)?.value }
}

/// Panelin tek satırı: bir parametre + sonucu + laboratuvarın referans aralığı.
@Model
final class LabResult {
    /// `LabCatalog` kanonik kodu ("vitaminD", "ldl" …). Tanınmayan parametrelerde boş
    /// kalır — satır yine saklanır ve "Diğer" başlığı altında gösterilir.
    var code: String = ""
    /// Raporda yazan ham ad — kullanıcı kendi çıktısındaki adı görmeye devam etsin.
    var name: String = ""
    /// Sayısal sonuç. "<0.4" gibi sınırlı okumalarda nil kalır, ham metin `textValue`'da durur.
    var value: Double?
    /// Sayısal olmayan sonuç: "Negatif", "Açık Sarı", "<1" …
    var textValue: String?
    var unit: String?
    /// Laboratuvarın kendi referans aralığı (alt/üst uçlar; tek yönlüyse biri nil).
    var refLow: Double?
    var refHigh: Double?
    /// Referansın ham metni ("30 - 100", "< 41", "Negatif").
    var refText: String?
    var panel: LabPanel?

    init(
        code: String = "",
        name: String,
        value: Double? = nil,
        textValue: String? = nil,
        unit: String? = nil,
        refLow: Double? = nil,
        refHigh: Double? = nil,
        refText: String? = nil
    ) {
        self.code = code
        self.name = name
        self.value = value
        self.textValue = textValue
        self.unit = unit
        self.refLow = refLow
        self.refHigh = refHigh
        self.refText = refText
    }

    /// Katalog kaydı (varsa) — görünen ad, kategori, optimal aralık buradan gelir.
    var analyte: LabAnalyte? { LabCatalog.analyte(code: code) }

    /// Listede gösterilecek ad: katalogdaki kısa ad varsa o, yoksa rapordaki ham ad.
    var displayName: String { analyte?.name ?? name }

    var category: LabCategory { analyte?.category ?? .other }

    /// Ekranda gösterilecek sonuç metni (sayı ise ondalık basamağı katalogdan).
    var displayValue: String {
        if let value {
            return Fmt.num(value, digits: analyte?.decimals ?? LabCatalog.inferredDecimals(value))
        }
        return textValue ?? "—"
    }

    /// Laboratuvar referansının okunur hâli ("30 – 100", "< 41"). Sayısal uçlar
    /// çözülebildiyse onlar biçimlenir (ondalık ayracı sonuçla aynı olsun);
    /// niteliksel referanslarda ("Negatif") ham metin kalır.
    var displayReference: String? {
        let range = LabRange(refLow, refHigh)
        if !range.isEmpty { return range.display }
        if let refText, !refText.isEmpty { return LabRange.pretty(refText) }
        return nil
    }

    /// Katalogdaki hedef bant — laboratuvar referansıyla AYNIYSA gösterilmez
    /// ("ref < 200, hedef < 200" gibi boş tekrarları önler).
    var distinctOptimal: LabRange? {
        guard let optimal = analyte?.optimal, !optimal.isEmpty else { return nil }
        return optimal == LabRange(refLow, refHigh) ? nil : optimal
    }

    /// Değerlendirme: referans dışı mı, sınırda mı, optimal bantta mı.
    var status: LabStatus { LabCatalog.status(for: self) }
}
