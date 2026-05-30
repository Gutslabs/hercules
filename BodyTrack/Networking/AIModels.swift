import Foundation

struct AIFoodResult: Codable, Equatable, Sendable {
    var name: String?
    var grams: Double?
    var calories: Double?
    var protein_g: Double?
    var carbs_g: Double?
    var fat_g: Double?
    var message: String
    var actions: [AIAppAction]?

    var isFood: Bool {
        calories != nil && (name?.isEmpty == false)
    }

    var actionList: [AIAppAction] {
        actions ?? []
    }

    init(
        name: String? = nil,
        grams: Double? = nil,
        calories: Double? = nil,
        protein_g: Double? = nil,
        carbs_g: Double? = nil,
        fat_g: Double? = nil,
        message: String,
        actions: [AIAppAction]? = nil
    ) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.protein_g = protein_g
        self.carbs_g = carbs_g
        self.fat_g = fat_g
        self.message = message
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case name, grams, calories, protein_g, carbs_g, fat_g, message, actions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        grams = try? c.decodeIfPresent(Double.self, forKey: .grams)
        calories = try? c.decodeIfPresent(Double.self, forKey: .calories)
        protein_g = try? c.decodeIfPresent(Double.self, forKey: .protein_g)
        carbs_g = try? c.decodeIfPresent(Double.self, forKey: .carbs_g)
        fat_g = try? c.decodeIfPresent(Double.self, forKey: .fat_g)
        message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? ""
        let decodedActions = ((try? c.decodeIfPresent(LossyAIActionList.self, forKey: .actions))?.values) ?? []
        actions = decodedActions.isEmpty ? nil : decodedActions
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(grams, forKey: .grams)
        try c.encodeIfPresent(calories, forKey: .calories)
        try c.encodeIfPresent(protein_g, forKey: .protein_g)
        try c.encodeIfPresent(carbs_g, forKey: .carbs_g)
        try c.encodeIfPresent(fat_g, forKey: .fat_g)
        try c.encode(message, forKey: .message)
        try c.encodeIfPresent(actions, forKey: .actions)
    }
}

struct LossyAIActionList: Decodable {
    let values: [AIAppAction]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var output: [AIAppAction] = []
        while !container.isAtEnd {
            let elementDecoder = try container.superDecoder()
            if let action = try? AIAppAction(from: elementDecoder) {
                output.append(action)
            }
        }
        values = output
    }
}

enum AIAppToolName: String, Codable, Equatable, Sendable {
    case logFood = "log_food"
    case addRecipe = "add_recipe"
    case updateWorkoutPlan = "update_workout_plan"

}

enum AIAppActionStatus: String, Codable, Equatable, Sendable {
    case pending
    case applied
    case rejected
    case failed
}

struct AIWorkoutExercisePlan: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var sets: Int?
    var reps: String?
    var load: String?
    var rir: String?
    var rest: String?
    var sourceURL: String?
    var notes: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, sets, reps, load, rir, rest, notes
        case sourceURL, source_url, url
    }

    init(
        id: UUID = UUID(),
        name: String,
        sets: Int? = nil,
        reps: String? = nil,
        load: String? = nil,
        rir: String? = nil,
        rest: String? = nil,
        sourceURL: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.load = load
        self.rir = rir
        self.rest = rest
        self.sourceURL = sourceURL
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        sets = try? c.decodeIfPresent(Int.self, forKey: .sets)
        if let value = try? c.decodeIfPresent(String.self, forKey: .reps) {
            reps = value
        } else if let value = try? c.decodeIfPresent(Int.self, forKey: .reps) {
            reps = "\(value)"
        } else {
            reps = nil
        }
        load = try? c.decodeIfPresent(String.self, forKey: .load)
        rir = try? c.decodeIfPresent(String.self, forKey: .rir)
        rest = try? c.decodeIfPresent(String.self, forKey: .rest)
        sourceURL = (try? c.decodeIfPresent(String.self, forKey: .sourceURL))
            ?? (try? c.decodeIfPresent(String.self, forKey: .source_url))
            ?? (try? c.decodeIfPresent(String.self, forKey: .url))
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(sets, forKey: .sets)
        try c.encodeIfPresent(reps, forKey: .reps)
        try c.encodeIfPresent(load, forKey: .load)
        try c.encodeIfPresent(rir, forKey: .rir)
        try c.encodeIfPresent(rest, forKey: .rest)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}

