import SwiftUI

/// 設定画面
struct SetupView: View {
    @Environment(UserSession.self) var session
    @Environment(\.dismiss) var dismiss
    @State private var copied = false
    @State private var showSignOutAlert = false

    private var user: AppUser? { session.currentUser }
    private var topic: String { user?.ntfyTopic ?? "" }

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

                // MARK: - 通知設定
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ntfy トピック")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(topic)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)

                    Button {
                        UIPasteboard.general.string = topic
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Label(
                            copied ? "コピーしました" : "トピックをコピー",
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
                    }

                    if let ntfyURL = URL(string: "ntfy://\(topic)") {
                        Link(destination: ntfyURL) {
                            Label("ntfy アプリで開く", systemImage: "arrow.up.right.square")
                        }
                    }

                    Link(destination: URL(string: "https://apps.apple.com/app/ntfy/id1625396347")!) {
                        Label("ntfy を App Store で見る", systemImage: "arrow.down.app")
                    }
                } header: {
                    Text("通知設定")
                } footer: {
                    Text("通知を受け取るには ntfy アプリでこのトピックを購読してください。")
                }

                // MARK: - アプリについて
                Section("アプリについて") {
                    LabeledContent("バージョン", value: appVersion)

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                }

                // MARK: - サインアウト
                Section {
                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("サインアウト")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("サインアウト", isPresented: $showSignOutAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("サインアウト", role: .destructive) {
                    session.signOut()
                    dismiss()
                }
            } message: {
                Text("サインアウトしてもよろしいですか？")
            }
        }
    }
}
