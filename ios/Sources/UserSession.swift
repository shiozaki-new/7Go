import SwiftUI
import AuthenticationServices
#if DEBUG
import UIKit
#endif

struct AppUser: Codable {
    let userId: String
    let displayName: String
    let sessionToken: String
    let ntfyTopic: String
}

@MainActor
@Observable
final class UserSession {
    var currentUser: AppUser?
    var loginError: String?
    var hasCompletedOnboarding: Bool

    var isLoggedIn: Bool { currentUser != nil }

    private static let userKey = "currentUser"

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    func restoreSession() async {
        // Keychain から復元（新方式）
        if let data = KeychainHelper.load(forKey: Self.userKey),
           let user = try? JSONDecoder().decode(AppUser.self, from: data) {
            currentUser = user
            syncToWatch(user)
            return
        }

        // UserDefaults からのマイグレーション（旧方式）
        if let data = UserDefaults.standard.data(forKey: Self.userKey),
           let user = try? JSONDecoder().decode(AppUser.self, from: data) {
            persist(user) // Keychainに移行
            UserDefaults.standard.removeObject(forKey: Self.userKey) // 旧データ削除
            return
        }
    }

    func handleSignIn(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }

            let appleID = credential.user
            let given  = credential.fullName?.givenName  ?? ""
            let family = credential.fullName?.familyName ?? ""
            let name   = [given, family].filter { !$0.isEmpty }.joined(separator: " ")

            do {
                let user = try await APIClient.shared.register(appleID: appleID, displayName: name)
                persist(user)
                loginError = nil
                await requestNotificationsIfNeeded()
                registerDeviceToken(for: user)
            } catch {
                loginError = "ログイン失敗: \(error.localizedDescription)"
            }

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            loginError = error.localizedDescription
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
            loginError = nil
            await requestNotificationsIfNeeded()
            registerDeviceToken(for: user)
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
        KeychainHelper.delete(forKey: Self.userKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey) // 旧データも念のため削除
    }

    // MARK: - Private

    private func persist(_ user: AppUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            KeychainHelper.save(data, forKey: Self.userKey)
        }
        syncToWatch(user)
    }

    private func syncToWatch(_ user: AppUser) {
        WatchConnectivityManager.shared.syncUserContext(
            displayName: user.displayName,
            userId: user.userId
        )
    }

    private func requestNotificationsIfNeeded() async {
        let manager = NotificationManager.shared
        if !manager.isAuthorized {
            await manager.requestPermission()
        }
    }

    private func registerDeviceToken(for user: AppUser) {
        guard let token = NotificationManager.shared.deviceToken else { return }
        Task {
            try? await APIClient.shared.registerDeviceToken(
                token: token,
                sessionToken: user.sessionToken
            )
        }
    }
}
