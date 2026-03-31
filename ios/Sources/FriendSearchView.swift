import SwiftUI

struct FriendSearchView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Friend] = []
    @State private var addedIds: Set<String> = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var hasSearched = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if !hasSearched && query.isEmpty {
                    emptyPromptView
                } else if isSearching {
                    loadingView
                } else if results.isEmpty && hasSearched {
                    noResultsView
                } else {
                    resultsList
                }
            }
            .navigationTitle("友達を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "名前で友達を検索")
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .alert("エラー", isPresented: showErrorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var emptyPromptView: some View {
        ContentUnavailableView(
            "名前で友達を検索",
            systemImage: "person.badge.plus",
            description: Text("追加したい友達の名前を入力してください")
        )
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("検索中...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var noResultsView: some View {
        ContentUnavailableView(
            "見つかりませんでした",
            systemImage: "magnifyingglass",
            description: Text("「\(query)」に一致するユーザーはいません")
        )
    }

    private var resultsList: some View {
        List(results) { user in
            FriendSearchRow(
                user: user,
                isAdded: addedIds.contains(user.id),
                onAdd: { await addFriend(user) }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        .listStyle(.plain)
        .animation(.default, value: addedIds)
    }

    // MARK: - Debounced Search

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch(trimmed)
        }
    }

    // MARK: - API

    private func performSearch(_ q: String) async {
        isSearching = true
        defer {
            isSearching = false
            hasSearched = true
        }

        do {
            let token = session.currentUser?.sessionToken ?? ""
            let found = try await APIClient.shared.searchUsers(query: q, token: token)
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
            // ignore
        } catch {
            results = []
            errorMessage = friendlyError(from: error)
        }
    }

    private func addFriend(_ user: Friend) async {
        do {
            let token = session.currentUser?.sessionToken ?? ""
            try await APIClient.shared.addFriend(friendId: user.id, token: token)
            _ = withAnimation { addedIds.insert(user.id) }
        } catch {
            errorMessage = "友達の追加に失敗しました。もう一度お試しください。"
        }
    }

    // MARK: - Helpers

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func friendlyError(from error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        return "通信エラーが発生しました。もう一度お試しください。"
    }
}

// MARK: - Row

private struct FriendSearchRow: View {
    let user: Friend
    let isAdded: Bool
    let onAdd: () async -> Void

    @State private var isAddingInProgress = false

    var body: some View {
        HStack(spacing: 12) {
            avatar
            nameLabel
            Spacer()
            statusView
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(user.displayName)")
        .accessibilityValue(isAdded ? "追加済み" : "未追加")
    }

    private var avatar: some View {
        Text(String(user.displayName.prefix(1)))
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(avatarColor.gradient, in: Circle())
    }

    private var nameLabel: some View {
        Text(user.displayName)
            .font(.body)
            .lineLimit(1)
    }

    @ViewBuilder
    private var statusView: some View {
        if isAdded {
            Label("追加済み", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        } else if isAddingInProgress {
            ProgressView()
                .controlSize(.small)
        } else {
            Button {
                Task {
                    isAddingInProgress = true
                    await onAdd()
                    isAddingInProgress = false
                }
            } label: {
                Text("追加")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan]
        let hash = abs(user.id.hashValue)
        return colors[hash % colors.count]
    }
}

#Preview {
    FriendSearchView()
        .environment(UserSession())
}
