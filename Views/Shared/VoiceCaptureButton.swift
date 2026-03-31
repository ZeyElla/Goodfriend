import SwiftUI

// MARK: – Result emitted after a successful capture + AI extraction

struct VoiceCaptureResult {
    var bullets: [BulletPoint]
    var giftIdeas: [GiftIdea]
    var reminders: [Reminder]
}

// MARK: – VoiceCaptureButton

/// Floating mic button. When `contact` is non-nil the extracted data is saved to that contact.
/// When `contact` is nil (from contacts list) the user must confirm which contact first — for now
/// we show a contact picker (stubbed here, wire up ContactsRepository.shared.contacts).

struct VoiceCaptureButton: View {
    var contact: Contact?
    var onResult: ((VoiceCaptureResult) -> Void)? = nil

    @EnvironmentObject private var authService: AuthService
    @StateObject private var captureService = VoiceCaptureService.shared
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showContactPicker = false

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
            if contact == nil {
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
        guard let contact else { return }
        guard let userId = authService.currentUserId else { return }

        isProcessing = true
        Task {
            do {
                // 1. Transcribe via Whisper
                let transcript = try await OpenAIService.shared.transcribe(audioURL: audioURL)

                // 2. Extract via Claude
                let extraction = try await ClaudeService.shared.extractFromTranscript(transcript, contact: contact)

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
