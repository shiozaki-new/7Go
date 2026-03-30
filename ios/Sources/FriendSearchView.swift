import SwiftUI

struct FriendSearchView: View {
    @Environment(UserSession.self) var session
    @Environment(\.dismiss) var dismiss

    @State private var query   = ""
    @State private var results: [Friend] = []
    @State private var addedIds: Set<String> = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List(results) { user in
                HStack {
                    Text(user.displayName)
                    Spacer()
                    if addedIds.contains(user.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("追加") {
                            Task { await add(user) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .overlay {
                if isSearching { ProgressView() }
                else if results.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("友達を検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "名前で検索")
            .onChange(of: query) { _, q in
                guard q.count >= 1 else { results = []; return }
                Task { await search(q) }
            }
        }
    }

    private func search(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        results = (try? await APIClient.shared.searchUsers(
            query: q,
            token: session.currentUser?.sessionToken ?? ""
        )) ?? []
    }

    private func add(_ user: Friend) async {
        try? await APIClient.shared.addFriend(
            friendId: user.id,
            token: session.currentUser?.sessionToken ?? ""
        )
        addedIds.insert(user.id)
    }
}
