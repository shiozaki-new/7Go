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
        WatchPushRegistration.shared.clearSession()
    }

    private func restoreSession() {
        guard
            let data = UserDefaults.standard.data(forKey: "currentUser"),
            let user = try? JSONDecoder().decode(AppUser.self, from: data)
        else { return }
        currentUser = user
        Task {
            await WatchPushRegistration.shared.registerIfPossible(sessionToken: user.sessionToken)
        }
    }

    private func persist(_ user: AppUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "currentUser")
        }
        Task {
            await WatchPushRegistration.shared.registerIfPossible(sessionToken: user.sessionToken)
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
            let sessionToken = context["sessionToken"] as? String
        else { return }

        let user = AppUser(
            userId: userId,
            displayName: displayName,
            sessionToken: sessionToken
        )
        persist(user)
    }
}

@MainActor
final class WatchPushRegistration {
    static let shared = WatchPushRegistration()

    private var pushToken: String?
    private var activeSessionToken: String?
    private var lastRegistrationKey: String?

    func updateDeviceToken(_ tokenData: Data) {
        pushToken = tokenData.map { String(format: "%02x", $0) }.joined()
        Task {
            await registerIfPossible(sessionToken: activeSessionToken)
        }
    }

    func registerIfPossible(sessionToken: String?) async {
        activeSessionToken = sessionToken

        guard
            let sessionToken,
            !sessionToken.isEmpty,
            let pushToken,
            !pushToken.isEmpty,
            let pushTopic = Bundle.main.bundleIdentifier,
            !pushTopic.isEmpty
        else {
            return
        }

        let registrationKey = "\(sessionToken)|\(pushToken)|\(pushTopic)"
        guard registrationKey != lastRegistrationKey else { return }

        do {
            try await WatchAPIClient.shared.registerDevice(
                pushToken: pushToken,
                deviceKind: "watch",
                pushTopic: pushTopic,
                token: sessionToken
            )
            lastRegistrationKey = registrationKey
        } catch {
            print("Watch push registration sync failed: \(error.localizedDescription)")
        }
    }

    func clearSession() {
        activeSessionToken = nil
        lastRegistrationKey = nil
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
