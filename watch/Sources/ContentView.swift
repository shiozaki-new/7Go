import SwiftUI
import WatchKit

// MARK: - Signal Options

private struct SignalOption: Identifiable, Hashable {
    let emoji: String
    let label: String

    var id: String { emoji }

    static let all: [SignalOption] = [
        .init(emoji: "🏪", label: "コンビニ"),
        .init(emoji: "☕️", label: "コーヒー"),
        .init(emoji: "🍽️", label: "ランチ"),
        .init(emoji: "🚻", label: "トイレ"),
        .init(emoji: "🏠", label: "家"),
        .init(emoji: "🏢", label: "会社"),
        .init(emoji: "🏫", label: "学校"),
        .init(emoji: "🤫", label: "会議中"),
        .init(emoji: "🚑", label: "緊急"),
    ]
}

// MARK: - Root

struct ContentView: View {
    @Environment(WatchUserSession.self) var session

    var body: some View {
        if session.isLoggedIn {
            FriendsView()
        } else {
            WatchWaitingView()
        }
    }
}

// MARK: - Waiting

struct WatchWaitingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 34))
                .foregroundStyle(.tint)

            Text("7Go4")
                .font(.system(.title3, design: .rounded, weight: .bold))

            Text("iPhoneでログインすると\nApple Watchにも同期されます")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ProgressView()
                .padding(.top, 4)
        }
        .padding()
    }
}

// MARK: - Friends

struct FriendsView: View {
    @Environment(WatchUserSession.self) var session
    @Environment(SignalStore.self) var store

    @State private var friends: [Friend] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                        Image(systemName: "number")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("iPhoneでコード接続してね")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        if store.lastSenderName != nil {
                            Section {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(store.statusColor)
                                        .frame(width: 6, height: 6)
                                    Text(store.lastReceivedText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Section("相手") {
                            ForEach(friends) { friend in
                                NavigationLink(friend.displayName) {
                                    SignalBoardView(friend: friend, token: token)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("7Go4")
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
            .task {
                await loadFriends()
                await pollPendingSignals()
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

    private func loadFriends() async {
        isLoading = true
        defer { isLoading = false }

        do {
            friends = try await WatchAPIClient.shared.getFriends(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pollPendingSignals() async {
        while !Task.isCancelled {
            do {
                let signals = try await WatchAPIClient.shared.getPendingSignals(token: token)
                for signal in signals {
                    await MainActor.run {
                        store.recordSignal(from: signal.senderName, emoji: signal.emoji)
                    }
                }
            } catch {
                // Ignore polling failures; APNs is the primary delivery path.
            }

            try? await Task.sleep(for: .seconds(5))
        }
    }
}

// MARK: - Signal Board

private struct SignalBoardView: View {
    let friend: Friend
    let token: String

    @State private var sendingEmoji: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(SignalOption.all) { option in
                    Button {
                        Task { await send(option) }
                    } label: {
                        VStack(spacing: 4) {
                            if sendingEmoji == option.emoji {
                                ProgressView()
                                    .frame(height: 24)
                            } else {
                                Text(option.emoji)
                                    .font(.system(size: 24))
                                    .frame(height: 24)
                            }

                            Text(option.label)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.darkGray).opacity(0.2))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sendingEmoji != nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
        .navigationTitle(friend.displayName)
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(statusIsError ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                    )
                    .foregroundStyle(.white)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 4)
            }
        }
    }

    private func send(_ option: SignalOption) async {
        guard sendingEmoji == nil else { return }
        sendingEmoji = option.emoji
        defer { sendingEmoji = nil }

        do {
            try await WatchAPIClient.shared.sendSignal(to: friend.id, emoji: option.emoji, token: token)
            WKInterfaceDevice.current().play(.success)
            showStatus("\(option.emoji) を送信", isError: false)
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
            try? await Task.sleep(for: .seconds(1.8))
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
