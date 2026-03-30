import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    var friends: [Friend] = []
    var statusText = ""
    var sendingToId: String?

    func load(token: String) async {
        friends = (try? await APIClient.shared.getFriends(token: token)) ?? []
    }

    func send(to friend: Friend, token: String) async {
        guard sendingToId == nil else { return }
        sendingToId = friend.id
        defer { sendingToId = nil }
        do {
            try await APIClient.shared.sendSignal(to: friend.id, token: token)
            statusText = "\(friend.displayName) に送りました 👋"
        } catch {
            statusText = "送信失敗: \(error.localizedDescription)"
        }
    }
}

struct HomeView: View {
    @Environment(UserSession.self) var session
    @State private var vm = HomeViewModel()
    @State private var showSearch = false
    @State private var showSetup  = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.friends.isEmpty {
                    ContentUnavailableView {
                        Label("友達がいません", systemImage: "person.badge.plus")
                    } description: {
                        Text("右上の＋から友達を追加してください")
                    }
                } else {
                    List(vm.friends) { friend in
                        HStack {
                            Text(friend.displayName)
                                .font(.headline)
                            Spacer()
                            Button {
                                Task { await vm.send(to: friend, token: session.currentUser?.sessionToken ?? "") }
                            } label: {
                                if vm.sendingToId == friend.id {
                                    ProgressView()
                                        .frame(width: 36, height: 36)
                                } else {
                                    Image(systemName: "hand.tap.fill")
                                        .font(.title2)
                                        .frame(width: 36, height: 36)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(vm.sendingToId != nil)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("7Go")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSetup = true } label: {
                        Image(systemName: "bell.badge")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !vm.statusText.isEmpty {
                    Text(vm.statusText)
                        .font(.caption)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { vm.statusText = "" }
                }
            }
            .sheet(isPresented: $showSearch) {
                FriendSearchView()
                    .onDisappear {
                        Task { await vm.load(token: session.currentUser?.sessionToken ?? "") }
                    }
            }
            .sheet(isPresented: $showSetup) {
                SetupView()
            }
            .task {
                await vm.load(token: session.currentUser?.sessionToken ?? "")
            }
        }
    }
}
