import SwiftUI

/// 設定画面
struct SetupView: View {
    private enum PendingAction: String, Identifiable {
        case signOut
        case deleteAccount

        var id: String { rawValue }
    }

    @Environment(UserSession.self) var session
    @Environment(\.dismiss) var dismiss
    @State private var pendingAction: PendingAction?
    @State private var errorMessage: String?
    @State private var isDeletingAccount = false

    private var user: AppUser? { session.currentUser }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - アカウント
                Section("アカウント") {
                    LabeledContent("表示名") {
                        Text(user?.displayName ?? "-")
                    }
                    LabeledContent("ユーザー ID") {
                        Text(user?.userId ?? "-")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                // MARK: - アプリについて
                Section("アプリについて") {
                    LabeledContent("バージョン", value: appVersion)

                    if let privacyURL = APIClient.privacyPolicyURL {
                        Link(destination: privacyURL) {
                            Label("プライバシーポリシー", systemImage: "hand.raised")
                        }
                    }
                }

                // MARK: - アカウント操作
                Section {
                    Button(role: .destructive) {
                        pendingAction = .signOut
                    } label: {
                        HStack {
                            Spacer()
                            Text("サインアウト")
                            Spacer()
                        }
                    }
                    .disabled(isDeletingAccount)

                    Button(role: .destructive) {
                        pendingAction = .deleteAccount
                    } label: {
                        HStack {
                            Spacer()
                            if isDeletingAccount {
                                ProgressView()
                            } else {
                                Text("アカウントを削除")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isDeletingAccount)
                } footer: {
                    Text("アカウント削除を実行すると、プロフィール、友達関係、ログイン中のセッションが削除されます。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .disabled(isDeletingAccount)
                }
            }
            .alert(item: $pendingAction) { action in
                switch action {
                case .signOut:
                    Alert(
                        title: Text("サインアウト"),
                        message: Text("サインアウトしてもよろしいですか？"),
                        primaryButton: .destructive(Text("サインアウト")) {
                            session.signOut()
                            dismiss()
                        },
                        secondaryButton: .cancel()
                    )
                case .deleteAccount:
                    Alert(
                        title: Text("アカウントを削除"),
                        message: Text("この操作は取り消せません。アカウントと関連データを削除します。"),
                        primaryButton: .destructive(Text("削除")) {
                            Task { await deleteAccount() }
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .alert("エラー", isPresented: showErrorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func deleteAccount() async {
        guard let token = user?.sessionToken else {
            errorMessage = "ログイン情報を確認できませんでした。"
            return
        }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await APIClient.shared.deleteAccount(token: token)
            session.signOut()
            dismiss()
        } catch {
            if let apiError = error as? APIError {
                errorMessage = apiError.localizedDescription
            } else {
                errorMessage = "アカウント削除に失敗しました。時間を置いて再度お試しください。"
            }
        }
    }
}
