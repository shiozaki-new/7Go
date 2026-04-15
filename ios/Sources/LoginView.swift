import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(UserSession.self) var session

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // MARK: - App Icon & Title
            VStack(spacing: 16) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.bottom, 4)

                Text("7Go4")
                    .font(.system(size: 56, weight: .bold, design: .rounded))

                Text("Apple Watchに最短で絵文字を届けよう")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
                .frame(maxHeight: 48)

            // MARK: - Feature Bullets
            VStack(spacing: 24) {
                FeatureRow(
                    icon: "applewatch.radiowaves.left.and.right",
                    title: "最短で振動",
                    subtitle: "相手のApple Watchをすぐ呼び出す"
                )
                FeatureRow(
                    icon: "number",
                    title: "6桁コードで接続",
                    subtitle: "検索なしで相手とすぐつながる"
                )
                FeatureRow(
                    icon: "face.smiling",
                    title: "9つの絵文字",
                    subtitle: "ポケベルのように短く伝える"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // MARK: - Sign In & Footer
            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await session.handleSignIn(result: result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

#if DEBUG
                Button {
                    Task { await session.handleLocalDebugSignIn() }
                } label: {
                    Label("ローカルデバッグで入る", systemImage: "hammer.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
#endif

                if let error = session.loginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Text("Apple IDで安全にサインイン")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

#if DEBUG
                Text("Personal Team での実機確認用に簡易ログインを表示しています")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
#endif
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 40, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
