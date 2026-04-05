import Foundation
import Speech
import FoundationModels

// MARK: – Result types

struct ExtractionResult {
    var bulletPoints: [String]
    var reminders: [ReminderSuggestion]
    var giftIdeas: [String]
}

struct ReminderSuggestion {
    var title: String
    var dueDate: Date
    var draftMessage: String?
}

// MARK: – Generable structs for structured output

@Generable
struct ContactExtraction {
    @Guide(description: "Concise factual bullet points about the contact, each under 20 words")
    var bulletPoints: [String]

    @Guide(description: "Reminders only when a specific date or relative time is clearly mentioned")
    var reminders: [ExtractedReminder]

    @Guide(description: "Gift ideas or wishlist items mentioned, empty if none")
    var giftIdeas: [String]
}

@Generable
struct ExtractedReminder {
    @Guide(description: "Short title for the reminder")
    var title: String

    @Guide(description: "Due date in YYYY-MM-DD format")
    var dueDate: String

    @Guide(description: "Short warm iMessage-style text the user could send about this reminder")
    var draftMessage: String
}

@Generable
struct AssistantReply {
    @Guide(description: "A warm, conversational 2-4 sentence answer based on the contact information")
    var answer: String
}

// MARK: – AIService

final class AIService {
    static let shared = AIService()
    private init() {}

    // ─────────────────────────────────────────
    // Voice capture: transcribe + extract
    // ─────────────────────────────────────────

    func transcribeAndExtract(audioURL: URL, contact: Contact) async throws -> ExtractionResult {
        let transcript = try await transcribe(audioURL: audioURL)
        return try await extract(from: transcript, contact: contact)
    }

    // ─────────────────────────────────────────
    // Conversational assistant
    // ─────────────────────────────────────────

    func assistantQuery(_ query: String, contacts: [Contact]) async throws -> String {
        let contactSummaries = contacts.prefix(20).map { c in
            let bullets = c.bulletPoints.prefix(5).map { "  • \($0.content)" }.joined(separator: "\n")
            return "\(c.name) (tags: \(c.tags.joined(separator: ", ")))\n\(bullets)"
        }.joined(separator: "\n\n")

        let session = LanguageModelSession(instructions: """
            You are a warm, concise personal assistant who knows the user's contacts well.
            Here is relevant contact information:

            \(contactSummaries)

            Speak as if you know these people personally. Be helpful and specific.
            """)

        let response = try await session.respond(to: query, generating: AssistantReply.self)
        return response.content.answer
    }

    // ─────────────────────────────────────────
    // Private
    // ─────────────────────────────────────────

    func transcribe(audioURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized else {
                    continuation.resume(throwing: AIError.speechRecognitionNotAuthorized)
                    return
                }

                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
                      recognizer.isAvailable else {
                    continuation.resume(throwing: AIError.speechRecognizerUnavailable)
                    return
                }

                let request = SFSpeechURLRecognitionRequest(url: audioURL)
                request.shouldReportPartialResults = false

                recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let result, result.isFinal {
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    }
                }
            }
        }
    }

    private func extract(from transcript: String, contact: Contact) async throws -> ExtractionResult {
        let today = ISO8601DateFormatter().string(from: Date())

        let session = LanguageModelSession(instructions: """
            You are a personal CRM assistant. Today's date is \(today).
            Extract structured information from voice notes about contacts.
            Convert relative dates (e.g. "next Friday") to absolute YYYY-MM-DD dates using today's date.
            bullet_points should be factual, third-person, about \(contact.name).
            """)

        let response = try await session.respond(
            to: "Extract information from this voice note about \(contact.name): \(transcript)",
            generating: ContactExtraction.self
        )

        let extraction = response.content
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let reminders: [ReminderSuggestion] = extraction.reminders.compactMap { r in
            guard let date = df.date(from: r.dueDate) else { return nil }
            return ReminderSuggestion(title: r.title, dueDate: date, draftMessage: r.draftMessage)
        }

        return ExtractionResult(
            bulletPoints: extraction.bulletPoints,
            reminders: reminders,
            giftIdeas: extraction.giftIdeas
        )
    }
}

// MARK: – Errors

enum AIError: LocalizedError {
    case speechRecognitionNotAuthorized
    case speechRecognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .speechRecognitionNotAuthorized: return "Speech recognition permission was denied."
        case .speechRecognizerUnavailable:   return "Speech recognizer is not available on this device."
        }
    }
}
