import SwiftUI

struct ContactsView: View {
    @StateObject private var repo = ContactsRepository.shared
    @EnvironmentObject private var authService: AuthService

    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var showImport = false
    @State private var showVoiceAssistant = false
    @State private var selectedContact: Contact?

    var filtered: [Contact] {
        guard !searchText.isEmpty else { return repo.contacts }
        return repo.contacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.joined().localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                List {
                    ForEach(filtered) { contact in
                        NavigationLink(value: contact) {
                            ContactRowView(contact: contact)
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for i in indexSet {
                                try? await repo.delete(filtered[i])
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search contacts")
                .navigationTitle("Contacts")
                .navigationDestination(for: Contact.self) { contact in
                    ContactDetailView(contact: contact)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("New contact", systemImage: "person.badge.plus") {
                                showAddContact = true
                            }
                            Button("Import from iPhone", systemImage: "square.and.arrow.down") {
                                showImport = true
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { showVoiceAssistant = true }) {
                            Image(systemName: "mic.fill.badge.ellipsis")
                        }
                    }
                }
                .refreshable { try? await repo.fetchAll() }

                // Floating voice capture button
                VoiceCaptureButton(contact: nil)
                    .padding(20)
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet()
        }
        .sheet(isPresented: $showImport) {
            ContactImportView()
        }
        .sheet(isPresented: $showVoiceAssistant) {
            VoiceAssistantView()
        }
        .task { try? await repo.fetchAll() }
    }
}

// MARK: – Row

struct ContactRowView: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(contact: contact, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.headline)

                if !contact.tags.isEmpty {
                    Text(contact.tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let latest = contact.bulletPoints.first {
                Text(latest.content)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 100, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: – Avatar

struct ContactAvatarView: View {
    let contact: Contact
    let size: CGFloat

    var body: some View {
        Group {
            if let urlStr = contact.photoUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.accent)
            }
    }

    private var initials: String {
        contact.name
            .split(separator: " ")
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

// MARK: – Add contact sheet

struct AddContactSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService
    @State private var name = ""
    @State private var tagText = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Full name", text: $name)
                }
                Section("Tags") {
                    TextField("e.g. college, NYC, client", text: $tagText)
                }
            }
            .navigationTitle("New Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let userId = authService.currentUserId else { return }
        let tags = tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let contact = Contact(userId: userId, name: name.trimmingCharacters(in: .whitespaces), tags: tags)
        isSaving = true
        Task {
            try? await ContactsRepository.shared.upsert(contact)
            isSaving = false
            dismiss()
        }
    }
}
