import Foundation

struct Contact: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    /// Freeform "where you know them from" line, e.g. "Barista at Blue Bottle".
    var context: String?
    var photoUrl: String?
    var tags: [String]
    var phone: String?
    var email: String?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    // Locally loaded relations (not stored in the contacts table)
    var bulletPoints: [BulletPoint] = []
    var giftIdeas: [GiftIdea] = []

    // MARK: – Journal helpers

    /// Persistent facts shown at the top of a profile ("Fiancé: Sean").
    var keyFacts: [BulletPoint] { bulletPoints.filter { $0.kind == .keyFact } }

    /// Dated journal entries, newest first.
    var journalEntries: [BulletPoint] {
        bulletPoints.filter { $0.kind == .note }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// When we last logged anything about this person (drives "3d ago").
    var lastContactAt: Date? { bulletPoints.map(\.recordedAt).max() }

    // MARK: – Codable

    // Used for encoding (upsert) — deliberately omits the loaded relations.
    enum CodingKeys: String, CodingKey {
        case id, name, context, phone, email, notes, tags
        case userId     = "user_id"
        case photoUrl   = "photo_url"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }

    // Used for decoding — additionally pulls in embedded bullet_points when present.
    private enum ReadKeys: String, CodingKey {
        case id, name, context, phone, email, notes, tags
        case userId       = "user_id"
        case photoUrl     = "photo_url"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
        case bulletPoints = "bullet_points"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ReadKeys.self)
        id        = try c.decode(UUID.self, forKey: .id)
        userId    = try c.decode(UUID.self, forKey: .userId)
        name      = try c.decode(String.self, forKey: .name)
        context   = try c.decodeIfPresent(String.self, forKey: .context)
        photoUrl  = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        tags      = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        phone     = try c.decodeIfPresent(String.self, forKey: .phone)
        email     = try c.decodeIfPresent(String.self, forKey: .email)
        notes     = try c.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        bulletPoints = (try? c.decode([BulletPoint].self, forKey: .bulletPoints)) ?? []
        giftIdeas = []
    }

    // Initialiser used when creating a new contact locally before upsert
    init(id: UUID = UUID(), userId: UUID, name: String, context: String? = nil, tags: [String] = []) {
        self.id = id
        self.userId = userId
        self.name = name
        self.context = context?.isEmpty == true ? nil : context
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
