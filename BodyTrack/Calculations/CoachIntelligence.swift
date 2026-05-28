import Foundation

enum EvidenceStrength: String {
    case high = "yüksek"
    case moderate = "orta"
    case conditional = "koşullu"
}

struct EvidenceClaim {
    let topic: String
    let claim: String
    let strength: EvidenceStrength
    let useWhen: [String]
    let coachNote: String
}

struct CoachDecisionFlag {
    let level: String
    let title: String
    let detail: String
}

enum CoachIntelligence {
    private static let evidenceClaims: [EvidenceClaim] = [
        EvidenceClaim(
            topic: "Protein",
            claim: "Definasyon ve resistance training döneminde günlük protein için pratik evidence bandı çoğu kişi için yaklaşık 1.6-2.2 g/kg/gün; yağ oranı yüksekse hedef/yağsız kütleye göre alt band daha anlamlı olabilir.",
            strength: .high,
            useWhen: ["protein", "whey", "cut", "definasyon", "kas", "kilo", "beslenme"],
            coachNote: "Kullanıcı protein stresinden bahsettiyse mükemmel günü değil haftalık ortalamayı optimize et."
        ),
        EvidenceClaim(
            topic: "Kalori Açığı",
            claim: "Kilo kaybı için sürdürülebilir hız çoğu natural lifter için haftalık vücut ağırlığının yaklaşık %0.5-1.0'ı; daha agresif hız performans, toparlanma ve yağsız kütle riskini artırabilir.",
            strength: .high,
            useWhen: ["definasyon", "cut", "kilo", "yağ", "yag", "hedef", "plato"],
            coachNote: "Sadece günlük tartıya göre hüküm verme; 7-14 günlük trend, log kalitesi ve su/glikojen etkisini ayır."
        ),
        EvidenceClaim(
            topic: "Hipertrofi Volume",
            claim: "Hipertrofi için kas grubu başına haftalık set ihtiyacı bireysel değişir; çoğu intermediate lifter için 10-20 hard set/hafta makul başlangıç aralığıdır.",
            strength: .moderate,
            useWhen: ["antrenman", "program", "volume", "set", "hipertrofi", "kas", "split"],
            coachNote: "Set sayısını tek başına artırma; RIR, performans trendi ve recovery ile beraber değerlendir."
        ),
        EvidenceClaim(
            topic: "Failure / RIR",
            claim: "Kas kazanımı için her sette failure şart değil; çoğu çalışma 0-3 RIR bandının etkili olduğunu, failure'ın seçili izolasyon setlerinde daha mantıklı olduğunu destekler.",
            strength: .moderate,
            useWhen: ["failure", "rir", "rpe", "tekrar", "set", "antrenman", "program"],
            coachNote: "Compound hareketlerde sürekli failure yerine teknik kalite ve progresyonu koru."
        ),
        EvidenceClaim(
            topic: "Frekans",
            claim: "Haftalık volume eşitse frekans mucize değildir; ama volume'u daha kaliteli dağıtmak ve yorgunluğu yönetmek için kas başına haftada 2 temas çoğu kişide pratik avantaj sağlar.",
            strength: .moderate,
            useWhen: ["frekans", "frequency", "split", "program", "antrenman"],
            coachNote: "Program değişikliği önerirken önce mevcut seans sayısı ve adherence'a bak."
        ),
        EvidenceClaim(
            topic: "Creatine",
            claim: "Creatine monohydrate için yaygın etkili doz 3-5 g/gün; loading şart değildir, düzenli kullanım daha önemlidir.",
            strength: .high,
            useWhen: ["kreatin", "creatine", "supplement"],
            coachNote: "Böbrek hastalığı gibi klinik durum yoksa pratik cevap kısa tutulabilir."
        ),
        EvidenceClaim(
            topic: "NEAT / Adım",
            claim: "Cut döneminde adım/NEAT, açığı büyütmenin ve iştah yönetimini bozmadan enerji harcamasını artırmanın düşük maliyetli yoludur; ama antrenman performansını baltalayacak seviyeye zorlanmamalı.",
            strength: .moderate,
            useWhen: ["adim", "step", "yürüyüş", "yuruyus", "kilo", "definasyon", "cut"],
            coachNote: "Kullanıcının önceki tercihi: çok yüksek adım zorlaması yok; 6-9k bandı daha sürdürülebilir."
        ),
        EvidenceClaim(
            topic: "Recovery",
            claim: "Uyku, performans düşüşü, eklem ağrısı ve iştah artışı birlikte bozuluyorsa sorun çoğu zaman tek egzersiz değil toplam stres yüküdür: deficit + volume + düşük NEAT/adherence kombinasyonu kontrol edilir.",
            strength: .conditional,
            useWhen: ["uyku", "sleep", "recovery", "toparlanma", "performans", "yorgunluk"],
            coachNote: "Önce semptomu sınıflandır: lokal kas yorgunluğu mu, sistemik yorgunluk mu?"
        )
    ]

