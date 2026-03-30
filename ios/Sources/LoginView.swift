import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(UserSession.self) var session

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("7Go")
                    .font(.system(size: 72, weight: .bold, design: .rounded))

                Text("友達の Apple Watch を振動させよう")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    Task { await session.handleSignIn(result: result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .cornerRadius(12)

                if let error = session.loginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text("Apple ID は Xcode のサイニングと同じアカウントを使用してください")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
        .preferredColorScheme(.dark)
    }
}
