import SwiftUI

/// 受信セットアップ画面
/// 自分の ntfy トピックを確認し、ntfy アプリで購読するためのガイド
struct SetupView: View {
    @Environment(UserSession.self) var session
    @Environment(\.dismiss) var dismiss
    @State private var copied = false

    private var topic: String { session.currentUser?.ntfyTopic ?? "" }
    private var ntfyURL: URL? { URL(string: "ntfy://\(topic)") }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("あなたの受信トピック")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(topic)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)

                    Button {
                        UIPasteboard.general.string = topic
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Label(copied ? "コピーしました ✓" : "トピックをコピー", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("受信設定")
                } footer: {
                    Text("このトピックを ntfy アプリで購読すると、友達からのサインが Apple Watch に届きます。")
                }

                Section {
                    if let url = ntfyURL {
                        Link(destination: url) {
                            Label("ntfy アプリで購読する", systemImage: "arrow.up.right.square")
                        }
                    }

                    Link(destination: URL(string: "https://apps.apple.com/app/ntfy/id1625396347")!) {
                        Label("ntfy アプリをインストール (App Store)", systemImage: "arrow.down.app")
                    }
                } header: {
                    Text("ntfy セットアップ")
                } footer: {
                    Text("ntfy アプリ → 通知 → Apple Watch 通知も ON にしてください。")
                }

                Section {
                    Button(role: .destructive) {
                        session.signOut()
                        dismiss()
                    } label: {
                        Label("サインアウト", systemImage: "rectangle.portrait.and.arrow.right")
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
        }
    }
}
