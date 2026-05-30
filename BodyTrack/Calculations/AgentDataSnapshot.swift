import Foundation
import SwiftData

struct AgentDataScope: Sendable {
    var includeProfile = false
    var includeMeasurements = false
    var measurementLimit: Int?
    var includeFoods = false
    var foodStart: Date?
    var foodEndExclusive: Date?
    var foodLimit: Int?
    var includeSteps = false
    var stepStart: Date?
    var stepEndExclusive: Date?
    var stepLimit: Int?
    var includeWorkoutLogs = false
    var workoutLogStart: Date?
    var workoutLogEndExclusive: Date?
    var workoutLogLimit: Int?
    var includeWorkoutSessions = false
    var includeFoodPresets = false
    var includeRecipes = false

    static func infer(
        query: String,
        explicitTags tags: Set<MentionTag>,
        now: Date = .now,
        calendar cal: Calendar = .current
    ) -> AgentDataScope {
        let lower = AgentQueryClassifier.normalized(query)
        if tags.contains(.hepsi) || containsAny(lower, ["hepsi", "tumu", "tum veri", "her sey", "all", "everything"]) {
            return full()
        }

        var scope = AgentDataScope()
        let coach = AgentQueryClassifier.isCoachQuery(query) && !AgentQueryClassifier.isLikelyFoodLog(query)
        let training = tags.contains(.antrenman) || containsAny(lower, AgentQueryClassifier.trainingSignals)
        let nutrition = tags.contains(.kalori) || tags.contains(.takvim) || containsAny(lower, AgentQueryClassifier.nutritionSignals)
        let body = !tags.intersection([.genelBakis, .olcumler, .grafikler, .profil]).isEmpty
            || containsAny(lower, ["kilo", "yag", "lean", "definasyon", "cut", "bulk", "plato", "hedef"])
        let recipe = tags.contains(.tarifler) || containsAny(lower, [
            "tarif", "recipe", "bowl", "smoothie", "shake", "pankek", "pancake",
            "waffle", "tatli", "tatlı", "meal prep"
        ])
        let micro = containsAny(lower, [
            "vitamin", "mineral", "mikro", "micronutrient", "lif", "fiber",
            "cesit", "çeşit", "sebze", "meyve"
        ])
        let calorieDecision = containsAny(lower, [
            "cut", "definasyon", "bulk", "plato", "tdee", "maintenance",
            "hedefe", "ulasir", "ulaşır", "acik", "açık", "tempo", "hiz", "hız"
        ])
        let aggregate = containsAny(lower, [
            "ortalama", "average", "ozet", "özet", "toplam", "total",
            "bu hafta", "gecen hafta", "geçen hafta", "son 30", "30 gun", "30 gün",
            "son 90", "90 gun", "90 gün", "bu ay", "gecen ay", "geçen ay",
            "aylik", "aylık", "haftalik", "haftalık"
        ])

        scope.includeProfile = coach || !tags.isEmpty || nutrition || body || recipe
        scope.includeMeasurements = coach || body || nutrition || recipe
        scope.measurementLimit = scope.includeMeasurements ? 180 : nil

        if let requestedInterval = UserContextSnapshot.requestedFoodInterval(for: query, now: now, calendar: cal) {
            scope.includeFoods = true
            scope.foodStart = requestedInterval.start
            scope.foodEndExclusive = requestedInterval.end
            scope.foodLimit = nil
        } else if nutrition || recipe || micro || calorieDecision {
            let days: Int
            if aggregate || calorieDecision {
                days = 30
            } else if recipe || micro {
                days = 14
            } else {
                days = 14
            }
            scope.includeFoods = true
            scope.foodStart = startOfRollingWindow(days: days, now: now, calendar: cal)
            scope.foodEndExclusive = endOfToday(now: now, calendar: cal)
            scope.foodLimit = days <= 7 ? 160 : (days <= 14 ? 260 : 520)
        } else if containsAny(lower, ["bugun", "bugün", "today", "kalan", "remaining"]) || tags.contains(.genelBakis) {
            scope.includeFoods = true
            scope.foodStart = cal.startOfDay(for: now)
            scope.foodEndExclusive = endOfToday(now: now, calendar: cal)
            scope.foodLimit = 120
        }

        if training {
            scope.includeWorkoutSessions = true
            scope.includeWorkoutLogs = true
            scope.workoutLogStart = startOfRollingWindow(days: 30, now: now, calendar: cal)
            scope.workoutLogEndExclusive = endOfToday(now: now, calendar: cal)
            scope.workoutLogLimit = 120
        } else if tags.contains(.genelBakis) || tags.contains(.profil) {
            scope.includeWorkoutSessions = true
        }

        if containsAny(lower, ["adim", "step", "hareket", "neat", "cut", "definasyon"]) || tags.contains(.genelBakis) {
            let days = aggregate || calorieDecision ? 30 : 7
            scope.includeSteps = true
            scope.stepStart = startOfRollingWindow(days: days, now: now, calendar: cal)
            scope.stepEndExclusive = endOfToday(now: now, calendar: cal)
            scope.stepLimit = days <= 7 ? 80 : 240
        }

        if recipe {
            scope.includeFoodPresets = true
            scope.includeRecipes = true
            if !scope.includeFoods {
                scope.includeFoods = true
                scope.foodStart = cal.startOfDay(for: now)
                scope.foodEndExclusive = endOfToday(now: now, calendar: cal)
                scope.foodLimit = 120
            }
        } else if tags.contains(.tarifler) {
            scope.includeRecipes = true
        }

        return scope
    }

