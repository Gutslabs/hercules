import Foundation
import SwiftData

// MARK: - Mention tags

/// Sidebar menü öğeleri + aliasları. Kullanıcı `@yemek planı` yazdığında
/// AI'ya sadece o bölümün verisi enjekte edilir.
enum MentionTag: String, CaseIterable, Identifiable, Hashable {
    case genelBakis, olcumler, grafikler, antrenman, takvim, kalori, yemekPlani, tarifler, profil, hepsi

    var id: String { rawValue }

    /// Birincil görünür isim (sidebar'daki etiketle uyumlu).
    var displayName: String {
        switch self {
        case .genelBakis: return "Genel Bakış"
        case .olcumler:   return "Ölçümler"
        case .grafikler:  return "Grafikler"
        case .antrenman:  return "Antrenman"
        case .takvim:     return "Takvim"
        case .kalori:     return "Kalori"
        case .yemekPlani: return "Yemek Planı"
        case .tarifler:   return "Tarifler"
        case .profil:     return "Profil"
        case .hepsi:      return "Hepsi"
        }
    }

    /// Eşleşme için ek varyantlar.
    var aliases: [String] {
        switch self {
        case .genelBakis: return ["genel bakış", "genel bakis", "dashboard", "overview", "ozet", "özet"]
        case .olcumler:   return ["ölçümler", "olcumler", "ölçüm", "olcum", "tartı", "tarti", "kilo", "vücut", "vucut"]
        case .grafikler:  return ["grafikler", "grafik", "charts", "chart", "trend", "trendler", "değişim", "degisim", "ilerleme"]
        case .antrenman:  return ["antrenman", "workout", "spor", "egzersiz", "training", "gym", "seans", "hareket"]
        case .takvim:     return ["takvim", "calendar", "hedef", "hedefler", "aylık", "ay"]
        case .kalori:     return ["kalori", "calorie", "macros", "makro", "bugün", "bugun"]
        case .yemekPlani: return ["yemek planı", "yemek plani", "meal plan", "meal", "yemek", "diyet", "plan"]
        case .tarifler:   return ["tarifler", "tarif", "recipe", "recipes", "yemek tarif"]
        case .profil:     return ["profil", "profile", "ayar", "settings"]
        case .hepsi:      return ["hepsi", "tümü", "tumu", "all", "everything", "her şey", "her sey"]
        }
    }

    /// Autocomplete için kısa hint (gösterilecek alias).
    var hintAlias: String {
        switch self {
        case .genelBakis: return "dashboard, özet"
        case .olcumler:   return "kilo, yağ %"
        case .grafikler:  return "trendler, değişim"
        case .antrenman:  return "seans, hareket, tempo"
        case .takvim:     return "günlük yiyecek, aylık hedefler"
        case .kalori:     return "bugün, makro"
        case .yemekPlani: return "meal, diyet"
        case .tarifler:   return "kayıtlı tarifler"
        case .profil:     return "kimlik, aktivite, hedef"
        case .hepsi:      return "all — tüm veri"
        }
    }

    /// Verilen prefix bu tag'in displayName veya aliaslarından birine eşleşiyor mu?
    /// Türkçe aksanlara duyarsız.
    func matches(prefix: String) -> Bool {
        guard !prefix.isEmpty else { return true }
        let needle = UserContextSnapshot.publicNormalize(prefix)
        let haystack = ([displayName] + aliases).map { UserContextSnapshot.publicNormalize($0) }
        return haystack.contains { $0.hasPrefix(needle) || $0.contains(needle) }
    }

