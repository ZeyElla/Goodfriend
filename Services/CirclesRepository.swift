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
