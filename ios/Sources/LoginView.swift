import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(UserSession.self) var session
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // MARK: - App Icon & Title
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)

                    Circle()
                        .fill(Color.accentColor.opacity(0.05))
                        .frame(width: 160, height: 160)
                        .scaleEffect(isAnimating ? 1.15 : 1.0)

                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }
                .animation(
                    .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                    value: isAnimating
                )

                Text("7Go")
                    .font(.system(size: 48, weight: .bold, design: .rounded))

                Text("友達のApple Watchを振動させよう")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // MARK: - Feature Bullets
            VStack(spacing: 20) {
                FeatureRow(
                    icon: "hand.tap.fill",
                    title: "ワンタップで通知",
                    subtitle: "友達のApple Watchを振動させよう",
                    color: .blue
                )
                FeatureRow(
                    icon: "person.2.fill",
                    title: "友達を追加",
                    subtitle: "簡単につながる",
                    color: .purple
                )
                FeatureRow(
                    icon: "applewatch.radiowaves.left.and.right",
                    title: "Apple Watch対応",
                    subtitle: "手首で感じるリアルタイム通知",
                    color: .orange
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // MARK: - Sign In & Footer
            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    Task { await session.handleSignIn(result: result) }
                }
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Apple IDでサインイン")

#if DEBUG
                Button {
                    Task { await session.handleLocalDebugSignIn() }
                } label: {
                    Label("ローカルデバッグで入る", systemImage: "hammer.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
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

#if DEBUG
                Text("Personal Team での実機確認用に簡易ログインを表示しています")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
#endif
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
