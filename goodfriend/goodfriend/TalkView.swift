import SwiftUI

// MARK: – Talk it through
//
// One screen: you type or dictate freely. On submit the on-device AI decides
// whether you're ASKING about someone (→ show a quick bio) or TELLING an update
// (→ file notes under the matched person, creating them if new). Not a chat —
// each submission is a one-shot.

struct TalkView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @StateObject private var repo = ContactsRepository.shared
    @StateObject private var captureService = VoiceCaptureService.shared

    @State private var text = ""
    @State private var phase: Phase = .input
    @State private var outcome: Outcome?
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    enum Phase: Equatable { case input, transcribing, thinking, done }

    enum Outcome {
        case answer(person: String, text: String)
        case recorded(person: String, isNew: Bool, noteCount: Int, nudgeCount: Int)
        case nobody
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let outcome {
                    resultView(outcome)
                    Spacer()
                    Button("New entry") { reset() }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 24)
                } else {
                    editor
                    controls
                }
            }
            .padding()
            .navigationTitle("Talk it through")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        _ = captureService.stopRecording()
                        dismiss()
                    }
                }
            }
            .task { focused = true }
        }
    }

    // MARK: – Input

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("What happened? Or ask for the latest on someone…")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            // Dictate toggle
            Button {
                toggleDictation()
            } label: {
                Image(systemName: captureService.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(captureService.isRecording ? .red : Color.accent)
            }
            .disabled(phase == .transcribing || phase == .thinking)

            Spacer()

            if phase == .transcribing || phase == .thinking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(phase == .transcribing ? "taking it down…" : "reading it back…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    submit(text)
                } label: {
                    Label("Save", systemImage: "arrow.up.circle.fill")
                        .font(.headline)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    // MARK: – Result

    @ViewBuilder
    private func resultView(_ outcome: Outcome) -> some View {
        switch outcome {
        case let .answer(person, answer):
            VStack(alignment: .leading, spacing: 12) {
                Text(person).font(.title2.bold())
                Text(answer).font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)

        case let .recorded(person, isNew, noteCount, nudgeCount):
            VStack(alignment: .leading, spacing: 10) {
                Label("Saved to \(person)\(isNew ? " (new)" : "")", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("\(noteCount) note\(noteCount == 1 ? "" : "s")"
                     + (nudgeCount > 0 ? " · \(nudgeCount) nudge\(nudgeCount == 1 ? "" : "s")" : ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)

        case .nobody:
            Text("I couldn't tell who that was about. Mention a name and try again.")
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }

    // MARK: – Dictation

    private func toggleDictation() {
        if captureService.isRecording {
            guard let url = captureService.stopRecording() else { return }
            phase = .transcribing
            Task {
                do {
                    let spoken = try await AIService.shared.transcribe(audioURL: url)
                    try? FileManager.default.removeItem(at: url)
                    text = text.isEmpty ? spoken : text + " " + spoken
                    phase = .input
                } catch {
                    errorMessage = error.localizedDescription
                    phase = .input
                }
            }
        } else {
            focused = false
            Task { try? await captureService.startRecording() }
        }
    }

    // MARK: – Submit

    private func submit(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        guard let userId = authService.currentUserId else {
            errorMessage = "Not signed in."
            return
        }
        focused = false
        phase = .thinking

        Task {
            do {
                let result = try await AIService.shared.interpret(input)
                let name = result.personName.trimmingCharacters(in: .whitespaces)

                guard !name.isEmpty else {
                    outcome = .nobody
                    phase = .done
                    return
                }

                let match = matchContact(named: name)

                if result.isQuestion {
                    // Quick bio: lean on the existing recap over the matched person.
                    if let match {
                        let full = (try? await repo.fetchContact(id: match.id)) ?? match
                        let answer = try await AIService.shared.recap(for: full)
                        outcome = .answer(person: full.name, text: answer)
                    } else {
                        outcome = .answer(person: name,
                                          text: "I don't have anyone named \(name) yet.")
                    }
                    phase = .done
                    return
                }

                // Recording an update → resolve (or create) the person, then file notes.
                let contact: Contact
                let isNew: Bool
                if let match {
                    contact = match
                    isNew = false
                } else {
                    contact = Contact(userId: userId, name: name)
                    try await repo.upsert(contact)
                    isNew = true
                }

                let notes = result.notes.map {
                    BulletPoint(contactId: contact.id, userId: userId, content: $0,
                                source: .voice, kind: .note)
                }
                try await repo.insertBulletPoints(notes)

                let nudges = AIService.shared.reminderSuggestions(from: result.reminders)
                for n in nudges {
                    let reminder = Reminder(userId: userId, contactId: contact.id,
                                            title: n.title, dueDate: n.dueDate,
                                            draftMessage: n.draftMessage)
                    try? await RemindersRepository.shared.upsert(reminder)
                }

                outcome = .recorded(person: contact.name, isNew: isNew,
                                    noteCount: notes.count, nudgeCount: nudges.count)
                phase = .done
            } catch {
                errorMessage = error.localizedDescription
                phase = .input
            }
        }
    }

    /// Case-insensitive match on full name or first name.
    private func matchContact(named name: String) -> Contact? {
        let lower = name.lowercased()
        if let exact = repo.contacts.first(where: { $0.name.lowercased() == lower }) {
            return exact
        }
        return repo.contacts.first {
            $0.name.lowercased().split(separator: " ").first.map(String.init) == lower
        }
    }

    private func reset() {
        text = ""
        outcome = nil
        errorMessage = nil
        phase = .input
        focused = true
    }
}
