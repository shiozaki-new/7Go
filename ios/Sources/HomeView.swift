import SwiftUI

// MARK: - Signal Options

fileprivate struct SignalOption: Identifiable, Hashable {
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

// MARK: - Toast Model

fileprivate enum ToastStyle {
    case success
    case error

    var iconName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success: .green
        case .error: .red
        }
    }
}

fileprivate struct ToastMessage: Equatable {
    let text: String
    let style: ToastStyle

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class HomeViewModel {
    var friends: [Friend] = []
    var isLoading = false
    var isInitialLoad = true
    var sendingKey: String?
    fileprivate var toast: ToastMessage?

    private var toastDismissTask: Task<Void, Never>?

    func load(token: String) async {
        if isInitialLoad { isLoading = true }
        defer {
            isLoading = false
            isInitialLoad = false
        }

        do {
            let loaded = try await APIClient.shared.getFriends(token: token)
            withAnimation(.easeInOut(duration: 0.25)) {
                friends = loaded
            }
        } catch {
            showToast(friendlyMessage(from: error), style: .error)
        }
    }

    func send(to friend: Friend, emoji: String, token: String) async {
        let key = "\(friend.id)|\(emoji)"
        guard sendingKey == nil else { return }
        sendingKey = key
        defer { sendingKey = nil }

        do {
            try await APIClient.shared.sendSignal(to: friend.id, emoji: emoji, token: token)
            triggerHaptic(.success)
            showToast("\(friend.displayName) に \(emoji) を送りました", style: .success)
        } catch {
            triggerHaptic(.error)
            showToast(friendlyMessage(from: error), style: .error)
        }
    }

    func remove(friend: Friend, token: String) async {
        do {
            try await APIClient.shared.removeFriend(friendId: friend.id, token: token)
            withAnimation(.easeInOut(duration: 0.25)) {
                friends.removeAll { $0.id == friend.id }
            }
            showToast("\(friend.displayName) との接続を解除しました", style: .success)
        } catch {
            showToast(friendlyMessage(from: error), style: .error)
        }
    }

    func dismissToast() {
        withAnimation(.easeOut(duration: 0.2)) {
            toast = nil
        }
    }

    private func showToast(_ text: String, style: ToastStyle) {
        toastDismissTask?.cancel()
        withAnimation(.spring(duration: 0.28)) {
            toast = ToastMessage(text: text, style: style)
        }
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    private func friendlyMessage(from error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        return "通信エラーが発生しました。再度お試しください。"
    }

    private func triggerHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Home View

struct HomeView: View {
    @Environment(UserSession.self) private var session
    @State private var vm = HomeViewModel()
    @State private var showPairing = false
    @State private var showSetup = false

    private var token: String {
        session.currentUser?.sessionToken ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                content
                loadingOverlay
            }
            .navigationTitle("7Go4")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSetup = true
                    } label: {
                        Image(systemName: "gearshape")
                            .fontWeight(.medium)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPairing = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .fontWeight(.medium)
                    }
                }
            }
            .overlay(alignment: .top) {
                toastBanner
            }
            .sheet(isPresented: $showPairing) {
                FriendSearchView()
                    .onDisappear {
                        Task { await vm.load(token: token) }
                    }
            }
            .sheet(isPresented: $showSetup) {
                SetupView()
            }
            .task {
                await vm.load(token: token)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.friends.isEmpty && !vm.isLoading {
            emptyStateView
        } else {
            friendsBoard
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("まだつながっていません")
                    .font(.title3.weight(.semibold))

                Text("6桁コードで相手を追加すると、\nすぐに絵文字を送れます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showPairing = true
            } label: {
                Label("コードでつなぐ", systemImage: "number")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    private var friendsBoard: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(vm.friends) { friend in
                    FriendPagerCard(
                        friend: friend,
                        sendingKey: vm.sendingKey,
                        onSend: { emoji in
                            Task { await vm.send(to: friend, emoji: emoji, token: token) }
                        },
                        onRemove: {
                            Task { await vm.remove(friend: friend, token: token) }
                        }
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await vm.load(token: token)
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if vm.isLoading && vm.isInitialLoad {
            ZStack {
                Color(.systemBackground)
                    .opacity(0.82)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.15)
                    Text("読み込み中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var toastBanner: some View {
        if let toast = vm.toast {
            HStack(spacing: 10) {
                Image(systemName: toast.style.iconName)
                    .foregroundStyle(toast.style.tint)
                    .font(.body.weight(.semibold))

                Text(toast.text)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Button {
                    vm.dismissToast()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .padding(.horizontal)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { vm.dismissToast() }
        }
    }
}

// MARK: - Card

private struct FriendPagerCard: View {
    let friend: Friend
    let sendingKey: String?
    let onSend: (String) -> Void
    let onRemove: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.displayName)
                        .font(.headline)

                    Text("1タップで送信")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Label("接続を解除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(SignalOption.all) { option in
                    SignalPadButton(
                        option: option,
                        isSending: sendingKey == "\(friend.id)|\(option.emoji)",
                        action: { onSend(option.emoji) }
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct SignalPadButton: View {
    let option: SignalOption
    let isSending: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 6) {
                if isSending {
                    ProgressView()
                        .tint(.accentColor)
                        .frame(height: 28)
                } else {
                    Text(option.emoji)
                        .font(.system(size: 28))
                        .frame(height: 28)
                }

                Text(option.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor.opacity(isSending ? 0.4 : 0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSending)
    }
}
