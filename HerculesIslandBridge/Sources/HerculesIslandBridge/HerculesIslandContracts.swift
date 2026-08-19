import Foundation

public enum HerculesIslandMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct HerculesIslandMessage: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var role: HerculesIslandMessageRole
    public var text: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: HerculesIslandMessageRole,
        text: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct HerculesIslandChatRequest: Codable, Equatable, Sendable {
    public var history: [HerculesIslandMessage]
    public var text: String
    /// JPEG bytes, already downscaled by the sender. Optional so that a client
    /// and a server updated at different times keep understanding each other:
    /// an old payload simply decodes as nil.
    public var images: [Data]?

    public init(
        history: [HerculesIslandMessage],
        text: String,
        images: [Data]? = nil
    ) {
        self.history = history
        self.text = text
        self.images = images
    }
}

public struct HerculesIslandFoodCandidate: Codable, Equatable, Sendable {
    public var saveToken: UUID?
    public var name: String
    public var grams: Double?
    public var calories: Double
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var isSaved: Bool

    public init(
        saveToken: UUID? = nil,
        name: String,
        grams: Double? = nil,
        calories: Double,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        isSaved: Bool = false
    ) {
        self.saveToken = saveToken
        self.name = name
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.isSaved = isSaved
    }
}

public struct HerculesIslandChatResponse: Codable, Equatable, Sendable {
    public var reply: String
    public var food: HerculesIslandFoodCandidate?

    public init(reply: String, food: HerculesIslandFoodCandidate? = nil) {
        self.reply = reply
        self.food = food
    }
}

public struct HerculesIslandFoodSaveRequest: Codable, Equatable, Sendable {
    public var saveToken: UUID

    public init(saveToken: UUID) {
        self.saveToken = saveToken
    }
}

public struct HerculesIslandWeightSaveRequest: Codable, Equatable, Sendable {
    public var kilograms: Double
    public var recordedAt: Date

    public init(kilograms: Double, recordedAt: Date = .now) {
        self.kilograms = kilograms
        self.recordedAt = recordedAt
    }
}

public struct HerculesIslandMutationResponse: Codable, Equatable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

public struct HerculesIslandStatusResponse: Codable, Equatable, Sendable {
    public var latestWeight: Double?
    public var latestWeightDate: Date?
    public var todayCalories: Double

    public init(
        latestWeight: Double? = nil,
        latestWeightDate: Date? = nil,
        todayCalories: Double = 0
    ) {
        self.latestWeight = latestWeight
        self.latestWeightDate = latestWeightDate
        self.todayCalories = todayCalories
    }
}
