import SwiftData
import Foundation

@Model
final class UserGuideSection {
    var title: String
    var subtitle: String
    var iconName: String
    var colorName: String
    var sortIndex: Int
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \UserGuideCard.section)
    var cards: [UserGuideCard]

    init(title: String = "", subtitle: String = "", iconName: String = "book.closed", colorName: String = "blue") {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.colorName = colorName
        self.sortIndex = 0
        self.createdAt = .now
        self.cards = []
    }
}

@Model
final class UserGuideCard {
    var cardTitle: String
    var body: String
    var sortIndex: Int
    var isTable: Bool
    var headersJSON: String
    var rowsJSON: String
    var section: UserGuideSection?

    init(cardTitle: String = "", body: String = "", sortIndex: Int = 0) {
        self.cardTitle = cardTitle
        self.body = body
        self.sortIndex = sortIndex
        self.isTable = false
        self.headersJSON = "[]"
        self.rowsJSON = "[]"
    }

    // MARK: - Table helpers

    var headers: [String] {
        get { decode([String].self, from: headersJSON) ?? [] }
        set { headersJSON = encode(newValue) }
    }

    var rows: [[String]] {
        get { decode([[String]].self, from: rowsJSON) ?? [] }
        set { rowsJSON = encode(newValue) }
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }
}
