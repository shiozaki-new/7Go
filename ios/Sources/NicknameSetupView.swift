import SwiftUI

struct NicknameSetupView: View {
    @Environment(UserSession.self) var session
    @State private var nickname = ""
    @State private var isRegistering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // MARK: - Header
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                Text("ニックネームを決めよう")
                    .font(.title2.weight(.bold))

                Text("友達があなたを検索するときに\nこの名前が表示されます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
                .frame(maxHeight: 40)

            // MARK: - Input
            VStack(spacing: 16) {
                TextField("ニックネーム", text: $nickname)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.systemGray6))
                    )
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit { register() }

                Text("\(nickname.count)/20")
                    .font(.caption)
                    .foregroundStyle(nickname.count > 20 ? .red : .secondary)
            }
            .padding(.horizontal, 40)

            Spacer()

            // MARK: - Button
            VStack(spacing: 12) {
                Button {
                    register()
                } label: {
                    if isRegistering {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    } else {
                        Text("はじめる")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty || nickname.count > 20 || isRegistering)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let error = session.loginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
        .onAppear {
            if let suggested = session.suggestedName, !suggested.isEmpty {
                nickname = suggested
            }
            isFocused = true
        }
        .preferredColorScheme(.dark)
    }

    private func register() {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 20, !isRegistering else { return }
        isRegistering = true
        Task {
            await session.completeRegistration(displayName: trimmed)
            isRegistering = false
        }
    }
}
