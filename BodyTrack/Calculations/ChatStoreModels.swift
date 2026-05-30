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

// MARK: - AI action execution engine (extracted from ChatStore for isolation + testability)

/// LLM çıktısındaki AIAppAction'ları SwiftData store'una uygular. UI state'i (messages/
/// conversations) TAŞIMAZ — sadece (action, ctx) alır, sonuç String'i döner. ChatStore bu
/// motoru çağırır; böylece "veriyi LLM'e göre değiştir" kodu izole + test edilebilir.
enum ChatActionExecutor {
    @discardableResult
    static func executeAction(_ action: AIAppAction, ctx: ModelContext) throws -> String {
        switch action.tool {
        case .logFood:
            let name = nonEmpty(action.name ?? action.itemName, fallback: "Yemek")
            guard let calories = action.calories else {
                throw AppToolError.missing("Kalori değeri yok")
            }
            ctx.insert(FoodEntry(
                date: .now,
                name: name,
                grams: action.grams ?? action.amount,
                calories: calories,
                protein: action.proteinG,
                carbs: action.carbsG,
                fat: action.fatG
            ))
            try ctx.save()
            return "\(name) bugüne eklendi"

        case .addRecipe:
            let title = nonEmpty(action.title ?? action.name, fallback: "")
            guard !title.isEmpty else {
                throw AppToolError.missing("Tarif başlığı yok")
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
                existing.createdAt = .now
                try ctx.save()
                return "\(title) zaten vardı, tarif güncellendi"
            }

            let recipe = Recipe(title: title, urlString: "", category: category)
            applyRecipeDetails(from: action, title: title, to: recipe)
            ctx.insert(recipe)
            try ctx.save()
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
                try ctx.save()
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
                try ctx.save()
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
                try ctx.save()
                return "\(WorkoutSession.weekdayName(weekday)) planına \(exerciseName) eklendi"

            default:
                let weekday = try validWeekday(action.weekday)
                let name = nonEmpty(action.name, fallback: "")
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
                if let day = action.days?.first(where: { $0.weekday == weekday }) {
                    try applyWorkoutDayPlan(day, to: session, ctx: ctx, replaceExercises: true)
                }
                try ctx.save()
                return "\(WorkoutSession.weekdayName(weekday)) antrenmanı güncellendi"
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
        normalizedRecipeURL(action.url ?? action.sourceURL, title: title)
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
