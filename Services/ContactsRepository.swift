import Foundation
import Supabase

// MARK: – ContactsRepository

@MainActor
final class ContactsRepository: ObservableObject {
    static let shared = ContactsRepository()

    @Published var contacts: [Contact] = []

    private var db: SupabaseClient { SupabaseService.shared.client }

    private init() {}

    // ─────────────────────────────────────────
    // Fetch
    // ─────────────────────────────────────────

    func fetchAll() async throws {
        let fetched: [Contact] = try await db
            .from("contacts")
            .select()
            .order("name")
            .execute()
            .value
        contacts = fetched
    }

    func fetchContact(id: UUID) async throws -> Contact {
        var contact: Contact = try await db
            .from("contacts")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        contact.bulletPoints = try await fetchBulletPoints(contactId: id)
        contact.giftIdeas    = try await fetchGiftIdeas(contactId: id)
        return contact
    }

    // ─────────────────────────────────────────
    // Upsert / Delete
    // ─────────────────────────────────────────

    func upsert(_ contact: Contact) async throws {
        try await db.from("contacts").upsert(contact).execute()
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx] = contact
        } else {
            contacts.append(contact)
        }
    }

    func delete(_ contact: Contact) async throws {
        try await db.from("contacts").delete().eq("id", value: contact.id.uuidString).execute()
        contacts.removeAll { $0.id == contact.id }
    }

    // ─────────────────────────────────────────
    // Bullet points
    // ─────────────────────────────────────────

    func fetchBulletPoints(contactId: UUID) async throws -> [BulletPoint] {
        try await db
            .from("bullet_points")
            .select()
            .eq("contact_id", value: contactId.uuidString)
            .order("recorded_at", ascending: false)
            .execute()
            .value
    }

    func insertBulletPoints(_ points: [BulletPoint]) async throws {
        guard !points.isEmpty else { return }
        try await db.from("bullet_points").insert(points).execute()
    }

    // ─────────────────────────────────────────
    // Gift ideas
    // ─────────────────────────────────────────

    func fetchGiftIdeas(contactId: UUID) async throws -> [GiftIdea] {
        try await db
            .from("gift_ideas")
            .select()
            .eq("contact_id", value: contactId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func upsertGiftIdea(_ idea: GiftIdea) async throws {
        try await db.from("gift_ideas").upsert(idea).execute()
    }

    func deleteGiftIdea(_ idea: GiftIdea) async throws {
        try await db.from("gift_ideas").delete().eq("id", value: idea.id.uuidString).execute()
    }
}
