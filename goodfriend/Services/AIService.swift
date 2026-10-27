import Foundation
import Speech
import FoundationModels

// MARK: – Result types

struct ExtractionResult {
    var bulletPoints: [String]
    var reminders: [ReminderSuggestion]
}

struct ReminderSuggestion {
    var title: String
    var dueDate: Date
    var draftMessage: String?
}

// MARK: – Generable structs for structured output

@Generable
struct ContactExtraction {
    @Guide(description: "Concise factual journal notes about the person, each under 20 words. Include anything mentioned — details, gifts they'd like, things going on in their life.")
    var bulletPoints: [String]

    @Guide(description: "Check-in nudges, only when a specific date or relative time is clearly mentioned (e.g. an interview, trip, birthday)")
    var reminders: [ExtractedReminder]
}

@Generable
struct ExtractedReminder {
    @Guide(description: "A gentle check-in prompt, e.g. 'Sam had an interview today — want to check in?'")
    var title: String

    @Guide(description: "Due date in YYYY-MM-DD format")
    var dueDate: String

    @Guide(description: "Short warm iMessage-style text the user could send to check in")
    var draftMessage: String
}

@Generable
struct AssistantReply {
    @Guide(description: "A warm, conversational 2-4 sentence answer based on the contact information")
    var answer: String
}

@Generable
struct FreeformInterpretation {
    @Guide(description: "true if the user is ASKING for information about someone; false if they are TELLING you an update to record")
    var isQuestion: Bool

    @Guide(description: "The name of the person this is about; empty string if no person is mentioned")
    var personName: String

    @Guide(description: "When recording an update: concise, factual third-person notes about the person, each under 20 words. Empty when asking a question.")
    var notes: [String]

    @Guide(description: "When recording: check-in nudges, only when a specific date or relative time is clearly mentioned")
    var reminders: [ExtractedReminder]
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
    // Freeform capture: is this a question or an update, and who about?
    // ─────────────────────────────────────────

    func interpret(_ text: String) async throws -> FreeformInterpretation {
        let today = ISO8601DateFormatter().string(from: Date())

        let session = LanguageModelSession(instructions: """
            You process quick journal inputs about the people in someone's life. Today's date is \(today).
            Decide whether the user is ASKING for an update about a person (isQuestion = true) or
            TELLING you something to record about them (isQuestion = false).
            Always identify the person's name if one is mentioned.
            When recording, extract concise factual notes and any date-bound check-in nudges,
            converting relative dates (e.g. "next Friday") to absolute YYYY-MM-DD dates.
            """)

        let response = try await session.respond(to: text, generating: FreeformInterpretation.self)
        return response.content
    }

    func reminderSuggestions(from extracted: [ExtractedReminder]) -> [ReminderSuggestion] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return extracted.compactMap { r in
            guard let date = df.date(from: r.dueDate) else { return nil }
            return ReminderSuggestion(title: r.title, dueDate: date, draftMessage: r.draftMessage)
        }
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
            You help keep a personal journal about the people in someone's life. Today's date is \(today).
            Extract structured information from spoken journal entries about a person.
            Convert relative dates (e.g. "next Friday") to absolute YYYY-MM-DD dates using today's date.
            bullet_points should be factual, third-person, about \(contact.name).
            Only create a reminder when there is a clearly time-bound event worth a future check-in.
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
            reminders: reminders
        )
    }

    // ─────────────────────────────────────────
    // "Turn back a page" — a warm prose recap
    // ─────────────────────────────────────────

    func recap(for contact: Contact) async throws -> String {
        let facts = contact.keyFacts.map { "• \($0.content)" }.joined(separator: "\n")
        let recentNotes = contact.journalEntries.prefix(5)
            .map { "• \($0.content)" }.joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            You write a short, warm "story so far" recap to help someone remember a person
            before they reconnect. Two or three sentences, intimate and natural — not a list,
            not corporate. Weave in the key facts and what's recently been going on.
            """)

        let response = try await session.respond(
            to: """
            Person: \(contact.name)\(contact.context.map { " (\($0))" } ?? "")
            Key facts:
            \(facts.isEmpty ? "(none)" : facts)
            Recent entries:
            \(recentNotes.isEmpty ? "(none)" : recentNotes)
            """,
            generating: AssistantReply.self
        )
        return response.content.answer
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
