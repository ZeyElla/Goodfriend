import Combine
import Foundation

// MARK: – Deep link routing for notification tap-through

@MainActor
final class DeepLinkHandler: ObservableObject {
    static let shared = DeepLinkHandler()

    @Published var pendingReminderId: String?

    private init() {}

    func handle(_ url: URL) {
        // Handle custom URL scheme: goodfriend://reminder/<id>
        guard url.scheme == "goodfriend", url.host == "reminder" else { return }
        let id = url.pathComponents.dropFirst().first
        pendingReminderId = id
    }

    func openReminder(id: String) {
        pendingReminderId = id
    }
}
