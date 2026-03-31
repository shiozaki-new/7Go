import SwiftUI

struct SetupView: View {
    @Environment(UserSession.self) var session
    @Environment(\.dismiss) var dismiss
    @State private var showSignOutAlert = false
    @State private var notificationStatus: String = "確認中..."

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

                // MARK: - 通知
                Section {
                    HStack {
                        Label("通知", systemImage: "bell.fill")
                        Spacer()
                        Text(notificationStatus)
                            .foregroundStyle(.secondary)
                    }

                    if !NotificationManager.shared.isAuthorized {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("通知設定を開く", systemImage: "gear")
                        }
                        .accessibilityHint("システム設定で通知を許可します")
                    }
                } header: {
                    Text("通知設定")
                } footer: {
                    Text("シグナルを受け取るには通知を許可してください。")
                }

                // MARK: - Apple Watch
                Section("Apple Watch") {
                    HStack {
                        Label("接続状態", systemImage: "applewatch")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(WatchConnectivityManager.shared.isWatchPaired ? .green : .orange)
                                .frame(width: 8, height: 8)
                            Text(watchStatusText)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - アプリについて
                Section("アプリについて") {
                    LabeledContent("バージョン", value: appVersion)

                    if let privacyURL = URL(string: "https://7go.app/privacy") {
                        Link(destination: privacyURL) {
                            Label("プライバシーポリシー", systemImage: "hand.raised.fill")
                        }
                    }

                    if let termsURL = URL(string: "https://7go.app/terms") {
                        Link(destination: termsURL) {
                            Label("利用規約", systemImage: "doc.text.fill")
                        }
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
            .task {
                await refreshNotificationStatus()
            }
        }
    }

    // MARK: - Helpers

    private var watchStatusText: String {
        let wc = WatchConnectivityManager.shared
        if wc.isWatchReachable {
            return "接続中"
        } else if wc.isWatchPaired {
            return "ペアリング済み"
        } else {
            return "未接続"
        }
    }

    private func refreshNotificationStatus() async {
        await NotificationManager.shared.refreshStatus()
        let status = NotificationManager.shared.authorizationStatus
        if status == .authorized {
            notificationStatus = "許可済み"
        } else if status == .denied {
            notificationStatus = "拒否"
        } else if status == .provisional {
            notificationStatus = "仮許可"
        } else if status == .notDetermined {
            notificationStatus = "未設定"
        } else {
            notificationStatus = "不明"
        }
    }
}
