import CryptoKit
import Foundation
import SwiftData

enum AppToolError: LocalizedError {
    case missing(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missing(let detail): return detail
        case .unsupported(let detail): return detail
        }
    }
}

struct ChatConversation: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var messages: [ChatTurn]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatTurn] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Uses the space allocated to chat, including when the window changes screens.
struct ChatPaneLayout {
    let availableWidth: Double
    let preferredThreadWidth: Double

    var isCompact: Bool { availableWidth < 860 }
    var maximumThreadWidth: Double { max(0, availableWidth - 301) }
    var threadWidth: Double {
        isCompact ? max(0, availableWidth)
            : min(max(preferredThreadWidth, 340), maximumThreadWidth)
    }
}

/// Günün thread'i: her takvim günü için koçun açtığı, tarih başlıklı konuşma.
/// Kullanıcı eskiden her sabah kanala "6 eylül" yazıp günün thread'ini elle
/// açıyordu; artık gece yarısından sonra (ya da o gün ilk açılışta) `ChatStore`
/// bunu kendisi yapar — bkz. `ChatStore.ensureDailyThread`.
///
/// Kimlik TAKVİM GÜNÜNDEN türetilir: aynı gün için nerede/ne zaman üretilirse
/// üretilsin aynı UUID çıkar. Böylece "bugünün thread'i var mı?" bir id
/// karşılaştırmasıdır ve Mac ile telefon aynası aynı konuşmayı ikilemez.
enum ChatDailyThread {
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Ad-tabanlı (v5 biçimli) UUID: SHA-256("hercules.chat.daily-thread:YYYY-MM-DD")
    /// özetinin ilk 16 baytı, sürüm ve varyant bitleri RFC 4122'ye göre işaretli.
    static func id(for date: Date, calendar: Calendar = .current) -> UUID {
        let name = "hercules.chat.daily-thread:" + dayKey(for: date, calendar: calendar)
        var bytes = Array(Array(SHA256.hash(data: Data(name.utf8)))[0..<16])
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func isDaily(_ conversation: ChatConversation, calendar: Calendar = .current) -> Bool {
        conversation.id == id(for: conversation.createdAt, calendar: calendar)
    }

    /// Thread başlığı — kullanıcının elle yazdığı "6 eylül" ile aynı biçim: "7 Eylül".
    static func title(for date: Date) -> String {
        Fmt.dayMonth.string(from: date)
    }

    /// Koçun kök mesajı: "7 Eylül Pazartesi". Kanalda gün başlığı gibi okunur;
    /// modele de o günün tarihini bağlamda verir.
    static func openerText(for date: Date) -> String {
        Fmt.dayMonthWeekday.string(from: date)
    }

    static func makeConversation(for date: Date) -> ChatConversation {
        ChatConversation(
            id: id(for: date),
            title: title(for: date),
            messages: [ChatTurn(role: .assistant, text: openerText(for: date), createdAt: date)],
            createdAt: date,
            updatedAt: date
        )
    }

    /// Yanıtsız günün thread'inin hapı: bugünse "Günün thread'i", gün geçtiyse "Yanıt yok".
    static func emptyReplyLabel(for conversation: ChatConversation, calendar: Calendar = .current) -> String {
        calendar.isDateInToday(conversation.createdAt) ? "Günün thread'i" : "Yanıt yok"
    }

    // MARK: Kayıt günü

    /// Thread'in günü bugüne göre kaç gün geride: 20 Eylül'ün thread'ine 22 Eylül'de
    /// yazılıyorsa -2. Bugünün thread'i ve serbest sohbetler 0 döner — onlar "şimdi"ye
    /// yazar. Gün `createdAt`'ten okunur (kök mesaj 7 günlük saklamayla silinebilir).
    static func logDayOffset(
        for conversation: ChatConversation?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard let conversation, isDaily(conversation, calendar: calendar) else { return 0 }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: conversation.createdAt)
        ).day ?? 0
        return min(0, days)
    }

    /// Bu thread'de kaydedilen öğünün yazılacağı an: thread'in günü + şimdiki saat.
    /// Saat korunur ki geçmiş güne yazılan öğün o günün akışında makul bir yerde dursun
    /// (öğün kartındaki gün seçiciyle aynı kural).
    static func logDate(
        for conversation: ChatConversation?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let offset = logDayOffset(for: conversation, now: now, calendar: calendar)
        guard offset != 0 else { return now }
        return calendar.date(byAdding: .day, value: offset, to: now) ?? now
    }

    /// Geçmiş bir günün thread'inde modele giden bağlam notu. Kayıt gününe model karar
    /// VERMEZ (host `logDate` ile belirler); not yalnız cevabın "bugüne ekledim" yerine
    /// doğru günü anmasını sağlar. Bugünün thread'i / serbest sohbet için nil.
    static func contextNote(
        for conversation: ChatConversation?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard let conversation,
              logDayOffset(for: conversation, now: now, calendar: calendar) < 0
        else { return nil }
        let day = Fmt.dayMonthWeekday.string(from: conversation.createdAt)
        return """
            [THREAD GÜNÜ]
            - Bu konuşma \(day) gününün thread'i; bugün değil, geçmiş bir gün.
            - Bu thread'de kaydedilen öğünler uygulama tarafından \(day) gününe yazılır. Kaydı "bugüne" diye değil bu günün tarihiyle an.
            - Snapshot'taki "bugün" toplamları bu thread'in gününe ait değildir; o gün için kalan kalori hesabını bugünün verisinden yapma.
            """
    }

    /// "… bugüne eklendi" / "… 20 Eylül gününe eklendi" — ek, ay adına göre ünlü uyumu
    /// gerektirmesin diye "gününe" kalıbı kullanılır. `sentenceStart`: cümle başında
    /// tek başına duracaksa ("Bugüne eklendi").
    static func loggedPhrase(
        on date: Date,
        sentenceStart: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        guard calendar.isDate(date, inSameDayAs: now) else {
            return "\(Fmt.dayMonth.string(from: date)) gününe eklendi"
        }
        return sentenceStart ? "Bugüne eklendi" : "bugüne eklendi"
    }
}

