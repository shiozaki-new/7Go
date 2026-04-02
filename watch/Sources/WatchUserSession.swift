import SwiftUI
import WatchConnectivity

@MainActor
@Observable
final class WatchUserSession: NSObject {
    static let shared = WatchUserSession()

    var currentUser: AppUser?

    var isLoggedIn: Bool { currentUser != nil }

    override init() {
        super.init()
        restoreSession()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func signOut() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: "currentUser")
    }

    private func restoreSession() {
        guard
            let data = UserDefaults.standard.data(forKey: "currentUser"),
            let user = try? JSONDecoder().decode(AppUser.self, from: data)
        else { return }
        currentUser = user
    }

    private func persist(_ user: AppUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "currentUser")
        }
    }

    fileprivate func handleContext(_ context: [String: Any]) {
        if context["signedOut"] as? Bool == true {
            signOut()
            return
        }

        guard
            let userId = context["userId"] as? String,
            let displayName = context["displayName"] as? String,
            let sessionToken = context["sessionToken"] as? String,
            let ntfyTopic = context["ntfyTopic"] as? String
        else { return }

        let user = AppUser(
            userId: userId,
            displayName: displayName,
            sessionToken: sessionToken,
            ntfyTopic: ntfyTopic
        )
        persist(user)
    }
}

// MARK: - WCSessionDelegate

extension WatchUserSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                let snapshot = Dictionary(uniqueKeysWithValues: context.compactMap { key, value -> (String, String)? in
                    guard let v = value as? String else { return nil }
                    return (key, v)
                })
                let signedOut = context["signedOut"] as? Bool ?? false
                Task { @MainActor in
                    if signedOut {
                        self.handleContext(["signedOut": true as Any])
                    } else {
                        self.handleContext(snapshot as [String: Any])
                    }
                }
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let snapshot = Dictionary(uniqueKeysWithValues: applicationContext.compactMap { key, value -> (String, String)? in
            guard let v = value as? String else { return nil }
            return (key, v)
        })
        let signedOut = applicationContext["signedOut"] as? Bool ?? false
        Task { @MainActor in
            if signedOut {
                self.handleContext(["signedOut": true as Any])
            } else {
                self.handleContext(snapshot as [String: Any])
            }
        }
    }
}
