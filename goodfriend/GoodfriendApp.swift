import SwiftUI
import Supabase
import UserNotifications

@main
struct GoodfriendApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var notificationService = NotificationService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(notificationService)
                .onOpenURL { url in
                    // Handle deep-links (e.g. reminder tap-through)
                    DeepLinkHandler.shared.handle(url)
                }
        }
    }

    init() {
        SupabaseService.configure()
    }
}

// MARK: – Root routing

struct RootView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        Group {
            switch authService.state {
            case .unauthenticated:
                SignInView()
            case .authenticated:
                MainTabView()
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut, value: authService.state)
    }
}