    static func full() -> AgentDataScope {
        AgentDataScope(
            includeProfile: true,
            includeMeasurements: true,
            measurementLimit: nil,
            includeFoods: true,
            foodStart: nil,
            foodEndExclusive: nil,
            foodLimit: nil,
            includeSteps: true,
            stepStart: nil,
            stepEndExclusive: nil,
            stepLimit: nil,
            includeWorkoutLogs: true,
            workoutLogStart: nil,
            workoutLogEndExclusive: nil,
            workoutLogLimit: nil,
            includeWorkoutSessions: true,
            includeFoodPresets: true,
            includeRecipes: true
        )
    }

    func coversFoods(days: Int, now: Date = .now, calendar cal: Calendar = .current) -> Bool {
        covers(include: includeFoods, start: foodStart, end: foodEndExclusive, days: days, now: now, calendar: cal)
    }

    func coversSteps(days: Int, now: Date = .now, calendar cal: Calendar = .current) -> Bool {
        covers(include: includeSteps, start: stepStart, end: stepEndExclusive, days: days, now: now, calendar: cal)
    }

    func coversWorkoutLogs(days: Int, now: Date = .now, calendar cal: Calendar = .current) -> Bool {
        covers(include: includeWorkoutLogs, start: workoutLogStart, end: workoutLogEndExclusive, days: days, now: now, calendar: cal)
    }

    private func covers(
        include: Bool,
        start: Date?,
        end: Date?,
        days: Int,
        now: Date,
        calendar cal: Calendar
    ) -> Bool {
        guard include else { return false }
        let neededEnd = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let neededStart = cal.date(byAdding: .day, value: -max(1, days), to: neededEnd) ?? neededEnd
        let needed = DateInterval(start: neededStart, end: neededEnd)
        if let start, start > needed.start { return false }
        if let end, end < needed.end { return false }
        return true
    }

    private static func containsAny(_ lowercasedText: String, _ needles: [String]) -> Bool {
        AgentQueryClassifier.containsAny(lowercasedText, needles)
    }

    private static func startOfRollingWindow(days: Int, now: Date, calendar cal: Calendar) -> Date {
        let today = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
    }

    private static func endOfToday(now: Date, calendar cal: Calendar) -> Date {
        let today = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: 1, to: today) ?? now
    }
}

struct AgentDataSnapshot: Sendable {
    var scope: AgentDataScope
    var profile: AgentUserProfileSnapshot?
    var measurements: [AgentMeasurementSnapshot]
    var foods: [AgentFoodSnapshot]
    var steps: [AgentStepSnapshot]
    var workoutLogs: [AgentWorkoutLogSnapshot]
    var workoutSessions: [AgentWorkoutSessionSnapshot]
    var foodPresets: [AgentFoodPresetSnapshot]
    var recipes: [AgentRecipeSnapshot]
    var capturedAt: Date

