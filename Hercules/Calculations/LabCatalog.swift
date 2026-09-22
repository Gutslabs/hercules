import Foundation

// MARK: - Kategoriler

/// Tahlil parametrelerinin gruplanması — sayfadaki bölümler ve AI özetindeki
/// başlıklar aynı sırayı kullanır.
enum LabCategory: String, CaseIterable, Identifiable, Hashable {
    case hemogram, lipid, metabolic, hormone, thyroid, liver, kidney, mineral, urine, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hemogram:  return "Kan Sayımı"
        case .lipid:     return "Lipid Paneli"
        case .metabolic: return "Şeker & Metabolizma"
        case .hormone:   return "Hormonlar"
        case .thyroid:   return "Tiroit"
        case .liver:     return "Karaciğer"
        case .kidney:    return "Böbrek"
        case .mineral:   return "Vitamin & Mineral"
        case .urine:     return "İdrar"
        case .other:     return "Diğer"
        }
    }

    /// Sayfadaki sıra — "spor performansına en çok dokunan" üstte.
    var order: Int {
        switch self {
        case .hormone:   return 0
        case .metabolic: return 1
        case .lipid:     return 2
        case .mineral:   return 3
        case .thyroid:   return 4
        case .hemogram:  return 5
        case .liver:     return 6
        case .kidney:    return 7
        case .urine:     return 8
        case .other:     return 9
        }
    }

    var icon: String {
        switch self {
        case .hemogram:  return "droplet"
        case .lipid:     return "heart-pulse"
        case .metabolic: return "activity"
        case .hormone:   return "flame"
        case .thyroid:   return "gauge"
        case .liver:     return "shield"
        case .kidney:    return "filter"
        case .mineral:   return "pill"
        case .urine:     return "flask-conical"
        case .other:     return "circle-help"
        }
    }
}

// MARK: - Yön ve durum

/// Parametrenin "iyi" yönü: bant içi mi, yüksek mi, düşük mü daha iyi.
enum LabDirection: String, Hashable {
    case band, higherBetter, lowerBetter
}

/// Bir sonucun değerlendirmesi. Renkler view katmanında bağlanır (bu dosya saf mantık).
enum LabStatus: String, Hashable {
    /// Referans dışı — alt sınırın altında.
    case low
    /// Referans dışı — üst sınırın üstünde.
    case high
    /// Referans içinde ama optimal bandın dışında (izlenecek).
    case watch
    /// Optimal bantta.
    case optimal
    /// Referans içinde, tanımlı optimal bandı yok.
    case normal
    /// Değerlendirilemedi (sonuç ya da referans yok).
    case unknown

    var label: String {
        switch self {
        case .low:     return "Düşük"
        case .high:    return "Yüksek"
        case .watch:   return "Sınırda"
        case .optimal: return "İdeal"
        case .normal:  return "Normal"
        case .unknown: return "—"
        }
    }

    /// Referans aralığının dışında mı (kırmızı bayrak).
    var isOutOfRange: Bool { self == .low || self == .high }

    /// "Öne çıkanlar" listesine girer mi.
    var needsAttention: Bool { isOutOfRange || self == .watch }

    /// Öne çıkanlar sıralaması — önce referans dışı, sonra sınırda.
    var severity: Int {
        switch self {
        case .low, .high: return 0
        case .watch:      return 1
        case .normal:     return 2
        case .optimal:    return 3
        case .unknown:    return 4
        }
    }
}

// MARK: - Aralık

/// Alt/üst uçlu aralık. Tek yönlü referanslarda ("< 41") uçlardan biri nil kalır.
struct LabRange: Hashable {
    var low: Double?
    var high: Double?

    init(_ low: Double?, _ high: Double?) {
        self.low = low
        self.high = high
    }

    var isEmpty: Bool { low == nil && high == nil }

    func contains(_ v: Double) -> Bool {
        if let low, v < low { return false }
        if let high, v > high { return false }
        return true
    }

