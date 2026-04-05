import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    // ─────────────────────────────────────────
    // Permission
    // ─────────────────────────────────────────

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // ─────────────────────────────────────────
    // Local notification scheduling
    // ─────────────────────────────────────────

    func schedule(_ reminder: Reminder, contactName: String) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = contactName.isEmpty ? "" : "About \(contactName)"
        content.sound = .default
        content.userInfo = ["reminderId": reminder.id.uuidString]

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    func cancel(_ reminderId: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [reminderId.uuidString])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // ─────────────────────────────────────────
    // Foreground delivery
    // ─────────────────────────────────────────

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let reminderId = response.notification.request.content.userInfo["reminderId"] as? String
        Task { @MainActor in
            if let id = reminderId {
                DeepLinkHandler.shared.openReminder(id: id)
            }
        }
        completionHandler()
    }
}
