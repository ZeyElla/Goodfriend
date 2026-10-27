import SwiftUI

// MARK: – Hands-free voice assistant

struct VoiceAssistantView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var captureService = VoiceCaptureService.shared
    @StateObject private var ttsService    = SpeechSynthesisService.shared
    @StateObject private var repo          = ContactsRepository.shared

    @State private var phase: Phase = .idle
    @State private var transcript = ""
    @State private var response   = ""

    enum Phase: Equatable {
        case idle, recording, transcribing, thinking, speaking
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Waveform / status indicator
                ZStack {
                    // Background pulse circle
                    SwiftUI.Circle()
                        .fill(phaseColor.opacity(0.15))
                        .frame(width: 140, height: 140)
                        .scaleEffect(phase == .recording
                            ? 1 + CGFloat(captureService.audioLevel) * 0.4
                            : (ttsService.isSpeaking ? 1.15 : 1.0))
                        .animation(Animation.easeInOut(duration: 0.12), value: captureService.audioLevel)
                        .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                                   value: ttsService.isSpeaking)

                    Image(systemName: phaseIcon)
                        .font(.system(size: 48))
                        .foregroundStyle(phaseColor)
                }

                Text(phaseLabel)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // Response text
                if !response.isEmpty {
                    ScrollView {
                        Text(response)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .frame(maxHeight: 200)
                }

                Spacer()

                // Main button
                Button {
                    handleMainButton()
                } label: {
                    Label(phase == .idle ? "Ask something…" : "Stop", systemImage: phase == .idle ? "mic" : "stop.fill")
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(phase == .idle ? Color.accent : Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(phase == .transcribing || phase == .thinking)
                .padding(.bottom, 40)
            }
            .padding()
            .navigationTitle("Assistant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        ttsService.stop()
                        _ = captureService.stopRecording()
                        dismiss()
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────

    private func handleMainButton() {
        switch phase {
        case .idle:
            startListening()
        case .recording:
            stopAndQuery()
        case .speaking:
            ttsService.stop()
            phase = .idle
        default:
            break
        }
    }

    private func startListening() {
        Task {
            try? await captureService.startRecording()
            phase = .recording
        }
    }

    private func stopAndQuery() {
        guard let audioURL = captureService.stopRecording() else { phase = .idle; return }
        phase = .transcribing

        Task {
            do {
                let query = try await AIService.shared.transcribe(audioURL: audioURL)
                transcript = query
                try? FileManager.default.removeItem(at: audioURL)

                phase = .thinking
                let answer = try await AIService.shared.assistantQuery(query, contacts: repo.contacts)
                response = answer

                phase = .speaking
                ttsService.speak(answer)

                // Wait for speech to finish
                while ttsService.isSpeaking { try? await Task.sleep(for: .milliseconds(200)) }
                phase = .idle
            } catch {
                response = "Sorry, something went wrong."
                phase = .idle
            }
        }
    }

    // ─────────────────────────────────────────

    private var phaseColor: Color {
        switch phase {
        case .idle:         return .accent
        case .recording:    return .red
        case .transcribing: return .orange
        case .thinking:     return .purple
        case .speaking:     return .green
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .idle:         return "mic"
        case .recording:    return "waveform"
        case .transcribing: return "ellipsis"
        case .thinking:     return "brain"
        case .speaking:     return "speaker.wave.3.fill"
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .idle:         return "Tap to ask"
        case .recording:    return "Listening…"
        case .transcribing: return "Transcribing…"
        case .thinking:     return "Thinking…"
        case .speaking:     return "Speaking…"
        }
    }
}
