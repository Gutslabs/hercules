import Foundation
import SwiftData

enum RecipeCategory: String, Codable, CaseIterable, Identifiable {
    case breakfast, dinner, dessert

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Kahvaltı"
        case .dinner: return "Akşam Yemeği"
        case .dessert: return "Tatlı"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .dessert: return "birthday.cake.fill"
        }
    }
}

@Model
final class Recipe {
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

    init(
        title: String,
        urlString: String,
        category: RecipeCategory,
        summary: String? = nil,
        ingredientsText: String? = nil,
        instructionsText: String? = nil,
        servings: Int? = nil,
        prepMinutes: Int? = nil,
        calories: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        createdAt: Date = .now
    ) {
        self.title = title
        self.urlString = urlString
        self.category = category
        self.summary = summary
        self.ingredientsText = ingredientsText
        self.instructionsText = instructionsText
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.createdAt = createdAt
    }

    var url: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    var hasDetail: Bool {
        [summary, ingredientsText, instructionsText].contains { value in
            !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}
