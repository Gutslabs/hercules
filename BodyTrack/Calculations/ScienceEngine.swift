import Foundation

/// Bilim-temelli analitik motoru. SAF hesaplama (UI/SwiftData state taşımaz) — sadece
/// `Measurement` + `FoodEntry` zaman serilerinden türetir. İlk modül: enerji dengesi
/// kimliğinden ADAPTİF TDEE + trend kilo + kayıp-hızı bekçisi + hedef ETA.
///
/// Bilim: Statik TDEE (BMR × aktivite) bir TAHMİNDİR ve metabolik adaptasyonu (Rosenbaum
/// & Leibel) yansıtmaz. Gerçek bakım, enerji dengesi kimliğinden geriye çözülür:
///   TDEE ≈ ortalama_alım − (Δkilo_kg × ~7700 kcal/kg) / gün
/// MacroFactor'ın yaklaşımı budur. ~7700 kcal/kg vücut kütlesi (yağ) konvansiyonudur
/// (1 lb ≈ 3500 kcal). Sağlıklı kayıp hızı ~%0.5–1.0 BW/hafta yağsız kütleyi korur
/// (Garthe 2011; Helms 2014).
enum ScienceEngine {

    /// 1 kg vücut kütlesi ≈ ~7700 kcal (yağ dokusu konvansiyonu).
    static let kcalPerKg: Double = 7700

    // MARK: - Adaptif enerji

    struct AdaptiveEnergy {
        enum Confidence: Int, Comparable {
            case low, medium, high
            static func < (l: Confidence, r: Confidence) -> Bool { l.rawValue < r.rawValue }
            var label: String {
                switch self {
                case .low:    return "Düşük güven"
                case .medium: return "Orta güven"
                case .high:   return "Yüksek güven"
                }
            }
            var detail: String {
                switch self {
                case .low:    return "Az veri — birkaç gün daha logla, netleşir."
                case .medium: return "İyi veri; trend oturuyor."
                case .high:   return "Bol veri — bu tahmin sağlam."
                }
            }
        }

        let windowDays: Int
        let loggedDays: Int
        let avgIntake: Double          // kcal/gün (yalnızca kayıtlı günler)
        let weightPoints: Int
        let weightSpanDays: Int
        let slopeKgPerWeek: Double      // işaretli; negatif = kaybediyor
        let trendWeightNow: Double      // regresyon fit (now) — gürültüsüz trend kilo
        let rawWeightNow: Double        // en son ham ölçüm
        let adaptiveTDEE: Double        // kcal/gün — gerçek bakım tahmini
        let confidence: Confidence

        /// Haftalık değişimin vücut ağırlığına oranı (%/hafta). Negatif = kayıp.
        var ratePercentPerWeek: Double {
            guard trendWeightNow > 0 else { return 0 }
            return slopeKgPerWeek / trendWeightNow * 100
        }

        /// Ortalama alımın adaptif bakıma göre günlük dengesi (negatif = açık).
        var dailyBalanceVsMaintenance: Double { avgIntake - adaptiveTDEE }
    }

