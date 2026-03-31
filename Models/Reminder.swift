import Foundation

struct Reminder: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let contactId: UUID
    var title: String
    var description: String?
    var dueDate: Date
    var isFired: Bool
    var draftMessage: String?
    let createdAt: Date
    var updatedAt: Date

    // Locally joined
    var contact: Contact?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case userId       = "user_id"
        case contactId    = "contact_id"
        case dueDate      = "due_date"
        case isFired      = "is_fired"
        case draftMessage = "draft_message"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        contactId: UUID,
        title: String,
        dueDate: Date,
        draftMessage: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.contactId = contactId
        self.title = title
        self.dueDate = dueDate
        self.draftMessage = draftMessage
        self.isFired = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