    /// "30 - 100", "< 41", "<= 2", ">= 90", "0.108 - 0.282" → sayısal uçlar.
    /// Niteliksel referanslar ("Negatif") nil döner.
    static func parse(_ raw: String?) -> LabRange? {
        guard let raw else { return nil }
        let text = raw
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "≤", with: "<=")
            .replacingOccurrences(of: "≥", with: ">=")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        if let m = firstMatch(#"^(-?[\d.,]+)\s*-\s*(-?[\d.,]+)$"#, in: text),
           let lo = number(m[1]), let hi = number(m[2]) {
            return LabRange(min(lo, hi), max(lo, hi))
        }
        if let m = firstMatch(#"^<=?\s*(-?[\d.,]+)$"#, in: text), let hi = number(m[1]) {
            return LabRange(nil, hi)
        }
        if let m = firstMatch(#"^>=?\s*(-?[\d.,]+)$"#, in: text), let lo = number(m[1]) {
            return LabRange(lo, nil)
        }
        return nil
    }

    /// Uçların okunur hâli: "40 – 60", "< 2", "> 7". Ondalık basamak sayısı her uç
    /// için AYRI kestirilir — sabit basamak "hedef 40,0–60,0" gibi gereksiz sıfırlar
    /// üretiyordu.
    var display: String {
        func f(_ v: Double) -> String { Fmt.num(v, digits: LabCatalog.inferredDecimals(v)) }
        switch (low, high) {
        case let (lo?, hi?): return "\(f(lo)) – \(f(hi))"
        case let (nil, hi?): return "< \(f(hi))"
        case let (lo?, nil): return "> \(f(lo))"
        default: return ""
        }
    }

    /// Ham referans metnini okunur hâle getirir ("30 - 100" → "30 – 100").
    static func pretty(_ raw: String) -> String {
        raw.replacingOccurrences(of: " - ", with: " – ")
            .replacingOccurrences(of: "<=", with: "≤")
            .replacingOccurrences(of: ">=", with: "≥")
    }

    /// "<0.4" / "> 12" gibi sınırlı okumaları (karşılaştırıcı, sayı) olarak çözer.
    static func comparator(_ raw: String) -> (isLess: Bool, value: Double)? {
        let text = raw.replacingOccurrences(of: "≤", with: "<").replacingOccurrences(of: "≥", with: ">")
        guard let m = firstMatch(#"^([<>])=?\s*(-?[\d.,]+)$"#, in: text.trimmingCharacters(in: .whitespaces)),
              let v = number(m[2]) else { return nil }
        return (m[1] == "<", v)
    }

    /// Türkçe/İngilizce ondalık ayracını tolere eden sayı çözümü.
    static func number(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        // "1.003" gibi değerlerde '.' ondalık; binlik ayracı bu raporlarda geçmiyor.
        s = s.replacingOccurrences(of: ",", with: ".")
        return Double(s)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
        }
    }
}

// MARK: - Katalog kaydı

/// Bilinen bir tahlil parametresi: görünen adı, kategorisi, optimal bandı ve
/// "bu neden önemli" tek satırı. Optimal bant laboratuvar referansından AYRIDIR —
/// referans "hasta değilsin" sınırıdır, optimal bant sporcu/sağlık hedefidir.
struct LabAnalyte: Identifiable, Hashable {
    let code: String
    let name: String
    let category: LabCategory
    let unit: String?
    let aliases: [String]
    /// Bilgilendirici hedef bant (referansın içinde daha dar bir pencere).
    let optimal: LabRange?
    let direction: LabDirection
    let decimals: Int
    /// Tek satır bağlam — sayfada ve AI özetinde kullanılır.
    let note: String?
    /// Niteliksel parametrelerde beklenen sonuç ("Negatif").
    let expectedText: String?

    var id: String { code }

    init(
        _ code: String,
        _ name: String,
        _ category: LabCategory,
        unit: String? = nil,
        aliases: [String] = [],
        optimal: LabRange? = nil,
        direction: LabDirection = .band,
        decimals: Int = 1,
        note: String? = nil,
        expectedText: String? = nil
    ) {
        self.code = code
        self.name = name
        self.category = category
        self.unit = unit
        self.aliases = aliases
        self.optimal = optimal
        self.direction = direction
        self.decimals = decimals
        self.note = note
        self.expectedText = expectedText
    }
}

// MARK: - Katalog

enum LabCatalog {