    static func buildContext(query: String, data: AgentDataSnapshot) -> String? {
        guard AgentQueryClassifier.isCoachQuery(query),
              !AgentQueryClassifier.isLikelyFoodLog(query)
        else { return nil }

        let profile = data.profile
        let measurements = data.measurements
        let foods = data.foods
        let steps = data.steps
        let workoutLogs = data.workoutLogs
        let sessions = data.workoutSessions
        let scope = data.scope

        var sections: [String] = []

        if let personal = personalModelSection(
            profile: profile,
            measurements: measurements,
            foods: foods,
            steps: steps,
            workoutLogs: workoutLogs,
            sessions: sessions,
            scope: scope
        ) {
            sections.append(personal)
        }

        let flags = decisionFlags(
            profile: profile,
            measurements: measurements,
            foods: foods,
            steps: steps,
            workoutLogs: workoutLogs,
            scope: scope
        )
        if !flags.isEmpty {
            sections.append(flagSection(flags))
        }

        let claims = relevantEvidenceClaims(for: query)
        if !claims.isEmpty {
            sections.append(evidenceSection(claims))
        }

        if let review = weeklyReviewSection(
            profile: profile,
            measurements: measurements,
            foods: foods,
            steps: steps,
            workoutLogs: workoutLogs,
            scope: scope
        ) {
            sections.append(review)
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Personal model

    private static func personalModelSection(
        profile: AgentUserProfileSnapshot?,
        measurements: [AgentMeasurementSnapshot],
        foods: [AgentFoodSnapshot],
        steps: [AgentStepSnapshot],
        workoutLogs: [AgentWorkoutLogSnapshot],
        sessions: [AgentWorkoutSessionSnapshot],
        scope: AgentDataScope
    ) -> String? {
        var lines = ["[COACH PERSONAL MODEL — uygulama verisinden hesaplandı]"]

        let latest = measurements.first
        let weight = latest?.weight
        let bodyFat = latest?.bodyFat ?? profile?.manualBodyFat
        let leanMass = latest?.leanMass

        if let profile, let weight {
            let target = dailyTarget(profile: profile, latestWeight: weight, bodyFat: bodyFat)
            lines.append("- App hedef kalorisi: \(Fmt.int(target.goalCalories)) kcal/gün; BMR \(Fmt.int(target.bmr)) · TDEE \(Fmt.int(target.tdee))")
            lines.append("- App makro hedefi: P \(Fmt.int(target.protein.grams))g · K \(Fmt.int(target.carbs.grams))g · Y \(Fmt.int(target.fat.grams))g")
            if profile.manualProteinGrams != nil || profile.manualCarbsGrams != nil || profile.manualFatGrams != nil {
                lines.append("- Profilde manuel makro hedefi aktif; kalori hedefi bu makroların toplamından hesaplanıyor.")
            }
            let supplements = profile.supplements
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !supplements.isEmpty {
                lines.append("- Supplementler: \(supplements.joined(separator: " · "))")
            }
        }

        if let weight {
            var bodyLine = "- Güncel vücut: \(Fmt.num(weight, digits: 1)) kg"
            if let bodyFat { bodyLine += " · %\(Fmt.num(bodyFat, digits: 1)) yağ" }
            if let leanMass { bodyLine += " · \(Fmt.num(leanMass, digits: 1)) kg yağsız kütle" }
            lines.append(bodyLine)

            let protein = proteinRange(weight: weight, leanMass: leanMass)
            lines.append("- Protein bandı: minimum \(Fmt.int(protein.floor))g · pratik hedef \(Fmt.int(protein.targetLow))-\(Fmt.int(protein.targetHigh))g/gün")
        }

        for days in [7, 14, 30] {
            if let delta = weightDelta(measurements: measurements, days: days) {
                lines.append("- Kilo trendi \(days) gün: \(Fmt.signed(delta.kg, digits: 2)) kg · \(Fmt.signed(delta.percentPerWeek, digits: 2))%/hafta")
            }
        }

        for days in [7, 30] {
            guard scope.coversFoods(days: days) else { continue }
            let nutrition = nutritionStats(foods: foods, days: days)
            guard nutrition.loggedDays > 0 else { continue }
            lines.append("- Beslenme \(days) gün: \(nutrition.loggedDays)/\(nutrition.totalDays) gün log · ort. \(Fmt.int(nutrition.avgKcal)) kcal · P \(Fmt.int(nutrition.avgProtein))g · K \(Fmt.int(nutrition.avgCarbs))g · Y \(Fmt.int(nutrition.avgFat))g")
        }

        for days in [7, 30] {
            guard scope.coversSteps(days: days) else { continue }
            let step = stepStats(steps: steps, days: days)
            guard step.loggedDays > 0 else { continue }
            lines.append("- Adım \(days) gün: toplam \(Fmt.int(Double(step.totalSteps))) · takvim ort. \(Fmt.int(Double(step.calendarAverage))) adım/gün · loglu gün ort. \(Fmt.int(Double(step.loggedAverage)))")
        }

        let workout = workoutStats(logs: workoutLogs, plannedSessions: sessions)
        if workout.plannedDays > 0 || (scope.coversWorkoutLogs(days: 30) && workout.last30Count > 0) {
            lines.append("- Antrenman: plan \(workout.plannedDays) gün/hafta · son 30 gün \(workout.last30Count) seans · gerçek frekans \(String(format: "%.1f", workout.frequencyPerWeek))/hafta")
        }

        if scope.coversFoods(days: 21), let tdee = calibratedTDEE(measurements: measurements, foods: foods) {
            lines.append("- Tahmini gerçek maintenance: \(Fmt.int(tdee.estimate)) kcal/gün (\(tdee.confidence) güven; \(tdee.note))")
        }

        return lines.count > 1 ? lines.joined(separator: "\n") : nil
    }

    private static func dailyTarget(profile: AgentUserProfileSnapshot, latestWeight: Double, bodyFat: Double?) -> CalorieResult {
        CalorieCalculator.compute(
            weight: latestWeight,
            height: profile.height,
            age: profile.age,
            sex: profile.sex,
            bodyFat: bodyFat,
            activity: profile.activity,
            goal: profile.goal,
            manualOffset: profile.manualCalorieOffset,
            manualOffsetMacro: profile.manualCalorieOffsetMacro,
            manualProteinGrams: profile.manualProteinGrams,
            manualCarbsGrams: profile.manualCarbsGrams,
            manualFatGrams: profile.manualFatGrams
        )
    }

    private static func proteinRange(weight: Double, leanMass: Double?) -> (floor: Double, targetLow: Double, targetHigh: Double) {
        let evidenceLow = weight * 1.6
        let leanAnchor = (leanMass ?? weight * 0.78) * 2.1
        let floor = min(evidenceLow, leanAnchor)
        let targetLow = max(evidenceLow, leanAnchor)
        let targetHigh = min(weight * 2.2, max(targetLow + 25, weight * 1.95))
        return (floor.rounded(), targetLow.rounded(), targetHigh.rounded())
    }

    private static func weightDelta(measurements: [AgentMeasurementSnapshot], days: Int) -> (kg: Double, percentPerWeek: Double)? {
        guard let latest = measurements.first(where: { $0.weight != nil }),
              let latestWeight = latest.weight
        else { return nil }

        let target = Calendar.current.date(byAdding: .day, value: -days, to: latest.date) ?? latest.date
        guard let previous = measurements
            .filter({ $0.weight != nil && $0.date <= latest.date })
            .min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }),
              let previousWeight = previous.weight
        else { return nil }

        let spanDays = max(1, latest.date.timeIntervalSince(previous.date) / 86_400)
        guard spanDays >= Double(max(4, days / 2)) else { return nil }

        let kg = latestWeight - previousWeight
        let percentPerWeek = (kg / latestWeight) * (7 / spanDays) * 100
        return (kg, percentPerWeek)
    }

