import SwiftUI
import AuthenticationServices

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

    var isLoggedIn: Bool { currentUser != nil }

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
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }

            let appleID = credential.user
            let given  = credential.fullName?.givenName  ?? ""
            let family = credential.fullName?.familyName ?? ""
            let name   = [given, family].filter { !$0.isEmpty }.joined(separator: " ")

            do {
                let user = try await APIClient.shared.register(appleID: appleID, displayName: name)
                persist(user)
                loginError = nil
            } catch {
                loginError = "ログイン失敗: \(error.localizedDescription)"
            }

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            loginError = error.localizedDescription
        }
    }

    func signOut() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: "currentUser")
    }

    private func persist(_ user: AppUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "currentUser")
        }
    }
}
