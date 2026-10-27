import Foundation

struct BulletPoint: Identifiable, Codable, Hashable {
    let id: UUID
    let contactId: UUID
    let userId: UUID
    var content: String
    var source: Source
    var kind: Kind
    var recordedAt: Date
    let createdAt: Date

    enum Source: String, Codable {
        case voice, manual
    }

    /// Distinguishes a persistent key fact ("Fiancé: Sean") from a dated journal entry.
    enum Kind: String, Codable {
        case keyFact = "key_fact"
        case note
    }

    enum CodingKeys: String, CodingKey {
        case id, content, source, kind
        case contactId  = "contact_id"
        case userId     = "user_id"
        case recordedAt = "recorded_at"
        case createdAt  = "created_at"
    }

    init(id: UUID = UUID(), contactId: UUID, userId: UUID, content: String,
         source: Source = .voice, kind: Kind = .note) {
        self.id = id
        self.contactId = contactId
        self.userId = userId
        self.content = content
        self.source = source
        self.kind = kind
        self.recordedAt = Date()
        self.createdAt = Date()
    }
}
