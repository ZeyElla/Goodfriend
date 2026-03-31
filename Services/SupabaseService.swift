import Foundation
import Supabase

// MARK: – Singleton client

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: AppConfig.supabaseURL)!,
            supabaseKey: AppConfig.supabaseAnonKey
        )
    }

    // Called from GoodfriendApp.init() to warm up the client early.
    static func configure() { _ = shared }
}

// MARK: – App configuration (replace with your actual values)

enum AppConfig {
    static let supabaseURL     = "https://<YOUR_PROJECT_REF>.supabase.co"
    static let supabaseAnonKey = "<YOUR_ANON_KEY>"
    static let openAIAPIKey    = "<YOUR_OPENAI_API_KEY>"
    static let claudeAPIKey    = "<YOUR_CLAUDE_API_KEY>"
}