/// Coalesces cumulative provider updates between display ticks. A retry may
/// replace the entire answer, including with a longer text of a different prefix.
struct ChatStreamBuffer {
    private(set) var latestText = ""
    private(set) var visibleText = ""
    private var pendingText: String?
    private var characters: [Character] = []
    private var revealed = 0

    var isCaughtUp: Bool { pendingText == nil && revealed == characters.count }

    mutating func update(_ text: String) {
        latestText = text
        pendingText = text
    }

    /// Called at 30 Hz, regardless of how many network chunks arrived.
    @discardableResult
    mutating func advance(isComplete: Bool = false) -> String? {
        let previous = visibleText
        if let pendingText {
            let updated = Array(pendingText)
            if !updated.starts(with: characters.prefix(revealed)) {
                revealed = min(revealed, updated.count)
                visibleText = String(updated.prefix(revealed))
            }
            characters = updated
            self.pendingText = nil
        }
        let behind = characters.count - revealed
        if behind > 0 {
            let step: Int
            if behind > 600 { step = max(24, behind / 12) }
            else if behind > 200 { step = 12 }
            else if behind > 60 { step = 6 }
            else { step = isComplete ? 8 : 4 }
            let next = min(characters.count, revealed + step)
            visibleText.append(contentsOf: characters[revealed..<next])
            revealed = next
        }
        return visibleText == previous ? nil : visibleText
    }
}

