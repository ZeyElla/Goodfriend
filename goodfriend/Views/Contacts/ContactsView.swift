import SwiftUI

struct ContactsView: View {
    @StateObject private var repo = ContactsRepository.shared
    @EnvironmentObject private var authService: AuthService

    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var showImport = false
    // Talk-it-through screen temporarily disabled — its dictation currently
    // behaves like plain voice-to-text. Re-enable TalkView when it adds more.
    // @State private var showTalk = false
    @State private var selectedContact: Contact?
    @State private var graphSelection: Contact?
    @State private var viewMode: ViewMode = .cloud

    enum ViewMode { case list, cloud }

    var filtered: [Contact] {
        guard !searchText.isEmpty else { return repo.contacts }
        return repo.contacts.filter { contact in
            let haystack = ([contact.name, contact.context ?? ""]
                + contact.tags
                + contact.bulletPoints.map(\.content)).joined(separator: " ")
            return AliasSearch.matches(query: searchText, haystack: haystack)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    switch viewMode {
                    case .cloud:
                        PeopleCloudView(contacts: filtered) { graphSelection = $0 }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    case .list:
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
                        .refreshable { try? await repo.fetchAll() }
                        .transition(.opacity)
                    }
                }
                .searchable(text: $searchText, prompt: "Search names, facts, notes")
                .navigationTitle("goodfriend")
                .navigationDestination(for: Contact.self) { contact in
                    ContactDetailView(contact: contact)
                }
                .navigationDestination(item: $graphSelection) { contact in
                    ContactDetailView(contact: contact)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
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
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                                viewMode = viewMode == .cloud ? .list : .cloud
                            }
                        } label: {
                            Image(systemName: viewMode == .cloud ? "list.bullet" : "circle.hexagongrid")
                        }
                    }
                }

                // Floating talk-it-through button — temporarily disabled.
                // Re-enable alongside TalkView() and the showTalk state/sheet.
                // Button {
                //     showTalk = true
                // } label: {
                //     Image(systemName: "mic.fill")
                //         .font(.system(size: 22))
                //         .foregroundStyle(.white)
                //         .frame(width: 56, height: 56)
                //         .background(Color.accent)
                //         .clipShape(SwiftUI.Circle())
                //         .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                // }
                // .padding(20)
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet()
        }
        .sheet(isPresented: $showImport) {
            ContactImportView()
        }
        // .sheet(isPresented: $showTalk) {
        //     TalkView()
        // }
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

                if let subtitle = contact.context ?? (contact.tags.isEmpty ? nil : contact.tags.joined(separator: " · ")) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let last = contact.lastContactAt {
                Text(last.relativeFormatted)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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
        .clipShape(SwiftUI.Circle())
    }

    private var initialsView: some View {
        SwiftUI.Circle()
            .fill(Color.accentColor.opacity(0.15))
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Color.accent)
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
    @State private var context = ""
    @State private var selectedChips: Set<String> = []
    @State private var keyFactsText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let chips = ["Barista", "Gym", "Work", "Neighbor", "Friend"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First name", text: $name)
                }
                Section("Where you know them from") {
                    TextField("e.g. Barista at Blue Bottle", text: $context)
                    chipRow
                }
                Section {
                    TextField("One per line", text: $keyFactsText, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Key facts (optional)")
                } footer: {
                    Text("e.g. Fiancé: Sean")
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New person")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

    private var chipRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                let isOn = selectedChips.contains(chip)
                Button {
                    if isOn { selectedChips.remove(chip) } else { selectedChips.insert(chip) }
                } label: {
                    Text(chip)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
                        .foregroundStyle(isOn ? Color.accent : Color.secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        guard let userId = authService.currentUserId else {
            errorMessage = "Not signed in (userId is nil)"
            return
        }
        let tags = Array(selectedChips)
        let contact = Contact(
            userId: userId,
            name: name.trimmingCharacters(in: .whitespaces),
            context: context.trimmingCharacters(in: .whitespaces),
            tags: tags
        )
        let keyFacts = keyFactsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { BulletPoint(contactId: contact.id, userId: userId, content: $0, source: .manual, kind: .keyFact) }

        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await ContactsRepository.shared.upsert(contact)
                try await ContactsRepository.shared.insertBulletPoints(keyFacts)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