struct AIWorkoutDayPlan: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var weekday: Int
    var name: String
    var estimatedCalories: Double?
    var durationMinutes: Int?
    var focus: String?
    var warmup: String?
    var progression: String?
    var notes: String?
    var exercises: [AIWorkoutExercisePlan]

    private enum CodingKeys: String, CodingKey {
        case id, weekday, name, focus, warmup, progression, notes, exercises
        case estimatedCalories, estimated_calories
        case durationMinutes, duration_minutes
    }

    init(
        id: UUID = UUID(),
        weekday: Int,
        name: String,
        estimatedCalories: Double? = nil,
        durationMinutes: Int? = nil,
        focus: String? = nil,
        warmup: String? = nil,
        progression: String? = nil,
        notes: String? = nil,
        exercises: [AIWorkoutExercisePlan] = []
    ) {
        self.id = id
        self.weekday = weekday
        self.name = name
        self.estimatedCalories = estimatedCalories
        self.durationMinutes = durationMinutes
        self.focus = focus
        self.warmup = warmup
        self.progression = progression
        self.notes = notes
        self.exercises = exercises
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        weekday = (try? c.decode(Int.self, forKey: .weekday)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        estimatedCalories = (try? c.decodeIfPresent(Double.self, forKey: .estimatedCalories))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .estimated_calories))
        durationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .durationMinutes))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .duration_minutes))
        focus = try? c.decodeIfPresent(String.self, forKey: .focus)
        warmup = try? c.decodeIfPresent(String.self, forKey: .warmup)
        progression = try? c.decodeIfPresent(String.self, forKey: .progression)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        exercises = (try? c.decodeIfPresent([AIWorkoutExercisePlan].self, forKey: .exercises)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(weekday, forKey: .weekday)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(estimatedCalories, forKey: .estimatedCalories)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(focus, forKey: .focus)
        try c.encodeIfPresent(warmup, forKey: .warmup)
        try c.encodeIfPresent(progression, forKey: .progression)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(exercises, forKey: .exercises)
    }
}