#if os(macOS)
/// Model bir tool çağrısı ÜRETEBİLİR; bu ona yazma yetkisi vermez. Otomatik
/// mutasyon kararı yalnız kullanıcının güncel, ham mesajından host tarafında çıkar.
enum ChatActionAuthorization {
    static func allowsAutomatic(_ action: AIAppAction, currentUserText: String) -> Bool {
        switch action.tool {
        case .logFood:
            let name = (action.name ?? action.itemName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let values = [
                action.grams, action.amount, action.calories,
                action.proteinG, action.carbsG, action.fatG
            ].compactMap { $0 }
            return AgentQueryClassifier.isLikelyFoodLog(currentUserText)
                && !name.isEmpty
                && name.count <= 200
                && action.calories.map { $0.isFinite && (0...10_000).contains($0) } == true
                && (action.grams ?? action.amount).map { $0.isFinite && (0...10_000).contains($0) } != false
                && values.allSatisfy(\.isFinite)
                && [action.proteinG, action.carbsG, action.fatG]
                    .compactMap { $0 }
                    .allSatisfy { (0...2_000).contains($0) }
        case .addRecipe, .updateWorkoutPlan:
            return false
        }
    }

    static func idempotencyKey(for action: AIAppAction) -> String {
        switch action.tool {
        case .logFood:
            return [
                action.tool.rawValue,
                ChatActionExecutor.normalizedKey(action.name ?? action.itemName ?? ""),
                numberKey(action.grams ?? action.amount),
                numberKey(action.calories),
                numberKey(action.proteinG),
                numberKey(action.carbsG),
                numberKey(action.fatG)
            ].joined(separator: "|")
        case .addRecipe:
            return [
                action.tool.rawValue,
                ChatActionExecutor.normalizedKey(action.title ?? action.name ?? ""),
                (action.sourceURL ?? action.url ?? "").lowercased()
            ].joined(separator: "|")
        case .updateWorkoutPlan:
            return "\(action.tool.rawValue)|\(action.id.uuidString)"
        }
    }

    private static func numberKey(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.3f", value)
    }
}

/// Kısa inline onay/ret mesajlarını fail-closed sınıflandırır. Model çıktısı veya
/// eski konuşma bu kararı veremez; yalnız güncel ham kullanıcı mesajı değerlendirilir.
enum ChatInlineConfirmation {
    enum Decision: Equatable {
        case approve
        case reject
        case none
    }

    struct Pending {
        var turnID: UUID
        var actionID: UUID
        var action: AIAppAction
    }

    static func decision(for text: String) -> Decision {
        let normalized = ChatActionExecutor.normalizedKey(text)
            .lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: #"[^a-z0-9ğüşöçı ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 60 else { return .none }

        // Ret/negation her zaman önce gelir. “Onay vermiyorum” gibi bir cümle,
        // içinde "onay" geçtiği için asla olumluya düşmemeli.
        let rejectionMarkers = [
            "hayir", "istemiyorum", "onaylamiyorum", "onay vermiyorum",
            "vazgectim", "vazgec", "iptal", "yapma", "uygulama",
            "ekleme", "kaydetme", "bosver"
        ]
        if rejectionMarkers.contains(where: { marker in
            normalized == marker
                || normalized.hasPrefix(marker + " ")
                || normalized.hasSuffix(" " + marker)
                || normalized.contains(" " + marker + " ")
        }) {
            return .reject
        }

        // Yalnız dar, açık ifadeler. hasPrefix("onay")/contains(" onay") gibi
        // geniş eşleşmeler olumsuz veya alakasız cümleleri yanlış yetkilendirir.
        let approvals: Set<String> = [
            "evet", "tamam", "ok", "okay", "olur", "yap", "uygula", "ekle", "kaydet",
            "onayliyorum", "onay veriyorum", "onayladim", "aynen", "tamamdir",
            "evet onayliyorum", "tamam onayliyorum", "bunu onayliyorum",
            "evet yap", "tamam yap", "evet uygula", "tamam uygula"
        ]
        return approvals.contains(normalized) ? .approve : .none
    }

