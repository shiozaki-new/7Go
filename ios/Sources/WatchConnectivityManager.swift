import Foundation
import WatchConnectivity

@MainActor
@Observable
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    var isWatchReachable = false
    var isWatchPaired = false
    var isWatchAppInstalled = false

    private let wcSession: WCSession

    private override init() {
        self.wcSession = WCSession.default
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        wcSession.delegate = self
        wcSession.activate()
    }

    /// 友達からのシグナルをWatchに転送する
    func sendSignal(senderName: String) {
        guard wcSession.activationState == .activated else { return }

        let message: [String: Any] = [
            "type": "signal",
            "senderName": senderName,
            "timestamp": Date().timeIntervalSince1970,
        ]

        if wcSession.isReachable {
            wcSession.sendMessage(message, replyHandler: nil) { error in
                print("[7Go] Watch message error: \(error.localizedDescription)")
                // フォールバック: transferUserInfo
                self.wcSession.transferUserInfo(message)
            }
        } else {
            wcSession.transferUserInfo(message)
        }
    }

    /// ユーザー情報をWatchに同期する
    func syncUserContext(displayName: String, userId: String) {
        guard wcSession.activationState == .activated else { return }
        do {
            try wcSession.updateApplicationContext([
                "displayName": displayName,
                "userId": userId,
            ])
        } catch {
            print("[7Go] Context sync error: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchPaired = paired
            self.isWatchAppInstalled = installed
            self.isWatchReachable = reachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchReachable = reachable
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchPaired = paired
            self.isWatchAppInstalled = installed
            self.isWatchReachable = reachable
        }
    }
}
