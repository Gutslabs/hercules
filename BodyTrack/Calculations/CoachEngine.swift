import Foundation
import SwiftData

/// Günlük AI koç raporunu üretir ve günden güne takip eder.
///
/// Chat ile **birebir aynı bağlamı** toplar (coachContext + AgentDataSnapshot +
/// AgentRouter skill'leri → CoachIntelligence analizi dahil), dünden açık takip
/// maddelerini ekler, modele gönderir; çıkan uzun analiz + makine-okunur takip
/// bloğunu (```coach_items```) parse edip `CoachReport` ve `CoachFocusItem`
/// olarak saklar.
@MainActor
enum CoachEngine {

    // MARK: - Hata

    enum CoachError: LocalizedError {
        case alreadyRunning
        case emptyResponse
        var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "Zaten bir analiz çalışıyor."
            case .emptyResponse:  return "AI boş yanıt döndürdü. AI sağlayıcının (Codex/OpenRouter) bağlı mı?"
            }
        }
    }

    private(set) static var isRunning = false
    private static var lastReportAttempt: Date?
    private static var lastRecipeAttempt: Date?

    // MARK: - Sorgular

    static func startOfDay(_ date: Date = .now) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Belirli günün raporu (varsa).
    static func existingReport(for day: Date, ctx: ModelContext) -> CoachReport? {
        let target = Calendar.current.startOfDay(for: day)
        let all = (try? ctx.fetch(FetchDescriptor<CoachReport>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []
        return all.first { Calendar.current.isDate($0.day, inSameDayAs: target) }
    }

    /// Verilen günden ÖNCEKİ en yeni rapor — "önceki raporun" sürekliliği için.
    static func latestReport(beforeDay day: Date, ctx: ModelContext) -> CoachReport? {
        let target = Calendar.current.startOfDay(for: day)
        let all = (try? ctx.fetch(FetchDescriptor<CoachReport>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []
        return all.first { $0.day < target }
    }

    /// Belirli günün tarifi (varsa).
    static func existingRecipe(for day: Date, ctx: ModelContext) -> CoachRecipe? {
        let target = Calendar.current.startOfDay(for: day)
        let all = (try? ctx.fetch(FetchDescriptor<CoachRecipe>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []
        return all.first { Calendar.current.isDate($0.day, inSameDayAs: target) }
    }

    /// Hâlâ açık (Açık/Gelişiyor) takip maddeleri.
    static func openItems(ctx: ModelContext) -> [CoachFocusItem] {
        let all = (try? ctx.fetch(FetchDescriptor<CoachFocusItem>(sortBy: [SortDescriptor(\.firstAdvisedAt)]))) ?? []
        return all.filter { $0.status.isOpen }
    }

    // MARK: - Zamanlayıcı (foreground tetik)

    /// Sabah 08:00'den sonra ve bugünün raporu yoksa otomatik üret.
    /// App açılışında + öne gelince + periyodik çağrılır (gerçek background
    /// garanti edilemez; bu yüzden foreground-check). Saatte en fazla 1 deneme.
    /// Açılışta / öne gelince / 30 dk timer'da çağrılır — hem 08:00 analizini hem
    /// 10:00 tarifini gerektiğinde üretir.
    static func maybeRunDaily(ctx: ModelContext) {
        maybeRunDailyReport(ctx: ctx)
        maybeRunDailyRecipe(ctx: ctx)
    }

    /// 08:00 sonrası, bugünün ANALİZİ yoksa üret (saatte 1 deneme).
    static func maybeRunDailyReport(ctx: ModelContext) {
        guard !isRunning else { return }
        let now = Date()
        guard Calendar.current.component(.hour, from: now) >= 8 else { return }
        guard existingReport(for: startOfDay(now), ctx: ctx) == nil else { return }
        if let last = lastReportAttempt, now.timeIntervalSince(last) < 3600 { return }
        lastReportAttempt = now
        Task { @MainActor in
            do { _ = try await generateDailyReport(ctx: ctx) } catch { }
        }
    }

    /// 10:00 sonrası, bugünün TARİFİ yoksa üret (saatte 1 deneme).
    static func maybeRunDailyRecipe(ctx: ModelContext) {
        guard !isRunning else { return }
        let now = Date()
        guard Calendar.current.component(.hour, from: now) >= 10 else { return }
        guard existingRecipe(for: startOfDay(now), ctx: ctx) == nil else { return }
        if let last = lastRecipeAttempt, now.timeIntervalSince(last) < 3600 { return }
        lastRecipeAttempt = now
        Task { @MainActor in
            do { _ = try await generateDailyRecipe(ctx: ctx) } catch { }
        }
    }

    // MARK: - Üretim

    /// Bugünün raporunu üret (var olanı günceller). UI "Şimdi analiz et" + zamanlayıcı buraya gelir.
    @discardableResult
    static func generateDailyReport(ctx: ModelContext) async throws -> CoachReport {
        guard !isRunning else { throw CoachError.alreadyRunning }
        isRunning = true
        defer { isRunning = false }

        let today = startOfDay()
        let open = openItems(ctx: ctx)
        let previous = latestReport(beforeDay: today, ctx: ctx)
        let prompt = buildPrompt(openItems: open, previousReport: previous, today: today)

        // Chat ile aynı bağlam: tüm mention bölümleri + full data snapshot + skill (CoachIntelligence).
        let allTags = Set(MentionTag.allCases)
        let appContext = UserContextSnapshot.coachContext(for: prompt, explicitTags: allTags, ctx: ctx)
        let data = AgentDataSnapshot.make(ctx: ctx, scope: .full())
        let skill = await AgentRouter.shared.buildSkillContext(query: prompt, appContext: appContext, history: [], dataSnapshot: data)
        // Deterministik bilim verisi (adaptif TDEE + hacim) — AI uydurmasın, hesaplanmışı kullansın.
        let science = scienceContext(ctx: ctx)
        let fullContext = [appContext, skill, science].compactMap { $0 }.joined(separator: "\n\n")

        let (result, _) = try await AIKeyStore.shared.makeClient().send(
            history: [],
            newUserText: prompt,
            userContext: fullContext,
            onSearchStart: { _ in },
            onMessageUpdate: { _ in }
        )

        let rawText = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { throw CoachError.emptyResponse }

        let (narrative, items) = splitItems(from: rawText)
        let snap = metricSnapshot(ctx: ctx)

        let report: CoachReport
        if let existing = existingReport(for: today, ctx: ctx) {
            existing.narrative = narrative
            existing.createdAt = .now
            existing.weight = snap.weight
            existing.weeklyDelta = snap.weeklyDelta
            existing.avgCalories = snap.avgCalories
            existing.avgProtein = snap.avgProtein
            existing.sessionsLast30 = snap.sessions
            existing.generatedBy = AIKeyStore.shared.provider.label
            existing.updatedAt = .now
            report = existing
        } else {
            let r = CoachReport(
                day: today,
                narrative: narrative,
                weight: snap.weight,
                weeklyDelta: snap.weeklyDelta,
                avgCalories: snap.avgCalories,
                avgProtein: snap.avgProtein,
                sessionsLast30: snap.sessions,
                generatedBy: AIKeyStore.shared.provider.label
            )
            ctx.insert(r)
            report = r
        }

        applyItems(items, today: today, ctx: ctx)

        ctx.saveOrReport()
        BackupService.shared.exportAsync(from: ctx)
        return report
    }

    /// ScienceEngine'den hesaplanan gerçek metabolizma + hacim özetini koç bağlamına ekler.
    /// AI bunları UYDURMAZ; doğrudan kullanır (adaptif TDEE, trend kilo, hız, hacim açıkları).
    private static func scienceContext(ctx: ModelContext) -> String? {
        let measurements = (try? ctx.fetch(FetchDescriptor<Measurement>())) ?? []
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let workouts = (try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? []

        guard let e = ScienceEngine.bestAdaptiveEnergy(measurements: measurements, foods: foods) else {
            return nil
        }

        var lines: [String] = ["[HESAPLANMIŞ BİLİM VERİSİ — bu sayıları uydurma, doğrudan kullan]"]
        lines.append("Adaptif TDEE (enerji dengesinden çözülmüş gerçek bakım): \(Int(e.adaptiveTDEE.rounded())) kcal/gün — güven: \(e.confidence.label).")
        lines.append(String(
            format: "Trend kilo %.1f kg; haftalık değişim %+.2f kg (%+.2f%%/hafta); ort. alım %d kcal/gün (%d kayıtlı gün).",
            e.trendWeightNow, e.slopeKgPerWeek, e.ratePercentPerWeek, Int(e.avgIntake.rounded()), e.loggedDays
        ))

        let vols = ScienceEngine.weeklyVolume(workouts: workouts)
        let under = vols.filter { $0.sets > 0 && $0.status == .under }.map(\.muscle.label)
        let over = vols.filter { $0.status == .over }.map(\.muscle.label)
        let untrained = vols.filter { $0.sets == 0 }.map(\.muscle.label)
        if !under.isEmpty { lines.append("Haftalık hacmi MEV altında (az çalışılan) kaslar: \(under.joined(separator: ", ")).") }
        if !over.isEmpty { lines.append("MRV üstü (fazla, toparlanma riski) kaslar: \(over.joined(separator: ", ")).") }
        if !untrained.isEmpty { lines.append("Son 7 günde hiç çalışılmamış kaslar: \(untrained.joined(separator: ", ")).") }

        return lines.joined(separator: "\n")
    }

    // MARK: - Günlük tarif (internetten araştırılmış, kaynaklı)

    /// Kullanıcının yediklerine + tariflerine bakıp internetten ARAŞTIRILMIŞ
    /// (kaynak URL'li) yüksek proteinli bowl tarifi üretir. Sistem prompt'u tarif
    /// isteğinde web_search'ü ZORUNLU kılar; uydurma tarif engellenir.
    @discardableResult
    static func generateDailyRecipe(ctx: ModelContext) async throws -> CoachRecipe {
        guard !isRunning else { throw CoachError.alreadyRunning }
        isRunning = true
        defer { isRunning = false }

        let today = startOfDay()
        let prompt = buildRecipePrompt(today: today)

        let allTags = Set(MentionTag.allCases)
        let appContext = UserContextSnapshot.coachContext(for: prompt, explicitTags: allTags, ctx: ctx)
        let data = AgentDataSnapshot.make(ctx: ctx, scope: .full())
        let skill = await AgentRouter.shared.buildSkillContext(query: prompt, appContext: appContext, history: [], dataSnapshot: data)
        let fullContext = [appContext, skill].compactMap { $0 }.joined(separator: "\n\n")

        let (result, _) = try await AIKeyStore.shared.makeClient().send(
            history: [], newUserText: prompt, userContext: fullContext,
            onSearchStart: { _ in }, onMessageUpdate: { _ in }
        )

        let action = result.actionList.first(where: { $0.tool == .addRecipe })
        let message = result.message.trimmingCharacters(in: .whitespacesAndNewlines)

        let rawTitle = (action?.title ?? action?.name)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? "Günün yüksek proteinli bowl'u" : rawTitle
        let sourceURL = (action?.sourceURL ?? action?.url)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryText = action?.recipeSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredients = action?.ingredients?.trimmingCharacters(in: .whitespacesAndNewlines)
        // add_recipe yoksa (nadiren) modelin düz metnini yapılış olarak sakla.
        let instructions = action?.instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? (action == nil && !message.isEmpty ? message : nil)
        let note = (summaryText?.isEmpty == false ? summaryText : (message.isEmpty ? nil : message))
        let host = sourceURL.flatMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") }

        let recipe: CoachRecipe
        if let existing = existingRecipe(for: today, ctx: ctx) {
            existing.createdAt = .now
            existing.title = title
            existing.summary = note
            existing.ingredientsText = ingredients
            existing.instructionsText = instructions
            existing.sourceURL = sourceURL
            existing.sourceName = host
            existing.calories = action?.calories
            existing.protein = action?.proteinG
            existing.carbs = action?.carbsG
            existing.fat = action?.fatG
            existing.servings = action?.servings
            existing.prepMinutes = action?.prepMinutes
            existing.category = action?.category
            existing.generatedBy = AIKeyStore.shared.provider.label
            existing.updatedAt = .now
            recipe = existing
        } else {
            let r = CoachRecipe(
                day: today,
                title: title,
                summary: note,
                ingredientsText: ingredients,
                instructionsText: instructions,
                sourceURL: sourceURL,
                sourceName: host,
                calories: action?.calories,
                protein: action?.proteinG,
                carbs: action?.carbsG,
                fat: action?.fatG,
                servings: action?.servings,
                prepMinutes: action?.prepMinutes,
                category: action?.category,
                generatedBy: AIKeyStore.shared.provider.label
            )
            ctx.insert(r)
            recipe = r
        }

        ctx.saveOrReport()
        BackupService.shared.exportAsync(from: ctx)
        return recipe
    }

    /// `.coachRecipe` varsayılanı — "Bugün <tarih>. " öneki koddan eklenir; yemek günlüğü +
    /// kayıtlı tarifler bağlam olarak gelir. Admin ▸ System'den düzenlenebilir.
    static let recipeInstructionsDefault = """
    Bana BUGÜN için YÜKSEK PROTEİNLİ bir BOWL tarifi öner.

    ÇOK ÖNEMLİ KURALLAR:
    - Tarifi internette ARAŞTIR (web_search ZORUNLU). KAFANA GÖRE TARİF UYDURMA. Gerçek, denenmiş/yorumlu bir kaynaktan al.
    - add_recipe action'ı ile dön ve GERÇEK KAYNAK URL'sini (gerçek tarif sayfası) ZORUNLU ver. Kaynaksız tarif verme.
    - Benim son yediğim yemeklere ve KAYITLI TARİFLERİME bak (bağlamda: yemek günlüğü + tarifler). Damak zevkime ve sık kullandığım malzemelere (whey/protein tozu, süzme yoğurt, yulaf, muz, yumurta vb.) uygun olsun; her gün aynı şeyi önerme, çeşitlilik kat.
    - Cut dönemindeyim; protein hedefim yüksek (bağlamdaki makro hedefime göre). Bowl yüksek proteinli ama makul kalorili olsun.
    - add_recipe içinde mutlaka: title, ingredients (madde madde), instructions (adım adım), calories, protein_g, carbs_g, fat_g, servings, prep_minutes, category (breakfast/dinner/dessert), url (kaynak).
    - recipe_summary'de "neden bugün bana uygun" kısa notunu yaz (bugünkü makro boşluğuma/yediklerime göre).
    - message kısmında 1-2 cümle samimi koç notu yaz.
    """

    /// `.coachReport` varsayılanı (ana analiz direktifi). "Bugün <tarih>. " öneki + sonuna
    /// bilimsel-dayanak direktifi, açık takip maddeleri, önceki rapor ve makine-okunur takip
    /// formatı koddan otomatik eklenir. Admin ▸ System'den düzenlenebilir.
    static let reportInstructionsDefault = """
    Sen benim kişisel fitness/beslenme koçumsun ve her sabah bana o günkü durumu DETAYLI bir koç analizi olarak veriyorsun. @Ölçümler @Antrenman @Beslenme verilerimin HEPSİNE bak.

    Bana UZUN, somut ve samimi-ama-net bir analiz yaz (gerçek sayılarla):
    - Kilo trendi: 7 / 14 / 30 günlük değişim ve haftalık hız; bu hız benim için sağlıklı mı.
    - Beslenme: son dönem ortalama kalori ve protein, app hedefime göre durum; yağ ve karbonhidrat dağılımı.
    - Besin kalitesi: sebze/lif, mikrobesin çeşitliliği, aşırı yağlı/işlenmiş günler — somut örnek ver.
    - Antrenman: frekans (hedef vs gerçek), performans sinyalleri, kas koruma için öneriler.
    - Kilo hedeflerime göre neredeyim, gerçekçi mi.
    - En büyük riskler (madde madde).
    - Önümüzdeki ~14 gün için net strateji (madde madde).
    - Sonda kısa koç yorumu + net karar.
    """

    private static func buildRecipePrompt(today: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "tr_TR")
        df.dateFormat = "d MMMM yyyy EEEE"
        return "Bugün \(df.string(from: today)). " + PromptStore.shared.text(.coachRecipe)
    }

    // MARK: - Prompt

    private static func buildPrompt(openItems: [CoachFocusItem], previousReport: CoachReport?, today: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "tr_TR")
        df.dateFormat = "d MMMM yyyy EEEE"
        let dateStr = df.string(from: today)

        var p = "Bugün \(dateStr). " + PromptStore.shared.text(.coachReport)

        p += """


        BİLİMSEL DAYANAK (ÇOK ÖNEMLİ — her şeyi olabildiğince science-based yap): Sayısal ya da fizyolojik bir öneride bulunurken (ör. günde X g lif, Y g/kg protein, haftalık Z set, su, adım) DAYANDIĞIN kaynağı kısaca belirt — tanınmış kılavuz/kuruluş (WHO, EFSA, ABD DGA, AHA, ACSM, ISSN, Academy of Nutrition) ya da meta-analiz/RCT düzeyi. Bağlamdaki [EVIDENCE] bloğunu kullan ve kaynağını an. ASLA uydurma DOI / çalışma adı / sahte sayı verme; emin değilsen kaynağı kuruluş/kılavuz düzeyinde tut ("genel kabul gören kılavuzlara göre, ör. EFSA"). Doğru kullanım örneği: "Lif için EFSA yetişkinlerde ~25 g/gün önerir (AHA ~25-30 g); tokluk ve bağırsak sağlığı için faydalı." Kısacası her sayısal öneriyi mümkünse bir dayanağa bağla.
        """

        if !openItems.isEmpty {
            let lines = openItems.map { "- [\($0.area)] \($0.title) — \($0.daysOpen) gündür açık (şu anki durum: \($0.status.label))" }
                .joined(separator: "\n")
            p += """


            DÜNDEN AÇIK TAKİP MADDELERİM — bugünkü GERÇEK veriye göre HER BİRİNİ tek tek değerlendir. Düzelmişse "halledildi" de ve NEDEN öyle düşündüğünü (hangi veriye dayanarak) söyle; kısmi ilerleme varsa "gelişiyor"; hâlâ sorunsa "açık" bırak:
            \(lines)
            """
        }

        if let previousReport {
            let cap = 3000
            let body = previousReport.narrative.count > cap
                ? String(previousReport.narrative.prefix(cap)) + "…"
                : previousReport.narrative
            let pdf = DateFormatter()
            pdf.locale = Locale(identifier: "tr_TR")
            pdf.dateFormat = "d MMMM EEEE"
            p += """


            ÖNCEKİ RAPORUN — \(pdf.string(from: previousReport.day)) günü bu raporu SEN yazmıştın. Sürekliliği koru: gerektiğinde buna atıfta bulun ("geçen sefer şunu demiştim, bugün ..."), aynı cümleleri birebir tekrarlama, değişen / ilerleyen / kötüleşen şeyleri bununla kıyasla:
            \"\"\"
            \(body)
            \"\"\"
            """
        }

        p += """


        ÇOK ÖNEMLİ — analizini bitirdikten sonra, en alta, ayrı bir blok olarak AYNEN şu formatta makine-okunur JSON ekle (bu bloğu kullanıcıya göstermeyeceğim, sadece günden güne takip için kullanacağım):
        ```coach_items
        [
          {"area":"sebze-lif","title":"Sebze/lif alımı","status":"improving","note":"son 2 gün sebze eklenmiş, devam etmeli"}
        ]
        ```
        Kurallar:
        - status SADECE: advised | improving | resolved
        - Yukarıdaki açık maddeleri AYNI "area" anahtarıyla geri ver (durumlarını bugüne göre güncelle).
        - Yeni tespit ettiğin geliştirilecek alanları yeni "area" olarak ekle. area kısa, tireli, küçük harf (ör: yag-kontrolu, antrenman-frekansi, protein, su, adim).
        - En fazla 6 madde. Gerçekten halledilenleri "resolved" yap. Blok geçerli JSON dizisi olmalı.
        """
        return p
    }

    // MARK: - Parsing

    private struct ParsedItem: Decodable {
        let area: String
        let title: String?
        let status: String?
        let note: String?
    }

    /// `rawText` içinden ```coach_items ... ``` bloğunu ayırır; narrative'den temizler.
    private static func splitItems(from rawText: String) -> (narrative: String, items: [ParsedItem]) {
        guard let range = fencedRange(in: rawText) else { return (rawText, []) }
        let items = decodeItems(String(rawText[range.json]))
        var narrative = rawText
        narrative.removeSubrange(range.full)
        narrative = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        return (narrative, items)
    }

    private static func fencedRange(in raw: String) -> (full: Range<String.Index>, json: Range<String.Index>)? {
        for marker in ["```coach_items", "```json", "```"] {
            guard let start = raw.range(of: marker) else { continue }
            let afterMarker = start.upperBound
            guard let close = raw.range(of: "```", range: afterMarker..<raw.endIndex) else { continue }
            let jsonRange = afterMarker..<close.lowerBound
            let body = raw[jsonRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasPrefix("[") {
                return (start.lowerBound..<close.upperBound, jsonRange)
            }
        }
        return nil
    }

    private static func decodeItems(_ jsonText: String) -> [ParsedItem] {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ParsedItem].self, from: data)) ?? []
    }

    // MARK: - Takip maddesi upsert

    private static func applyItems(_ items: [ParsedItem], today: Date, ctx: ModelContext) {
        guard !items.isEmpty else { return }
        let existing = (try? ctx.fetch(FetchDescriptor<CoachFocusItem>())) ?? []

        for parsed in items {
            let area = parsed.area.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !area.isEmpty else { continue }
            let status = CoachItemStatus(rawValue: (parsed.status ?? "advised").lowercased()) ?? .advised
            let trimmedTitle = (parsed.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle.isEmpty ? area : trimmedTitle
            let note = parsed.note?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let item = existing.first(where: { $0.area.lowercased() == area }) {
                item.status = status
                if let note, !note.isEmpty { item.detail = note }
                item.title = title
                item.lastCheckedAt = .now
                item.lastReportDay = today
                item.resolvedAt = (status == .resolved) ? (item.resolvedAt ?? .now) : nil
                item.updatedAt = .now
            } else {
                let item = CoachFocusItem(area: area, title: title, detail: note, status: status, firstAdvisedAt: today, lastReportDay: today)
                if status == .resolved { item.resolvedAt = .now }
                ctx.insert(item)
            }
        }
    }

    // MARK: - Metrik snapshot (kart gösterimi)

    private struct Snap {
        var weight: Double?
        var weeklyDelta: Double?
        var avgCalories: Double?
        var avgProtein: Double?
        var sessions: Int?
    }

    private static func metricSnapshot(ctx: ModelContext) -> Snap {
        let cal = Calendar.current
        let measurements = (try? ctx.fetch(FetchDescriptor<Measurement>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let weight = measurements.compactMap(\.weight).first
        let weekAgo = cal.date(byAdding: .day, value: -7, to: .now) ?? .now
        let pastWeight = measurements.first(where: { $0.date <= weekAgo })?.weight
        let weeklyDelta: Double? = (weight != nil && pastWeight != nil) ? (weight! - pastWeight!) : nil

        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let cutoff14 = cal.date(byAdding: .day, value: -14, to: .now) ?? .now
        let byDay = Dictionary(grouping: foods.filter { $0.date >= cutoff14 }) { cal.startOfDay(for: $0.date) }
        let dayCals = byDay.values.map { $0.reduce(0.0) { $0 + $1.calories } }
        let dayProts = byDay.values.map { $0.reduce(0.0) { $0 + ($1.protein ?? 0) } }
        let avgCalories = dayCals.isEmpty ? nil : dayCals.reduce(0, +) / Double(dayCals.count)
        let avgProtein = dayProts.isEmpty ? nil : dayProts.reduce(0, +) / Double(dayProts.count)

        let cutoff30 = cal.date(byAdding: .day, value: -30, to: .now) ?? .now
        let logs = (try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        let sessions = logs.filter { $0.date >= cutoff30 }.count

        return Snap(weight: weight, weeklyDelta: weeklyDelta, avgCalories: avgCalories, avgProtein: avgProtein, sessions: sessions)
    }
}

#if os(macOS)
/// Sabah 08:00'de uygulamayı arka planda (gizli) açan kullanıcı LaunchAgent'ı.
/// App kapalıysa launchd onu açar → açılışta o günün koç raporu üretilir; böylece
/// tetikleme app'in açık olmasına bağlı kalmaz. (App sandbox'lı değil; ~/Library/
/// LaunchAgents'a yazıp launchctl ile yükler. Mac kapalı/uykudaysa launchd kaçan
/// işi uyanışta çalıştırır.)
enum CoachLaunchAgent {
    static let label = "com.samorai.hercules.coach"
    static let reportHour = 8
    static let recipeHour = 10

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Kur (idempotent — içerik aynıysa hiç dokunmaz). Ana thread'i bloklamamak
    /// için arka planda çağır.
    static func installIfNeeded() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.samorai.hercules"
        let plist: [String: Any] = [
            "Label": label,
            // -g: ön plana getirme, -j: gizli başlat → kullanıcıyı rahatsız etmez.
            "ProgramArguments": ["/usr/bin/open", "-g", "-j", "-b", bundleID],
            "StartCalendarInterval": [
                ["Hour": reportHour, "Minute": 0],
                ["Hour": recipeHour, "Minute": 0]
            ],
            "RunAtLoad": false,
            "ProcessType": "Background"
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        let url = plistURL
        if let existing = try? Data(contentsOf: url), existing == data { return } // zaten güncel
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            reload(url: url)
        } catch {
            // sessiz geç — foreground check + 30 dk timer zaten yedek
        }
    }

    static func uninstall() {
        let uid = getuid()
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func reload(url: URL) {
        let uid = getuid()
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"]) // varsa kaldır (hata önemsiz)
        _ = run("/bin/launchctl", ["bootstrap", "gui/\(uid)", url.path])
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = nil
        proc.standardError = nil
        do { try proc.run(); proc.waitUntilExit(); return proc.terminationStatus }
        catch { return -1 }
    }
}
#endif
