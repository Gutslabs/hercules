import Foundation
import SwiftData

// MARK: - Mention tags

/// Sidebar menü öğeleri + aliasları. Kullanıcı `@yemek planı` yazdığında
/// AI'ya sadece o bölümün verisi enjekte edilir.

extension UserContextSnapshot {
    /// Türkçe aksanları silen + case-fold yapan helper. View'lardan da kullanılabilir.
    static func publicNormalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                  locale: Locale(identifier: "en_US"))
    }
}

enum SnapshotSection: CaseIterable, Hashable {
    case profile, latestMeasurement, measurementLog, trend, todayIntake, foodDiary, caloriePeriods, goals, workout, workoutLogs, steps, recipes, labs
}

enum UserContextSnapshot {

    // MARK: - Public API

    /// Mesaj içindeki `@etiket` ifadelerini ayrıştırır. Tanınmayan etiketleri
    /// boş döndürür. Aksanlara duyarsız (Türkçe i/ı/ş/ğ farkları normalize).
    /// `@Etiket[token]` biçimindeki AÇIK aralık seçimlerini çıkarır.
    ///
    /// Orijinal metin üzerinde çalışır (normalize edilmiş değil): köşeli parantez içeriği
    /// birebir korunmalı, aksi halde "2026-06..2026-07" bozulur.
    static func parseMentionSelections(_ text: String) -> [MentionSelection] {
        guard text.contains("@") else { return [] }
        var byTag: [MentionTag: MentionRange] = [:]

        let pattern = #"@([^\[\]\n]{1,40}?)\[([^\]\n]{1,40})\]"#
        if let re = try? NSRegularExpression(pattern: pattern) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard m.numberOfRanges == 3 else { continue }
                let label = ns.substring(with: m.range(at: 1))
                let token = ns.substring(with: m.range(at: 2))
                guard let range = MentionRange.parse(token: token) else { continue }
                let needle = normalize(label).trimmingCharacters(in: .whitespaces)
                let tag = MentionTag.allCases.first { candidate in
                    ([candidate.displayName] + candidate.aliases)
                        .contains { normalize($0) == needle }
                }
                guard let tag else { continue }
                byTag[tag.canonical] = range
            }
        }

        // Parantezsiz etiketler de seçim sayılır, aralıkları nil.
        var out = byTag.map { MentionSelection(tag: $0.key, range: $0.value) }
        for tag in parseMentions(text) where byTag[tag] == nil {
            out.append(MentionSelection(tag: tag, range: nil))
        }
        return out
    }

    /// Seçimler arasından zaman aralığı taşıyan İLKİNİ döndürür. Birden çok etikete farklı
    /// aralık verilmesi anlamlı değil (snapshot tek bir zaman penceresi kullanıyor); ilkini
    /// alıp diğerlerini yok saymak, sessizce yanlış pencere kullanmaktan iyi.
    static func explicitRange(in selections: [MentionSelection]) -> MentionRange? {
        selections.compactMap(\.range).first
    }

    static func parseMentions(_ text: String) -> Set<MentionTag> {
        guard text.contains("@") else { return [] }
        let normalizedText = normalize(text)
        var found: Set<MentionTag> = []
        for tag in MentionTag.allCases {
            let candidates = [tag.displayName] + tag.aliases
            for cand in candidates {
                let needle = "@" + normalize(cand)
                if normalizedText.contains(needle) {
                    found.insert(tag.canonical)
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

    /// Kullanıcının düzenli kullandığı supplementler — her sohbette kalıcı
    /// context olarak AI'ya verilir. Boşsa nil.
    static func supplementsSection(ctx: ModelContext) -> String? {
        guard let profile = fetchProfile(ctx: ctx) else { return nil }
        let trimmed = profile.effectiveSupplements.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let items = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }
        return "[KULLANICI SUPPLEMENTLERİ — kalıcı profil bilgisi]\n- \(items.joined(separator: "\n- "))"
    }

    /// `aboutSection` + (varsa) mention-based snapshot'ı birleştirir.
    /// **About metnindeki `@etiket`leri de tarar** — kullanıcı bio'sunda
    /// "@Ölçümler'e bak" diye yazdıysa, ölçüm verisi HER sohbette inject olur.
    /// Chat input'taki @ etiketleri ile birleşir.
    static func combined(tags: Set<MentionTag>, ctx: ModelContext) -> String? {
        let about = aboutSection(ctx: ctx)
        let supplements = supplementsSection(ctx: ctx)
        let aboutMentions = aboutMentionTags(ctx: ctx)
        let allTags = tags.union(aboutMentions)
        let mentionData = allTags.isEmpty ? nil : build(tags: allTags, ctx: ctx)
        let parts = [about, supplements, mentionData].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    /// V4 coach context: @mention olmasa bile fitness/nutrition sorularında
    /// alakalı profil, ölçüm, kalori, adım ve antrenman verisini otomatik ekler.
    static func coachContext(
        for query: String,
        explicitTags tags: Set<MentionTag>,
        ctx: ModelContext,
        explicitRange: MentionRange? = nil
    ) -> String? {
        let about = aboutSection(ctx: ctx)
        let supplements = supplementsSection(ctx: ctx)
        let aboutMentions = aboutMentionTags(ctx: ctx)
        let allTags = tags.union(aboutMentions)

        var neededSections = Set(allTags.flatMap { $0.sections })
        neededSections.formUnion(inferredSections(for: query))
        // Kullanıcı bir aralık seçtiyse geçmiş günlük ŞART — sadece "bugün" bölümüyle
        // cevaplanamaz. Seçim varken bunu çıkarımın insafına bırakmıyoruz.
        if let explicitRange {
            neededSections.insert(explicitRange == .today ? .todayIntake : .foodDiary)
            neededSections.insert(.measurementLog)
        }

        let data = neededSections.isEmpty
            ? nil
            : buildSnapshot(sections: neededSections, ctx: ctx, query: query, explicitRange: explicitRange)
        let parts = [about, supplements, data].compactMap { $0 }
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

    private static func buildSnapshot(sections requested: Set<SnapshotSection>, ctx: ModelContext, query: String? = nil, explicitRange: MentionRange? = nil) -> String? {
        var output: [String] = []
        // Açık seçim varsa metin ayrıştırıcı ÇALIŞMAZ. İkisi birlikte çalışsaydı hangi
        // pencerenin kazandığı belirsiz olurdu ve yine tahmine düşerdik.
        let foodScope = explicitRange.map { FoodDiaryScope(explicit: $0) }
            ?? query.flatMap { FoodDiaryScope.parse(query: $0) }
        let shouldFetchMeasurements = !requested.intersection([.latestMeasurement, .measurementLog, .trend, .goals, .steps, .caloriePeriods]).isEmpty
        let measurements = shouldFetchMeasurements
            ? fetchMeasurements(ctx: ctx, limit: measurementFetchLimit(for: query, scope: foodScope))
            : []

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
        if !requested.intersection([.trend, .goals, .measurementLog]).isEmpty,
           let epochs = dietEpochsSection(ctx: ctx) {
            output.append(epochs)
        }
        if requested.contains(.measurementLog),
           let log = measurementLogSection(measurements, scope: foodScope) {
            output.append(log)
        }
        if requested.contains(.todayIntake), let today = todayIntakeSection(ctx: ctx) {
            output.append(today)
        }
        if requested.contains(.foodDiary), let diary = foodDiarySection(ctx: ctx, scope: foodScope) {
            output.append(diary)
        }
        if requested.contains(.caloriePeriods), let aggregates = caloriePeriodsSection(ctx: ctx, query: query) {
            output.append(aggregates)
        }
        if requested.contains(.goals),
           let goals = goalsSection(ctx: ctx, latestWeight: measurements.first?.weight) {
            output.append(goals)
        }
        if requested.contains(.workout), let workout = todaysWorkoutSection(ctx: ctx) {
            output.append(workout)
        }
        if requested.contains(.workoutLogs),
           let workoutLogs = workoutLogsSection(ctx: ctx, query: query, scope: foodScope) {
            output.append(workoutLogs)
        }
        if requested.contains(.steps),
           let steps = stepsSection(ctx: ctx, weight: measurements.first?.weight, scope: foodScope) {
            output.append(steps)
        }

        if requested.contains(.recipes), let r = recipesSection(ctx: ctx) {
            output.append(r)
        }

        if requested.contains(.labs), let labs = labsSection(ctx: ctx) {
            output.append(labs)
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

    private static func inferredSections(for query: String) -> Set<SnapshotSection> {
        let lower = normalize(query).lowercased()

        if isAllDataRequest(lower) {
            return Set(SnapshotSection.allCases)
        }

        let dateScope = FoodDiaryScope.parse(query: query)
        var sections: Set<SnapshotSection> = []

        if let dateScope {
            if dateScope.isToday {
                sections.insert(.todayIntake)
            } else {
                sections.insert(.foodDiary)
            }
            if wantsCaloriePeriodSummary(lower, scope: dateScope) {
                sections.insert(.caloriePeriods)
            }
            if containsAny(lower, ["takvim", "calendar", "hedef", "goal"]) {
                sections.insert(.goals)
            }
        } else {
            if containsAny(lower, ["bugun", "bugün", "today", "kalan", "remaining"]) {
                sections.insert(.todayIntake)
            }
            if wantsFoodDiary(lower) {
                sections.insert(.foodDiary)
            }
            if wantsCaloriePeriodSummary(lower, scope: nil) {
                sections.insert(.caloriePeriods)
            }
            if containsAny(lower, ["takvim", "calendar", "hedef", "goal"]) {
                sections.insert(.goals)
            }
        }

        // Kan tahlili soruları koç sorusu sayılmasa bile panel verisi olmadan
        // cevap tahmine düşer — bu yüzden kapıdan ÖNCE bakılıyor.
        if containsAny(lower, labSignals) {
            sections.insert(.labs)
            sections.insert(.profile)
        }

        guard AgentQueryClassifier.isCoachQuery(query) else { return sections }

        sections.formUnion([.profile, .latestMeasurement, .trend, .goals])

        if containsAny(lower, AgentQueryClassifier.trainingSignals) {
            sections.formUnion([.workout, .workoutLogs, .steps])
        }

        if containsAny(lower, AgentQueryClassifier.nutritionSignals) {
            sections.insert(.todayIntake)
            if wantsFoodDiary(lower) || dateScope != nil {
                sections.insert(.foodDiary)
            }
            if wantsCaloriePeriodSummary(lower, scope: dateScope) {
                sections.insert(.caloriePeriods)
            }
            if containsAny(lower, ["cut", "definasyon", "bulk", "tdee", "maintenance", "adim", "step"]) {
                sections.insert(.steps)
            }
        }

        // "yuru" → yürüyorum / yürüyüş / yürümem — adım verisi bu sorularda da lazım.
        if containsAny(lower, ["kilo", "yag", "lean", "definasyon", "cut", "bulk", "plato", "hedef", "adim", "step", "yuru", "neat"]) {
            sections.insert(.todayIntake)
            sections.insert(.steps)
            if wantsCaloriePeriodSummary(lower, scope: dateScope) {
                sections.insert(.caloriePeriods)
            }
        }

        // Kilo/plato/trend + tarih soruları özet 4 noktayla cevaplanamaz — günlük
        // tartı kayıtları şart ("1 Temmuz'dan beri aynı kilodayım" gibi).
        if containsAny(lower, ["kilo", "tarti", "plato", "durgun", "sabit", "ayni kilo", "trend", "degisim", "ilerleme"])
            || dateScope != nil {
            sections.insert(.measurementLog)
        }

        if containsAny(lower, ["takvim", "calendar", "dun", "dunku", "dünkü", "onceki", "önceki", "mayis", "mayıs", "nisan", "haziran"]) {
            sections.insert(dateScope?.isToday == true ? .todayIntake : .foodDiary)
            sections.insert(.goals)
            if wantsCaloriePeriodSummary(lower, scope: dateScope) {
                sections.insert(.caloriePeriods)
            }
        }

        if containsAny(lower, ["tarif", "recipe", "yemek tarifi"]) {
            sections.formUnion([.recipes])
        }




        return sections
    }

    private struct FoodDiaryScope {
        let start: Date
        let endExclusive: Date
        let label: String
        let isExactDay: Bool
        let dayCount: Int

        /// Kullanıcının picker'dan seçtiği aralık. Metin ayrıştırıcıya HİÇ uğramaz.
        init(explicit range: MentionRange, now: Date = .now, cal: Calendar = .current) {
            let i = range.interval(now: now, calendar: cal)
            self.start = i.start
            self.endExclusive = i.endExclusive
            self.label = range.displayLabel
            self.isExactDay = range == .today
            self.dayCount = max(1, cal.dateComponents([.day], from: i.start, to: i.endExclusive).day ?? 1)
        }

        init(start: Date, endExclusive: Date, label: String, isExactDay: Bool, dayCount: Int) {
            self.start = start
            self.endExclusive = endExclusive
            self.label = label
            self.isExactDay = isExactDay
            self.dayCount = dayCount
        }

        func contains(_ date: Date) -> Bool {
            date >= start && date < endExclusive
        }

        var isToday: Bool {
            isExactDay && Calendar.current.isDateInToday(start)
        }

        static func parse(query: String, now: Date = .now, calendar cal: Calendar = .current) -> FoodDiaryScope? {
            let lower = UserContextSnapshot.normalize(query).lowercased()

            if UserContextSnapshot.containsAny(lower, ["evvelsi gun", "evvelki gun", "onceki gun", "önceki gün"]) {
                return exactDay(offset: -2, label: "evvelsi gün", now: now, cal: cal)
            }
            if UserContextSnapshot.containsAny(lower, ["dun", "dunku", "dünkü", "yesterday"]) {
                return exactDay(offset: -1, label: "dün", now: now, cal: cal)
            }
            if UserContextSnapshot.containsAny(lower, ["bugun", "bugünkü", "bugunku", "today"]) {
                return exactDay(offset: 0, label: "bugün", now: now, cal: cal)
            }
            if UserContextSnapshot.containsAny(lower, ["bu hafta", "current week"]) {
                let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
                let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
                let days = max(1, cal.dateComponents([.day], from: start, to: end).day ?? 1)
                return FoodDiaryScope(start: start, endExclusive: end, label: "bu hafta", isExactDay: false, dayCount: days)
            }
            if UserContextSnapshot.containsAny(lower, ["gecen hafta", "geçen hafta", "previous week"]) {
                guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now),
                      let previousWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start),
                      let previousWeek = cal.dateInterval(of: .weekOfYear, for: previousWeekStart)
                else { return nil }
                let days = max(1, cal.dateComponents([.day], from: previousWeek.start, to: previousWeek.end).day ?? 7)
                return FoodDiaryScope(start: previousWeek.start, endExclusive: previousWeek.end, label: "geçen hafta", isExactDay: false, dayCount: days)
            }

            // Ek payı ŞART: "son 3 günde / 2 haftada / 6 ayda" en doğal yazımlar ve
            // düz `\b` ile hiçbiri eşleşmiyordu.
            if let range = captures(in: lower, pattern: #"\bson\s+(\d+)\s*(gun|hafta|ay)\#(trSuffix)\b"#),
               let n = Int(range[0]) {
                let unit = range[1]
                let days = daysFor(amount: n, unit: unit)
                return rolling(days: days, label: "son \(n) \(displayUnit(unit))", now: now, cal: cal)
            }

            if let range = captures(in: lower, pattern: #"\b(\d+)\s*(gunluk|haftalik|aylik)\#(trSuffix)\b"#),
               let n = Int(range[0]) {
                let unit = range[1]
                let days = daysFor(amount: n, unit: unit)
                return rolling(days: days, label: "\(n) \(displayUnit(unit))", now: now, cal: cal)
            }

            if UserContextSnapshot.containsAny(lower, ["son ay", "1 ay", "aylik", "aylık"]) {
                return rolling(days: 30, label: "son 1 ay", now: now, cal: cal)
            }
            if UserContextSnapshot.containsAny(lower, ["haftalik", "haftalık"]) {
                return rolling(days: 7, label: "son 1 hafta", now: now, cal: cal)
            }
            if UserContextSnapshot.containsAny(lower, ["bu ay", "current month"]) {
                let start = cal.dateInterval(of: .month, for: now)?.start ?? cal.startOfDay(for: now)
                let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
                let days = max(1, cal.dateComponents([.day], from: start, to: end).day ?? 1)
                return FoodDiaryScope(start: start, endExclusive: end, label: "bu ay", isExactDay: false, dayCount: days)
            }
            if UserContextSnapshot.containsAny(lower, ["gecen ay", "geçen ay", "previous month"]) {
                guard let thisMonth = cal.dateInterval(of: .month, for: now),
                      let previousMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonth.start),
                      let previousMonth = cal.dateInterval(of: .month, for: previousMonthStart)
                else { return nil }
                let days = max(1, cal.dateComponents([.day], from: previousMonth.start, to: previousMonth.end).day ?? 1)
                return FoodDiaryScope(start: previousMonth.start, endExclusive: previousMonth.end, label: "geçen ay", isExactDay: false, dayCount: days)
            }

            if let iso = captures(in: lower, pattern: #"\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b"#),
               let year = Int(iso[0]), let month = Int(iso[1]), let day = Int(iso[2]),
               let date = date(year: year, month: month, day: day, cal: cal) {
                return dayOrSince(date: date, label: Fmt.dateLong.string(from: date), lower: lower, now: now, cal: cal)
            }

            if let numeric = captures(in: lower, pattern: #"\b(\d{1,2})[./-](\d{1,2})(?:[./-](20\d{2}))?\b"#),
               let day = Int(numeric[0]), let month = Int(numeric[1]) {
                let year = Int(numeric[2]) ?? cal.component(.year, from: now)
                if let date = date(year: year, month: month, day: day, cal: cal) {
                    return dayOrSince(date: date, label: Fmt.dateLong.string(from: date), lower: lower, now: now, cal: cal)
                }
            }

            if let textual = captures(in: lower, pattern: #"\b(\d{1,2})\s+(\#(monthAlternation))\#(trSuffix)(?:\s+(20\d{2}))?\b"#),
               let day = Int(textual[0]), let month = monthNumber(textual[1]) {
                let year = Int(textual[2]) ?? cal.component(.year, from: now)
                if let date = date(year: year, month: month, day: day, cal: cal) {
                    return dayOrSince(date: date, label: Fmt.dateLong.string(from: date), lower: lower, now: now, cal: cal)
                }
            }

            if let monthOnly = captures(in: lower, pattern: #"\b(\#(monthAlternation))\#(trSuffix)(?:\s+(20\d{2}))?\b"#),
               let month = monthNumber(monthOnly[0]) {
                let year = Int(monthOnly[1]) ?? cal.component(.year, from: now)
                return monthScope(year: year, month: month, monthName: monthOnly[0], cal: cal)
            }

            return nil
        }

        private static let monthAlternation =
            "ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik"

        /// Tek kaynak: `AgentQueryClassifier.turkishSuffix`. "1 temmuzdan", "temmuzda",
        /// "25 temmuzdaki", "son 3 günde"… Ek yoksa da eşleşir (grup opsiyonel).
        private static let trSuffix = AgentQueryClassifier.turkishSuffix

        /// "1 Temmuz'dan beri" → tek gün DEĞİL, o günden bugüne aralık.
        private static func dayOrSince(
            date: Date, label: String, lower: String, now: Date, cal: Calendar
        ) -> FoodDiaryScope {
            let sinceMarkers = ["beri", "itibaren", "itibariyle", "sonrasinda", "sonrasi", "since"]
            guard UserContextSnapshot.containsAny(lower, sinceMarkers) else {
                return exactDay(date: date, label: label, cal: cal)
            }
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            guard start < end else { return exactDay(date: date, label: label, cal: cal) }
            let days = max(1, cal.dateComponents([.day], from: start, to: end).day ?? 1)
            return FoodDiaryScope(
                start: start,
                endExclusive: end,
                label: "\(label) → bugün",
                isExactDay: false,
                dayCount: days
            )
        }

        private static func exactDay(offset: Int, label: String, now: Date, cal: Calendar) -> FoodDiaryScope? {
            guard let date = cal.date(byAdding: .day, value: offset, to: now) else { return nil }
            return exactDay(date: date, label: label, cal: cal)
        }

        private static func exactDay(date: Date, label: String, cal: Calendar) -> FoodDiaryScope {
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? date
            return FoodDiaryScope(start: start, endExclusive: end, label: label, isExactDay: true, dayCount: 1)
        }

        private static func rolling(days: Int, label: String, now: Date, cal: Calendar) -> FoodDiaryScope {
            let clampedDays = max(1, min(days, 120))
            let todayStart = cal.startOfDay(for: now)
            let start = cal.date(byAdding: .day, value: -(clampedDays - 1), to: todayStart) ?? todayStart
            let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? now
            return FoodDiaryScope(start: start, endExclusive: end, label: label, isExactDay: false, dayCount: clampedDays)
        }

        private static func monthScope(year: Int, month: Int, monthName: String, cal: Calendar) -> FoodDiaryScope? {
            guard let date = date(year: year, month: month, day: 1, cal: cal),
                  let interval = cal.dateInterval(of: .month, for: date)
            else { return nil }
            let days = max(1, cal.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
            return FoodDiaryScope(
                start: interval.start,
                endExclusive: interval.end,
                label: "\(monthName) \(year)",
                isExactDay: false,
                dayCount: days
            )
        }

        private static func daysFor(amount: Int, unit: String) -> Int {
            if unit.contains("hafta") { return amount * 7 }
            if unit.contains("ay") { return amount * 30 }
            return amount
        }

        private static func displayUnit(_ unit: String) -> String {
            if unit.contains("hafta") { return "hafta" }
            if unit.contains("ay") { return "ay" }
            return "gün"
        }

        private static func date(year: Int, month: Int, day: Int, cal: Calendar) -> Date? {
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            return cal.date(from: DateComponents(calendar: cal, year: year, month: month, day: day))
        }

        private static func monthNumber(_ normalizedMonth: String) -> Int? {
            [
                "ocak": 1, "subat": 2, "mart": 3, "nisan": 4, "mayis": 5, "haziran": 6,
                "temmuz": 7, "agustos": 8, "eylul": 9, "ekim": 10, "kasim": 11, "aralik": 12
            ][normalizedMonth]
        }

        private static func captures(in text: String, pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }
            return (1..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
                return String(text[swiftRange])
            }
        }
    }

    private static func containsAny(_ lowercasedText: String, _ needles: [String]) -> Bool {
        AgentQueryClassifier.containsAny(lowercasedText, needles)
    }

    static func requestedFoodInterval(for query: String, now: Date = .now, calendar cal: Calendar = .current) -> DateInterval? {
        guard let scope = FoodDiaryScope.parse(query: query, now: now, calendar: cal) else { return nil }
        return DateInterval(start: scope.start, end: scope.endExclusive)
    }

    private static func isAllDataRequest(_ lower: String) -> Bool {
        containsAny(lower, ["hepsi", "tumu", "tum veri", "her sey", "all", "everything"])
    }

    private static func wantsFoodDiary(_ lower: String) -> Bool {
        containsAny(lower, [
            "yemek gunlugu", "yemek günlüğü", "ne yedim", "neler yedim", "yediklerim",
            "ogunler", "öğünler", "log", "kayitlar", "kayıtlar", "takvim", "calendar",
            "dun", "dunku", "dünkü", "onceki", "önceki"
        ])
    }

    private static func wantsCaloriePeriodSummary(_ lower: String, scope: FoodDiaryScope?) -> Bool {
        if isAllDataRequest(lower) { return true }
        if containsAny(lower, [
            "ortalama", "average", "ozet", "özet", "toplam", "total", "acik", "açık",
            "fazla", "deficit", "surplus", "denge", "balance", "tempo", "hiz", "hız",
            "gidiyor", "plato", "tdee", "maintenance", "hedefe", "ulasir", "ulaşır"
        ]) {
            return true
        }
        if containsAny(lower, [
            "bu hafta", "gecen hafta", "geçen hafta", "son 7", "7 gun", "7 gün",
            "son 14", "14 gun", "14 gün", "son 30", "30 gun", "30 gün",
            "son 90", "90 gun", "90 gün", "bu ay", "gecen ay", "geçen ay",
            "aylik", "aylık", "haftalik", "haftalık"
        ]) {
            return true
        }
        guard let scope else { return false }
        return !scope.isExactDay && scope.dayCount >= 7
    }

    private static func measurementFetchLimit(for query: String?, scope: FoodDiaryScope? = nil) -> Int? {
        guard let query else { return nil }
        let lower = normalize(query).lowercased()
        if isAllDataRequest(lower) { return nil }
        // Geniş bir tarih aralığı istendiyse 180 kayıt yetmeyebilir (her gün
        // tartılan biri için ~6 ay) — sınırı kaldır.
        if let scope, scope.dayCount > 150 { return nil }
        return 180
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
        let supplements = p.effectiveSupplements
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !supplements.isEmpty {
            lines.append("- Supplementler: \(supplements.joined(separator: " · "))")
        }
        let manualMacros = [
            p.manualProteinGrams.map { "P \(Fmt.int($0))g" },
            p.manualCarbsGrams.map { "K \(Fmt.int($0))g" },
            p.manualFatGrams.map { "Y \(Fmt.int($0))g" },
        ].compactMap { $0 }
        if !manualMacros.isEmpty {
            lines.append("- Manuel makro hedefi: \(manualMacros.joined(separator: " · "))")
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

    /// Tek tek tartılar. `trendSection` yalnızca 4 ÖRNEK nokta verir (7/14/30/90 gün
    /// önce); "1 Temmuz'dan beri aynı kilodayım" gibi bir soruda AI'nın günlük
    /// kayıtlara ihtiyacı var — yoksa "elimde o tarihe ait kayıt yok" der (kayıt var).
    private static func measurementLogSection(_ measurements: [Measurement], scope: FoodDiaryScope?) -> String? {
        let recorded = measurements.filter { $0.weight != nil || $0.bodyFat != nil || $0.waist != nil }
        guard !recorded.isEmpty else { return nil }

        let scoped: [Measurement]
        let title: String
        if let scope {
            scoped = recorded.filter { scope.contains($0.date) }
            title = "[ÖLÇÜM GÜNLÜĞÜ — \(scope.label)]"
            if scoped.isEmpty {
                return "\(title)\n- Bu aralıkta kayıtlı ölçüm yok."
            }
        } else {
            scoped = Array(recorded.prefix(90))
            title = "[ÖLÇÜM GÜNLÜĞÜ — son \(scoped.count) kayıt, yeniden eskiye]"
        }

        var lines: [String] = [title]
        lines.append("AI talimatı: Bir tarih/aralık sorulursa bu satırları esas al. Burada olmayan gün için ölçüm YOK demektir — ara değer uydurma.")
        for m in scoped {
            var parts: [String] = []
            if let w = m.weight { parts.append("\(Fmt.num(w, digits: 1)) kg") }
            if let bf = m.bodyFat { parts.append("%\(Fmt.num(bf, digits: 1)) yağ") }
            if let waist = m.waist { parts.append("bel \(Fmt.num(waist, digits: 1))") }
            guard !parts.isEmpty else { continue }
            lines.append("- \(Fmt.dateLong.string(from: m.date)): \(parts.joined(separator: " · "))")
        }
        return lines.count > 2 ? lines.joined(separator: "\n") : nil
    }

    private static func trendSection(measurements: [Measurement]) -> String? {
        // measurements are sorted newest-first
        let withWeight = measurements.compactMap { m -> (Date, Double)? in
            guard let w = m.weight else { return nil }
            return (m.date, w)
        }
        guard let latest = withWeight.first, withWeight.count >= 2 else { return nil }

        let now = Date()
        func closest(daysAgo: Int, toleranceDays: Double) -> (Date, Double)? {
            let target = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            guard let best = withWeight.min(by: { abs($0.0.timeIntervalSince(target)) < abs($1.0.timeIntervalSince(target)) }),
                  abs(best.0.timeIntervalSince(target)) <= toleranceDays * 86_400 else { return nil }
            return best
        }

        var lines: [String] = ["[KİLO TRENDİ (son ölçümlere göre)]"]
        if let w7 = closest(daysAgo: 7, toleranceDays: 2.5), abs(w7.0.timeIntervalSince(latest.0)) > 86_400 {
            let delta = latest.1 - w7.1
            lines.append("- 7 gün önce: \(Fmt.num(w7.1, digits: 1)) kg → bugün \(Fmt.num(latest.1, digits: 1)) kg (\(Fmt.signed(delta, digits: 2)) kg)")
        }
        if let w14 = closest(daysAgo: 14, toleranceDays: 4), abs(w14.0.timeIntervalSince(latest.0)) > 6 * 86_400 {
            let delta = latest.1 - w14.1
            lines.append("- 14 gün önce: \(Fmt.num(w14.1, digits: 1)) kg (\(Fmt.signed(delta, digits: 2)) kg fark)")
        }
        if let w30 = closest(daysAgo: 30, toleranceDays: 10), abs(w30.0.timeIntervalSince(latest.0)) > 14 * 86_400 {
            let delta = latest.1 - w30.1
            lines.append("- 30 gün önce: \(Fmt.num(w30.1, digits: 1)) kg (\(Fmt.signed(delta, digits: 2)) kg fark)")
        }
        if let w90 = closest(daysAgo: 90, toleranceDays: 30), abs(w90.0.timeIntervalSince(latest.0)) > 45 * 86_400 {
            let delta = latest.1 - w90.1
            lines.append("- 90 gün önce: \(Fmt.num(w90.1, digits: 1)) kg (\(Fmt.signed(delta, digits: 2)) kg fark)")
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

    /// Diyet dönemleri (bkz. `DietEpoch`): koç ilerlemeyi AKTİF döneme göre yorumlasın,
    /// aradaki kilo değişimini diyet performansı sanmasın. Dönem sınırlarındaki kilolar
    /// için TÜM tartılar okunur — üstteki ölçüm limiti eski bir dönemin başını kesebilir.
    private static func dietEpochsSection(ctx: ModelContext, now: Date = .now) -> String? {
        let epochs = DietEpochArchive.load()
        let weights = TrendAnalysis.points(fetchMeasurements(ctx: ctx), for: .weight)
        let segments = DietTimeline.segments(epochs: epochs, weights: weights, today: now)
        guard !segments.isEmpty else { return nil }

        func weightText(_ segment: DietTimeline.Segment) -> String? {
            guard let start = segment.startWeight else { return nil }
            guard let end = segment.endWeight, let delta = segment.delta else {
                return "başlangıç \(Fmt.num(start, digits: 1)) kg"
            }
            return "\(Fmt.num(start, digits: 1)) → \(Fmt.num(end, digits: 1)) kg (\(Fmt.signed(delta, digits: 1)) kg)"
        }

        var lines: [String] = ["[DİYET DÖNEMLERİ]"]
        lines.append("AI talimatı: Kullanıcı diyetini dönemlere ayırıyor. İlerleme ve ritim yorumunu süren döneme göre yap; ara boyunca olan kilo değişimini diyet performansı gibi değerlendirme.")
        for segment in segments {
            let first = Fmt.dateLong.string(from: segment.firstDay)
            var parts: [String]
            switch segment.kind {
            case .epoch(let number, let id):
                parts = segment.isOngoing
                    ? ["Dönem \(number) (SÜRÜYOR): \(first) başladı", "\(segment.days). gün"]
                    : ["Dönem \(number): \(first) → \(Fmt.dateLong.string(from: segment.lastDay))", "\(segment.days) gün"]
                if let text = weightText(segment) { parts.append(text) }
                if let note = epochs.first(where: { $0.id == id })?.note { parts.append("not: \(note)") }
            case .rest:
                parts = segment.isOngoing
                    ? ["Ara (SÜRÜYOR, diyet yok): \(first) başladı", "\(segment.days) gün"]
                    : ["Ara (diyet yok): \(first) → \(Fmt.dateLong.string(from: segment.lastDay))", "\(segment.days) gün"]
                if let text = weightText(segment) { parts.append(text) }
            }
            lines.append("- " + parts.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    private static func todayIntakeSection(ctx: ModelContext) -> String? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? .now
        let todays = fetchFoods(ctx: ctx, start: start, endExclusive: end, limit: 120)
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

    /// Son kayıtlı yemek günleri. @Öğün Takip/date sorularında AI ekranı değil bu
    /// snapshot'ı gördüğü için geçmiş günleri burada açıkça veriyoruz.
    private static func foodDiarySection(ctx: ModelContext, scope: FoodDiaryScope? = nil) -> String? {
        let cal = Calendar.current
        let foods: [FoodEntry]
        if let scope {
            foods = fetchFoods(ctx: ctx, start: scope.start, endExclusive: scope.endExclusive)
        } else {
            foods = fetchFoods(ctx: ctx, limit: 350)
        }
        guard !foods.isEmpty else { return nil }

        let scopedFoods = foods

        let grouped = Dictionary(grouping: scopedFoods) { cal.startOfDay(for: $0.date) }
        let days = scope == nil ? Array(grouped.keys.sorted(by: >).prefix(14)) : grouped.keys.sorted(by: >)

        let sectionTitle = scope.map { "[YEMEK GÜNLÜĞÜ — \($0.label)]" } ?? "[YEMEK GÜNLÜĞÜ — son kayıtlı günler]"
        var lines: [String] = [sectionTitle]
        lines.append("AI talimatı: Kullanıcı 'dün', 'dünkü', '24 Mayıs', '1 aylık', '3 aylık', 'takvime bak' gibi bir tarih/aralık söylerse bu bölümdeki satırları esas al.")

        if let scope {
            let kcal = scopedFoods.reduce(0) { $0 + $1.calories }
            let p = scopedFoods.compactMap(\.protein).reduce(0, +)
            let c = scopedFoods.compactMap(\.carbs).reduce(0, +)
            let f = scopedFoods.compactMap(\.fat).reduce(0, +)
            let loggedDays = grouped.count
            let avgLogged = loggedDays > 0 ? kcal / Double(loggedDays) : 0
            let avgCalendar = kcal / Double(max(1, scope.dayCount))
            lines.append("- Kapsam: \(Fmt.dateLong.string(from: scope.start)) → \(Fmt.dateLong.string(from: scope.endExclusive.addingTimeInterval(-1)))")
            lines.append("- Toplam: \(Fmt.int(kcal)) kcal · P \(Fmt.int(p))g · C \(Fmt.int(c))g · Y \(Fmt.int(f))g · \(scopedFoods.count) öğün")
            lines.append("- Ortalama: kayıtlı gün \(Fmt.int(avgLogged)) kcal/gün · takvim günü \(Fmt.int(avgCalendar)) kcal/gün · \(loggedDays)/\(scope.dayCount) gün kayıtlı")
        }

        guard !days.isEmpty else {
            if let scope {
                lines.append("- Bu aralıkta yemek kaydı yok: \(Fmt.dateLong.string(from: scope.start)) → \(Fmt.dateLong.string(from: scope.endExclusive.addingTimeInterval(-1)))")
                return lines.joined(separator: "\n")
            }
            return nil
        }

        for day in days {
            guard let entries = grouped[day]?.sorted(by: { $0.date < $1.date }), !entries.isEmpty else { continue }
            let kcal = entries.reduce(0) { $0 + $1.calories }
            let p = entries.compactMap(\.protein).reduce(0, +)
            let c = entries.compactMap(\.carbs).reduce(0, +)
            let f = entries.compactMap(\.fat).reduce(0, +)

            var label = Fmt.dateLong.string(from: day)
            if cal.isDateInToday(day) {
                label += " (bugün)"
            } else if let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now)),
                      cal.isDate(day, inSameDayAs: yesterday) {
                label += " (dün)"
            }

            lines.append("- \(label): \(Fmt.int(kcal)) kcal · P \(Fmt.int(p))g · C \(Fmt.int(c))g · Y \(Fmt.int(f))g")
            for entry in entries {
                let gramStr = entry.grams.map { "\(Fmt.int($0))g " } ?? ""
                let time = Fmt.timeShort.string(from: entry.date)
                let pStr = entry.protein.map { " · P\(Fmt.int($0))" } ?? ""
                let cStr = entry.carbs.map { " · C\(Fmt.int($0))" } ?? ""
                let fStr = entry.fat.map { " · Y\(Fmt.int($0))" } ?? ""
                lines.append("  · \(time) — \(gramStr)\(entry.name) → \(Fmt.int(entry.calories)) kcal\(pStr)\(cStr)\(fStr)")
            }
        }

        return lines.count > 2 ? lines.joined(separator: "\n") : nil
    }

    private struct CaloriePeriodRequest {
        let label: String
        let range: DateInterval
        let includePaceEstimate: Bool
    }

    /// Sadece kullanıcının ima ettiği periyotları üretir. Böylece "bu ay" denmeden
    /// aylık veri prompt'a taşınmaz, ama açık aralık istekleri tam çalışır.
    private static func caloriePeriodsSection(ctx: ModelContext, query: String?) -> String? {
        let requests = caloriePeriodRequests(for: query)
        guard !requests.isEmpty else { return nil }

        let fetchStart = requests.map(\.range.start).min() ?? CalorieStats.last(days: 30).start
        let fetchEnd = requests.map(\.range.end).max() ?? CalorieStats.last(days: 30).end
        let foods = fetchFoods(ctx: ctx, start: fetchStart, endExclusive: fetchEnd)
        guard !foods.isEmpty else { return nil }
        guard let dailyResult = computeDailyResult(ctx: ctx) else { return nil }
        let target = dailyResult.goalCalories

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
            "- Hedef makrolar: P \(Fmt.int(dailyResult.protein.grams))g · K \(Fmt.int(dailyResult.carbs.grams))g · Y \(Fmt.int(dailyResult.fat.grams))g",
        ]

        for request in requests {
            let stats = CalorieStats.stats(for: request.range, foods: foods, dailyTarget: target)
            lines.append(line(request.label, stats))
            if request.includePaceEstimate, stats.loggedDays >= 7 {
                let dailyAvg = stats.averageDailyBalance
                let weekly = dailyAvg * 7
                let kgPerWeek = weekly / 7700.0  // ~7700 kcal = 1 kg yağ
                lines.append("- \(request.label) ortalama günlük net: \(Fmt.signed(dailyAvg, digits: 0)) kcal → tahmini \(Fmt.signed(kgPerWeek, digits: 2)) kg/hafta")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func caloriePeriodRequests(for query: String?) -> [CaloriePeriodRequest] {
        guard let query else {
            return [
                CaloriePeriodRequest(label: "Bu hafta", range: CalorieStats.thisWeek(), includePaceEstimate: false),
                CaloriePeriodRequest(label: "Bu ay", range: CalorieStats.thisMonth(), includePaceEstimate: false),
                CaloriePeriodRequest(label: "Son 30 gün", range: CalorieStats.last(days: 30), includePaceEstimate: true),
                CaloriePeriodRequest(label: "Son 90 gün", range: CalorieStats.last(days: 90), includePaceEstimate: false),
            ]
        }

        let lower = normalize(query).lowercased()
        if isAllDataRequest(lower) {
            return [
                CaloriePeriodRequest(label: "Bu hafta", range: CalorieStats.thisWeek(), includePaceEstimate: false),
                CaloriePeriodRequest(label: "Bu ay", range: CalorieStats.thisMonth(), includePaceEstimate: false),
                CaloriePeriodRequest(label: "Son 30 gün", range: CalorieStats.last(days: 30), includePaceEstimate: true),
                CaloriePeriodRequest(label: "Son 90 gün", range: CalorieStats.last(days: 90), includePaceEstimate: false),
            ]
        }

        var requests: [CaloriePeriodRequest] = []
        func append(_ request: CaloriePeriodRequest) {
            guard !requests.contains(where: { $0.label == request.label }) else { return }
            requests.append(request)
        }

        if containsAny(lower, ["bu hafta", "current week", "haftalik", "haftalık", "son 7", "7 gun", "7 gün"]) {
            append(CaloriePeriodRequest(label: "Bu hafta", range: CalorieStats.thisWeek(), includePaceEstimate: false))
        }
        if containsAny(lower, ["gecen hafta", "geçen hafta", "previous week"]) {
            if let previousWeek = previousWeekRange() {
                append(CaloriePeriodRequest(label: "Geçen hafta", range: previousWeek, includePaceEstimate: false))
            }
        }
        if containsAny(lower, ["bu ay", "current month"]) {
            append(CaloriePeriodRequest(label: "Bu ay", range: CalorieStats.thisMonth(), includePaceEstimate: false))
        }
        if containsAny(lower, ["gecen ay", "geçen ay", "previous month"]) {
            if let previousMonth = previousMonthRange() {
                append(CaloriePeriodRequest(label: "Geçen ay", range: previousMonth, includePaceEstimate: false))
            }
        }
        if containsAny(lower, ["son 90", "90 gun", "90 gün", "3 ay", "uc ay", "üç ay"]) {
            append(CaloriePeriodRequest(label: "Son 90 gün", range: CalorieStats.last(days: 90), includePaceEstimate: false))
        }
        if containsAny(lower, ["son 30", "30 gun", "30 gün", "son ay", "1 ay", "aylik", "aylık"]) {
            append(CaloriePeriodRequest(label: "Son 30 gün", range: CalorieStats.last(days: 30), includePaceEstimate: true))
        }
        if requests.isEmpty,
           let scope = FoodDiaryScope.parse(query: query),
           !scope.isExactDay,
           wantsCaloriePeriodSummary(lower, scope: scope) {
            append(CaloriePeriodRequest(
                label: scope.label.capitalized(with: Locale(identifier: "tr_TR")),
                range: DateInterval(start: scope.start, end: scope.endExclusive),
                includePaceEstimate: scope.dayCount >= 21
            ))
        }
        if requests.isEmpty, wantsCaloriePeriodSummary(lower, scope: nil) {
            append(CaloriePeriodRequest(label: "Bu hafta", range: CalorieStats.thisWeek(), includePaceEstimate: false))
            append(CaloriePeriodRequest(label: "Son 30 gün", range: CalorieStats.last(days: 30), includePaceEstimate: true))
        }
        return requests
    }

    private static func previousWeekRange(cal: Calendar = .current) -> DateInterval? {
        var weekCal = cal
        weekCal.firstWeekday = 2
        guard let thisWeek = weekCal.dateInterval(of: .weekOfYear, for: .now),
              let previousStart = weekCal.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start)
        else { return nil }
        return weekCal.dateInterval(of: .weekOfYear, for: previousStart)
    }

    private static func previousMonthRange(cal: Calendar = .current) -> DateInterval? {
        guard let thisMonth = cal.dateInterval(of: .month, for: .now),
              let previousStart = cal.date(byAdding: .month, value: -1, to: thisMonth.start)
        else { return nil }
        return cal.dateInterval(of: .month, for: previousStart)
    }

    /// Profil + son ölçümden günlük hedefi türet — CalorieCalculator ile.
    private static func computeDailyTarget(ctx: ModelContext) -> Double? {
        computeDailyResult(ctx: ctx)?.goalCalories
    }

    private static func computeDailyResult(ctx: ModelContext) -> CalorieResult? {
        guard let profile = fetchProfile(ctx: ctx) else { return nil }
        let measurements = fetchMeasurements(ctx: ctx, limit: 1)
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
            manualOffset: profile.manualCalorieOffset,
            manualOffsetMacro: profile.manualCalorieOffsetMacro,
            manualProteinGrams: profile.manualProteinGrams,
            manualCarbsGrams: profile.manualCarbsGrams,
            manualFatGrams: profile.manualFatGrams
        )
        return result
    }

    private static func goalsSection(ctx: ModelContext, latestWeight: Double?) -> String? {
        var goalsDescriptor = FetchDescriptor<MonthlyGoal>(sortBy: [SortDescriptor(\.anchorDate, order: .reverse)])
        goalsDescriptor.fetchLimit = 36   // son ~3 yıl; bağlam için fazlası gereksiz
        let goals = ((try? ctx.fetch(goalsDescriptor)) ?? []).sorted { $0.anchorDate < $1.anchorDate }
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
        var overridesDescriptor = FetchDescriptor<WorkoutPlanOverride>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        overridesDescriptor.fetchLimit = 50
        let overrides = ((try? ctx.fetch(overridesDescriptor)) ?? []).sorted { $0.createdAt < $1.createdAt }
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
        func short(_ i: Int) -> String { weekdayShort.indices.contains(i) ? weekdayShort[i] : "?" }
        var weekParts: [String] = []
        var totalKcal: Double = 0
        for wd in orderedWeekdays {
            if let w = workouts.first(where: { $0.weekday == wd }) {
                let exCount = w.templateExercises.count
                let detail = exCount > 0 ? " · \(exCount) hareket" : ""
                weekParts.append("\(short(wd))=\(w.name)\(detail)")
                totalKcal += w.estimatedCalories
            } else {
                weekParts.append("\(short(wd))=—")
            }
        }
        lines.append("- Tüm hafta: " + weekParts.joined(separator: " · "))
        let trainingDays = workouts.count
        lines.append("- \(trainingDays) gün/hafta · toplam ~\(Fmt.int(totalKcal)) kcal/hafta")
        lines.append("- ÖNEMLİ: Kullanıcı bu programı DÜZENLİ uyguluyor ama seansları tek tek loglamıyor. Antrenman logu yokluğu 'spor yapmıyor' demek DEĞİLDİR — değerlendirmeyi bu programa göre yap; gerçek ilerlemeyi kilo/ölçüm trendinden oku.")
        if !overrides.isEmpty {
            let overrideParts = overrides.map { item in
                "\(short(item.weekday)) + \(item.exerciseName) (\(item.prescriptionText))"
            }
            lines.append("- AI/user plan eklemeleri: " + overrideParts.joined(separator: " · "))
        }
        let detailedDays = workouts
            .sorted { $0.weekday < $1.weekday }
            .filter { !$0.templateExercises.isEmpty || ($0.focus?.isEmpty == false) || ($0.progression?.isEmpty == false) }
        if !detailedDays.isEmpty {
            lines.append("- Aktif program detayları:")
            for day in detailedDays {
                let exercises = day.sortedTemplateExercises.map {
                    var item = "\($0.name) [\($0.prescriptionText)]"
                    if let sourceURL = $0.sourceURL, !sourceURL.isEmpty {
                        item += " kaynak: \(sourceURL)"
                    }
                    return item
                }.joined(separator: "; ")
                var dayLine = "  - \(short(day.weekday)) \(day.name)"
                if let focus = day.focus, !focus.isEmpty { dayLine += " — amaç: \(focus)" }
                if !exercises.isEmpty { dayLine += " — hareketler: \(exercises)" }
                if let progression = day.progression, !progression.isEmpty { dayLine += " — progression: \(progression)" }
                if let notes = day.notes, !notes.isEmpty { dayLine += " — not: \(notes)" }
                lines.append(dayLine)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Antrenman logları — gerçek seanslar (haftalık template'ten farklı).
    private static func workoutLogsSection(ctx: ModelContext, query: String?, scope: FoodDiaryScope? = nil) -> String? {
        let lower = query.map { normalize($0).lowercased() } ?? ""
        let wantsAllTime = isAllDataRequest(lower) || containsAny(lower, ["tum zaman", "tüm zaman", "all time"])
        let cal = Calendar.current
        let now = Date()

        // Kullanıcı bir tarih aralığı söylediyse pencere O — sabit 30 gün değil.
        let start: Date?
        if wantsAllTime { start = nil }
        else if let scope { start = scope.start }
        else { start = cal.date(byAdding: .day, value: -30, to: now) }

        let fetched = fetchWorkoutLogs(ctx: ctx, start: start)
        let logs = scope.map { s in fetched.filter { s.contains($0.date) } } ?? fetched
        guard !logs.isEmpty else {
            return scope.map { "[ANTRENMAN LOGLARI — \($0.label)]\n- Bu aralıkta antrenman kaydı yok." }
        }

        var weekCal = cal
        weekCal.firstWeekday = 2
        let weekRange = weekCal.dateInterval(of: .weekOfYear, for: now)
        let thirtyAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now

        let weekLogs  = logs.filter { weekRange?.contains($0.date) ?? false }
        let last30    = logs.filter { $0.date >= thirtyAgo }

        var lines: [String] = [scope.map { "[ANTRENMAN LOGLARI — \($0.label)]" } ?? "[ANTRENMAN LOGLARI]"]
        if let scope {
            let minutes = logs.map(\.durationMinutes).reduce(0, +)
            let kcal = logs.map(\.estimatedCalories).reduce(0, +)
            lines.append("- \(scope.label): \(logs.count) seans · \(minutes) dk · \(Fmt.int(kcal)) kcal")
        } else {
            lines.append("- Bu hafta: \(weekLogs.count) seans · \(weekLogs.map(\.durationMinutes).reduce(0, +)) dk · \(Fmt.int(weekLogs.map(\.estimatedCalories).reduce(0, +))) kcal")
            let freqPerWeek = Double(last30.count) / (30.0 / 7.0)
            lines.append("- Son 30 gün: \(last30.count) seans · ort. \(String(format: "%.1f", freqPerWeek)) seans/hafta")
        }
        if wantsAllTime {
            lines.append("- Toplam (tüm zamanlar): \(logs.count) seans · \(logs.map(\.durationMinutes).reduce(0, +) / 60) saat")
        }

        // Aralık sorulduysa o aralıktaki seansların tamamı, yoksa son 5.
        lines.append(scope == nil ? "- Son seanslar:" : "- Seanslar:")
        for log in logs.prefix(scope == nil ? 5 : 25) {
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

    /// Adım: bugün + pencere ortalaması/aralığı + gün gün kayıtlar.
    /// Eskiden YALNIZCA bugünü veriyordu; "günde kaç adım atıyorum", "yürüyüşüm
    /// yeterli mi" gibi sorularda AI tek güne bakıp genelleme yapmak zorundaydı.
    private static func stepsSection(ctx: ModelContext, weight: Double?, scope: FoodDiaryScope?) -> String? {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let end = scope?.endExclusive ?? (cal.date(byAdding: .day, value: 1, to: todayStart) ?? now)
        let start = scope?.start ?? (cal.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart)

        let descriptor = FetchDescriptor<StepEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let entries = StepEntry.preferredEntries(from: (try? ctx.fetch(descriptor)) ?? [], calendar: cal)
        guard !entries.isEmpty else {
            return scope.map { "[ADIM — \($0.label)]\n- Bu aralıkta adım kaydı yok." }
        }

        var lines: [String] = [scope.map { "[ADIM — \($0.label)]" } ?? "[ADIM — son 30 gün]"]

        if let today = entries.first(where: { cal.isDate($0.date, inSameDayAs: now) }) {
            var l = "- Bugün: \(Fmt.int(Double(today.steps))) adım"
            if let w = weight {
                l += " · ~\(Fmt.int(StepEntry.calorieBurn(steps: today.steps, weightKg: w))) kcal"
            }
            lines.append(l)
        } else if scope == nil {
            lines.append("- Bugün: henüz kayıt yok")
        }

        let avg = Double(entries.reduce(0) { $0 + $1.steps }) / Double(entries.count)
        lines.append("- Ortalama: \(Fmt.int(avg)) adım/gün (\(entries.count) kayıtlı gün)")
        if let w = weight {
            let avgKcal = StepEntry.calorieBurn(steps: Int(avg.rounded()), weightKg: w)
            lines.append("- Adımdan günlük ortalama yakım: ~\(Fmt.int(avgKcal)) kcal")
        }
        if scope == nil,
           let sevenAgo = cal.date(byAdding: .day, value: -6, to: todayStart) {
            let last7 = entries.filter { $0.date >= sevenAgo }
            if !last7.isEmpty {
                let a7 = Double(last7.reduce(0) { $0 + $1.steps }) / Double(last7.count)
                lines.append("- Son 7 gün ortalaması: \(Fmt.int(a7)) adım/gün")
            }
        }
        if let mn = entries.map(\.steps).min(), let mx = entries.map(\.steps).max(), mn != mx {
            lines.append("- Aralık: \(Fmt.int(Double(mn)))–\(Fmt.int(Double(mx))) adım")
        }

        lines.append("- Gün gün:")
        for e in entries.prefix(30) {
            lines.append("  · \(Fmt.dateLong.string(from: e.date)): \(Fmt.int(Double(e.steps))) adım")
        }
        return lines.joined(separator: "\n")
    }

    /// Kayıtlı tarifler — başlık + kısa içerik + kategori. Çok uzarsa kategori
    /// bazlı sayım ve son 10 başlık.
    /// Tahlil sorusunu yakalayan sinyaller (aksansız/normalize edilmiş metinde aranır).
    private static let labSignals = [
        "tahlil", "kan degeri", "kan degerleri", "hemogram", "lab sonuc", "kan sayimi",
        "vitamin d", "d vitamini", "b12", "ferritin", "testosteron", "tsh", "tiroit", "tiroid",
        "kolesterol", "ldl", "hdl", "trigliserid", "hba1c", "insulin direnci", "homa",
        "kreatinin", "karaciger enzim", "demir eksikligi", "folat"
    ]

    /// Kan tahlili paneli — bayraklar, hesaplanan göstergeler ve tüm değerler.
    private static func labsSection(ctx: ModelContext) -> String? {
        var descriptor = FetchDescriptor<LabPanel>(sortBy: [SortDescriptor(\LabPanel.date, order: .reverse)])
        descriptor.fetchLimit = 3
        guard let panels = try? ctx.fetch(descriptor), !panels.isEmpty else { return nil }
        return LabInsights.contextText(panels: panels)
    }

    private static func recipesSection(ctx: ModelContext) -> String? {
        let totalCount = (try? ctx.fetchCount(FetchDescriptor<Recipe>())) ?? 0
        guard totalCount > 0 else { return nil }
        var descriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 120   // bağlam için son 120 yeterli; send tap'inde tümünü çekme
        let recipes = (try? ctx.fetch(descriptor)) ?? []
        guard !recipes.isEmpty else { return nil }
        var lines: [String] = ["[KAYITLI TARİFLER (\(totalCount))]"]
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
        if totalCount > 12 {
            lines.append("  · (... ve \(totalCount - 12) tarif daha)")
        }
        return lines.joined(separator: "\n")
    }



    // MARK: - Fetch helpers

    private static func fetchProfile(ctx: ModelContext) -> UserProfile? {
        (try? ctx.fetch(FetchDescriptor<UserProfile>()))?.first
    }

    private static func fetchMeasurements(ctx: ModelContext, limit: Int? = nil) -> [Measurement] {
        var descriptor = FetchDescriptor<Measurement>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let limit {
            descriptor.fetchLimit = limit
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    private static func fetchFoods(
        ctx: ModelContext,
        start: Date? = nil,
        endExclusive: Date? = nil,
        limit: Int? = nil
    ) -> [FoodEntry] {
        var descriptor: FetchDescriptor<FoodEntry>
        if let start, let endExclusive {
            descriptor = FetchDescriptor<FoodEntry>(
                predicate: #Predicate { $0.date >= start && $0.date < endExclusive },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else if let start {
            descriptor = FetchDescriptor<FoodEntry>(
                predicate: #Predicate { $0.date >= start },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else if let endExclusive {
            descriptor = FetchDescriptor<FoodEntry>(
                predicate: #Predicate { $0.date < endExclusive },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        }

        if let limit {
            descriptor.fetchLimit = limit
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    private static func fetchWorkoutLogs(ctx: ModelContext, start: Date? = nil, limit: Int? = nil) -> [WorkoutLog] {
        var descriptor: FetchDescriptor<WorkoutLog>
        if let start {
            descriptor = FetchDescriptor<WorkoutLog>(
                predicate: #Predicate { $0.date >= start },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        }
        if let limit {
            descriptor.fetchLimit = limit
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }
}
