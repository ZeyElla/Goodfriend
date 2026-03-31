import Foundation

struct Contact: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var photoUrl: String?
    var tags: [String]
    var phone: String?
    var email: String?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    // Locally loaded relations (not stored in this table)
    var bulletPoints: [BulletPoint] = []
    var giftIdeas: [GiftIdea] = []

    enum CodingKeys: String, CodingKey {
        case id, name, phone, email, notes, tags
        case userId     = "user_id"
        case photoUrl   = "photo_url"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }

    // Initialiser used when creating a new contact locally before upsert
    init(id: UUID = UUID(), userId: UUID, name: String, tags: [String] = []) {
        self.id = id
        self.userId = userId
        self.name = name
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