    fileprivate var sections: [SnapshotSection] {
        switch self {
        case .genelBakis: return [.profile, .latestMeasurement, .trend, .todayIntake, .caloriePeriods, .workout, .goals]
        case .olcumler:   return [.latestMeasurement, .trend]
        case .grafikler:  return [.trend, .latestMeasurement, .caloriePeriods]
        case .antrenman:  return [.workout, .workoutLogs]
        case .takvim:     return [.todayIntake, .caloriePeriods, .goals]
        case .kalori:     return [.profile, .todayIntake, .caloriePeriods]
        case .yemekPlani: return [.mealPlan]
        case .tarifler:   return [.recipes]
        case .profil:     return [.profile, .workout]
        case .hepsi:      return SnapshotSection.allCases
        }
    }
}

extension UserContextSnapshot {
    /// Türkçe aksanları silen + case-fold yapan helper. View'lardan da kullanılabilir.
    static func publicNormalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                  locale: Locale(identifier: "en_US"))
    }
}

private enum SnapshotSection: CaseIterable, Hashable {
    case profile, latestMeasurement, trend, todayIntake, caloriePeriods, goals, workout, workoutLogs, steps, mealPlan, recipes
}

enum UserContextSnapshot {

    // MARK: - Public API

    /// Mesaj içindeki `@etiket` ifadelerini ayrıştırır. Tanınmayan etiketleri
    /// boş döndürür. Aksanlara duyarsız (Türkçe i/ı/ş/ğ farkları normalize).
    static func parseMentions(_ text: String) -> Set<MentionTag> {
        guard text.contains("@") else { return [] }
        let normalizedText = normalize(text)
        var found: Set<MentionTag> = []
        for tag in MentionTag.allCases {
            let candidates = [tag.displayName] + tag.aliases
            for cand in candidates {
                let needle = "@" + normalize(cand)
                if normalizedText.contains(needle) {
                    found.insert(tag)
                    break
                }
            }
        }
        return found
    }

    /// Verilen etiketlere göre sadece ilgili bölümleri içeren snapshot üret.
    /// `tags` boşsa nil döner — context enjekte edilmez.
    static func build(tags: Set<MentionTag>, ctx: ModelContext) -> String? {
        guard !tags.isEmpty else { return nil }
        let neededSections = Set(tags.flatMap { $0.sections })
        return buildSnapshot(sections: neededSections, ctx: ctx)
    }

    /// Kullanıcının "Hakkında" metni — her sohbette kalıcı context olarak
    /// AI'ya verilir. UserProfile.about'tan okunur. Boşsa nil.
    static func aboutSection(ctx: ModelContext) -> String? {
        guard let profile = fetchProfile(ctx: ctx) else { return nil }
        let trimmed = profile.about.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "[KULLANICI HAKKINDA — kalıcı, kullanıcının kendisi yazdı]\n\(trimmed)"
    }

