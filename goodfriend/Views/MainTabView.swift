import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var deepLinkHandler = DeepLinkHandler.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            ContactsView()
                .tabItem {
                    Label("People", systemImage: "person.2.fill")
                }
                .tag(0)

            RemindersView()
                .tabItem {
                    Label("Nudges", systemImage: "bell.fill")
                }
                .tag(1)
        }
        .tint(.accent)
        .task {
            await NotificationService.shared.requestPermission()
        }
        .onChange(of: deepLinkHandler.pendingReminderId) { _, id in
            if id != nil { selectedTab = 1 }
        }
    }
}