struct AIAppAction: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var tool: AIAppToolName
    var summary: String?
    var status: AIAppActionStatus
    var resultMessage: String?

    var name: String?
    var title: String?
    var url: String?
    var category: String?
    var recipeSummary: String?
    var ingredients: String?
    var instructions: String?
    var servings: Int?
    var prepMinutes: Int?

    var weekday: Int?
    var estimatedCalories: Double?
    var durationMinutes: Int?
    var workoutOperation: String?
    var exerciseName: String?
    var sets: Int?
    var reps: String?
    var weight: Double?
    var load: String?
    var rir: String?
    var rest: String?
    var sourceURL: String?
    var workoutNotes: String?
    var focus: String?
    var warmup: String?
    var progression: String?
    var archiveCurrent: Bool?
    var programTitle: String?
    var programSummary: String?
    var programNotes: String?
    var days: [AIWorkoutDayPlan]?

    var itemName: String?
    var amount: Double?
    var unit: String?

    var grams: Double?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?

    var requiresConfirmation: Bool {
        tool == .updateWorkoutPlan
    }

    var displayTitle: String {
        switch tool {
        case .logFood: return "Kalori ekle"
        case .addRecipe: return "Tarif ekle"
        case .updateWorkoutPlan: return "Antrenman planı"
        }
    }

    var displaySummary: String {
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        switch tool {
        case .logFood:
            return "\(name ?? "Yemek") → \(Int((calories ?? 0).rounded())) kcal"
        case .addRecipe:
            return title ?? "Yeni tarif"
        case .updateWorkoutPlan:
            if let exerciseName, !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(weekdayLabel) → + \(exerciseName)"
            }
            if workoutOperation == "replace_program" {
                return programTitle ?? "Yeni program"
            }
            if workoutOperation == "archive_program" {
                return programTitle ?? "Mevcut programı arşivle"
            }
            return "\(weekdayLabel) → \(name ?? "Antrenman")"

        }
    }

    var weekdayLabel: String {
        guard let weekday, weekday >= 1, weekday < WorkoutSession.weekdayNames.count else { return "Gün" }
        return WorkoutSession.weekdayNames[weekday]
    }

    init(
        id: UUID = UUID(),
        tool: AIAppToolName,
        summary: String? = nil,
        status: AIAppActionStatus = .pending,
        resultMessage: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.summary = summary
        self.status = status
        self.resultMessage = resultMessage
    }

    private enum CodingKeys: String, CodingKey {
        case id, tool, summary, status, resultMessage
        case name, title, url, category, weekday, grams, calories, amount, unit
        case recipeSummary, recipe_summary
        case ingredients, instructions, servings
        case prepMinutes, prep_minutes
        case estimatedCalories, estimated_calories
        case durationMinutes, duration_minutes
        case workoutOperation, workout_operation
        case exerciseName, exercise_name
        case sets, reps, weight, load, rir, rest, focus, warmup, progression, days
        case sourceURL, source_url
        case workoutNotes, workout_notes
        case archiveCurrent, archive_current
        case programTitle, program_title
        case programSummary, program_summary
        case programNotes, program_notes

        case itemName, item_name
        case proteinG, protein_g
        case carbsG, carbs_g
        case fatG, fat_g
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        tool = try c.decode(AIAppToolName.self, forKey: .tool)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        status = (try? c.decodeIfPresent(AIAppActionStatus.self, forKey: .status)) ?? .pending
        resultMessage = try? c.decodeIfPresent(String.self, forKey: .resultMessage)

        name = try? c.decodeIfPresent(String.self, forKey: .name)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        recipeSummary = (try? c.decodeIfPresent(String.self, forKey: .recipeSummary))
            ?? (try? c.decodeIfPresent(String.self, forKey: .recipe_summary))
        ingredients = try? c.decodeIfPresent(String.self, forKey: .ingredients)
        instructions = try? c.decodeIfPresent(String.self, forKey: .instructions)
        servings = try? c.decodeIfPresent(Int.self, forKey: .servings)
        prepMinutes = (try? c.decodeIfPresent(Int.self, forKey: .prepMinutes))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .prep_minutes))
        weekday = try? c.decodeIfPresent(Int.self, forKey: .weekday)
        grams = try? c.decodeIfPresent(Double.self, forKey: .grams)
        calories = try? c.decodeIfPresent(Double.self, forKey: .calories)
        amount = try? c.decodeIfPresent(Double.self, forKey: .amount)
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        estimatedCalories = (try? c.decodeIfPresent(Double.self, forKey: .estimatedCalories))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .estimated_calories))
        durationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .durationMinutes))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .duration_minutes))
        workoutOperation = (try? c.decodeIfPresent(String.self, forKey: .workoutOperation))
            ?? (try? c.decodeIfPresent(String.self, forKey: .workout_operation))
        exerciseName = (try? c.decodeIfPresent(String.self, forKey: .exerciseName))
            ?? (try? c.decodeIfPresent(String.self, forKey: .exercise_name))
        sets = try? c.decodeIfPresent(Int.self, forKey: .sets)
        if let value = try? c.decodeIfPresent(String.self, forKey: .reps) {
            reps = value
        } else if let value = try? c.decodeIfPresent(Int.self, forKey: .reps) {
            reps = "\(value)"
        } else {
            reps = nil
        }
        weight = try? c.decodeIfPresent(Double.self, forKey: .weight)
        load = try? c.decodeIfPresent(String.self, forKey: .load)
        rir = try? c.decodeIfPresent(String.self, forKey: .rir)
        rest = try? c.decodeIfPresent(String.self, forKey: .rest)
        sourceURL = (try? c.decodeIfPresent(String.self, forKey: .sourceURL))
            ?? (try? c.decodeIfPresent(String.self, forKey: .source_url))
        workoutNotes = (try? c.decodeIfPresent(String.self, forKey: .workoutNotes))
            ?? (try? c.decodeIfPresent(String.self, forKey: .workout_notes))
        focus = try? c.decodeIfPresent(String.self, forKey: .focus)
        warmup = try? c.decodeIfPresent(String.self, forKey: .warmup)
        progression = try? c.decodeIfPresent(String.self, forKey: .progression)
        archiveCurrent = (try? c.decodeIfPresent(Bool.self, forKey: .archiveCurrent))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: .archive_current))
        programTitle = (try? c.decodeIfPresent(String.self, forKey: .programTitle))
            ?? (try? c.decodeIfPresent(String.self, forKey: .program_title))
        programSummary = (try? c.decodeIfPresent(String.self, forKey: .programSummary))
            ?? (try? c.decodeIfPresent(String.self, forKey: .program_summary))
        programNotes = (try? c.decodeIfPresent(String.self, forKey: .programNotes))
            ?? (try? c.decodeIfPresent(String.self, forKey: .program_notes))
        days = try? c.decodeIfPresent([AIWorkoutDayPlan].self, forKey: .days)

        itemName = (try? c.decodeIfPresent(String.self, forKey: .itemName))
            ?? (try? c.decodeIfPresent(String.self, forKey: .item_name))
        proteinG = (try? c.decodeIfPresent(Double.self, forKey: .proteinG))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .protein_g))
        carbsG = (try? c.decodeIfPresent(Double.self, forKey: .carbsG))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .carbs_g))
        fatG = (try? c.decodeIfPresent(Double.self, forKey: .fatG))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .fat_g))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tool, forKey: .tool)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(resultMessage, forKey: .resultMessage)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(recipeSummary, forKey: .recipeSummary)
        try c.encodeIfPresent(ingredients, forKey: .ingredients)
        try c.encodeIfPresent(instructions, forKey: .instructions)
        try c.encodeIfPresent(servings, forKey: .servings)
        try c.encodeIfPresent(prepMinutes, forKey: .prepMinutes)
        try c.encodeIfPresent(weekday, forKey: .weekday)
        try c.encodeIfPresent(estimatedCalories, forKey: .estimatedCalories)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(workoutOperation, forKey: .workoutOperation)
        try c.encodeIfPresent(exerciseName, forKey: .exerciseName)
        try c.encodeIfPresent(sets, forKey: .sets)
        try c.encodeIfPresent(reps, forKey: .reps)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(load, forKey: .load)
        try c.encodeIfPresent(rir, forKey: .rir)
        try c.encodeIfPresent(rest, forKey: .rest)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try c.encodeIfPresent(workoutNotes, forKey: .workoutNotes)
        try c.encodeIfPresent(focus, forKey: .focus)
        try c.encodeIfPresent(warmup, forKey: .warmup)
        try c.encodeIfPresent(progression, forKey: .progression)
        try c.encodeIfPresent(archiveCurrent, forKey: .archiveCurrent)
        try c.encodeIfPresent(programTitle, forKey: .programTitle)
        try c.encodeIfPresent(programSummary, forKey: .programSummary)
        try c.encodeIfPresent(programNotes, forKey: .programNotes)
        try c.encodeIfPresent(days, forKey: .days)

        try c.encodeIfPresent(itemName, forKey: .itemName)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(grams, forKey: .grams)
        try c.encodeIfPresent(calories, forKey: .calories)
        try c.encodeIfPresent(proteinG, forKey: .proteinG)
        try c.encodeIfPresent(carbsG, forKey: .carbsG)
        try c.encodeIfPresent(fatG, forKey: .fatG)
    }
}