    /// Adaptif TDEE'yi enerji dengesinden çöz. Yeterli veri yoksa nil.
    /// Gereksinim: pencerede ≥2 kilo ölçümü (≥10 gün aralık) + ≥7 kayıtlı yemek günü.
    static func adaptiveEnergy(
        measurements: [Measurement],
        foods: [FoodEntry],
        windowDays: Int = 28,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AdaptiveEnergy? {
        let end = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: end) else { return nil }

        // 1) Pencere içindeki kilo noktaları
        let weightPts = TrendAnalysis.points(measurements, for: .weight)
            .filter { $0.date >= start && $0.date <= end }
        guard weightPts.count >= 2, let firstW = weightPts.first, let lastW = weightPts.last else { return nil }
        let spanDays = Int((lastW.date.timeIntervalSince(firstW.date) / 86_400).rounded())
        guard spanDays >= 10 else { return nil }

        // 2) Regresyon eğimi (kg/gün) + trend kilo (now). 3+ nokta varsa en-küçük-kareler.
        let slopePerDay: Double
        let trendNow: Double
        if let fit = TrendAnalysis.linearFit(weightPts) {
            slopePerDay = fit.slope
            trendNow = fit.value(at: end)
        } else {
            let days = max(1, lastW.date.timeIntervalSince(firstW.date) / 86_400)
            slopePerDay = (lastW.value - firstW.value) / days
            trendNow = lastW.value
        }

        // 3) Pencere içi ortalama alım (kayıtlı günler)
        let inRange = foods.filter { $0.date >= start && $0.date <= end }
        let loggedDays = Set(inRange.map { calendar.startOfDay(for: $0.date) }).count
        guard loggedDays >= 7 else { return nil }
        let avgIntake = inRange.reduce(0) { $0 + $1.calories } / Double(loggedDays)

        // 4) Enerji dengesi: TDEE = alım − Δkilo×kcalPerKg
        let tdee = max(800, avgIntake - slopePerDay * kcalPerKg)

        // 5) Güven
        let confidence: AdaptiveEnergy.Confidence
        if loggedDays >= 21, spanDays >= 21, weightPts.count >= 5 {
            confidence = .high
        } else if loggedDays >= 14, spanDays >= 14, weightPts.count >= 3 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return AdaptiveEnergy(
            windowDays: windowDays,
            loggedDays: loggedDays,
            avgIntake: avgIntake,
            weightPoints: weightPts.count,
            weightSpanDays: spanDays,
            slopeKgPerWeek: slopePerDay * 7,
            trendWeightNow: trendNow,
            rawWeightNow: lastW.value,
            adaptiveTDEE: tdee,
            confidence: confidence
        )
    }

