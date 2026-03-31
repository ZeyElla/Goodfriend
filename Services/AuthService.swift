import AuthenticationServices
import Combine
import Foundation
import Supabase

// MARK: – Auth state

enum AuthState: Equatable {
    case loading
    case unauthenticated
    case authenticated
}

// MARK: – AuthService

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var state: AuthState = .loading
    @Published var currentUserId: UUID?

    private var sessionTask: Task<Void, Never>?
    private let db = SupabaseService.shared.client

    private init() {
        sessionTask = Task {
            await restoreSession()
            await listenToAuthChanges()
        }
    }

    // ─────────────────────────────────────────
    // Sign in with Apple
    // ─────────────────────────────────────────

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthError.missingIdentityToken
        }

        let session = try await db.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: identityToken,
                nonce: nil          // Pass nonce if you generate one during ASAuthorization
            )
        )
        currentUserId = UUID(uuidString: session.user.id.uuidString)
        state = .authenticated
    }

    func signOut() async throws {
        try await db.auth.signOut()
        currentUserId = nil
        state = .unauthenticated
    }

    // ─────────────────────────────────────────
    // Session restore
    // ─────────────────────────────────────────

    private func restoreSession() async {
        do {
            let session = try await db.auth.session
            currentUserId = UUID(uuidString: session.user.id.uuidString)
            state = .authenticated
        } catch {
            state = .unauthenticated
        }
    }

    private func listenToAuthChanges() async {
        for await (event, session) in db.auth.authStateChanges {
            switch event {
            case .signedIn:
                currentUserId = session.flatMap { UUID(uuidString: $0.user.id.uuidString) }
                state = .authenticated
            case .signedOut:
                currentUserId = nil
                state = .unauthenticated
            default:
                break
            }
        }
    }
}

// MARK: – Errors

enum AuthError: LocalizedError {
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken: return "Apple did not return a valid identity token."
        }
    }
}