    /// Inline cevap yalnız hemen önceki assistant turundaki, yeni ve hâlâ pending
    /// action'a bağlanabilir. Konuşmanın derininden eski bir action diriltilmez.
    static func adjacentPending(
        in messages: [ChatTurn],
        now: Date = .now,
        maxAge: TimeInterval = 10 * 60
    ) -> Pending? {
        guard let turn = messages.last,
              turn.role == .assistant,
              turn.createdAt >= now.addingTimeInterval(-maxAge),
              let action = turn.actions.reversed().first(where: {
                  $0.status == .pending && $0.requiresConfirmation
              })
        else { return nil }
        return Pending(turnID: turn.id, actionID: action.id, action: action)
    }
}

// MARK: - AI action execution engine (extracted from ChatStore for isolation + testability)

/// LLM çıktısındaki AIAppAction'ları SwiftData store'una uygular. UI state'i (messages/
/// conversations) TAŞIMAZ — sadece (action, ctx) alır, sonuç String'i döner. ChatStore bu
/// motoru çağırır; böylece "veriyi LLM'e göre değiştir" kodu izole + test edilebilir.
enum ChatActionExecutor {
    /// `logDate` yalnız `log_food` için anlamlıdır: öğünün yazılacağı an. Günü model
    /// değil host seçer — geçmiş bir günün thread'inde o gün (bkz. `ChatDailyThread.logDate`).
    @discardableResult
    static func executeAction(_ action: AIAppAction, ctx: ModelContext, logDate: Date = .now) throws -> String {
        switch action.tool {
        case .logFood:
            let name = nonEmpty(action.name ?? action.itemName, fallback: "Yemek")
            guard let calories = action.calories else {
                throw AppToolError.missing("Kalori değeri yok")
            }
            ctx.insert(FoodEntry(
                date: logDate,
                name: name,
                grams: action.grams ?? action.amount,
                calories: calories,
                protein: action.proteinG,
                carbs: action.carbsG,
                fat: action.fatG
            ))
            try ctx.saveStamped()
            return "\(name) \(ChatDailyThread.loggedPhrase(on: logDate))"

        case .addRecipe:
            let title = nonEmpty(action.title ?? action.name, fallback: "")
            guard !title.isEmpty else {
                throw AppToolError.missing("Tarif başlığı yok")
            }
            guard action.sourceVerified,
                  let source = action.unambiguousRecipeSourceURL,
                  let attested = action.verifiedSourceCanonicalURL,
                  AIWebSearchEvidence.canonicalURL(source) == attested
            else {
                throw AppToolError.missing(
                    "Tarif kaynağı tamamlanmış web aramasıyla doğrulanmadı; kayıt engellendi"
                )
            }
            let sourceURL = recipeSourceURL(for: action, title: title)
            guard isAcceptableRecipeSourceURL(sourceURL) else {
                throw AppToolError.missing("Kaynak URL yok; AI tarifleri sadece web'den bulunan gerçek tarif linkiyle eklenebilir")
            }
            guard cleaned(action.ingredients) != nil, cleaned(action.instructions) != nil else {
                throw AppToolError.missing("Kaynaklı tarif detayı eksik; malzeme ve yapılış olmadan eklenmedi")
            }
            let rawCategory = action.category ?? RecipeCategory.dinner.rawValue
            let category = RecipeCategory(rawValue: rawCategory) ?? .dinner
            let recipes = (try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []
            if let existing = recipes.first(where: {
                $0.category == category && normalizedKey($0.title) == normalizedKey(title)
            }) {
                existing.title = title
                existing.category = category
                applyRecipeDetails(from: action, title: title, to: existing)
                existing.updatedAt = .now
                try ctx.saveStamped()
                return "\(title) zaten vardı, tarif güncellendi"
            }

            let recipe = Recipe(title: title, urlString: "", category: category)
            applyRecipeDetails(from: action, title: title, to: recipe)
            ctx.insert(recipe)
            try ctx.saveStamped()
            return "\(title) tariflere eklendi"

        case .updateWorkoutPlan:
            let workoutOperation = action.workoutOperation ?? (action.exerciseName == nil ? "set_session" : "add_exercise")
            switch workoutOperation {
            case "replace_program":
                let days = action.days ?? []
                guard !days.isEmpty else {
                    throw AppToolError.missing("Yeni program günleri yok")
                }
                let archived = try archiveCurrentWorkoutProgram(
                    ctx,
                    title: action.programTitle ?? "Eski antrenman programı",
                    summary: action.programSummary,
                    notes: action.programNotes,
                    source: "ai"
                )
                try clearActiveWorkoutProgram(ctx)
                for day in days {
                    try upsertWorkoutSession(from: day, ctx: ctx, replaceExercises: true)
                }
                try ctx.saveStamped()
                return archived
                    ? "Eski plan arşivlendi, \(days.count) günlük yeni program aktif"
                    : "\(days.count) günlük yeni program aktif"

            case "archive_program":
                let archived = try archiveCurrentWorkoutProgram(
                    ctx,
                    title: action.programTitle ?? "Antrenman programı arşivi",
                    summary: action.programSummary,
                    notes: action.programNotes ?? action.summary,
                    source: "ai"
                )
                try ctx.saveStamped()
                return archived ? "Mevcut antrenman programı arşivlendi" : "Arşivlenecek aktif antrenman programı yok"

            case "add_exercise":
                let weekday = try validWeekday(action.weekday)
                let exerciseName = nonEmpty(action.exerciseName ?? action.name, fallback: "")
                guard !exerciseName.isEmpty else {
                    throw AppToolError.missing("Eklenecek hareket adı yok")
                }
                let session = try upsertWorkoutSession(
                    weekday: weekday,
                    name: action.name,
                    estimatedCalories: action.estimatedCalories,
                    durationMinutes: action.durationMinutes,
                    focus: action.focus,
                    warmup: action.warmup,
                    progression: action.progression,
                    notes: action.workoutNotes,
                    ctx: ctx
                )
                upsertTemplateExercise(
                    in: session,
                    name: exerciseName,
                    sets: action.sets,
                    reps: action.reps,
                    load: action.load ?? formattedLoad(action.weight),
                    rir: action.rir,
                    rest: action.rest,
                    sourceURL: action.sourceURL ?? action.url,
                    notes: action.workoutNotes ?? action.summary,
                    ctx: ctx
                )
                try ctx.saveStamped()
                return "\(WorkoutSession.weekdayName(weekday)) planına \(exerciseName) eklendi"

            default:
                let weekday = try validWeekday(action.weekday ?? action.days?.first?.weekday)
                let name = nonEmpty(action.name ?? action.days?.first?.name, fallback: "")
                guard !name.isEmpty else {
                    throw AppToolError.missing("Antrenman adı yok")
                }
                let session = try upsertWorkoutSession(
                    weekday: weekday,
                    name: name,
                    estimatedCalories: action.estimatedCalories,
                    durationMinutes: action.durationMinutes,
                    focus: action.focus,
                    warmup: action.warmup,
                    progression: action.progression,
                    notes: action.workoutNotes ?? action.summary,
                    ctx: ctx
                )
                // LLM hareket listesini farklı şekillerde gönderebiliyor: weekday eşleşen
                // days[] girdisi, tek elemanlı days[] (gün içi weekday eksik/yanlış) veya
                // top-level exercises[]. Hangisi doluysa onu uygula; boş listeyle mevcut
                // hareketleri SİLME (gün silme ayrı bir niyet, sessiz wipe olmasın).
                let inlineExercises = action.exercises ?? []
                let day = action.days?.first(where: { $0.weekday == weekday })
                    ?? (action.days?.count == 1 ? action.days?.first : nil)
                    ?? (inlineExercises.isEmpty ? nil : AIWorkoutDayPlan(weekday: weekday, name: name, exercises: inlineExercises))
                // Reçete düzenlemesi sync-merge için updatedAt'i bump'lamalı: hareketler
                // child nesne olduğundan parent session "changed" sayılmayabilir ve ham
                // ctx.save() stampUpdatedAtOnChangedSyncModels()'i çağırmaz. Bump olmazsa
                // iki cihaz aynı (eski) zaman damgasıyla FARKLI içerik tutar ve last-write-wins
                // merge (u > local, strict) ezberinde asla yakınsamaz.
                session.updatedAt = .now
                if let day, !day.exercises.isEmpty {
                    try applyWorkoutDayPlan(day, to: session, ctx: ctx, replaceExercises: true)
                    try ctx.saveStamped()
                    return "\(WorkoutSession.weekdayName(weekday)) antrenmanı güncellendi — \(day.exercises.count) hareketlik yeni liste uygulandı"
                }
                try ctx.saveStamped()
                return "\(WorkoutSession.weekdayName(weekday)) antrenman detayları güncellendi (hareket listesi değişmedi)"
            }

        }
    }

    @discardableResult
    static func archiveCurrentWorkoutProgram(
        _ ctx: ModelContext,
        title: String,
        summary: String?,
        notes: String?,
        source: String
    ) throws -> Bool {
        let snapshots = currentWorkoutProgramSnapshots(ctx)
        guard !snapshots.isEmpty else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshots)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AppToolError.unsupported("Antrenman arşivi JSON'a çevrilemedi")
        }
        ctx.insert(WorkoutProgramArchive(
            title: nonEmpty(title, fallback: "Antrenman programı arşivi"),
            summary: cleaned(summary),
            notes: cleaned(notes),
            source: source,
            sessionsJSON: json
        ))
        return true
    }

