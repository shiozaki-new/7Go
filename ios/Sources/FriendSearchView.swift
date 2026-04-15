import SwiftUI
import UIKit

struct FriendSearchView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var myCode = "------"
    @State private var pairingCode = ""
    @State private var isLoadingCode = false
    @State private var isRedeeming = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var sessionToken: String {
        session.currentUser?.sessionToken ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("あなたのコード") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(myCode)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)

                        Text("相手にこの6桁コードを入力してもらうと、すぐにつながれます。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            UIPasteboard.general.string = myCode
                            infoMessage = "コードをコピーしました"
                        } label: {
                            Label("コードをコピー", systemImage: "document.on.document")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("コードでつなぐ") {
                    TextField("6桁コード", text: $pairingCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(.title3, design: .monospaced))
                        .onChange(of: pairingCode) { _, newValue in
                            pairingCode = normalizedCode(newValue)
                        }

                    Button {
                        Task { await redeemPairingCode() }
                    } label: {
                        if isRedeeming {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("ペアを追加")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(pairingCode.count != 6 || isRedeeming)
                }

                if let infoMessage {
                    Section {
                        Text(infoMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("コードでつなぐ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .overlay {
                if isLoadingCode {
                    ProgressView("コードを取得中...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .task {
                await loadMyCode()
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

    private func loadMyCode() async {
        guard !sessionToken.isEmpty else { return }
        isLoadingCode = true
        defer { isLoadingCode = false }

        do {
            myCode = try await APIClient.shared.getPairingCode(token: sessionToken)
        } catch {
            errorMessage = friendlyError(from: error)
        }
    }

    private func redeemPairingCode() async {
        guard !sessionToken.isEmpty else { return }
        isRedeeming = true
        defer { isRedeeming = false }

        do {
            let friend = try await APIClient.shared.redeemPairingCode(pairingCode, token: sessionToken)
            infoMessage = "\(friend.displayName) とつながりました"
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        } catch {
            errorMessage = friendlyError(from: error)
        }
    }

    private func normalizedCode(_ rawValue: String) -> String {
        String(rawValue.filter(\.isNumber).prefix(6))
    }

    private func friendlyError(from error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        return "通信エラーが発生しました。もう一度お試しください。"
    }
}

#Preview {
    FriendSearchView()
        .environment(UserSession())
}
