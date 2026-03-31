import Foundation

struct GiftIdea: Identifiable, Codable, Hashable {
    let id: UUID
    let contactId: UUID
    let userId: UUID
    var title: String
    var note: String?
    var source: Source
    var status: Status
    let createdAt: Date
    var updatedAt: Date

    enum Source: String, Codable {
        case manual, ai
    }

    enum Status: String, Codable {
        case saved, purchased
    }

    enum CodingKeys: String, CodingKey {
        case id, title, note, source, status
        case contactId = "contact_id"
        case userId    = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: UUID = UUID(), contactId: UUID, userId: UUID, title: String, source: Source = .manual) {
        self.id = id
        self.contactId = contactId
        self.userId = userId
        self.title = title
        self.source = source
        self.status = .saved
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
