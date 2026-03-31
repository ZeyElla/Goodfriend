import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authService: AuthService
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon / wordmark
            VStack(spacing: 12) {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)

                Text("Goodfriend")
                    .font(.largeTitle.bold())

                Text("Stay close to the people who matter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Sign in with Apple button
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .cornerRadius(12)
            .padding(.horizontal, 32)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if isLoading {
                ProgressView()
            }

            Spacer().frame(height: 24)
        }
        .padding()
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    try await authService.signInWithApple(credential: credential)
                } catch {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        case .failure(let error):
            // ASAuthorization errors with code 1000 are user-cancelled — ignore silently
            let nsError = error as NSError
            if nsError.code != 1000 {
                errorMessage = error.localizedDescription
            }
        }
    }
}
