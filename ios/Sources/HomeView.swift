import SwiftUI

// MARK: - Signal Pattern

enum SignalPattern: String, CaseIterable, Identifiable {
    case poke = "ツンツン"
    case wave = "おーい"
    case urgent = "急ぎ！"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .poke: "hand.point.up.fill"
        case .wave: "hand.wave.fill"
        case .urgent: "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .poke: .blue
        case .wave: .purple
        case .urgent: .orange
        }
    }

    var message: String {
        switch self {
        case .poke: "ツンツン 👆"
        case .wave: "おーい 👋"
        case .urgent: "急ぎ！ 🚨"
        }
    }
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
    var sendingToId: String?
    var selectedPattern: SignalPattern = .poke
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
            withAnimation(.easeInOut(duration: 0.3)) {
                friends = loaded
            }
        } catch {
            showToast(friendlyMessage(from: error), style: .error)
        }
    }

    func send(to friend: Friend, pattern: SignalPattern, token: String) async {
        guard sendingToId == nil else { return }
        sendingToId = friend.id
        defer { sendingToId = nil }
        do {
            try await APIClient.shared.sendSignal(to: friend.id, pattern: pattern.rawValue, token: token)
            triggerHaptic(.success)
            showToast("\(friend.displayName) に「\(pattern.rawValue)」を送信しました", style: .success)
        } catch {
            triggerHaptic(.error)
            showToast(friendlyMessage(from: error), style: .error)
        }
    }

    func remove(friend: Friend, token: String) async {
        do {
            try await APIClient.shared.removeFriend(friendId: friend.id, token: token)
            withAnimation(.easeInOut(duration: 0.3)) {
                friends.removeAll { $0.id == friend.id }
            }
            showToast("\(friend.displayName) を削除しました", style: .success)
        } catch {
            showToast(friendlyMessage(from: error), style: .error)
        }
    }

    func dismissToast() {
        withAnimation(.easeOut(duration: 0.2)) {
            toast = nil
        }
    }

    // MARK: - Private

    private func showToast(_ text: String, style: ToastStyle) {
        toastDismissTask?.cancel()
        withAnimation(.spring(duration: 0.3)) {
            toast = ToastMessage(text: text, style: style)
        }
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
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

// MARK: - HomeView

struct HomeView: View {
    @Environment(UserSession.self) private var session
    @State private var vm = HomeViewModel()
    @State private var showSearch = false
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
            .navigationTitle("7Go")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSetup = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .fontWeight(.medium)
                    }
                    .accessibilityLabel("設定")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .fontWeight(.medium)
                    }
                    .accessibilityLabel("友達を追加")
                }
            }
            .overlay(alignment: .top) {
                toastBanner
            }
            .sheet(isPresented: $showSearch) {
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.friends.isEmpty && !vm.isLoading {
            emptyStateView
        } else {
            friendsList
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 120, height: 120)

                Image(systemName: "person.2.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                    .symbolEffect(.pulse, options: .repeating.speed(0.5))
            }

            VStack(spacing: 8) {
                Text("まだ友達がいません")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("友達を追加して、シグナルを送り合おう")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showSearch = true
            } label: {
                Label("友達を追加する", systemImage: "person.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    // MARK: - Friends List

    private var friendsList: some View {
        List {
            // Signal Pattern Picker
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(SignalPattern.allCases) { pattern in
                            PatternChip(
                                pattern: pattern,
                                isSelected: vm.selectedPattern == pattern
                            ) {
                                withAnimation(.spring(duration: 0.2)) {
                                    vm.selectedPattern = pattern
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            // Friends
            Section {
                ForEach(vm.friends) { friend in
                    FriendRow(
                        friend: friend,
                        pattern: vm.selectedPattern,
                        isSending: vm.sendingToId == friend.id,
                        isDisabled: vm.sendingToId != nil,
                        onSend: {
                            Task { await vm.send(to: friend, pattern: vm.selectedPattern, token: token) }
                        }
                    )
                }
                .onDelete { indexSet in
                    guard let index = indexSet.first else { return }
                    let friend = vm.friends[index]
                    Task { await vm.remove(friend: friend, token: token) }
                }
            } header: {
                Text("友達 (\(vm.friends.count))")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await vm.load(token: token)
        }
        .animation(.easeInOut(duration: 0.3), value: vm.friends.map(\.id))
    }

    // MARK: - Loading Overlay

    @ViewBuilder
    private var loadingOverlay: some View {
        if vm.isLoading && vm.isInitialLoad {
            ZStack {
                Color(.systemBackground)
                    .opacity(0.8)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.accentColor)
                    Text("読み込み中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Toast Banner

    @ViewBuilder
    private var toastBanner: some View {
        if let toast = vm.toast {
            HStack(spacing: 10) {
                Image(systemName: toast.style.iconName)
                    .foregroundStyle(toast.style.tint)
                    .font(.body.weight(.semibold))

                Text(toast.text)
                    .font(.subheadline)
                    .fontWeight(.medium)
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

// MARK: - Pattern Chip

private struct PatternChip: View {
    let pattern: SignalPattern
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: pattern.icon)
                    .font(.caption)
                Text(pattern.rawValue)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? pattern.color.opacity(0.15) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? pattern.color : .secondary)
            .overlay(
                Capsule()
                    .stroke(isSelected ? pattern.color.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pattern.rawValue)パターン")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Friend Row

private struct FriendRow: View {
    let friend: Friend
    let pattern: SignalPattern
    let isSending: Bool
    let isDisabled: Bool
    let onSend: () -> Void

    @State private var sendSuccess = false

    private var avatarInitial: String {
        String(friend.displayName.prefix(1))
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan]
        let hash = abs(friend.id.hashValue)
        return colors[hash % colors.count]
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            Text(avatarInitial)
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(avatarColor.gradient, in: Circle())

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Spacer()

            // Send button
            Button {
                onSend()
            } label: {
                ZStack {
                    if isSending {
                        ProgressView()
                            .tint(pattern.color)
                    } else if sendSuccess {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: pattern.icon)
                            .font(.title3)
                            .foregroundStyle(pattern.color)
                            .symbolEffect(.bounce, value: isSending)
                    }
                }
                .frame(width: 48, height: 48)
                .background(pattern.color.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityLabel("\(friend.displayName)に\(pattern.rawValue)を送る")
        }
        .padding(.vertical, 4)
    }
}
