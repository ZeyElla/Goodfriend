import SwiftUI

// MARK: – Result emitted after a successful capture + AI extraction

struct VoiceCaptureResult {
    var bullets: [BulletPoint]
    var giftIdeas: [GiftIdea]
    var reminders: [Reminder]
}

// MARK: – VoiceCaptureButton

/// Floating mic button. When `contact` is non-nil the extracted data is saved to that contact.
/// When `contact` is nil (from contacts list) a contact picker is shown first.

struct VoiceCaptureButton: View {
    var contact: Contact?
    var onResult: ((VoiceCaptureResult) -> Void)? = nil

    @EnvironmentObject private var authService: AuthService
    @StateObject private var captureService = VoiceCaptureService.shared
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showContactPicker = false
    @State private var pickedContact: Contact?

    var activeContact: Contact? { contact ?? pickedContact }

    var body: some View {
        ZStack {
            // Animated ring while recording
            if captureService.isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 3)
                    .scaleEffect(1 + CGFloat(captureService.audioLevel) * 0.6)
                    .animation(.easeInOut(duration: 0.1), value: captureService.audioLevel)
                    .frame(width: 66, height: 66)
            }

            Button {
                handleTap()
            } label: {
                ZStack {
                    Circle()
                        .fill(captureService.isRecording ? Color.red : Color.accent)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)

                    if isProcessing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: captureService.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(isProcessing)
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerSheet { selected in
                pickedContact = selected
                showContactPicker = false
                startRecording()
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }

    // ─────────────────────────────────────────

    private func handleTap() {
        if captureService.isRecording {
            stopAndProcess()
        } else {
            if activeContact == nil {
                showContactPicker = true
            } else {
                startRecording()
            }
        }
    }

    private func startRecording() {
        Task {
            do {
                try await captureService.startRecording()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopAndProcess() {
        guard let audioURL = captureService.stopRecording() else { return }
        guard let contact = activeContact else { return }
        guard let userId = authService.currentUserId else { return }

        isProcessing = true
        Task {
            do {
                let extraction = try await AIService.shared.transcribeAndExtract(audioURL: audioURL, contact: contact)

                // 3. Persist bullet points
                let bullets = extraction.bulletPoints.map {
                    BulletPoint(contactId: contact.id, userId: userId, content: $0, source: .voice)
                }
                try await ContactsRepository.shared.insertBulletPoints(bullets)

                // 4. Persist gift ideas
                let ideas = extraction.giftIdeas.map {
                    GiftIdea(contactId: contact.id, userId: userId, title: $0, source: .ai)
                }
                for idea in ideas { try? await ContactsRepository.shared.upsertGiftIdea(idea) }

                // 5. Persist reminders
                let reminders = extraction.reminders.map {
                    Reminder(userId: userId, contactId: contact.id, title: $0.title,
                             dueDate: $0.dueDate, draftMessage: $0.draftMessage)
                }
                for reminder in reminders { try? await RemindersRepository.shared.upsert(reminder) }

                // 6. Clean up temp file
                try? FileManager.default.removeItem(at: audioURL)

                onResult?(VoiceCaptureResult(bullets: bullets, giftIdeas: ideas, reminders: reminders))
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}

// MARK: – Contact picker sheet

private struct ContactPickerSheet: View {
    let onSelect: (Contact) -> Void

    @StateObject private var repo = ContactsRepository.shared
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var filtered: [Contact] {
        guard !searchText.isEmpty else { return repo.contacts }
        return repo.contacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { contact in
                Button {
                    onSelect(contact)
                } label: {
                    ContactRowView(contact: contact)
                }
                .tint(.primary)
            }
            .searchable(text: $searchText, prompt: "Search contacts")
            .navigationTitle("Who is this about?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
