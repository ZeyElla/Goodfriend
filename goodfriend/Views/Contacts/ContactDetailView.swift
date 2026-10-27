import SwiftUI

struct ContactDetailView: View {
    @State private var contact: Contact
    @State private var isLoadingDetail = false
    @State private var showAddNote = false
    @State private var showRecap = false

    @EnvironmentObject private var authService: AuthService

    init(contact: Contact) {
        _contact = State(initialValue: contact)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Divider().padding(.horizontal)

                actions

                if !contact.keyFacts.isEmpty {
                    Divider().padding(.horizontal)
                    keyFactsSection
                }

                Divider().padding(.horizontal)

                notesSection
            }
        }
        .navigationTitle(contact.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay(alignment: .bottomTrailing) {
            // "Write an entry" — spoken brain-dump
            VoiceCaptureButton(contact: contact) { result in
                contact.bulletPoints.insert(contentsOf: result.bullets, at: 0)
            }
            .padding(20)
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteSheet(contact: contact) { newBullet in
                contact.bulletPoints.insert(newBullet, at: 0)
            }
        }
        .sheet(isPresented: $showRecap) {
            RecapSheet(contact: contact)
        }
        .task { await loadDetail() }
    }

    // MARK: – Sections

    private var header: some View {
        HStack(spacing: 16) {
            ContactAvatarView(contact: contact, size: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text(contact.name)
                    .font(.title2.bold())

                if let context = contact.context, !context.isEmpty {
                    Text(context)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let last = contact.lastContactAt {
                    Text("Last talked \(last.relativeFormatted)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                showRecap = true
            } label: {
                Label("Recap", systemImage: "book.closed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showAddNote = true
            } label: {
                Label("Add note", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }

    private var keyFactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Key facts")
                .font(.headline)
                .padding(.horizontal)

            ForEach(contact.keyFacts) { fact in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Color.accent)
                        .padding(.top, 6)
                    Text(fact.content)
                        .font(.subheadline)
                }
                .padding(.horizontal)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.headline)
                .padding(.horizontal)

            if contact.journalEntries.isEmpty {
                Text("No entries yet. Tap the mic to write one, or add a note.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(contact.journalEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.content)
                            .font(.subheadline)
                        Text(entry.recordedAt.relativeFormatted)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func loadDetail() async {
        guard !isLoadingDetail else { return }
        isLoadingDetail = true
        if let loaded = try? await ContactsRepository.shared.fetchContact(id: contact.id) {
            contact = loaded
        }
        isLoadingDetail = false
    }
}

// MARK: – Add note sheet

struct AddNoteSheet: View {
    let contact: Contact
    var onSave: (BulletPoint) -> Void

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isKeyFact = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section {
                    Toggle("Save as a key fact", isOn: $isKeyFact)
                } footer: {
                    Text("Key facts stay pinned at the top of the profile. Notes are dated entries.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Add note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let userId = authService.currentUserId else {
            errorMessage = "Not signed in."
            return
        }
        let bullet = BulletPoint(
            contactId: contact.id,
            userId: userId,
            content: text.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .manual,
            kind: isKeyFact ? .keyFact : .note
        )
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await ContactsRepository.shared.insertBulletPoints([bullet])
                onSave(bullet)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: – Recap ("Turn back a page")

struct RecapSheet: View {
    let contact: Contact
    @Environment(\.dismiss) private var dismiss

    @State private var recap: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let recap {
                        Text("The story so far")
                            .font(.title3.italic())
                        Text(recap)
                            .font(.body)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text("turning back a few pages…")
                            .font(.body.italic())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(contact.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadRecap() }
        }
    }

    private func loadRecap() async {
        do {
            // Ensure we have the full set of facts + entries loaded.
            let full = (try? await ContactsRepository.shared.fetchContact(id: contact.id)) ?? contact
            recap = try await AIService.shared.recap(for: full)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: – Inline tag flow

struct FlowLayout: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accent)
                    .clipShape(Capsule())
            }
        }
    }
}
