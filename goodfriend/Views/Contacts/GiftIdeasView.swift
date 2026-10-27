import SwiftUI

struct GiftIdeasView: View {
    @Binding var contact: Contact
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService

    @State private var showAddIdea = false
    @State private var newIdeaTitle = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(contact.giftIdeas) { idea in
                    HStack(spacing: 12) {
                        Image(systemName: idea.status == .purchased ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(idea.status == .purchased ? .green : .secondary)
                            .onTapGesture { toggleStatus(idea) }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(idea.title)
                                .strikethrough(idea.status == .purchased)
                                .foregroundStyle(idea.status == .purchased ? .secondary : .primary)

                            if let note = idea.note {
                                Text(note).font(.caption).foregroundStyle(.tertiary)
                            }

                            HStack {
                                if idea.source == .ai {
                                    Label("AI", systemImage: "sparkles")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accent)
                                }
                                Text(idea.createdAt.relativeFormatted)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        let idea = contact.giftIdeas[i]
                        Task { try? await ContactsRepository.shared.deleteGiftIdea(idea) }
                    }
                    contact.giftIdeas.remove(atOffsets: indexSet)
                }
            }
            .navigationTitle("Gift Ideas — \(contact.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Add", systemImage: "plus") { showAddIdea = true }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if contact.giftIdeas.isEmpty {
                    ContentUnavailableView(
                        "No gift ideas yet",
                        systemImage: "gift",
                        description: Text("Add ideas manually or record a voice note mentioning gift ideas.")
                    )
                }
            }
        }
        .sheet(isPresented: $showAddIdea) {
            addIdeaSheet
        }
    }

    private var addIdeaSheet: some View {
        NavigationStack {
            Form {
                TextField("Idea title", text: $newIdeaTitle)
            }
            .navigationTitle("New Gift Idea")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddIdea = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveIdea() }
                        .disabled(newIdeaTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveIdea() {
        guard let userId = authService.currentUserId else { return }
        let idea = GiftIdea(contactId: contact.id, userId: userId, title: newIdeaTitle.trimmingCharacters(in: .whitespaces))
        contact.giftIdeas.insert(idea, at: 0)
        Task { try? await ContactsRepository.shared.upsertGiftIdea(idea) }
        newIdeaTitle = ""
        showAddIdea = false
    }

    private func toggleStatus(_ idea: GiftIdea) {
        guard let idx = contact.giftIdeas.firstIndex(where: { $0.id == idea.id }) else { return }
        let newStatus: GiftIdea.Status = idea.status == .saved ? .purchased : .saved
        contact.giftIdeas[idx].status = newStatus
        let updated = contact.giftIdeas[idx]
        Task { try? await ContactsRepository.shared.upsertGiftIdea(updated) }
    }
}
