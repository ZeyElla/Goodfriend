import Combine
import Foundation
import Supabase

@MainActor
final class CirclesRepository: ObservableObject {
    static let shared = CirclesRepository()

    @Published var circles: [Circle] = []

    private var db: SupabaseClient { SupabaseService.shared.client }

    private init() {}

    func fetchAll() async throws {
        let fetched: [Circle] = try await db
            .from("circles")
            .select()
            .order("name")
            .execute()
            .value
        circles = fetched
    }

    func upsert(_ circle: Circle) async throws {
        try await db.from("circles").upsert(circle).execute()
        if let idx = circles.firstIndex(where: { $0.id == circle.id }) {
            circles[idx] = circle
        } else {
            circles.append(circle)
        }
    }

    func delete(_ circle: Circle) async throws {
        try await db.from("circles").delete().eq("id", value: circle.id.uuidString).execute()
        circles.removeAll { $0.id == circle.id }
    }

    func addMember(contactId: UUID, toCircle circleId: UUID, userId: UUID, parentContactId: UUID? = nil) async throws {
        let member = CircleMember(circleId: circleId, contactId: contactId, userId: userId, parentContactId: parentContactId)
        try await db.from("circle_members").upsert(member).execute()
    }

    func removeMember(contactId: UUID, fromCircle circleId: UUID) async throws {
        try await db.from("circle_members")
            .delete()
            .eq("circle_id", value: circleId.uuidString)
            .eq("contact_id", value: contactId.uuidString)
            .execute()
    }

    // Auto-assign a contact to any circles whose name matches one of the contact's tags.
    func autoAssign(contact: Contact) async {
        try? await fetchAll()
        print("🔄 autoAssign: \(circles.count) circles, contact tags: \(contact.tags)")
        let matchingCircles = circles.filter { circle in
            contact.tags.contains { $0.lowercased() == circle.name.lowercased() }
        }
        print("🎯 matched circles: \(matchingCircles.map(\.name))")
        for circle in matchingCircles {
            do {
                try await addMember(contactId: contact.id, toCircle: circle.id, userId: contact.userId)
                print("✅ added \(contact.name) to \(circle.name)")
            } catch {
                print("❌ addMember failed: \(error)")
            }
        }
    }

    // Auto-assign all contacts whose tags match a newly created circle's name.
    func autoAssign(circle: Circle, contacts: [Contact]) async {
        let matching = contacts.filter { contact in
            contact.tags.contains { $0.lowercased() == circle.name.lowercased() }
        }
        for contact in matching {
            try? await addMember(contactId: contact.id, toCircle: circle.id, userId: contact.userId)
        }
    }

    func fetchMembers(forCircle circleId: UUID) async throws -> [Contact] {
        // Join circle_members → contacts
        struct Row: Decodable {
            let contacts: Contact
            enum CodingKeys: String, CodingKey { case contacts }
        }
        let rows: [Row] = try await db
            .from("circle_members")
            .select("contacts(*)")
            .eq("circle_id", value: circleId.uuidString)
            .execute()
            .value
        return rows.map(\.contacts)
    }
}
