import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

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
    }
}
