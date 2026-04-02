import WatchConnectivity

/// iPhoneからApple Watchにセッション情報を同期する
final class PhoneSessionSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneSessionSync()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// ログイン成功時に呼ぶ
    func sendSession(user: AppUser) {
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let context: [String: Any] = [
            "userId": user.userId,
            "displayName": user.displayName,
            "sessionToken": user.sessionToken,
        ]
        try? WCSession.default.updateApplicationContext(context)
    }

    /// サインアウト時に呼ぶ
    func clearSession() {
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        try? WCSession.default.updateApplicationContext(["signedOut": true])
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