    static func currentWorkoutProgramSnapshots(_ ctx: ModelContext) -> [WorkoutProgramSessionSnapshot] {
        let workouts = ((try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? [])
            .sorted { $0.weekday < $1.weekday }
        let overrides = ((try? ctx.fetch(FetchDescriptor<WorkoutPlanOverride>())) ?? [])
            .sorted { lhs, rhs in
                if lhs.weekday == rhs.weekday { return lhs.createdAt < rhs.createdAt }
                return lhs.weekday < rhs.weekday
            }
        var snapshots = workouts.map(\.snapshot)
        for override in overrides {
            let exercise = WorkoutTemplateExerciseSnapshot(
                name: override.exerciseName,
                order: snapshots.first(where: { $0.weekday == override.weekday })?.exercises.count ?? 0,
                sets: override.sets,
                reps: override.reps.map(String.init),
                load: formattedLoad(override.weight),
                rir: nil,
                rest: nil,
                sourceURL: nil,
                notes: override.note
            )
            if let idx = snapshots.firstIndex(where: { $0.weekday == override.weekday }) {
                snapshots[idx].exercises.append(exercise)
            } else {
                snapshots.append(WorkoutProgramSessionSnapshot(
                    weekday: override.weekday,
                    name: WorkoutSession.weekdayNames.indices.contains(override.weekday) ? WorkoutSession.weekdayNames[override.weekday] : "Antrenman",
                    estimatedCalories: 0,
                    durationMinutes: 60,
                    focus: "Eski AI plan eklemesi",
                    warmup: nil,
                    progression: nil,
                    notes: override.note,
                    exercises: [exercise]
                ))
            }
        }
        return snapshots.sorted { $0.weekday < $1.weekday }
    }

    static func clearActiveWorkoutProgram(_ ctx: ModelContext) throws {
        for session in (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? [] {
            ctx.delete(session)
        }
        for override in (try? ctx.fetch(FetchDescriptor<WorkoutPlanOverride>())) ?? [] {
            ctx.delete(override)
        }
    }

    @discardableResult
    static func upsertWorkoutSession(from day: AIWorkoutDayPlan, ctx: ModelContext, replaceExercises: Bool) throws -> WorkoutSession {
        let weekday = try validWeekday(day.weekday)
        let session = try upsertWorkoutSession(
            weekday: weekday,
            name: day.name,
            estimatedCalories: day.estimatedCalories,
            durationMinutes: day.durationMinutes,
            focus: day.focus,
            warmup: day.warmup,
            progression: day.progression,
            notes: day.notes,
            ctx: ctx
        )
        try applyWorkoutDayPlan(day, to: session, ctx: ctx, replaceExercises: replaceExercises)
        return session
    }

    @discardableResult
    static func upsertWorkoutSession(
        weekday: Int,
        name: String?,
        estimatedCalories: Double?,
        durationMinutes: Int?,
        focus: String?,
        warmup: String?,
        progression: String?,
        notes: String?,
        ctx: ModelContext
    ) throws -> WorkoutSession {
        let workouts = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let session: WorkoutSession
        if let existing = workouts.first(where: { $0.weekday == weekday }) {
            session = existing
        } else {
            session = WorkoutSession(
                weekday: weekday,
                name: name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? name!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : WorkoutSession.weekdayName(weekday),
                estimatedCalories: estimatedCalories ?? 0,
                durationMinutes: durationMinutes ?? 60
            )
            ctx.insert(session)
        }
        if let value = cleaned(name) { session.name = value }
        if let estimatedCalories { session.estimatedCalories = estimatedCalories }
        if let durationMinutes { session.durationMinutes = durationMinutes }
        if let value = cleaned(focus) { session.focus = value }
        if let value = cleaned(warmup) { session.warmup = value }
        if let value = cleaned(progression) { session.progression = value }
        if let value = cleaned(notes) { session.notes = value }
        // Ham `ctx.save()` kullanan AI eylemleri de CloudKit tekilleştirmesinde
        // güncel ebeveyni kazanan yapmalı; yalnız child hareket değişmiş olabilir.
        session.updatedAt = .now
        return session
    }

    static func applyWorkoutDayPlan(
        _ day: AIWorkoutDayPlan,
        to session: WorkoutSession,
        ctx: ModelContext,
        replaceExercises: Bool
    ) throws {
        if replaceExercises {
            for old in session.templateExercises {
                ctx.delete(old)
            }
            session.templateExercises.removeAll()
        }
        for (idx, exercise) in day.exercises.enumerated() {
            let name = nonEmpty(exercise.name, fallback: "")
            guard !name.isEmpty else { continue }
            upsertTemplateExercise(
                in: session,
                name: name,
                sets: exercise.sets,
                reps: exercise.reps,
                load: exercise.load,
                rir: exercise.rir,
                rest: exercise.rest,
                sourceURL: exercise.sourceURL,
                notes: exercise.notes,
                order: idx,
                ctx: ctx
            )
        }
    }

    static func upsertTemplateExercise(
        in session: WorkoutSession,
        name: String,
        sets: Int?,
        reps: String?,
        load: String?,
        rir: String?,
        rest: String?,
        sourceURL: String?,
        notes: String?,
        order explicitOrder: Int? = nil,
        ctx: ModelContext
    ) {
        let key = normalizedKey(name)
        let sorted = session.sortedTemplateExercises
        let exercise = sorted.first(where: { normalizedKey($0.name) == key }) ?? {
            let nextOrder = explicitOrder ?? ((sorted.map(\.order).max() ?? -1) + 1)
            let created = WorkoutTemplateExercise(name: name, order: nextOrder)
            ctx.insert(created)
            session.templateExercises.append(created)
            return created
        }()
        exercise.name = name
        exercise.order = explicitOrder ?? exercise.order
        exercise.sets = sets ?? exercise.sets
        exercise.reps = cleaned(reps) ?? exercise.reps
        exercise.load = cleaned(load) ?? exercise.load
        exercise.rir = cleaned(rir) ?? exercise.rir
        exercise.rest = cleaned(rest) ?? exercise.rest
        exercise.sourceURL = cleaned(sourceURL) ?? exercise.sourceURL
        exercise.notes = cleaned(notes) ?? exercise.notes
    }

    static func formattedLoad(_ weight: Double?) -> String? {
        guard let weight else { return nil }
        let formatted = weight == weight.rounded() ? "\(Int(weight))" : String(format: "%.1f", weight)
        return "@ \(formatted) kg"
    }

    static func validWeekday(_ value: Int?) throws -> Int {
        guard let value, (1...7).contains(value) else {
            throw AppToolError.missing("Geçerli gün yok")
        }
        return value
    }

    static func nonEmpty(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func applyRecipeDetails(from action: AIAppAction, title: String, to recipe: Recipe) {
        let url = recipeSourceURL(for: action, title: title)
        if !url.isEmpty {
            recipe.urlString = url
        }
        if let summary = cleaned(action.recipeSummary) ?? cleaned(action.summary) {
            recipe.summary = summary
        }
        if let ingredients = cleaned(action.ingredients) {
            recipe.ingredientsText = ingredients
        }
        if let instructions = cleaned(action.instructions) {
            recipe.instructionsText = instructions
        }
        if let servings = action.servings {
            recipe.servings = servings
        }
        if let prepMinutes = action.prepMinutes {
            recipe.prepMinutes = prepMinutes
        }
        if let calories = action.calories {
            recipe.calories = calories
        }
        if let protein = action.proteinG {
            recipe.protein = protein
        }
        if let carbs = action.carbsG {
            recipe.carbs = carbs
        }
        if let fat = action.fatG {
            recipe.fat = fat
        }
    }

    static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    static func normalizedRecipeURL(_ raw: String?, title: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return ""
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    static func recipeSourceURL(for action: AIAppAction, title: String) -> String {
        normalizedRecipeURL(action.unambiguousRecipeSourceURL, title: title)
    }

    static func isAcceptableRecipeSourceURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(),
              !host.isEmpty
        else { return false }

        let blockedHostFragments = [
            "google.", "bing.", "duckduckgo.", "search.yahoo.", "yandex.", "perplexity.",
            "chatgpt.", "openai.", "localhost", "127.0.0.1"
        ]
        guard !blockedHostFragments.contains(where: { host.contains($0) }) else {
            return false
        }
        guard !trimmed.contains("...") else {
            return false
        }
        return true
    }
}
#endif