    private static func nutritionStats(foods: [AgentFoodSnapshot], days: Int) -> (totalDays: Int, loggedDays: Int, avgKcal: Double, avgProtein: Double, avgCarbs: Double, avgFat: Double) {
        let cal = Calendar.current
        let range = CalorieStats.last(days: days, in: cal)
        let inRange = foods.filter { range.contains($0.date) }
        let dayKeys = Set(inRange.map { cal.startOfDay(for: $0.date) })
        let loggedDays = dayKeys.count
        let denominator = max(1, loggedDays)
        return (
            totalDays: days,
            loggedDays: loggedDays,
            avgKcal: inRange.reduce(0) { $0 + $1.calories } / Double(denominator),
            avgProtein: inRange.compactMap(\.protein).reduce(0, +) / Double(denominator),
            avgCarbs: inRange.compactMap(\.carbs).reduce(0, +) / Double(denominator),
            avgFat: inRange.compactMap(\.fat).reduce(0, +) / Double(denominator)
        )
    }

    private static func stepStats(steps: [AgentStepSnapshot], days: Int) -> (loggedDays: Int, totalSteps: Int, calendarAverage: Int, loggedAverage: Int) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(days - 1), to: .now) ?? .now)
        let inRange = steps.filter { $0.date >= start }
        var bestByDay: [Date: AgentStepSnapshot] = [:]
        for entry in inRange {
            let day = cal.startOfDay(for: entry.date)
            if let existing = bestByDay[day] {
                let entryStamp = entry.syncedAt ?? entry.date
                let existingStamp = existing.syncedAt ?? existing.date
                if entryStamp > existingStamp {
                    bestByDay[day] = entry
                }
            } else {
                bestByDay[day] = entry
            }
        }
        let total = bestByDay.values.reduce(0) { $0 + $1.steps }
        let logged = bestByDay.count
        return (
            loggedDays: logged,
            totalSteps: total,
            calendarAverage: total / max(1, days),
            loggedAverage: total / max(1, logged)
        )
    }

    private static func workoutStats(logs: [AgentWorkoutLogSnapshot], plannedSessions: [AgentWorkoutSessionSnapshot]) -> (plannedDays: Int, last30Count: Int, frequencyPerWeek: Double) {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let last30 = logs.filter { $0.date >= start }
        return (
            plannedDays: plannedSessions.count,
            last30Count: last30.count,
            frequencyPerWeek: Double(last30.count) / (30.0 / 7.0)
        )
    }

    private static func calibratedTDEE(measurements: [AgentMeasurementSnapshot], foods: [AgentFoodSnapshot]) -> (estimate: Double, confidence: String, note: String)? {
        let cal = Calendar.current
        let lookbackDays = 21
        let start = cal.date(byAdding: .day, value: -lookbackDays, to: .now) ?? .now
        let foodStats = nutritionStats(foods: foods.filter { $0.date >= start }, days: lookbackDays)
        guard foodStats.loggedDays >= 7 else { return nil }

        let weights = measurements
            .compactMap { m -> (date: Date, weight: Double)? in
                guard let weight = m.weight, m.date >= start else { return nil }
                return (m.date, weight)
            }
            .sorted { $0.date < $1.date }
        guard let first = weights.first, let last = weights.last else { return nil }
        let spanDays = max(1, last.date.timeIntervalSince(first.date) / 86_400)
        guard spanDays >= 7 else { return nil }

        let weightChange = last.weight - first.weight
        let energyBalancePerDay = (weightChange * 7700.0) / spanDays
        let estimate = foodStats.avgKcal - energyBalancePerDay
        let coverage = Double(foodStats.loggedDays) / Double(lookbackDays)
        let confidence: String
        if coverage >= 0.8 && spanDays >= 14 {
            confidence = "orta-yüksek"
        } else if coverage >= 0.55 {
            confidence = "orta"
        } else {
            confidence = "düşük"
        }
        let note = "\(foodStats.loggedDays)/\(lookbackDays) gün kalori logu, \(Fmt.num(spanDays, digits: 0)) gün tartı aralığı"
        return (max(1200, estimate).rounded(), confidence, note)
    }

    // MARK: - Decision flags

    private static func decisionFlags(
        profile: AgentUserProfileSnapshot?,
        measurements: [AgentMeasurementSnapshot],
        foods: [AgentFoodSnapshot],
        steps: [AgentStepSnapshot],
        workoutLogs: [AgentWorkoutLogSnapshot],
        scope: AgentDataScope
    ) -> [CoachDecisionFlag] {
        var flags: [CoachDecisionFlag] = []
        let latestWeight = measurements.first?.weight
        let nutrition7 = scope.coversFoods(days: 7) ? nutritionStats(foods: foods, days: 7) : nil
        let step7 = scope.coversSteps(days: 7) ? stepStats(steps: steps, days: 7) : nil

        if let nutrition7, nutrition7.loggedDays < 5 {
            flags.append(CoachDecisionFlag(
                level: "data",
                title: "Kalori verisi seyrek",
                detail: "Son 7 günde \(nutrition7.loggedDays) gün log var; kalori kararını sert değiştirmeden önce log tutarlılığı kontrol edilmeli."
            ))
        }

        if let latestWeight {
            let protein = proteinRange(weight: latestWeight, leanMass: measurements.first?.leanMass)
            if let nutrition7, nutrition7.loggedDays >= 3 && nutrition7.avgProtein < protein.floor {
                flags.append(CoachDecisionFlag(
                    level: "nutrition",
                    title: "Protein alt bandın altında",
                    detail: "7 gün ortalama \(Fmt.int(nutrition7.avgProtein))g; minimum band \(Fmt.int(protein.floor))g civarı. Öncelik kolay preset/öğünle haftalık ortalamayı yükseltmek."
                ))
            }

            if let delta14 = weightDelta(measurements: measurements, days: 14) {
                if profile?.goal == .loseFast || profile?.goal == .lose {
                    if delta14.percentPerWeek < -1.0 {
                        flags.append(CoachDecisionFlag(
                            level: "cut",
                            title: "Kayıp hızı agresif olabilir",
                            detail: "14 günlük tempo \(Fmt.signed(delta14.percentPerWeek, digits: 2))%/hafta; performans/recovery düşüyorsa kaloriyi kısmak yerine sabitlemek daha mantıklı."
                        ))
                    } else if delta14.percentPerWeek > -0.25 && (nutrition7?.loggedDays ?? 0) >= 5 {
                        flags.append(CoachDecisionFlag(
                            level: "cut",
                            title: "Kayıp hızı yavaş",
                            detail: "14 günlük tempo \(Fmt.signed(delta14.percentPerWeek, digits: 2))%/hafta; önce log doğruluğu ve adım ortalaması, sonra küçük kalori ayarı düşünülür."
                        ))
                    }
                }
            }
        }

        if let step7, step7.loggedDays > 0 && step7.calendarAverage < 6000 {
            flags.append(CoachDecisionFlag(
                level: "activity",
                title: "Adım düşük/orta",
                detail: "7 gün takvim ortalaması \(step7.calendarAverage) adım. Cut için 6-9k sürdürülebilir band; 10k+ şart değil."
            ))
        }

        let workout = workoutStats(logs: workoutLogs, plannedSessions: [])
        if scope.coversWorkoutLogs(days: 30) && workout.last30Count > 0 && workout.frequencyPerWeek < 2.0 {
            flags.append(CoachDecisionFlag(
                level: "training",
                title: "Antrenman frekansı düşük",
                detail: "Son 30 gün gerçek frekans \(String(format: "%.1f", workout.frequencyPerWeek))/hafta; hipertrofi hedefinde önce 2-3 stabil gün korunmalı."
            ))
        }

        return flags
    }

    private static func flagSection(_ flags: [CoachDecisionFlag]) -> String {
        var lines = ["[COACH DECISION FLAGS]"]
        lines += flags.map { "- [\($0.level)] \($0.title): \($0.detail)" }
        return lines.joined(separator: "\n")
    }

    // MARK: - Evidence

    private static func relevantEvidenceClaims(for query: String) -> [EvidenceClaim] {
        let lower = AgentQueryClassifier.normalized(query)
        var scored: [(claim: EvidenceClaim, score: Int)] = []

        for claim in evidenceClaims {
            var score = 0
            for keyword in claim.useWhen where AgentQueryClassifier.containsAny(lower, [keyword]) {
                score += 1
            }
            if score > 0 {
                scored.append((claim: claim, score: score))
            }
        }

        scored.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.claim.topic < rhs.claim.topic : lhs.score > rhs.score
        }

        if scored.isEmpty, AgentQueryClassifier.isCoachQuery(query) {
            return Array(evidenceClaims.prefix(3))
        }
        return scored.prefix(5).map { $0.claim }
    }

    private static func evidenceSection(_ claims: [EvidenceClaim]) -> String {
        var lines = ["[EVIDENCE CLAIM GRAPH — kısa, karar destekli kullan]"]
        lines += claims.map { claim in
            "- \(claim.topic) [kanıt: \(claim.strength.rawValue)]: \(claim.claim) Coach notu: \(claim.coachNote)"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Weekly review

    private static func weeklyReviewSection(
        profile: AgentUserProfileSnapshot?,
        measurements: [AgentMeasurementSnapshot],
        foods: [AgentFoodSnapshot],
        steps: [AgentStepSnapshot],
        workoutLogs: [AgentWorkoutLogSnapshot],
        scope: AgentDataScope
    ) -> String? {
        let nutrition = scope.coversFoods(days: 7) ? nutritionStats(foods: foods, days: 7) : nil
        let step = scope.coversSteps(days: 7) ? stepStats(steps: steps, days: 7) : nil
        let workout = workoutStats(logs: workoutLogs, plannedSessions: [])
        guard (nutrition?.loggedDays ?? 0) > 0
            || (step?.loggedDays ?? 0) > 0
            || (scope.coversWorkoutLogs(days: 30) && workout.last30Count > 0)
        else { return nil }

        var lines = ["[WEEKLY COACH REVIEW SEED]"]
        if let nutrition, nutrition.loggedDays > 0 {
            lines.append("- Bu hafta beslenme: \(nutrition.loggedDays)/7 gün log · \(Fmt.int(nutrition.avgKcal)) kcal/gün · P \(Fmt.int(nutrition.avgProtein))g/gün.")
        }
        if let step, step.loggedDays > 0 {
            lines.append("- Bu hafta hareket: \(step.calendarAverage) adım/gün takvim ortalaması.")
        }
        if let delta = weightDelta(measurements: measurements, days: 7) {
            lines.append("- Bu hafta tartı: \(Fmt.signed(delta.kg, digits: 2)) kg.")
        }
        if scope.coversWorkoutLogs(days: 30) && workout.last30Count > 0 {
            lines.append("- Antrenman ritmi: son 30 gün \(workout.last30Count) seans; \(String(format: "%.1f", workout.frequencyPerWeek))/hafta.")
        }
        lines.append("- Varsayılan koç kararı: veri çok net değilse büyük plan değişikliği yerine 7 günlük takip, küçük eşik ayarı ve adherence öner.")
        return lines.joined(separator: "\n")
    }

}
