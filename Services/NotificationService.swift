import Foundation
import UserNotifications
import Supabase

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var db: SupabaseClient { SupabaseService.shared.client }

    private override init() {
        super.init()
        center.delegate = self
    }

    // ─────────────────────────────────────────
    // Permission + token registration
    // ─────────────────────────────────────────

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Call this from your AppDelegate/scene callback after APNs registers.
    func registerDeviceToken(_ tokenData: Data, userId: UUID) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()

        struct TokenRow: Encodable {
            let user_id: String
            let token: String
            let platform: String
        }

        try? await db
            .from("device_tokens")
            .upsert(TokenRow(user_id: userId.uuidString, token: token, platform: "ios"),
                    onConflict: "token")
            .execute()
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
