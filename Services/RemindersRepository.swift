import Foundation
import Supabase

@MainActor
final class RemindersRepository: ObservableObject {
    static let shared = RemindersRepository()

    @Published var reminders: [Reminder] = []

    private var db: SupabaseClient { SupabaseService.shared.client }

    private init() {}

    func fetchUpcoming() async throws {
        let fetched: [Reminder] = try await db
            .from("reminders")
            .select()
            .eq("is_fired", value: false)
            .order("due_date")
            .execute()
            .value
        reminders = fetched
        // Reschedule all on fetch (covers reinstalls / app restarts)
        NotificationService.shared.cancelAll()
        for reminder in fetched where reminder.dueDate > Date() {
            let name = reminder.contact?.name ?? ""
            NotificationService.shared.schedule(reminder, contactName: name)
        }
    }

    func upsert(_ reminder: Reminder) async throws {
        try await db.from("reminders").upsert(reminder).execute()
        if let idx = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[idx] = reminder
        } else {
            reminders.append(reminder)
            reminders.sort { $0.dueDate < $1.dueDate }
        }
        if reminder.dueDate > Date() {
            let name = reminder.contact?.name ?? ""
            NotificationService.shared.schedule(reminder, contactName: name)
        }
    }

    func delete(_ reminder: Reminder) async throws {
        try await db.from("reminders").delete().eq("id", value: reminder.id.uuidString).execute()
        reminders.removeAll { $0.id == reminder.id }
        NotificationService.shared.cancel(reminder.id)
    }
}
