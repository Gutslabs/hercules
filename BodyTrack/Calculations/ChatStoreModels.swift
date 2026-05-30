import Foundation

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