    /// Bilinen parametreler. Sıra = kategori içindeki gösterim sırası.
    /// Optimal bantlar genel sağlık/spor literatüründeki yaygın hedeflerdir;
    /// tanı değildir, sayfada da öyle etiketlenir.
    static let all: [LabAnalyte] = [

        // MARK: Hormonlar
        LabAnalyte("testosteroneTotal", "Total Testosteron", .hormone, unit: "ng/dL",
                   aliases: ["total testesteron", "total testosteron", "testosteron", "total testesteron (serum)"],
                   optimal: LabRange(500, 900), direction: .higherBetter, decimals: 0,
                   note: "Kas yapımı, toparlanma ve motivasyonun ana sürücüsü."),
        LabAnalyte("testosteroneFree", "Serbest Testosteron", .hormone, unit: "pg/mL",
                   aliases: ["serbest testosteron", "free testosterone"],
                   optimal: LabRange(15, 25), direction: .higherBetter, decimals: 2,
                   note: "Dokuya gerçekten ulaşan pay — totalden daha belirleyici."),
        LabAnalyte("shbg", "SHBG", .hormone, unit: "nmol/L",
                   aliases: ["shbg", "seks hormonu baglayici globulin"],
                   optimal: LabRange(20, 45), decimals: 1,
                   note: "Yüksekse serbest testosteronu aşağı çeker."),
        LabAnalyte("dht", "DHT", .hormone, unit: "µg/L",
                   aliases: ["dehidrotestosteron (dht)", "dihidrotestosteron", "dht"],
                   decimals: 2, note: "Testosteronun güçlü türevi."),
        LabAnalyte("estradiol", "Östradiol (E2)", .hormone, unit: "pg/mL",
                   aliases: ["ostradiol", "estradiol", "e2"],
                   optimal: LabRange(20, 40), decimals: 1,
                   note: "Erkekte de gerekli; çok düşük/yüksek ikisi de sorun."),
        LabAnalyte("lh", "LH", .hormone, unit: "IU/L", aliases: ["lh", "luteinizan hormon"], decimals: 2),
        LabAnalyte("fsh", "FSH", .hormone, unit: "IU/L", aliases: ["fsh"], decimals: 2),
        LabAnalyte("prolactin", "Prolaktin", .hormone, unit: "ng/mL", aliases: ["prolaktin", "prl"], decimals: 1),
        LabAnalyte("cortisol", "Kortizol", .hormone, unit: "µg/dL",
                   aliases: ["kortizol", "cortisol"], optimal: LabRange(6, 18), decimals: 1,
                   note: "Kronik yüksekse toparlanma ve uyku bozulur."),
        LabAnalyte("igf1", "IGF-1", .hormone, unit: "ng/mL", aliases: ["igf-1", "igf 1", "somatomedin c"], decimals: 0),

        // MARK: Şeker & metabolizma
        LabAnalyte("glucose", "Açlık Glukozu", .metabolic, unit: "mg/dL",
                   aliases: ["glukoz", "aclik kan sekeri", "glukoz (serum)", "kan sekeri"],
                   optimal: LabRange(75, 92), decimals: 0,
                   note: "Aç karnına kan şekeri — insülin duyarlılığının ilk göstergesi."),
        LabAnalyte("insulin", "İnsülin", .metabolic, unit: "mU/L",
                   aliases: ["insulin", "aclik insulin"],
                   optimal: LabRange(nil, 8), direction: .lowerBetter, decimals: 1,
                   note: "Açlık insülini düşükse yağ yakımı daha kolay."),
        LabAnalyte("hba1c", "HbA1c", .metabolic, unit: "%",
                   aliases: ["glikolize hemoglobin (hb a1c), hplc yontemi ile", "glikolize hemoglobin (hb a1c)",
                             "hba1c", "hemoglobin a1c", "glikolize hemoglobin"],
                   optimal: LabRange(nil, 5.4), direction: .lowerBetter, decimals: 2,
                   note: "Son ~3 ayın ortalama kan şekeri."),
        LabAnalyte("hba1cIfcc", "HbA1c (IFCC)", .metabolic, unit: "mmol/mol",
                   aliases: ["hba1c (ifcc)", "hba1c ifcc"],
                   optimal: LabRange(nil, 36), direction: .lowerBetter, decimals: 0),
        LabAnalyte("uricAcid", "Ürik Asit", .metabolic, unit: "mg/dL",
                   aliases: ["urik asit", "ürik asit"], optimal: LabRange(3.5, 6.5), decimals: 1),

        // MARK: Lipid
        LabAnalyte("cholesterol", "Total Kolesterol", .lipid, unit: "mg/dL",
                   aliases: ["kolesterol", "total kolesterol", "kolesterol (total)"],
                   optimal: LabRange(nil, 200), direction: .lowerBetter, decimals: 0,
                   note: "Tek başına değil; HDL ve trigliseridle birlikte okunur."),
        LabAnalyte("ldl", "LDL Kolesterol", .lipid, unit: "mg/dL",
                   aliases: ["ldl kolesterol", "ldl", "ldl-kolesterol"],
                   optimal: LabRange(nil, 100), direction: .lowerBetter, decimals: 0,
                   note: "Damar riskinin ana taşıyıcısı — hedef bant referanstan dar."),
        LabAnalyte("hdl", "HDL Kolesterol", .lipid, unit: "mg/dL",
                   aliases: ["hdl kolesterol", "hdl"],
                   optimal: LabRange(50, nil), direction: .higherBetter, decimals: 0,
                   note: "Yüksek olması korur; kardiyo ve zeytinyağı yükseltir."),
        LabAnalyte("nonHdl", "Non-HDL Kolesterol", .lipid, unit: "mg/dL",
                   aliases: ["non-hdl kolesterol", "non hdl kolesterol", "nonhdl"],
                   optimal: LabRange(nil, 130), direction: .lowerBetter, decimals: 0,
                   note: "Total − HDL: aterojenik yükün tek sayıdaki özeti."),
        LabAnalyte("vldl", "VLDL Kolesterol", .lipid, unit: "mg/dL",
                   aliases: ["vldl kolesterol", "vldl"],
                   optimal: LabRange(nil, 30), direction: .lowerBetter, decimals: 0),
        LabAnalyte("triglyceride", "Trigliserid", .lipid, unit: "mg/dL",
                   aliases: ["trigliserid", "trigliserit", "triglyceride"],
                   optimal: LabRange(nil, 100), direction: .lowerBetter, decimals: 0,
                   note: "Karbonhidrat/alkol yüküne en hızlı tepki veren lipid."),

        // MARK: Vitamin & mineral
        LabAnalyte("vitaminD", "D Vitamini (25-OH)", .mineral, unit: "µg/L",
                   aliases: ["25-hidroksi vitamin d", "25 oh vitamin d", "vitamin d", "d vitamini", "25-oh vitamin d"],
                   optimal: LabRange(40, 60), direction: .higherBetter, decimals: 1,
                   note: "Testosteron, kemik ve bağışıklık; kışın kaçınılmaz düşer."),
        LabAnalyte("b12", "B12 Vitamini", .mineral, unit: "ng/L",
                   aliases: ["vitamin b12", "b12", "b12 vitamini", "kobalamin"],
                   optimal: LabRange(400, 800), direction: .higherBetter, decimals: 0,
                   note: "Sinir sistemi ve kan yapımı; alt sınıra yakın da semptom verebilir."),
        LabAnalyte("folate", "Folat", .mineral, unit: "µg/L",
                   aliases: ["folat", "folik asit"],
                   optimal: LabRange(7, nil), direction: .higherBetter, decimals: 1,
                   note: "B12 ile birlikte kan yapımında çalışır."),
        LabAnalyte("ferritin", "Ferritin", .mineral, unit: "µg/L",
                   aliases: ["ferritin"], optimal: LabRange(50, 150), decimals: 0,
                   note: "Demir deposu. Çok düşük = yorgunluk, çok yüksek = inflamasyon."),
        LabAnalyte("iron", "Demir (Serum)", .mineral, unit: "µg/dL",
                   aliases: ["demir (serum)", "demir", "serum demir"], decimals: 0),
        LabAnalyte("uibc", "Demir Bağlama (UIBC)", .mineral, unit: "µg/dL",
                   aliases: ["demir baglama kapasitesi", "uibc", "serbest demir baglama kapasitesi"], decimals: 0),
        LabAnalyte("tibc", "Total Demir Bağlama", .mineral, unit: "µg/dL",
                   aliases: ["total demir baglama kapasitesi", "tibc", "tdbk"], decimals: 0),
        LabAnalyte("zinc", "Çinko", .mineral, unit: "µg/dL",
                   aliases: ["cinko", "zn"], optimal: LabRange(90, 120), decimals: 0,
                   note: "Testosteron üretimi ve bağışıklık için kritik."),
        LabAnalyte("magnesium", "Magnezyum", .mineral, unit: "mg/dL",
                   aliases: ["magnezyum", "mg"], optimal: LabRange(2.0, 2.4), decimals: 2,
                   note: "Uyku kalitesi ve kas kasılması."),
        LabAnalyte("calcium", "Kalsiyum", .mineral, unit: "mg/dL",
                   aliases: ["kalsiyum", "ca"], optimal: LabRange(9.0, 10.2), decimals: 1),
        LabAnalyte("sodium", "Sodyum", .mineral, unit: "mmol/L",
                   aliases: ["sodyum (na) (serum ve vucut sivilarinda, herbiri)", "sodyum (na)", "sodyum", "na"],
                   decimals: 1),
        LabAnalyte("potassium", "Potasyum", .mineral, unit: "mmol/L",
                   aliases: ["potasyum", "k"], decimals: 2),

        // MARK: Tiroit
        LabAnalyte("tsh", "TSH", .thyroid, unit: "mIU/L",
                   aliases: ["tsh", "tiroid stimulan hormon"],
                   optimal: LabRange(0.5, 2.5), decimals: 2,
                   note: "Üst yarıya kayması yavaşlayan metabolizmanın erken işareti."),
        LabAnalyte("ft4", "Serbest T4", .thyroid, unit: "ng/dL",
                   aliases: ["serbest t4", "ft4", "st4"], optimal: LabRange(1.0, 1.5), decimals: 2),
        LabAnalyte("ft3", "Serbest T3", .thyroid, unit: "pg/mL",
                   aliases: ["serbest t3", "ft3", "st3"], optimal: LabRange(3.0, 4.2), decimals: 2,
                   note: "Uzun kalori açığında ilk düşen tiroit değeri."),

        // MARK: Karaciğer
        LabAnalyte("alt", "ALT", .liver, unit: "U/L",
                   aliases: ["alanin aminotransferaz (alt)", "alt", "sgpt", "alanin aminotransferaz"],
                   optimal: LabRange(nil, 30), direction: .lowerBetter, decimals: 0,
                   note: "Ağır antrenman sonrası geçici yükselebilir."),
        LabAnalyte("ast", "AST", .liver, unit: "U/L",
                   aliases: ["aspartat transaminaz (ast)", "ast", "sgot", "aspartat transaminaz"],
                   optimal: LabRange(nil, 30), direction: .lowerBetter, decimals: 0,
                   note: "Kas yıkımıyla da yükselir — tek başına karaciğer demek değil."),
        LabAnalyte("ggt", "GGT", .liver, unit: "IU/L",
                   aliases: ["gamma glutamil transferaz (ggt)", "ggt", "gama glutamil transferaz"],
                   optimal: LabRange(nil, 30), direction: .lowerBetter, decimals: 0,
                   note: "Alkol ve yağlanmaya en duyarlı karaciğer enzimi."),
        LabAnalyte("alp", "ALP", .liver, unit: "IU/L",
                   aliases: ["alkalen fosfataz", "alp"], decimals: 0),
        LabAnalyte("albumin", "Albümin", .liver, unit: "g/dL",
                   aliases: ["albumin"], optimal: LabRange(4.2, 5.0), decimals: 1),
        LabAnalyte("bilirubinTotal", "Total Bilirubin", .liver, unit: "mg/dL",
                   aliases: ["total bilirubin", "bilirubin (total)"], decimals: 2),

        // MARK: Böbrek
        LabAnalyte("creatinine", "Kreatinin", .kidney, unit: "mg/dL",
                   aliases: ["kreatinin"], decimals: 2,
                   note: "Kas kütlesi ve kreatin kullanımı bu değeri yukarı iter."),
        LabAnalyte("urea", "Üre", .kidney, unit: "mg/dL",
                   aliases: ["ure", "üre", "bun", "kan uresi"], decimals: 0,
                   note: "Yüksek protein alımında üst banda oturması beklenir."),
        LabAnalyte("egfr", "eGFR", .kidney, unit: "ml/dk/1.73 m²",
                   aliases: ["e-gfr", "egfr", "gfr"],
                   optimal: LabRange(90, nil), direction: .higherBetter, decimals: 0,
                   note: "Böbrek filtrasyon hızı — 90 üstü hedef."),

        // MARK: Kan sayımı
        LabAnalyte("wbc", "Lökosit (WBC)", .hemogram, unit: "10⁹/L",
                   aliases: ["wbc", "lokosit", "beyaz kure"], optimal: LabRange(4.5, 9.0), decimals: 2,
                   note: "Toplam bağışıklık hücresi."),
        LabAnalyte("rbc", "Eritrosit (RBC)", .hemogram, unit: "10¹²/L",
                   aliases: ["rbc", "eritrosit", "kirmizi kure"], decimals: 2),
        LabAnalyte("hgb", "Hemoglobin", .hemogram, unit: "g/dL",
                   aliases: ["hgb", "hemoglobin", "hb"], optimal: LabRange(14, 17), decimals: 1,
                   note: "Kasa oksijen taşıma kapasitesi — dayanıklılığın tabanı."),
        LabAnalyte("hct", "Hematokrit", .hemogram, unit: "%",
                   aliases: ["hct", "hematokrit"], optimal: LabRange(41, 50), decimals: 1),
        LabAnalyte("mcv", "MCV", .hemogram, unit: "fL", aliases: ["mcv"], decimals: 1,
                   note: "Alyuvar hacmi; düşükse demir, yüksekse B12 tarafına bakılır."),
        LabAnalyte("mch", "MCH", .hemogram, unit: "pg", aliases: ["mch"], decimals: 1),
        LabAnalyte("mchc", "MCHC", .hemogram, unit: "g/dL", aliases: ["mchc"], decimals: 1),
        LabAnalyte("rdw", "RDW", .hemogram, unit: "%", aliases: ["rdw"], decimals: 1),
        LabAnalyte("rdwsd", "RDW-SD", .hemogram, unit: "fL", aliases: ["rdw-sd", "rdw sd"], decimals: 1),
        LabAnalyte("plt", "Trombosit (Plt)", .hemogram, unit: "10⁹/L",
                   aliases: ["plt", "trombosit", "platelet"], decimals: 0),
        LabAnalyte("mpv", "MPV", .hemogram, unit: "fL", aliases: ["mpv"], decimals: 1),
        LabAnalyte("pdw", "PDW", .hemogram, aliases: ["pdw"], decimals: 1),
        LabAnalyte("pct", "Pct", .hemogram, aliases: ["pct"], decimals: 3),
        LabAnalyte("neuAbs", "Nötrofil #", .hemogram, unit: "10⁹/L", aliases: ["neu#", "neu #", "notrofil"], decimals: 2),
        LabAnalyte("neuPct", "Nötrofil %", .hemogram, unit: "%", aliases: ["neu%", "neu %"], decimals: 1),
        LabAnalyte("lyAbs", "Lenfosit #", .hemogram, unit: "10⁹/L", aliases: ["ly#", "ly #", "lenfosit"], decimals: 2),
        LabAnalyte("lyPct", "Lenfosit %", .hemogram, unit: "%", aliases: ["ly%", "ly %"], decimals: 1),
        LabAnalyte("moAbs", "Monosit #", .hemogram, unit: "10⁹/L", aliases: ["mo#", "mo #", "monosit"], decimals: 2),
        LabAnalyte("moPct", "Monosit %", .hemogram, unit: "%", aliases: ["mo%", "mo %"], decimals: 1),
        LabAnalyte("eosAbs", "Eozinofil #", .hemogram, unit: "10⁹/L", aliases: ["eos#", "eos #", "eozinofil"], decimals: 2),
        LabAnalyte("eosPct", "Eozinofil %", .hemogram, unit: "%", aliases: ["eos%", "eos %"], decimals: 1),
        LabAnalyte("basoAbs", "Bazofil #", .hemogram, unit: "10⁹/L", aliases: ["baso#", "baso #", "bazofil"], decimals: 2),
        LabAnalyte("basoPct", "Bazofil %", .hemogram, unit: "%", aliases: ["baso%", "baso %"], decimals: 1),
        LabAnalyte("nlr", "NLR", .hemogram,
                   aliases: ["nlr", "notrofil/lenfosit orani"],
                   optimal: LabRange(nil, 2.0), direction: .lowerBetter, decimals: 2,
                   note: "Nötrofil/lenfosit — sessiz inflamasyonun ucuz göstergesi."),
        LabAnalyte("nrbcAbs", "NRBC #", .hemogram, unit: "10⁹/L", aliases: ["nrbc#", "nrbc #"], decimals: 2),
        LabAnalyte("nrbcPct", "NRBC %", .hemogram, unit: "%", aliases: ["nrbc%", "nrbc %"], decimals: 1),

        // MARK: İdrar (niteliksel — beklenen sonuçla karşılaştırılır)
        LabAnalyte("urineColor", "Renk", .urine, aliases: ["renk"], decimals: 0),
        LabAnalyte("urineClarity", "Yassı Epitel", .urine, aliases: ["yassi epitel", "gorunum", "berraklik"],
                   decimals: 0, expectedText: "Berrak"),
        LabAnalyte("urineDensity", "Dansite", .urine, aliases: ["dansite", "yogunluk"], decimals: 3),
        LabAnalyte("urinePh", "pH", .urine, aliases: ["ph"], decimals: 1),
        LabAnalyte("urineProtein", "Protein", .urine, aliases: ["protein"], decimals: 0, expectedText: "Negatif"),
        LabAnalyte("urineGlucose", "Glukoz", .urine, aliases: ["glukoz"], decimals: 0, expectedText: "Negatif"),
        LabAnalyte("urineKetone", "Keton", .urine, aliases: ["keton"], decimals: 0, expectedText: "Negatif"),
        LabAnalyte("urineBilirubin", "Bilirübin", .urine, aliases: ["bilirubin", "bilirübin"], decimals: 0, expectedText: "Negatif"),
        LabAnalyte("urineUrobilinogen", "Ürobilinojen", .urine, aliases: ["urobilinojen"], decimals: 0, expectedText: "Normal"),
        LabAnalyte("urineBlood", "Kan (BLD)", .urine, aliases: ["bld", "kan"], decimals: 0, expectedText: "Negatif"),
        LabAnalyte("urineNitrite", "Nitrit", .urine, aliases: ["nitrin", "nitrit"], decimals: 0, expectedText: "Negatif"),
        LabAnalyte("urineLeukocyteEsterase", "Lökosit Esteraz (LEU)", .urine, aliases: ["leu"], decimals: 0, expectedText: "Negatif"),
        LabAnalyte("urineWbc", "Lökosit (mikroskopi)", .urine, unit: "/HPF", aliases: ["lokosit (wbc)", "lokosit"], decimals: 0),
        LabAnalyte("urineRbc", "Eritrosit (mikroskopi)", .urine, unit: "/HPF", aliases: ["eritrosit (rbc)", "eritrosit"], decimals: 0),
    ]

