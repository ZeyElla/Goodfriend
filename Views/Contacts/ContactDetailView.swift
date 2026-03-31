import SwiftUI

struct ContactDetailView: View {
    @State private var contact: Contact
    @State private var isLoadingDetail = false
    @State private var showGiftIdeas = false
    @State private var showVoiceCapture = false

    init(contact: Contact) {
        _contact = State(initialValue: contact)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    ContactAvatarView(contact: contact, size: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(contact.name)
                            .font(.title2.bold())

                        if !contact.tags.isEmpty {
                            FlowLayout(tags: contact.tags)
                        }

                        if let phone = contact.phone {
                            Label(phone, systemImage: "phone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding()

                Divider().padding(.horizontal)

                // Bullet points feed
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notes")
                        .font(.headline)
                        .padding(.horizontal)

                    if contact.bulletPoints.isEmpty {
                        Text("No notes yet. Tap the mic to add some.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(contact.bulletPoints) { bp in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.accent)
                                    .padding(.top, 5)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bp.content)
                                        .font(.subheadline)
                                    Text(bp.recordedAt.relativeFormatted)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                Divider().padding(.horizontal)

                // Gift ideas preview
                Button {
                    showGiftIdeas = true
                } label: {
                    HStack {
                        Label("Gift Ideas", systemImage: "gift")
                            .font(.headline)
                        Spacer()
                        Text("\(contact.giftIdeas.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            VoiceCaptureButton(contact: contact) { result in
                // Merge new bullets + gift ideas + reminders into contact
                contact.bulletPoints.insert(contentsOf: result.bullets, at: 0)
                contact.giftIdeas.insert(contentsOf: result.giftIdeas, at: 0)
            }
            .padding(20)
        }
        .sheet(isPresented: $showGiftIdeas) {
            GiftIdeasView(contact: $contact)
        }
        .task { await loadDetail() }
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

// MARK: – Inline tag flow

struct FlowLayout: View {
    let tags: [String]

    var body: some View {
        // Simple wrapping using LazyVGrid for iOS 16+
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.accent)
                    .clipShape(Capsule())
            }
        }
    }
}
