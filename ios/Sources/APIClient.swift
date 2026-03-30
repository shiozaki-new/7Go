import Foundation

// MARK: - Models

struct Friend: Identifiable, Codable, Sendable {
    let id: String
    let displayName: String
}

// MARK: - Error Types

enum APIError: LocalizedError, Sendable {
    case networkError(underlying: String)
    case serverError(statusCode: Int, message: String)
    case decodingError(underlying: String)
    case unauthorized
    case notFound

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "ネットワーク接続に問題があります。通信環境を確認してください。"
        case .serverError(let code, _):
            return "サーバーエラーが発生しました（コード: \(code)）。しばらくしてから再度お試しください。"
        case .decodingError:
            return "サーバーからの応答を処理できませんでした。アプリを最新版に更新してください。"
        case .unauthorized:
            return "認証の有効期限が切れました。再度ログインしてください。"
        case .notFound:
            return "指定されたリソースが見つかりませんでした。"
        }
    }
}

// MARK: - API Client

struct APIClient: Sendable {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession

    private init() {
        // Info.plist の SERVER_URL を読み取り、未設定時はフォールバック
        let urlString: String
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "SERVER_URL") as? String,
           !plistValue.isEmpty,
           plistValue != "$(SERVER_URL)" {
            urlString = plistValue
        } else {
            urlString = "https://api.7go.app"
        }

        var sanitized = urlString
#if !DEBUG
        // Release ビルドでは HTTPS を強制
        if sanitized.hasPrefix("http://") {
            sanitized = sanitized.replacingOccurrences(of: "http://", with: "https://")
        }
        if !sanitized.hasPrefix("https://") {
            sanitized = "https://" + sanitized
        }
#endif

        guard let url = URL(string: sanitized) else {
            fatalError("SERVER_URL が不正です: \(sanitized)")
        }
        self.baseURL = url

        // タイムアウト 15 秒
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    func register(appleID: String, displayName: String) async throws -> AppUser {
        struct Req: Encodable { let appleId: String; let displayName: String }
        struct Res: Decodable { let sessionToken: String; let userId: String; let displayName: String; let ntfyTopic: String }

        let res: Res = try await post("register", body: Req(appleId: appleID, displayName: displayName))
        return AppUser(
            userId: res.userId,
            displayName: res.displayName,
            sessionToken: res.sessionToken,
            ntfyTopic: res.ntfyTopic
        )
    }

    // MARK: - Friends

    func searchUsers(query: String, token: String) async throws -> [Friend] {
        var components = URLComponents(url: baseURL.appending(path: "users/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw APIError.networkError(underlying: "検索URLの生成に失敗しました")
        }
        return try await get(url: url, token: token)
    }

    func getFriends(token: String) async throws -> [Friend] {
        try await get(url: baseURL.appending(path: "friends"), token: token)
    }

    func addFriend(friendId: String, token: String) async throws {
        struct Req: Encodable { let friendId: String }
        let _: EmptyResponse = try await post("friends/add", body: Req(friendId: friendId), token: token)
    }

    func removeFriend(friendId: String, token: String) async throws {
        let url = baseURL.appending(path: "friends/\(friendId)")
        let _: EmptyResponse = try await delete(url: url, token: token)
    }

    // MARK: - Signal

    func sendSignal(to friendId: String, token: String) async throws {
        struct Req: Encodable { let friendId: String }
        let _: EmptyResponse = try await post("signal", body: Req(friendId: friendId), token: token)
    }

    // MARK: - Private Helpers

    private struct EmptyResponse: Decodable {}

    private func get<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func post<B: Encodable, R: Decodable>(
        _ path: String, body: B, token: String? = nil
    ) async throws -> R {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await perform(request)
    }

    private func delete<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    /// 共通のリクエスト実行・レスポンス検証・デコード処理
    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.networkError(underlying: urlError.localizedDescription)
        } catch {
            throw APIError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(underlying: "HTTPレスポンスを取得できませんでした")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            let message = String(data: data, encoding: .utf8) ?? "不明なエラー"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(underlying: error.localizedDescription)
        }
    }
}
