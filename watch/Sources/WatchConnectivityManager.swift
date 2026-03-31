import Foundation
import WatchConnectivity
import WatchKit

@MainActor
@Observable
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    var userName: String?

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
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let context = session.receivedApplicationContext as? [String: String] {
            Task { @MainActor in
                userName = context["displayName"]
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        handleIncomingMessage(message)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        handleIncomingMessage(userInfo)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        if let name = applicationContext["displayName"] as? String {
            Task { @MainActor in
                userName = name
            }
        }
    }

    // MARK: - Private

    nonisolated private func handleIncomingMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String, type == "signal",
              let senderName = message["senderName"] as? String else { return }

        Task { @MainActor in
            SignalStore.shared.recordSignal(from: senderName)
        }
    }
}
