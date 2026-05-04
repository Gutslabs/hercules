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
    var createdAt: Date

    init(
        title: String,
        urlString: String,
        category: RecipeCategory,
        createdAt: Date = .now
    ) {
        self.title = title
        self.urlString = urlString
        self.category = category
        self.createdAt = createdAt
    }

    var url: URL? { URL(string: urlString) }
}
