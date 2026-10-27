import Foundation
import Supabase

// MARK: – Singleton client

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: AppConfig.supabaseURL)!,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    // Called from GoodfriendApp.init() to warm up the client early.
    static func configure() { _ = shared }
}

// MARK: – App configuration (replace with your actual values)

enum AppConfig {
    static let supabaseURL     = "https://tdmqzjetxlxzxwzrmzyg.supabase.co"
    static let supabaseAnonKey = "sb_publishable_fyx-EWArHo_0-43HPY77WA_JvkNQWNa"
}