enum OpenRouterError: LocalizedError {
    case badResponse(Int, String)
    case decoding(String)
    case missingKey
    case toolLoop

    var errorDescription: String? {
        switch self {
        case .badResponse(let code, let msg): return "HTTP \(code): \(msg)"
        case .decoding(let s): return "Yanıt çözümlenemedi: \(s)"
        case .missingKey: return "OpenRouter API key tanımlı değil."
        case .toolLoop: return "Tool çağrı limiti aşıldı."
        }
    }
}

struct ChatTurn: Identifiable, Equatable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    var food: AIFoodResult? = nil
    var actions: [AIAppAction] = []
    var saved: Bool = false
    var searchedFor: String? = nil  // populated if AI did a web search
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        food: AIFoodResult? = nil,
        actions: [AIAppAction] = [],
        saved: Bool = false,
        searchedFor: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.food = food
        self.actions = actions
        self.saved = saved
        self.searchedFor = searchedFor
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, text, food, actions, saved, searchedFor, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        role = try c.decode(Role.self, forKey: .role)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        food = try? c.decodeIfPresent(AIFoodResult.self, forKey: .food)
        actions = (try? c.decodeIfPresent([AIAppAction].self, forKey: .actions)) ?? []
        saved = (try? c.decodeIfPresent(Bool.self, forKey: .saved)) ?? false
        searchedFor = try? c.decodeIfPresent(String.self, forKey: .searchedFor)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(food, forKey: .food)
        if !actions.isEmpty {
            try c.encode(actions, forKey: .actions)
        }
        try c.encode(saved, forKey: .saved)
        try c.encodeIfPresent(searchedFor, forKey: .searchedFor)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
