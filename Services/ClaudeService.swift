import Foundation

// MARK: – Claude API response types

struct ClaudeExtractionResult {
    var bulletPoints: [String]
    var reminders: [ReminderSuggestion]
    var giftIdeas: [String]
}

struct ReminderSuggestion {
    var title: String
    var dueDate: Date
    var draftMessage: String?
}

// MARK: – ClaudeService

final class ClaudeService {
    static let shared = ClaudeService()
    private init() {}

    private let model = "claude-sonnet-4-20250514"
    private let messagesEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // ─────────────────────────────────────────
    // Voice capture extraction
    // ─────────────────────────────────────────

    /// Sends a voice transcript to Claude and extracts bullet points, reminders, and gift ideas.
    func extractFromTranscript(_ transcript: String, contact: Contact) async throws -> ClaudeExtractionResult {
        let today = ISO8601DateFormatter().string(from: Date())
        let systemPrompt = """
        You are a personal CRM assistant. Today's date is \(today).

        The user just spoke a voice note about their contact "\(contact.name)".
        Return a JSON object with exactly these keys:
        {
          "bullet_points": ["..."],      // Array of concise bullet points about the contact
          "reminders": [                  // Array of date-specific events mentioned
            { "title": "...", "due_date": "YYYY-MM-DD", "draft_message": "..." }
          ],
          "gift_ideas": ["..."]           // Array of gift ideas mentioned, empty if none
        }

        Rules:
        - bullet_points: factual, third-person, about \(contact.name), each ≤ 20 words.
        - reminders: only create if a specific date or relative time is clearly mentioned. Convert relative dates (e.g. "next Friday") to absolute dates using today's date.
        - draft_message: a short, warm, natural iMessage-style text the user could send to \(contact.name) about this reminder.
        - gift_ideas: only if something sounds like a gift idea (wishlist item, hobby interest, etc.).
        Return ONLY valid JSON. No markdown, no code fences.
        """

        let response = try await sendMessage(system: systemPrompt, userContent: transcript)
        return try parseExtractionResult(response)
    }

    // ─────────────────────────────────────────
    // Conversational assistant
    // ─────────────────────────────────────────

    /// Handles a free-form assistant query with contact context injected.
    func assistantQuery(_ query: String, contacts: [Contact]) async throws -> String {
        let contactSummaries = contacts.prefix(20).map { c in
            let bullets = c.bulletPoints.prefix(5).map { "  • \($0.content)" }.joined(separator: "\n")
            return "**\(c.name)** (tags: \(c.tags.joined(separator: ", ")))\n\(bullets)"
        }.joined(separator: "\n\n")

        let system = """
        You are a warm, concise personal assistant who knows the user's contacts well.
        Here is relevant contact information:

        \(contactSummaries)

        Answer the user's question conversationally in 2-4 sentences. Be helpful and specific.
        Do not mention that you're an AI. Speak as if you know these people personally.
        """

        return try await sendMessage(system: system, userContent: query)
    }

    // ─────────────────────────────────────────
    // Core API call
    // ─────────────────────────────────────────

    private func sendMessage(system: String, userContent: String) async throws -> String {
        var request = URLRequest(url: messagesEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [["role": "user", "content": userContent]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ClaudeError.apiError(String(data: data, encoding: .utf8) ?? "unknown")
        }

        struct MessagesResponse: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }
        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    // ─────────────────────────────────────────
    // JSON parsing
    // ─────────────────────────────────────────

    private func parseExtractionResult(_ json: String) throws -> ClaudeExtractionResult {
        guard let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.invalidJSON
        }

        let bulletPoints = obj["bullet_points"] as? [String] ?? []
        let giftIdeas    = obj["gift_ideas"] as? [String] ?? []

        var reminders: [ReminderSuggestion] = []
        if let rawReminders = obj["reminders"] as? [[String: String]] {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            for r in rawReminders {
                guard let title = r["title"],
                      let dateStr = r["due_date"],
                      let date = df.date(from: dateStr) else { continue }
                reminders.append(ReminderSuggestion(title: title, dueDate: date, draftMessage: r["draft_message"]))
            }
        }

        return ClaudeExtractionResult(bulletPoints: bulletPoints, reminders: reminders, giftIdeas: giftIdeas)
    }
}

enum ClaudeError: LocalizedError {
    case apiError(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "Claude API error: \(msg)"
        case .invalidJSON:       return "Claude returned invalid JSON."
        }
    }
}