    /// Veri yetersizse en geniş pencereden başlayıp daralarak ilk geçerli sonucu dener.
    static func bestAdaptiveEnergy(
        measurements: [Measurement],
        foods: [FoodEntry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AdaptiveEnergy? {
        for w in [28, 35, 42, 21] {
            if let r = adaptiveEnergy(measurements: measurements, foods: foods, windowDays: w, now: now, calendar: calendar) {
                return r
            }
        }
        return nil
    }

    // MARK: - Kayıp/kazanım hızı bekçisi

    enum RateTone { case good, warn, bad, neutral }

    struct RateVerdict {
        let label: String
        let note: String
        let tone: RateTone
    }

    /// %/hafta (negatif = kayıp) + hedefe göre bilimsel hız yorumu.
    static func rateVerdict(percentPerWeek p: Double, goal: Goal) -> RateVerdict {
        // Hedef kilo vermek ama trend düz/yukarı → stall uyarısı
        if (goal == .lose || goal == .loseFast), p > -0.1 {
            return RateVerdict(
                label: "Plato / ters yön",
                note: "Hedefin kilo vermek ama trend düşmüyor. Ya alım bakıma yakın, ya loglama eksik, ya da su tutuyorsun. Adaptif TDEE'ye göre küçük bir açık aç.",
                tone: .warn
            )
        }
        switch p {
        case ..<(-1.0):
            return RateVerdict(
                label: "Çok hızlı kayıp",
                note: ">%1/hafta. Kas kaybı + metabolik adaptasyon riski (Garthe 2011). Açığı biraz daralt, proteini yüksek tut.",
                tone: .bad
            )
        case (-1.0)..<(-0.35):
            return RateVerdict(
                label: "Sağlıklı kayıp",
                note: "~%0.5–1/hafta ideal aralık — yağ giderken yağsız kütle korunur (Helms 2014).",
                tone: .good
            )
        case (-0.35)..<(-0.1):
            return RateVerdict(
                label: "Yavaş kayıp",
                note: "Sürdürülebilir ama açık küçük. Acelen varsa biraz artırabilirsin; değilse kas koruma açısından gayet iyi.",
                tone: .neutral
            )
        case (-0.1)...0.1:
            return RateVerdict(
                label: "Stabil (bakım)",
                note: "Kilo trendi düz — şu an bakım kalorisindesin.",
                tone: .neutral
            )
        case 0.1...0.5:
            let leanBulk = (goal == .gain || goal == .gainFast)
            return RateVerdict(
                label: leanBulk ? "Lean bulk aralığı" : "Hafif kilo alımı",
                note: "~%0.25–0.5/hafta — kas kazanımı için verimli, yağ kazanımı sınırlı (Aragon & Schoenfeld).",
                tone: leanBulk ? .good : .neutral
            )
        default:
            return RateVerdict(
                label: "Hızlı kilo alımı",
                note: ">%0.5/hafta. Fazlanın artan kısmı yağ olarak gider; bulk'taysan surplus'u biraz kıs.",
                tone: .warn
            )
        }
    }

    // MARK: - Hedef ETA

    struct GoalProjection {
        let targetWeight: Double
        let trendNow: Double
        let kgToGo: Double          // hedef − trend (negatif = vermesi gerek)
        let movingToward: Bool
        let etaDays: Int?
        let etaDate: Date?
    }

    /// Adaptif trend + eğimle hedef kiloya varış tahmini.
    static func goalProjection(
        energy: AdaptiveEnergy,
        targetWeight: Double?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalProjection? {
        guard let target = targetWeight, target > 0 else { return nil }
        let kgToGo = target - energy.trendWeightNow
        let slopePerDay = energy.slopeKgPerWeek / 7
        // Hedefe yaklaşma yönü doğru mu (ikisi de aynı işaret)?
        let movingToward = (kgToGo < 0 && slopePerDay < -1e-4) || (kgToGo > 0 && slopePerDay > 1e-4)
        var etaDays: Int? = nil
        var etaDate: Date? = nil
        if movingToward {
            let d = Int((kgToGo / slopePerDay).rounded())
            if d > 0, d < 3650 {
                etaDays = d
                etaDate = calendar.date(byAdding: .day, value: d, to: now)
            }
        }
        return GoalProjection(
            targetWeight: target,
            trendNow: energy.trendWeightNow,
            kgToGo: kgToGo,
            movingToward: movingToward,
            etaDays: etaDays,
            etaDate: etaDate
        )
    }

    // MARK: - Güç ilerlemesi (tahmini 1RM)

    /// Epley formülü: e1RM = ağırlık × (1 + tekrar/30). Tek tekrar ≈ ağırlık.
    /// Loglanan set verisinden lift başına güç trendini çıkarır.
    static func estimatedOneRM(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    struct LiftProgress: Identifiable {
        enum Trend { case improving, flat, declining }
        let name: String              // gösterilecek ad (en sık kullanılan yazım)
        let sessions: Int
        let firstE1RM: Double
        let latestE1RM: Double
        let bestE1RM: Double
        let changePercent: Double     // ilk → son
        let trend: Trend
        let lastDate: Date
        var id: String { name }

        /// ≥4 seans + düşüş trendi → yorgunluk birikmiş olabilir, deload mantıklı.
        var suggestsDeload: Bool { sessions >= 4 && trend == .declining }
    }

    static func strengthProgress(
        workouts: [WorkoutLog],
        windowDays: Int = 90,
        minSessions: Int = 2,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [LiftProgress] {
        let start = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now

        // exerciseKey → (date, bestE1RM, displayName)
        struct Sample { let date: Date; let e1rm: Double; let display: String }
        var byKey: [String: [Sample]] = [:]

        for log in workouts where log.date >= start {
            for ex in log.exercises {
                let best = ex.setEntries.compactMap { s -> Double? in
                    guard let w = s.weight, w > 0, s.reps > 0 else { return nil }
                    return estimatedOneRM(weight: w, reps: s.reps)
                }.max()
                guard let bestE1RM = best, bestE1RM > 0 else { continue }
                let key = normalizeName(ex.name)
                guard !key.isEmpty else { continue }
                byKey[key, default: []].append(Sample(date: log.date, e1rm: bestE1RM, display: ex.name))
            }
        }

        var out: [LiftProgress] = []
        for (_, rawSamples) in byKey {
            // Aynı günde birden fazla → o günün en iyisi (set/oturum gürültüsünü azalt)
            let byDay = Dictionary(grouping: rawSamples) { calendar.startOfDay(for: $0.date) }
            let daily = byDay.map { (day, samples) -> Sample in
                let best = samples.max(by: { $0.e1rm < $1.e1rm })!
                return Sample(date: day, e1rm: best.e1rm, display: best.display)
            }.sorted { $0.date < $1.date }

            guard daily.count >= minSessions, let first = daily.first, let last = daily.last else { continue }
            let bestE1RM = daily.map(\.e1rm).max() ?? last.e1rm
            let change = first.e1rm > 0 ? (last.e1rm - first.e1rm) / first.e1rm * 100 : 0

            // Trend: e1RM serisine regresyon eğimi (kg/gün); eşik ~%0.05/gün
            let trend: LiftProgress.Trend
            let pts = daily.map { TrendPoint(date: $0.date, value: $0.e1rm) }
            if let fit = TrendAnalysis.linearFit(pts) {
                let perWeek = fit.slope * 7
                if perWeek > 0.3 { trend = .improving }
                else if perWeek < -0.3 { trend = .declining }
                else { trend = .flat }
            } else {
                if change > 2 { trend = .improving }
                else if change < -2 { trend = .declining }
                else { trend = .flat }
            }

            // En sık kullanılan yazımı göster
            let display = mostCommonDisplay(daily.map(\.display))
            out.append(LiftProgress(
                name: display,
                sessions: daily.count,
                firstE1RM: first.e1rm,
                latestE1RM: last.e1rm,
                bestE1RM: bestE1RM,
                changePercent: change,
                trend: trend,
                lastDate: last.date
            ))
        }

        // En çok loglanan + en güncel önce
        return out.sorted {
            if $0.sessions != $1.sessions { return $0.sessions > $1.sessions }
            return $0.lastDate > $1.lastDate
        }
    }

    private static func normalizeName(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func mostCommonDisplay(_ names: [String]) -> String {
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? names.first ?? "Hareket"
    }

    // MARK: - Antrenman hacmi landmark'ları (MEV–MAV–MRV)

    /// Haftalık zorlu-set hedefleri (set/hafta). Renaissance Periodization (Israetel)
    /// landmarkları + Schoenfeld doz-yanıt meta-analizleri (≥10 set/hafta hipertrofi için
    /// çoğu kasta verimli). Bireysel değişir — bunlar pratik referans aralıkları.
    enum MuscleGroup: String, CaseIterable, Identifiable {
        case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, abs
        var id: String { rawValue }

        var label: String {
            switch self {
            case .chest:      return "Göğüs"
            case .back:       return "Sırt"
            case .shoulders:  return "Omuz"
            case .biceps:     return "Biceps"
            case .triceps:    return "Triceps"
            case .quads:      return "Quadriceps"
            case .hamstrings: return "Hamstring"
            case .glutes:     return "Kalça"
            case .calves:     return "Baldır"
            case .abs:        return "Karın"
            }
        }

        /// (MEV minimum etkili, MAV verimli üst sınır, MRV maks. toparlanabilir) set/hafta.
        var landmarks: (mev: Double, mav: Double, mrv: Double) {
            switch self {
            case .chest:      return (10, 18, 22)
            case .back:       return (10, 20, 25)
            case .shoulders:  return (8, 20, 26)
            case .biceps:     return (8, 18, 24)
            case .triceps:    return (8, 16, 22)
            case .quads:      return (8, 16, 20)
            case .hamstrings: return (6, 14, 20)
            case .glutes:     return (4, 12, 16)
            case .calves:     return (8, 16, 20)
            case .abs:        return (6, 20, 25)
            }
        }
    }

    enum VolumeStatus { case under, productive, high, over }

    struct MuscleVolume: Identifiable {
        let muscle: MuscleGroup
        let sets: Double            // haftalık (sekonder kaslar 0.5 kredi)
        var id: String { muscle.rawValue }
        var status: VolumeStatus {
            let l = muscle.landmarks
            if sets < l.mev { return .under }
            if sets < l.mav { return .productive }
            if sets < l.mrv { return .high }
            return .over
        }
    }

    /// Egzersiz adını birincil + (yarım kredili) ikincil kaslara eşler. Sıralama önemli:
    /// spesifik bileşik ifadeler genel anahtar kelimelerden ÖNCE kontrol edilir.
    static func classify(_ rawName: String) -> (primary: MuscleGroup, secondary: [MuscleGroup])? {
        let n = normalizeName(rawName)
        guard !n.isEmpty else { return nil }
        func has(_ s: String) -> Bool { n.contains(s) }

        // Bacak/kalça — "leg curl" mutlaka "curl"dan önce
        if has("hip thrust") || has("hip bridge") || has("glute") || has("kalca") { return (.glutes, [.hamstrings]) }
        if has("leg curl") || has("ham curl") || has("hamstring") || has("rdl") || has("romanian") || has("good morning") || has("nordic") || has("arka bacak") { return (.hamstrings, [.glutes]) }
        if has("deadlift") || has("deadlif") { return (.back, [.hamstrings, .glutes]) }
        if has("calf") || has("baldir") { return (.calves, []) }
        if has("leg extension") || has("leg ext") || has("on bacak") { return (.quads, []) }
        if has("leg press") || has("hack squat") || has("squat") || has("lunge") || has("split squat") || has("bulgarian") || has("step up") { return (.quads, [.glutes, .hamstrings]) }

        // Omuz — "shoulder press"/"lateral" generic press/raise'den önce
        if has("lateral raise") || has("side raise") || has("yan kald") || has("lateral") { return (.shoulders, []) }
        if has("rear delt") || has("face pull") || has("reverse fly") || has("reverse pec") { return (.shoulders, [.back]) }
        if has("shoulder press") || has("overhead press") || has("ohp") || has("military") || has("arnold") || has("omuz") { return (.shoulders, [.triceps]) }
        if has("upright row") { return (.shoulders, [.biceps]) }

        // Kol — "close grip"/"close-grip" bench tricepse
        if has("pushdown") || has("pressdown") || has("skull") || has("kickback") || has("triceps") || has("triseps") || has("close grip") || has("close-grip") || has("overhead extension") { return (.triceps, []) }
        if has("hammer curl") || has("curl") || has("biceps") || has("biseps") { return (.biceps, []) }

        // Sırt
        if has("chin") { return (.back, [.biceps]) }
        if has("pulldown") || has("pull-up") || has("pull up") || has("pullup") || has("lat ") || has("lat pull") || has("row") || has("sirt") { return (.back, [.biceps]) }

        // Göğüs — generic press EN SONA (shoulder/leg press yukarıda yakalandı)
        if has("dip") { return (.chest, [.triceps]) }
        if has("incline") || has("fly") || has("pec") || has("gogus") || has("chest") || has("bench") || has("press") { return (.chest, [.triceps, .shoulders]) }

        // Karın
        if has("crunch") || has("plank") || has("sit up") || has("situp") || has("karin") || has("leg raise") || has("hanging") || has("ab wheel") || n == "ab" || n == "abs" { return (.abs, []) }

        return nil
    }

    /// Son `days` gündeki haftalık zorlu set sayısı (kas başına). İkincil kaslar 0.5 kredi.
    /// Loglanan her set bir çalışma seti sayılır (ısınmalar genelde loglanmaz).
    static func weeklyVolume(
        workouts: [WorkoutLog],
        days: Int = 7,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [MuscleVolume] {
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        var sets: [MuscleGroup: Double] = [:]
        for log in workouts where log.date >= start {
            for ex in log.exercises {
                let count = Double(ex.setEntries.count)
                guard count > 0, let cls = classify(ex.name) else { continue }
                sets[cls.primary, default: 0] += count
                for sec in cls.secondary {
                    sets[sec, default: 0] += count * 0.5
                }
            }
        }
        return MuscleGroup.allCases.map { MuscleVolume(muscle: $0, sets: sets[$0] ?? 0) }
    }

    // MARK: - Haftalık Science Scorecard

    struct ScoreItem: Identifiable {
        let title: String
        let value: String
        let target: String
        let tone: RateTone
        let note: String
        var id: String { title }
    }

    private static func goalRateTarget(_ goal: Goal) -> String {
        switch goal {
        case .loseFast, .lose: return "ideal −0.5…−1%/hafta"
        case .gain, .gainFast: return "ideal +0.25…0.5%/hafta"
        case .maintain:        return "hedef ~%0/hafta"
        }
    }

    /// Tüm motorları tek panele toplar: protein · kilo trendi · hacim · adım · loglama.
    /// Her satır kaynaklı bir hedefe göre derecelendirilir.
    static func scorecard(
        foods: [FoodEntry],
        steps: [StepEntry],
        measurements: [Measurement],
        energy: AdaptiveEnergy?,
        volumes: [MuscleVolume],
        bodyWeightKg: Double?,
        goal: Goal,
        days: Int = 14,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ScoreItem] {
        var items: [ScoreItem] = []
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now

        let foodsInRange = foods.filter { $0.date >= start && $0.date <= now }
        let loggedDays = Set(foodsInRange.map { calendar.startOfDay(for: $0.date) }).count

        // 1) Protein (g/kg)
        if let bw = bodyWeightKg, bw > 0, loggedDays >= 3 {
            let totalP = foodsInRange.reduce(0) { $0 + ($1.protein ?? 0) }
            let avgP = totalP / Double(loggedDays)
            let perKg = avgP / bw
            let tone: RateTone = perKg >= 1.6 ? .good : (perKg >= 1.2 ? .warn : .bad)
            items.append(ScoreItem(
                title: "Protein",
                value: "\(Fmt.num(perKg, digits: 1)) g/kg",
                target: "≥1.6 g/kg (cut'ta ~2.0+)",
                tone: tone,
                note: "~1.6 g/kg çoğu kişide kas kazanımı platosudur (Morton 2018 meta); kalori açığında 2.0–2.4 g/kg daha koruyucu (Helms 2014). Ort. \(Fmt.int(avgP)) g/gün."
            ))
        }

        // 2) Kilo trendi
        if let e = energy {
            let v = rateVerdict(percentPerWeek: e.ratePercentPerWeek, goal: goal)
            items.append(ScoreItem(
                title: "Kilo trendi",
                value: "\(Fmt.signed(e.ratePercentPerWeek, digits: 2))%/hafta",
                target: goalRateTarget(goal),
                tone: v.tone,
                note: "\(v.label) — \(v.note)"
            ))
        }

        // 3) Antrenman hacmi
        let trained = volumes.filter { $0.sets > 0 }
        if !trained.isEmpty {
            let productive = trained.filter { $0.status == .productive || $0.status == .high }.count
            let under = trained.filter { $0.status == .under }.count
            let over = trained.filter { $0.status == .over }.count
            let tone: RateTone = (under == 0 && over == 0) ? .good : (over > 0 ? .warn : .neutral)
            items.append(ScoreItem(
                title: "Antrenman hacmi",
                value: "\(productive)/\(trained.count) kas verimli",
                target: "MEV–MRV arası",
                tone: tone,
                note: "\(under) kas MEV altında, \(over) kas MRV üstünde. Hipertrofi için kas başına ~10+ set/hafta (Schoenfeld doz-yanıt)."
            ))
        }

        // 4) Adım
        let stepsInRange = steps.filter { $0.date >= start && $0.date <= now }
        let stepDays = Set(stepsInRange.map { calendar.startOfDay(for: $0.date) })
        if !stepDays.isEmpty {
            let avg = Double(stepsInRange.reduce(0) { $0 + $1.steps }) / Double(stepDays.count)
            let tone: RateTone = avg >= 8000 ? .good : (avg >= 5000 ? .neutral : .warn)
            items.append(ScoreItem(
                title: "Adım",
                value: "\(Fmt.int(avg))/gün",
                target: "≥8.000/gün",
                tone: tone,
                note: "Günlük ~7–8 bin adım mortalite riskini belirgin düşürür (Paluch 2022). NEAT, kalori açığının sessiz kaldıracıdır."
            ))
        }

        // 5) Loglama tutarlılığı
        let frac = Double(loggedDays) / Double(max(1, days))
        let adhTone: RateTone = frac >= 0.8 ? .good : (frac >= 0.5 ? .warn : .bad)
        items.append(ScoreItem(
            title: "Loglama tutarlılığı",
            value: "%\(Int((frac * 100).rounded()))",
            target: "≥%80",
            tone: adhTone,
            note: "Son \(days) günde \(loggedDays) gün kayıtlı. Tutarlı loglama, ilerlemenin en güçlü davranışsal yordayıcısıdır."
        ))

        return items
    }
}
