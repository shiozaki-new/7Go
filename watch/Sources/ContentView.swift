import SwiftUI
import AuthenticationServices
import WatchKit

// MARK: - Content View (Root)

struct ContentView: View {
    @Environment(WatchUserSession.self) var session
    @Environment(SignalStore.self) var store

    var body: some View {
        if session.isLoggedIn {
            FriendsView()
        } else {
            WatchLoginView()
        }
    }
}

// MARK: - Watch Login View

struct WatchLoginView: View {
    @Environment(WatchUserSession.self) var session

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)

                Text("7Go")
                    .font(.system(.title3, design: .rounded, weight: .bold))

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    Task { await session.handleSignIn(result: result) }
                }
                .frame(height: 44)

                if let error = session.loginError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
    }
}

// MARK: - Friends View

struct FriendsView: View {
    @Environment(WatchUserSession.self) var session
    @Environment(SignalStore.self) var store
    @State private var friends: [Friend] = []
    @State private var isLoading = true
    @State private var sendingToId: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var token: String {
        session.currentUser?.sessionToken ?? ""
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("読み込み中...")
                } else if friends.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("友達がいません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("iPhoneで友達を追加してね")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    List {
                        // 最後の通知セクション
                        if store.lastSenderName != nil {
                            Section {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(store.statusColor)
                                        .frame(width: 6, height: 6)
                                    Text(store.lastReceivedText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // 友達リスト
                        Section("友達") {
                            ForEach(friends) { friend in
                                Button {
                                    Task { await send(to: friend) }
                                } label: {
                                    HStack {
                                        Text(String(friend.displayName.prefix(1)))
                                            .font(.system(.caption, design: .rounded, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 28, height: 28)
                                            .background(Circle().fill(Color.accentColor))

                                        Text(friend.displayName)
                                            .font(.caption)
                                            .lineLimit(1)

                                        Spacer()

                                        if sendingToId == friend.id {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "hand.tap.fill")
                                                .foregroundStyle(.tint)
                                                .font(.caption)
                                        }
                                    }
                                }
                                .disabled(sendingToId != nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("7Go")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        session.signOut()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.caption2)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = statusMessage {
                    Text(msg)
                        .font(.caption2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(statusIsError ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                        )
                        .foregroundStyle(.white)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 4)
                }
            }
        }
        .task {
            await loadFriends()
        }
    }

    private func loadFriends() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await WatchAPIClient.shared.getFriends(token: token)
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func send(to friend: Friend) async {
        guard sendingToId == nil else { return }
        sendingToId = friend.id
        defer { sendingToId = nil }
        do {
            try await WatchAPIClient.shared.sendSignal(to: friend.id, token: token)
            WKInterfaceDevice.current().play(.success)
            showStatus("\(friend.displayName) に送信！", isError: false)
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func showStatus(_ message: String, isError: Bool) {
        withAnimation {
            statusMessage = message
            statusIsError = isError
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                statusMessage = nil
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(WatchUserSession.shared)
        .environment(SignalStore.shared)
}
