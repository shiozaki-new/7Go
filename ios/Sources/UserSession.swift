import SwiftUI
import AuthenticationServices
#if DEBUG
import UIKit
#endif

struct AppUser: Codable {
    let userId: String
    let displayName: String
    let sessionToken: String
}

struct PendingSignal: Identifiable, Codable, Sendable {
    let id: String
    let senderId: String
    let senderName: String
    let createdAt: String
}

@MainActor
@Observable
final class UserSession {
    var currentUser: AppUser?
    var loginError: String?

    /// Apple Sign In 後、ニックネーム設定待ちの状態
    var pendingAppleID: String?
    var suggestedName: String?

    var isLoggedIn: Bool { currentUser != nil }
    var needsNickname: Bool { pendingAppleID != nil }

    func restoreSession() async {
        guard
            let data = UserDefaults.standard.data(forKey: "currentUser"),
            let user = try? JSONDecoder().decode(AppUser.self, from: data)
        else { return }
        currentUser = user
    }

    func handleSignIn(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                loginError = "Apple ID認証情報を取得できませんでした。"
                return
            }

            do {
                let user = try await APIClient.shared.register(
                    appleID: credential.user,
                    displayName: resolvedDisplayName(from: credential)
                )
                persist(user)
                pendingAppleID = nil
                suggestedName = nil
                loginError = nil
            } catch {
                loginError = "ログイン失敗: \(error.localizedDescription)"
            }

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            loginError = error.localizedDescription
        }
    }

    /// ニックネーム決定後にサーバー登録
    func completeRegistration(displayName: String) async {
        guard let appleID = pendingAppleID else { return }
        do {
            let user = try await APIClient.shared.register(appleID: appleID, displayName: displayName)
            persist(user)
            pendingAppleID = nil
            suggestedName = nil
            loginError = nil
        } catch {
            loginError = "登録に失敗しました: \(error.localizedDescription)"
        }
    }

#if DEBUG
    func handleLocalDebugSignIn() async {
        let appleID = debugAppleID()
        let displayName = UserDefaults.standard.string(forKey: "debugDisplayName")
            ?? UIDevice.current.name

        do {
            let user = try await APIClient.shared.register(appleID: appleID, displayName: displayName)
            persist(user)
            pendingAppleID = nil
            suggestedName = nil
            loginError = nil
        } catch {
            loginError = "デバッグログイン失敗: \(error.localizedDescription)"
        }
    }

    private func debugAppleID() -> String {
        if let existing = UserDefaults.standard.string(forKey: "debugAppleID"), !existing.isEmpty {
            return existing
        }
        let generated = "debug-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(generated, forKey: "debugAppleID")
        return generated
    }
#endif

    func signOut() {
        currentUser = nil
        pendingAppleID = nil
        suggestedName = nil
        UserDefaults.standard.removeObject(forKey: "currentUser")
        PhoneSessionSync.shared.clearSession()
    }

    private func persist(_ user: AppUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "currentUser")
        }
        PhoneSessionSync.shared.sendSession(user: user)
    }

    private func resolvedDisplayName(from credential: ASAuthorizationAppleIDCredential) -> String {
        let given = credential.fullName?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let family = credential.fullName?.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty {
            return String(name.prefix(20))
        }

        if let email = credential.email,
           let localPart = email.split(separator: "@").first,
           !localPart.isEmpty {
            return String(localPart.prefix(20))
        }

        return "7Go-\(credential.user.suffix(6))"
    }
}