    /// `aboutSection` + (varsa) mention-based snapshot'ı birleştirir.
    /// **About metnindeki `@etiket`leri de tarar** — kullanıcı bio'sunda
    /// "@Ölçümler'e bak" diye yazdıysa, ölçüm verisi HER sohbette inject olur.
    /// Chat input'taki @ etiketleri ile birleşir.
    static func combined(tags: Set<MentionTag>, ctx: ModelContext) -> String? {
        let about = aboutSection(ctx: ctx)
        let aboutMentions = aboutMentionTags(ctx: ctx)
        let allTags = tags.union(aboutMentions)
        let mentionData = allTags.isEmpty ? nil : build(tags: allTags, ctx: ctx)
        let parts = [about, mentionData].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    /// Profil.about metnindeki @ etiketlerini çıkar — kalıcı veri attachment olarak.
    static func aboutMentionTags(ctx: ModelContext) -> Set<MentionTag> {
        guard let profile = fetchProfile(ctx: ctx) else { return [] }
        let trimmed = profile.about.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return parseMentions(trimmed)
    }

    /// Geriye dönük uyumluluk için: tüm bölümleri içeren snapshot.
    /// (Aktif kullanımda yok — silmek istersen okay.)
    static func build(ctx: ModelContext) -> String? {
        buildSnapshot(sections: Set(SnapshotSection.allCases), ctx: ctx)
    }

    // MARK: - Internal builder

    private static func buildSnapshot(sections requested: Set<SnapshotSection>, ctx: ModelContext) -> String? {
        var output: [String] = []
        let measurements = fetchMeasurements(ctx: ctx)

        if requested.contains(.profile), let profile = fetchProfile(ctx: ctx) {
            output.append(profileSection(profile))
        }
        if requested.contains(.latestMeasurement), let latest = measurements.first {
            output.append(latestMeasurementSection(latest))
        }
        if requested.contains(.trend), measurements.count >= 2,
           let trend = trendSection(measurements: measurements) {
            output.append(trend)
        }
        if requested.contains(.todayIntake), let today = todayIntakeSection(ctx: ctx) {
            output.append(today)
        }
        if requested.contains(.caloriePeriods), let aggregates = caloriePeriodsSection(ctx: ctx) {
            output.append(aggregates)
        }
        if requested.contains(.goals),
           let goals = goalsSection(ctx: ctx, latestWeight: measurements.first?.weight) {
            output.append(goals)
        }
        if requested.contains(.workout), let workout = todaysWorkoutSection(ctx: ctx) {
            output.append(workout)
        }
        if requested.contains(.workoutLogs), let workoutLogs = workoutLogsSection(ctx: ctx) {
            output.append(workoutLogs)
        }
        if requested.contains(.steps),
           let steps = todaysStepsSection(ctx: ctx, weight: measurements.first?.weight) {
            output.append(steps)
        }
        if requested.contains(.mealPlan) {
            output.append(mealPlanTodaySection(ctx: ctx))
        }
        if requested.contains(.recipes), let r = recipesSection(ctx: ctx) {
            output.append(r)
        }

        guard !output.isEmpty else { return nil }
        let header = "=== KULLANICI VERİSİ (uygulamadan canlı, \(Fmt.dateLong.string(from: .now))) ==="
        let footer = "=== VERİ SONU ==="
        return ([header] + output + [footer]).joined(separator: "\n\n")
    }

    // MARK: - Normalization

    /// Türkçe harf farklarını siler (i/ı, ş, ç, ğ, ü, ö → ascii) ve lowercase yapar.
    private static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "en_US"))
        return folded
    }

    // MARK: - Sections

    private static func profileSection(_ p: UserProfile) -> String {
        var lines: [String] = ["[PROFİL]"]
        let name = p.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { lines.append("- İsim: \(name)") }
        lines.append("- \(p.age)y · \(p.sex.label) · \(Fmt.num(p.height, digits: 0)) cm")
        lines.append("- Aktivite: \(p.activity.label) (\(p.activity.detail))")
        lines.append("- Hedef: \(p.goal.label) (\(p.goal.detail))")
        if let target = p.targetWeight {
            lines.append("- Hedef kilo: \(Fmt.num(target, digits: 1)) kg")
        }
        if p.manualCalorieOffset != 0 {
            lines.append("- Manuel kalori offset: \(Fmt.signed(p.manualCalorieOffset, digits: 0)) kcal/gün")
        }
        return lines.joined(separator: "\n")
    }

    private static func latestMeasurementSection(_ m: Measurement) -> String {
        var lines: [String] = ["[SON ÖLÇÜM — \(Fmt.dateLong.string(from: m.date)) (\(Fmt.relative(m.date)))]"]
        if let w = m.weight { lines.append("- Kilo: \(Fmt.num(w, digits: 1)) kg") }
        if let bf = m.bodyFat { lines.append("- Yağ oranı: %\(Fmt.num(bf, digits: 1))") }
        if let lm = m.leanMass { lines.append("- Yağsız kütle: \(Fmt.num(lm, digits: 1)) kg") }
        if let fm = m.fatMass { lines.append("- Yağ kütlesi: \(Fmt.num(fm, digits: 1)) kg") }
        var circ: [String] = []
        if let v = m.waist { circ.append("Bel \(Fmt.num(v, digits: 1))") }
        if let v = m.chest { circ.append("Göğüs \(Fmt.num(v, digits: 1))") }
        if let v = m.neck { circ.append("Boyun \(Fmt.num(v, digits: 1))") }
        if !circ.isEmpty { lines.append("- Çevreler (cm): \(circ.joined(separator: " · "))") }
        if let note = m.note?.trimmingCharacters(in: .whitespaces), !note.isEmpty {
            lines.append("- Not: \(note)")
        }
        return lines.joined(separator: "\n")
    }

    private static func trendSection(measurements: [Measurement]) -> String? {
        // measurements are sorted newest-first
        let withWeight = measurements.compactMap { m -> (Date, Double)? in
            guard let w = m.weight else { return nil }
            return (m.date, w)
        }
        guard let latest = withWeight.first, withWeight.count >= 2 else { return nil }

        let now = Date()
        func closest(daysAgo: Int) -> (Date, Double)? {
            let target = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return withWeight.min(by: { abs($0.0.timeIntervalSince(target)) < abs($1.0.timeIntervalSince(target)) })
        }

        var lines: [String] = ["[KİLO TRENDİ (son ölçümlere göre)]"]
        if let w7 = closest(daysAgo: 7), abs(w7.0.timeIntervalSince(latest.0)) > 86_400 {
            let delta = latest.1 - w7.1
            lines.append("- 7 gün önce: \(Fmt.num(w7.1, digits: 1)) kg → bugün \(Fmt.num(latest.1, digits: 1)) kg (\(Fmt.signed(delta, digits: 2)) kg)")
        }
        if let w14 = closest(daysAgo: 14), abs(w14.0.timeIntervalSince(latest.0)) > 6 * 86_400 {
            let delta = latest.1 - w14.1
            lines.append("- 14 gün önce: \(Fmt.num(w14.1, digits: 1)) kg (\(Fmt.signed(delta, digits: 2)) kg fark)")
        }
        if let w30 = closest(daysAgo: 30), abs(w30.0.timeIntervalSince(latest.0)) > 14 * 86_400 {
            let delta = latest.1 - w30.1
            lines.append("- 30 gün önce: \(Fmt.num(w30.1, digits: 1)) kg (\(Fmt.signed(delta, digits: 2)) kg fark)")
        }

        // Weekly pace over recorded range
        if let oldest = withWeight.last, oldest.0 < latest.0 {
            let weeks = max(1.0, latest.0.timeIntervalSince(oldest.0) / (7 * 86_400))
            let pace = (latest.1 - oldest.1) / weeks
            lines.append("- Toplam kayıt aralığı: \(Fmt.dateLong.string(from: oldest.0)) → \(Fmt.dateLong.string(from: latest.0))")
            lines.append("- Ortalama hız: \(Fmt.signed(pace, digits: 2)) kg/hafta")
        }
        return lines.count > 1 ? lines.joined(separator: "\n") : nil
    }

    private static func todayIntakeSection(ctx: ModelContext) -> String? {
        let cal = Calendar.current
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let todays = foods.filter { cal.isDateInToday($0.date) }
        guard !todays.isEmpty else { return nil }

        let kcal = todays.reduce(0) { $0 + $1.calories }
        let p = todays.compactMap(\.protein).reduce(0, +)
        let c = todays.compactMap(\.carbs).reduce(0, +)
        let f = todays.compactMap(\.fat).reduce(0, +)

        var lines: [String] = ["[BUGÜN YENENLER (\(todays.count) öğün)]"]
        lines.append("- Toplam: \(Fmt.int(kcal)) kcal · P \(Fmt.int(p))g · C \(Fmt.int(c))g · Y \(Fmt.int(f))g")
        // Tüm öğünler — kullanıcı her şeyi görmek istiyor. Time formatter static cache'den.
        let detail = todays.sorted { $0.date < $1.date }.map { entry -> String in
            let gramStr = entry.grams.map { "\(Fmt.int($0))g " } ?? ""
            let time = Fmt.timeShort.string(from: entry.date)
            let pStr = entry.protein.map { " · P\(Fmt.int($0))" } ?? ""
            return "  · \(time) — \(gramStr)\(entry.name) → \(Fmt.int(entry.calories)) kcal\(pStr)"
        }.joined(separator: "\n")
        lines.append(detail)
        return lines.joined(separator: "\n")
    }

    /// Haftalık + aylık + son 30 gün toplam tüketim, ortalama ve net açık.
    /// AI bunu "cut hızı uygun mu / hedefe ulaşır mıyım" sorularında kullanır.
    private static func caloriePeriodsSection(ctx: ModelContext) -> String? {
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        guard !foods.isEmpty else { return nil }
        guard let target = computeDailyTarget(ctx: ctx) else { return nil }

        let week  = CalorieStats.stats(for: CalorieStats.thisWeek(),  foods: foods, dailyTarget: target)
        let month = CalorieStats.stats(for: CalorieStats.thisMonth(), foods: foods, dailyTarget: target)
        let last30 = CalorieStats.stats(for: CalorieStats.last(days: 30), foods: foods, dailyTarget: target)

        func line(_ label: String, _ s: CaloriePeriodStats) -> String {
            let balanceLabel: String = {
                if s.netBalance > 0 { return "+\(Fmt.int(s.netBalance)) kcal fazla" }
                if s.netBalance < 0 { return "\(Fmt.int(s.netBalance)) kcal açık" }
                return "dengeli"
            }()
            return "- \(label): \(Fmt.int(s.totalConsumed)) kcal toplam · \(s.loggedDays)/\(s.totalDays) gün · ort. \(Fmt.int(s.averageDailyKcal))/gün · \(balanceLabel)"
        }

        var lines: [String] = [
            "[KALORİ ÖZETİ (günlük hedef: \(Fmt.int(target)) kcal)]",
            line("Bu hafta", week),
            line("Bu ay", month),
            line("Son 30 gün", last30),
        ]
        // ortalama günlük net (son 30 gün) — kilo verme/alma hızını tahmin etmek için
        if last30.loggedDays >= 7 {
            let dailyAvg = last30.averageDailyBalance
            let weekly = dailyAvg * 7
            let kgPerWeek = weekly / 7700.0  // ~7700 kcal = 1 kg yağ
            lines.append("- 30 gün ortalama günlük net: \(Fmt.signed(dailyAvg, digits: 0)) kcal → tahmini \(Fmt.signed(kgPerWeek, digits: 2)) kg/hafta")
        }
        return lines.joined(separator: "\n")
    }

    /// Profil + son ölçümden günlük hedefi türet — CalorieCalculator ile.
    private static func computeDailyTarget(ctx: ModelContext) -> Double? {
        guard let profile = fetchProfile(ctx: ctx) else { return nil }
        let measurements = fetchMeasurements(ctx: ctx)
        guard let weight = measurements.first?.weight else { return nil }
        let bf = measurements.first?.bodyFat ?? profile.manualBodyFat
        let result = CalorieCalculator.compute(
            weight: weight,
            height: profile.height,
            age: profile.age,
            sex: profile.sex,
            bodyFat: bf,
            activity: profile.activity,
            goal: profile.goal,
            manualOffset: profile.manualCalorieOffset
        )
        return result.goalCalories
    }

    private static func goalsSection(ctx: ModelContext, latestWeight: Double?) -> String? {
        let goals = (try? ctx.fetch(FetchDescriptor<MonthlyGoal>(sortBy: [SortDescriptor(\.anchorDate)]))) ?? []
        guard !goals.isEmpty else { return nil }
        let now = Date()
        let past = goals.filter { $0.anchorDate <= now }
        let upcoming = goals.filter { $0.anchorDate > now }

        var lines: [String] = ["[AYLIK HEDEFLER]"]
        if let last = past.last {
            lines.append("- Geçmiş son hedef: \(Fmt.num(last.targetWeight, digits: 1)) kg (\(Fmt.dateLong.string(from: last.anchorDate)))")
        }
        if let next = upcoming.first {
            var line = "- Yaklaşan hedef: \(Fmt.num(next.targetWeight, digits: 1)) kg (\(Fmt.dateLong.string(from: next.anchorDate)))"
            if let w = latestWeight {
                let diff = w - next.targetWeight
                line += " — hedefe \(Fmt.num(abs(diff), digits: 1)) kg \(diff > 0 ? "düşmek" : "çıkmak") gerekiyor"
            }
            lines.append(line)
        }
        let later = upcoming.dropFirst().prefix(4)
        if !later.isEmpty {
            let str = later.map { "\(Fmt.dateLong.string(from: $0.anchorDate)): \(Fmt.num($0.targetWeight, digits: 1)) kg" }.joined(separator: " · ")
            lines.append("- Sonraki: \(str)")
        }
        lines.append("- Toplam: \(goals.count) ay · \(upcoming.count) ay kaldı")
        return lines.joined(separator: "\n")
    }

    private static func todaysWorkoutSection(ctx: ModelContext) -> String? {
        let weekday = Calendar.current.component(.weekday, from: .now)
        let workouts = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let overrides = (try? ctx.fetch(FetchDescriptor<WorkoutPlanOverride>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard !workouts.isEmpty || !overrides.isEmpty else { return nil }

        var lines: [String] = ["[HAFTALIK ANTRENMAN PROGRAMI]"]
        if let today = workouts.first(where: { $0.weekday == weekday }) {
            lines.append("- Bugün (\(today.weekdayName)): \(today.name) · ~\(Fmt.int(today.estimatedCalories)) kcal")
        } else {
            lines.append("- Bugün antrenman yok")
        }
        // Tüm hafta — Pzt'den başla (Calendar weekday 2)
        let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1] // Pzt..Paz
        let weekdayShort = ["", "Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"]
        var weekParts: [String] = []
        var totalKcal: Double = 0
        for wd in orderedWeekdays {
            if let w = workouts.first(where: { $0.weekday == wd }) {
                weekParts.append("\(weekdayShort[wd])=\(w.name)")
                totalKcal += w.estimatedCalories
            } else {
                weekParts.append("\(weekdayShort[wd])=—")
            }
        }
        lines.append("- Tüm hafta: " + weekParts.joined(separator: " · "))
        let trainingDays = workouts.count
        lines.append("- \(trainingDays) gün/hafta · toplam ~\(Fmt.int(totalKcal)) kcal/hafta")
        if !overrides.isEmpty {
            let overrideParts = overrides.map { item in
                "\(weekdayShort[item.weekday]) + \(item.exerciseName) (\(item.prescriptionText))"
            }
            lines.append("- AI/user plan eklemeleri: " + overrideParts.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    /// Antrenman logları — gerçek seanslar (haftalık template'ten farklı).
    /// Bu hafta + bu ay özet + son 5 seansın detayı (hareketler dahil).
    private static func workoutLogsSection(ctx: ModelContext) -> String? {
        let logs = (try? ctx.fetch(FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        guard !logs.isEmpty else { return nil }

        let cal = Calendar.current
        let now = Date()
        var weekCal = cal
        weekCal.firstWeekday = 2
        let weekRange = weekCal.dateInterval(of: .weekOfYear, for: now)
        let monthRange = cal.dateInterval(of: .month, for: now)
        let thirtyAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now

        let weekLogs  = logs.filter { weekRange?.contains($0.date) ?? false }
        let monthLogs = logs.filter { monthRange?.contains($0.date) ?? false }
        let last30    = logs.filter { $0.date >= thirtyAgo }

        var lines: [String] = ["[ANTRENMAN LOGLARI]"]
        lines.append("- Bu hafta: \(weekLogs.count) seans · \(weekLogs.map(\.durationMinutes).reduce(0, +)) dk · \(Fmt.int(weekLogs.map(\.estimatedCalories).reduce(0, +))) kcal")
        lines.append("- Bu ay: \(monthLogs.count) seans · \(monthLogs.map(\.durationMinutes).reduce(0, +)) dk")
        let freqPerWeek = Double(last30.count) / (30.0 / 7.0)
        lines.append("- Son 30 gün: \(last30.count) seans · ort. \(String(format: "%.1f", freqPerWeek)) seans/hafta")
        lines.append("- Toplam (tüm zamanlar): \(logs.count) seans · \(logs.map(\.durationMinutes).reduce(0, +) / 60) saat")

        // Son 5 seansın detayı
        lines.append("- Son seanslar:")
        for log in logs.prefix(5) {
            let dateStr = Fmt.date.string(from: log.date)
            let exCount = log.exercises.count
            let exSummary = log.exercises
                .sorted { $0.order < $1.order }
                .prefix(3)
                .map { ex in
                    "\(ex.name) \(ex.summary)"
                }
                .joined(separator: ", ")
            let extra = exCount > 3 ? " +\(exCount - 3) hareket" : ""
            let exLine = exCount > 0 ? " — \(exSummary)\(extra)" : ""
            lines.append("  · \(dateStr): \(log.name) (\(log.durationMinutes) dk)\(exLine)")
        }

        return lines.joined(separator: "\n")
    }

    private static func todaysStepsSection(ctx: ModelContext, weight: Double?) -> String? {
        let cal = Calendar.current
        let steps = (try? ctx.fetch(FetchDescriptor<StepEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        guard let today = steps.first(where: { cal.isDateInToday($0.date) }) else { return nil }
        var lines: [String] = ["[ADIM (bugün)]"]
        var line = "- \(Fmt.int(Double(today.steps))) adım"
        if let w = weight {
            let kcal = StepEntry.calorieBurn(steps: today.steps, weightKg: w)
            line += " · ~\(Fmt.int(kcal)) kcal"
        }
        lines.append(line)
        return lines.joined(separator: "\n")
    }

    /// Kayıtlı tarifler — başlık + kısa içerik + kategori. Çok uzarsa kategori
    /// bazlı sayım ve son 10 başlık.
    private static func recipesSection(ctx: ModelContext) -> String? {
        let recipes = (try? ctx.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        guard !recipes.isEmpty else { return nil }
        var lines: [String] = ["[KAYITLI TARİFLER (\(recipes.count))]"]
        // Kategori sayımı
        let counts = Dictionary(grouping: recipes, by: { $0.category }).mapValues { $0.count }
        let countLine = RecipeCategory.allCases.compactMap { cat -> String? in
            guard let n = counts[cat], n > 0 else { return nil }
            return "\(cat.label) \(n)"
        }.joined(separator: " · ")
        if !countLine.isEmpty {
            lines.append("- Dağılım: \(countLine)")
        }
        // Son 12 tarif başlığı
        let recent = recipes.prefix(12)
        let titles = recent.map { recipe -> String in
            let summary = recipe.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = summary.isEmpty ? "" : " — \(summary)"
            return "  · [\(recipe.category.label)] \(recipe.title)\(detail)"
        }
        lines.append(contentsOf: titles)
        if recipes.count > 12 {
            lines.append("  · (... ve \(recipes.count - 12) tarif daha)")
        }
        return lines.joined(separator: "\n")
    }

    private static func mealPlanTodaySection(ctx: ModelContext) -> String {
        let weekday = Calendar.current.component(.weekday, from: .now)
        let overrides = (try? ctx.fetch(FetchDescriptor<MealPlanOverride>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let dayType = MealPlanOverride.dayTypeOverride(for: weekday, in: overrides) ?? MealLibrary.dayType(for: weekday)
        let template = MealLibrary.template(for: dayType)
        let todaysOverrides = overrides.filter { $0.weekday == weekday }
        let customItems = todaysOverrides.filter { $0.operation == .addItem }

        // Aktif deficit seviyesini AppStorage'dan oku (kullanıcı MealPlan view'da seçtiyse)
        let deficitRaw = UserDefaults.standard.string(forKey: "mealplan.deficit") ?? DeficitLevel.maintain.rawValue
        let deficit = DeficitLevel(rawValue: deficitRaw) ?? .maintain
        let customTotals = customItems.reduce(Macros.zero) { $0 + $1.macros }
        let totals = template.totals(deficit: deficit.factor) + customTotals

        let wd = Weekday(rawValue: weekday)?.long ?? "Bugün"
        var lines: [String] = ["[YEMEK PLANI — \(wd) (\(dayType.label) günü)]"]
        lines.append("- \(dayType.headline)")

        if deficit != .maintain {
            lines.append("- Aktif DEFICIT: \(deficit.label) (\(deficit.deltaKcal) kcal) — porsiyonlar bu orana göre kısılmış halde aşağıda.")
        }

        lines.append("- Bugünkü hedef toplam: ~\(Fmt.int(totals.kcal)) kcal · P \(Fmt.int(totals.p))g · C \(Fmt.int(totals.c))g · Y \(Fmt.int(totals.f))g")

        // Öğün öğün döküm
        lines.append("- Öğünler (tüm gramlar çiğ ağırlık):")
        for meal in template.meals {
            let mealCustomItems = customItems.filter { $0.slot == meal.slot }
            let mealTotals = meal.totals(deficit: deficit.factor) + mealCustomItems.reduce(Macros.zero) { $0 + $1.macros }
            var mealLine = "  · \(meal.slot.label) (~\(Fmt.int(mealTotals.kcal)) kcal):"
            var items = meal.items.map { item -> String in
                let amount = item.amount(deficit: deficit.factor)
                let amountStr: String
                if item.unit == "adet" || item.unit == "tabak" {
                    amountStr = "\(Int(amount.rounded())) \(item.unit)"
                } else {
                    // 5g'a yuvarla
                    let rounded = (amount / 5.0).rounded() * 5.0
                    amountStr = "\(Int(rounded)) \(item.unit)"
                }
                return "\(amountStr) \(item.name)"
            }
            items.append(contentsOf: mealCustomItems.map { item in
                let amount = item.amountText.isEmpty ? "" : "\(item.amountText) "
                let kcal = item.calories.map { " (~\(Fmt.int($0)) kcal)" } ?? ""
                return "\(amount)\(item.displayName)\(kcal) [AI düzenleme]"
            })
            mealLine += " " + items.joined(separator: " + ")
            lines.append(mealLine)
        }

        // Haftalık rotasyon — AI "yarın ne yiyeceğim" gibi soruları yanıtlayabilsin
        lines.append("- Haftalık rotasyon: " + Weekday.orderedTrWeek.map {
            let override = MealPlanOverride.dayTypeOverride(for: $0.rawValue, in: overrides)
            return "\($0.short)=\((override ?? MealLibrary.dayType(for: $0.rawValue)).short)"
        }.joined(separator: " · "))

        return lines.joined(separator: "\n")
    }

    // MARK: - Fetch helpers

    private static func fetchProfile(ctx: ModelContext) -> UserProfile? {
        (try? ctx.fetch(FetchDescriptor<UserProfile>()))?.first
    }

    private static func fetchMeasurements(ctx: ModelContext) -> [Measurement] {
        (try? ctx.fetch(FetchDescriptor<Measurement>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }
}
