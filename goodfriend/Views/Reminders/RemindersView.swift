import SwiftUI

struct RemindersView: View {
    @StateObject private var repo = RemindersRepository.shared
    @StateObject private var deepLinkHandler = DeepLinkHandler.shared
    @State private var selectedReminder: Reminder?

    var body: some View {
        NavigationStack {
            List {
                ForEach(repo.reminders) { reminder in
                    Button {
                        selectedReminder = reminder
                    } label: {
                        ReminderRowView(reminder: reminder)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    Task {
                        for i in indexSet {
                            try? await repo.delete(repo.reminders[i])
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .overlay {
                if repo.reminders.isEmpty {
                    ContentUnavailableView(
                        "No upcoming reminders",
                        systemImage: "bell.slash",
                        description: Text("Record a voice note mentioning a date and Goodfriend will create a reminder automatically.")
                    )
                }
            }
            .refreshable { try? await repo.fetchUpcoming() }
        }
        .sheet(item: $selectedReminder) { reminder in
            ReminderDetailView(reminder: reminder)
        }
        .task { try? await repo.fetchUpcoming() }
        .onChange(of: deepLinkHandler.pendingReminderId) { _, id in
            guard let id else { return }
            selectedReminder = repo.reminders.first { $0.id.uuidString == id }
            deepLinkHandler.pendingReminderId = nil
        }
    }
}

// MARK: – Row

struct ReminderRowView: View {
    let reminder: Reminder

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if let contact = reminder.contact {
                    Text(contact.name)
                        .font(.caption)
                        .foregroundStyle(Color.accent)
                }
                Text(reminder.title)
                    .font(.headline)
                Text(reminder.dueDate.shortFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: reminder.dueDate < Date() ? "exclamationmark.circle.fill" : "bell")
                .foregroundStyle(reminder.dueDate < Date() ? .red : .secondary)
        }
        .padding(.vertical, 4)
    }
}