    static func make(ctx: ModelContext, now: Date = .now, scope: AgentDataScope = .full()) -> AgentDataSnapshot {
        let profile = scope.includeProfile
            ? (try? ctx.fetch(FetchDescriptor<UserProfile>()))?.first.map(AgentUserProfileSnapshot.init)
            : nil
        let measurements = scope.includeMeasurements
            ? fetchMeasurements(ctx: ctx, limit: scope.measurementLimit).map(AgentMeasurementSnapshot.init)
            : []
        let foods = scope.includeFoods
            ? fetchFoods(ctx: ctx, start: scope.foodStart, endExclusive: scope.foodEndExclusive, limit: scope.foodLimit).map(AgentFoodSnapshot.init)
            : []
        let steps = scope.includeSteps
            ? fetchSteps(ctx: ctx, start: scope.stepStart, endExclusive: scope.stepEndExclusive, limit: scope.stepLimit).map(AgentStepSnapshot.init)
            : []
        let workoutLogs = scope.includeWorkoutLogs
            ? fetchWorkoutLogs(ctx: ctx, start: scope.workoutLogStart, endExclusive: scope.workoutLogEndExclusive, limit: scope.workoutLogLimit).map(AgentWorkoutLogSnapshot.init)
            : []
        let sessions = scope.includeWorkoutSessions
            ? ((try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []).map(AgentWorkoutSessionSnapshot.init)
            : []
        let presets = scope.includeFoodPresets
            ? ((try? ctx.fetch(FetchDescriptor<FoodPreset>(
                sortBy: [SortDescriptor(\.sortOrder)]
            ))) ?? []).map(AgentFoodPresetSnapshot.init)
            : []
        let recipes: [AgentRecipeSnapshot] = scope.includeRecipes
            ? {
                var d = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                d.fetchLimit = 80   // bağlam için son 80 tarif yeterli
                return ((try? ctx.fetch(d)) ?? []).map(AgentRecipeSnapshot.init)
            }()
            : []

        return AgentDataSnapshot(
            scope: scope,
            profile: profile,
            measurements: measurements,
            foods: foods,
            steps: steps,
            workoutLogs: workoutLogs,
            workoutSessions: sessions,
            foodPresets: presets,
            recipes: recipes,
            capturedAt: now
        )
    }

    private static func fetchMeasurements(ctx: ModelContext, limit: Int?) -> [Measurement] {
        var descriptor = FetchDescriptor<Measurement>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let limit {
            descriptor.fetchLimit = limit
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    private static func fetchFoods(
        ctx: ModelContext,
        start: Date?,
        endExclusive: Date?,
        limit: Int?
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

    private static func fetchSteps(
        ctx: ModelContext,
        start: Date?,
        endExclusive: Date?,
        limit: Int?
    ) -> [StepEntry] {
        var descriptor: FetchDescriptor<StepEntry>
        if let start, let endExclusive {
            descriptor = FetchDescriptor<StepEntry>(
                predicate: #Predicate { $0.date >= start && $0.date < endExclusive },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else if let start {
            descriptor = FetchDescriptor<StepEntry>(
                predicate: #Predicate { $0.date >= start },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else if let endExclusive {
            descriptor = FetchDescriptor<StepEntry>(
                predicate: #Predicate { $0.date < endExclusive },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<StepEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        }
        if let limit {
            descriptor.fetchLimit = limit
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    private static func fetchWorkoutLogs(
        ctx: ModelContext,
        start: Date?,
        endExclusive: Date?,
        limit: Int?
    ) -> [WorkoutLog] {
        var descriptor: FetchDescriptor<WorkoutLog>
        if let start, let endExclusive {
            descriptor = FetchDescriptor<WorkoutLog>(
                predicate: #Predicate { $0.date >= start && $0.date < endExclusive },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else if let start {
            descriptor = FetchDescriptor<WorkoutLog>(
                predicate: #Predicate { $0.date >= start },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else if let endExclusive {
            descriptor = FetchDescriptor<WorkoutLog>(
                predicate: #Predicate { $0.date < endExclusive },
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

struct AgentUserProfileSnapshot: Sendable {
    var name: String
    var sex: Sex
    var birthDate: Date
    var age: Int
    var height: Double
    var activity: ActivityLevel
    var goal: Goal
    var targetWeight: Double?
    var manualBodyFat: Double?
    var manualCalorieOffset: Double
    var manualCalorieOffsetMacro: CalorieOffsetMacro
    var manualProteinGrams: Double?
    var manualCarbsGrams: Double?
    var manualFatGrams: Double?
    var about: String
    var supplements: String

    init(_ profile: UserProfile) {
        name = profile.name
        sex = profile.sex
        birthDate = profile.birthDate
        age = profile.age
        height = profile.height
        activity = profile.activity
        goal = profile.goal
        targetWeight = profile.targetWeight
        manualBodyFat = profile.manualBodyFat
        manualCalorieOffset = profile.manualCalorieOffset
        manualCalorieOffsetMacro = profile.manualCalorieOffsetMacro
        manualProteinGrams = profile.manualProteinGrams
        manualCarbsGrams = profile.manualCarbsGrams
        manualFatGrams = profile.manualFatGrams
        about = profile.about
        supplements = profile.effectiveSupplements
    }
}

struct AgentMeasurementSnapshot: Sendable {
    var date: Date
    var weight: Double?
    var bodyFat: Double?
    var waist: Double?
    var chest: Double?
    var neck: Double?
    var note: String?

    var leanMass: Double? {
        guard let weight, let bodyFat else { return nil }
        return weight * (1.0 - bodyFat / 100.0)
    }

    init(_ measurement: Measurement) {
        date = measurement.date
        weight = measurement.weight
        bodyFat = measurement.bodyFat
        waist = measurement.waist
        chest = measurement.chest
        neck = measurement.neck
        note = measurement.note
    }
}

struct AgentFoodSnapshot: Sendable {
    var date: Date
    var name: String
    var grams: Double?
    var calories: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    init(_ food: FoodEntry) {
        date = food.date
        name = food.name
        grams = food.grams
        calories = food.calories
        protein = food.protein
        carbs = food.carbs
        fat = food.fat
    }
}

struct AgentStepSnapshot: Sendable {
    var date: Date
    var steps: Int
    var source: String
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    var syncedAt: Date?

    init(_ entry: StepEntry) {
        date = entry.date
        steps = entry.steps
        source = entry.source
        distanceMeters = entry.distanceMeters
        activeEnergyKcal = entry.activeEnergyKcal
        syncedAt = entry.syncedAt
    }
}

struct AgentWorkoutLogSnapshot: Sendable {
    var date: Date
    var name: String
    var durationMinutes: Int
    var notes: String?
    var estimatedCalories: Double
    var exercises: [AgentWorkoutExerciseSnapshot]

    init(_ log: WorkoutLog) {
        date = log.date
        name = log.name
        durationMinutes = log.durationMinutes
        notes = log.notes
        estimatedCalories = log.estimatedCalories
        exercises = log.exercises
            .sorted { $0.order < $1.order }
            .map(AgentWorkoutExerciseSnapshot.init)
    }
}

struct AgentWorkoutExerciseSnapshot: Sendable {
    var name: String
    var order: Int
    var summary: String

    init(_ exercise: WorkoutExerciseEntry) {
        name = exercise.name
        order = exercise.order
        summary = exercise.summary
    }
}

struct AgentWorkoutSessionSnapshot: Sendable {
    var weekday: Int
    var name: String
    var estimatedCalories: Double
    var durationMinutes: Int
    var focus: String?
    var warmup: String?
    var progression: String?
    var notes: String?
    var exercises: [AgentWorkoutTemplateExerciseSnapshot]

    init(_ session: WorkoutSession) {
        weekday = session.weekday
        name = session.name
        estimatedCalories = session.estimatedCalories
        durationMinutes = session.durationMinutes
        focus = session.focus
        warmup = session.warmup
        progression = session.progression
        notes = session.notes
        exercises = session.sortedTemplateExercises.map(AgentWorkoutTemplateExerciseSnapshot.init)
    }
}

struct AgentWorkoutTemplateExerciseSnapshot: Sendable {
    var name: String
    var order: Int
    var sets: Int?
    var reps: String?
    var load: String?
    var rir: String?
    var rest: String?
    var sourceURL: String?
    var notes: String?

    init(_ exercise: WorkoutTemplateExercise) {
        name = exercise.name
        order = exercise.order
        sets = exercise.sets
        reps = exercise.reps
        load = exercise.load
        rir = exercise.rir
        rest = exercise.rest
        sourceURL = exercise.sourceURL
        notes = exercise.notes
    }
}

struct AgentFoodPresetSnapshot: Sendable {
    var name: String
    var brand: String
    var category: String
    var servingLabel: String
    var servingGrams: Double
    var calories: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var searchText: String
    var sortOrder: Int

    init(_ preset: FoodPreset) {
        name = preset.name
        brand = preset.brand
        category = preset.category
        servingLabel = preset.servingLabel
        servingGrams = preset.servingGrams
        calories = preset.calories
        protein = preset.protein
        carbs = preset.carbs
        fat = preset.fat
        searchText = preset.searchText
        sortOrder = preset.sortOrder
    }
}

struct AgentRecipeSnapshot: Sendable {
    var title: String
    var urlString: String
    var category: RecipeCategory
    var summary: String?
    var ingredientsText: String?
    var instructionsText: String?
    var servings: Int?
    var prepMinutes: Int?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var createdAt: Date

    init(_ recipe: Recipe) {
        title = recipe.title
        urlString = recipe.urlString
        category = recipe.category
        summary = recipe.summary
        ingredientsText = recipe.ingredientsText
        instructionsText = recipe.instructionsText
        servings = recipe.servings
        prepMinutes = recipe.prepMinutes
        calories = recipe.calories
        protein = recipe.protein
        carbs = recipe.carbs
        fat = recipe.fat
        createdAt = recipe.createdAt
    }
}
