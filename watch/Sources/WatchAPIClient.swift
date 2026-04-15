import Foundation

// MARK: - Models

struct Friend: Identifiable, Codable, Sendable {
    let id: String
    let displayName: String
}

struct AppUser: Codable, Sendable {
    let userId: String
    let displayName: String
    let sessionToken: String
}

struct PendingSignal: Identifiable, Codable, Sendable {
    let id: String
    let senderId: String
    let senderName: String
    let emoji: String
    let createdAt: String
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
            return "ネットワーク接続に問題があります。"
        case .serverError(let code, _):
            return "サーバーエラー（コード: \(code)）"
        case .decodingError:
            return "サーバー応答の処理に失敗しました。"
        case .unauthorized:
            return "認証切れ。再ログインしてください。"
        case .notFound:
            return "リソースが見つかりません。"
        }
    }
}

// MARK: - API Client

struct WatchAPIClient: Sendable {
    static let shared = WatchAPIClient()

    private let baseURL: URL
    private let session: URLSession

    private init() {
        let urlString: String
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "SERVER_URL") as? String,
           !plistValue.isEmpty,
           plistValue != "$(SERVER_URL)" {
            urlString = plistValue
        } else {
            urlString = "https://api.7go.app"
        }

        var sanitized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("http://") {
            sanitized = sanitized.replacingOccurrences(of: "http://", with: "https://")
        }
        if !sanitized.hasPrefix("https://") {
            sanitized = "https://" + sanitized
        }

        guard let url = URL(string: sanitized) else {
            fatalError("SERVER_URL が不正です: \(sanitized)")
        }
        self.baseURL = url

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    func register(appleID: String, displayName: String) async throws -> AppUser {
        struct Req: Encodable { let appleId: String; let displayName: String }
        struct Res: Decodable { let sessionToken: String; let userId: String; let displayName: String }

        let res: Res = try await post("register", body: Req(appleId: appleID, displayName: displayName))
        return AppUser(
            userId: res.userId,
            displayName: res.displayName,
            sessionToken: res.sessionToken
        )
    }

    // MARK: - Friends

    func getFriends(token: String) async throws -> [Friend] {
        try await get(url: baseURL.appending(path: "friends"), token: token)
    }

    // MARK: - Signal

    func sendSignal(to friendId: String, token: String) async throws {
        struct Req: Encodable {
            let friendId: String
            let emoji: String
        }
        let _: EmptyResponse = try await post("signal", body: Req(friendId: friendId, emoji: "☕️"), token: token)
    }

    func getPendingSignals(token: String) async throws -> [PendingSignal] {
        try await get(url: baseURL.appending(path: "signals/pending"), token: token)
    }

    func sendSignal(to friendId: String, emoji: String, token: String) async throws {
        struct Req: Encodable {
            let friendId: String
            let emoji: String
        }
        let _: EmptyResponse = try await post("signal", body: Req(friendId: friendId, emoji: emoji), token: token)
    }

    func registerDevice(pushToken: String, deviceKind: String, pushTopic: String, token: String) async throws {
        struct Req: Encodable {
            let pushToken: String
            let platform: String
            let deviceKind: String
            let pushTopic: String
        }

        let _: EmptyResponse = try await post(
            "devices/register",
            body: Req(
                pushToken: pushToken,
                platform: "watchos",
                deviceKind: deviceKind,
                pushTopic: pushTopic
            ),
            token: token
        )
    }

    // MARK: - Private

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

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let maxRetries = 3
        var lastError: Error?

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(Double(attempt) * 2))
            }

            let data: Data
            let response: URLResponse

            do {
                (data, response) = try await session.data(for: request)
            } catch let urlError as URLError {
                lastError = APIError.networkError(underlying: urlError.localizedDescription)
                continue
            } catch {
                throw APIError.networkError(underlying: error.localizedDescription)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(underlying: "HTTPレスポンスを取得できませんでした")
            }

            if [502, 503].contains(httpResponse.statusCode) && attempt < maxRetries - 1 {
                lastError = APIError.serverError(statusCode: httpResponse.statusCode, message: "サーバー起動中...")
                continue
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

        throw lastError ?? APIError.networkError(underlying: "リクエストに失敗しました")
    }
}
