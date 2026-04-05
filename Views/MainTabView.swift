import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var deepLinkHandler = DeepLinkHandler.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            ContactsView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2.fill")
                }
                .tag(0)

            CirclesView()
                .tabItem {
                    Label("Circles", systemImage: "circle.hexagongrid.fill")
                }
                .tag(1)

            RemindersView()
                .tabItem {
                    Label("Reminders", systemImage: "bell.fill")
                }
                .tag(2)
        }
        .tint(.accent)
        .task {
            await NotificationService.shared.requestPermission()
        }
        .onChange(of: deepLinkHandler.pendingReminderId) { _, id in
            if id != nil { selectedTab = 2 }
        }
    }
}
