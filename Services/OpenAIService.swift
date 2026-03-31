import Foundation

// MARK: – OpenAI Whisper transcription

final class OpenAIService {
    static let shared = OpenAIService()
    private init() {}

    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    /// Transcribes an audio file (m4a / wav / mp3) using Whisper.
    func transcribe(audioURL: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(AppConfig.openAIAPIKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let ext = audioURL.pathExtension.lowercased()
        let mimeType: String = switch ext {
            case "m4a": "audio/m4a"
            case "mp3": "audio/mpeg"
            default:    "audio/wav"
        }

        var body = Data()
        body.appendFormField(name: "model", value: "whisper-1", boundary: boundary)
        body.appendFormField(name: "language", value: "en", boundary: boundary)
        body.appendFileField(name: "file", filename: "audio.\(ext)", mimeType: mimeType, data: audioData, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OpenAIError.transcriptionFailed(String(data: data, encoding: .utf8) ?? "unknown")
        }

        struct TranscriptionResponse: Decodable { let text: String }
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
    }
}

enum OpenAIError: LocalizedError {
    case transcriptionFailed(String)
    var errorDescription: String? {
        switch self {
        case .transcriptionFailed(let msg): return "Whisper transcription failed: \(msg)"
        }
    }
}

// MARK: – Multipart helpers

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendFileField(name: String, filename: String, mimeType: String, data fileData: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