    // MARK: Arama

    private static let byCode: [String: LabAnalyte] = Dictionary(
        all.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a }
    )

    private static let rankByCode: [String: Int] = {
        var out: [String: Int] = [:]
        for (i, a) in all.enumerated() { out[a.code] = a.category.order * 1000 + i }
        return out
    }()

    /// Kan (idrar dışı) parametrelerin ad → kod tablosu.
    private static let bloodIndex: [String: String] = buildIndex(all.filter { $0.category != .urine })
    /// İdrar parametrelerinin ad → kod tablosu ("Glukoz", "Protein" gibi adlar
    /// kanla ÇAKIŞIR; hangisinin kazanacağına rapordaki bölüm karar verir).
    private static let urineIndex: [String: String] = buildIndex(all.filter { $0.category == .urine })

    private static func buildIndex(_ items: [LabAnalyte]) -> [String: String] {
        var out: [String: String] = [:]
        for a in items {
            for key in ([a.name] + a.aliases).map(normalize) where !key.isEmpty {
                if out[key] == nil { out[key] = a.code }
            }
        }
        return out
    }

    static func analyte(code: String) -> LabAnalyte? {
        code.isEmpty ? nil : byCode[code]
    }

    /// Rapordaki ham adı kanonik koda çevirir. `preferUrine` idrar bölümündeki
    /// satırlar için verilir.
    static func match(name: String, preferUrine: Bool = false) -> String? {
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        let primary = preferUrine ? urineIndex : bloodIndex
        let secondary = preferUrine ? bloodIndex : urineIndex
        if let hit = primary[key] ?? secondary[key] { return hit }

        // Parantezli açıklama kuyruğunu at: "Sodyum (Na) (Serum ve vücut …)" → "sodyum".
        if let cut = key.firstIndex(of: "("), cut != key.startIndex {
            let head = String(key[key.startIndex..<cut]).trimmingCharacters(in: .whitespaces)
            if !head.isEmpty, let hit = primary[head] ?? secondary[head] { return hit }
        }
        return nil
    }

    /// Kategori → katalog sırası. Tanınmayan parametreler kendi kategorisinin sonunda.
    static func sortRank(code: String, name: String) -> Int {
        if let rank = rankByCode[code] { return rank }
        return LabCategory.other.order * 1000 + 500
    }

    /// Türkçe harfleri sadeleştirip noktalama/boşluk gürültüsünü siler.
    /// `ı` ve `İ` diacritic DEĞİL, ayrı harflerdir — folding onları çevirmez, bu
    /// yüzden "Yassı Epitel" ↔ "yassi epitel" eşleşsin diye elle çeviriyoruz.
    static func normalize(_ s: String) -> String {
        var ascii = s
        for (from, to) in [("ı", "i"), ("İ", "i"), ("ş", "s"), ("Ş", "s"), ("ğ", "g"), ("Ğ", "g"),
                           ("ç", "c"), ("Ç", "c"), ("ö", "o"), ("Ö", "o"), ("ü", "u"), ("Ü", "u"),
                           ("â", "a"), ("î", "i"), ("û", "u")] {
            ascii = ascii.replacingOccurrences(of: from, with: to)
        }
        let folded = ascii.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US"))
        let cleaned = folded.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "(" || ch == ")" || ch == "#" || ch == "%" || ch == "-" || ch == "/" {
                return ch
            }
            return " "
        }
        return String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .lowercased()
    }

    // MARK: Değerlendirme

    static func status(for result: LabResult) -> LabStatus {
        let analyte = analyte(code: result.code)

        guard let value = result.value else {
            guard let raw = result.textValue?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
                return .unknown
            }
            // "<1" gibi sınırlı okuma: referansın hangi tarafında kaldığı belliyse değerlendir.
            if let cmp = LabRange.comparator(raw) {
                if cmp.isLess {
                    if let hi = result.refHigh, cmp.value <= hi { return .optimal }
                    if result.refHigh == nil, result.refLow == nil { return .normal }
                    return .normal
                }
                if let lo = result.refLow, cmp.value >= lo { return .optimal }
                return .normal
            }
            // Niteliksel: beklenen sonuçla karşılaştır ("Negatif" == "Negatif").
            let expected = analyte?.expectedText ?? result.refText
            guard let expected, !expected.isEmpty, LabRange.parse(expected) == nil else { return .normal }
            return normalize(raw) == normalize(expected) ? .optimal : .watch
        }

        if let lo = result.refLow, value < lo { return .low }
        if let hi = result.refHigh, value > hi { return .high }

        if let optimal = analyte?.optimal, !optimal.isEmpty {
            return optimal.contains(value) ? .optimal : .watch
        }
        return (result.refLow != nil || result.refHigh != nil) ? .normal : .normal
    }

    /// Skalanın çizileceği aralık: referans + hedef bandı + sonucun kendisi.
    ///
    /// Tek yönlü referanslarda ("< 200", "> 90") skalanın diğer ucu YOKTUR. Sadece
    /// mevcut uçlardan aralık kurarsak sınır çubuğun dışında kalır ve bar baştan
    /// sona "referans dışı" görünür — "ne kadar aştım" sorusu cevapsız kalır. Bu
    /// yüzden alt uç yoksa sıfıra, üst uç yoksa değerin bir miktar üstüne açılır.
    static func displayRange(for result: LabResult) -> LabRange? {
        guard let value = result.value else { return nil }
        let optimal = analyte(code: result.code)?.optimal

        let bounds = [result.refLow, result.refHigh, optimal?.low, optimal?.high].compactMap { $0 } + [value]
        guard var lo = bounds.min(), var hi = bounds.max() else { return nil }

        let hasLower = result.refLow != nil || optimal?.low != nil
        let hasUpper = result.refHigh != nil || optimal?.high != nil
        if !hasLower, lo >= 0 { lo = 0 }
        if !hasUpper { hi = max(hi, 0) * 1.35 }
        if hi <= lo { hi = lo + max(abs(lo) * 0.2, 1) }

        // Uçlarda nefes payı: değer tam sınıra otursa bile imleç kenara yapışmasın.
        // Yalnız gerçek sınırı olan tarafa eklenir; sıfır tabanı sıfırda kalsın.
        let pad = (hi - lo) * 0.12
        return LabRange(hasLower ? lo - pad : lo, hasUpper ? hi + pad : hi)
    }

    static func position(for result: LabResult) -> Double? {
        guard let value = result.value,
              let range = displayRange(for: result),
              let lo = range.low, let hi = range.high, hi > lo
        else { return nil }
        return min(1, max(0, (value - lo) / (hi - lo)))
    }

    static func inferredDecimals(_ v: Double) -> Int {
        let a = abs(v)
        for digits in 0...3 {
            let scaled = a * pow(10, Double(digits))
            if abs(scaled - scaled.rounded()) < 1e-6 { return digits }
        }
        return 2
    }
}
