import Foundation

struct Friend: Identifiable, Codable, Sendable {
    let id: String
    let displayName: String
}

struct APIClient: Sendable {
    static let shared = APIClient()

    // シミュレータ:  http://127.0.0.1:8787
    // 実機 (同一 Wi-Fi): http://<MacのIPアドレス>:8787
    var baseURL = URL(string: "http://127.0.0.1:8787")!

    // MARK: - Auth

    func register(appleID: String, displayName: String) async throws -> AppUser {
        struct Req: Encodable { let appleId: String; let displayName: String }
        struct Res: Decodable { let sessionToken: String; let userId: String; let displayName: String; let ntfyTopic: String }

        let res: Res = try await post("register", body: Req(appleId: appleID, displayName: displayName))
        return AppUser(userId: res.userId, displayName: res.displayName,
                       sessionToken: res.sessionToken, ntfyTopic: res.ntfyTopic)
    }

    // MARK: - Friends

    func searchUsers(query: String, token: String) async throws -> [Friend] {
        var comps = URLComponents(url: baseURL.appending(path: "users/search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        return try await get(url: comps.url!, token: token)
    }

    func getFriends(token: String) async throws -> [Friend] {
        try await get(url: baseURL.appending(path: "friends"), token: token)
    }

    func addFriend(friendId: String, token: String) async throws {
        struct Req: Encodable { let friendId: String }
        let _: EmptyResponse = try await post("friends/add", body: Req(friendId: friendId), token: token)
    }

    // MARK: - Signal

    func sendSignal(to friendId: String, token: String) async throws {
        struct Req: Encodable { let friendId: String }
        let _: EmptyResponse = try await post("signal", body: Req(friendId: friendId), token: token)
    }

    // MARK: - Helpers

    private struct EmptyResponse: Decodable {}

    private func get<T: Decodable>(url: URL, token: String) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<B: Encodable, R: Decodable>(
        _ path: String, body: B, token: String? = nil
    ) async throws -> R {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(R.self, from: data)
    }
}
