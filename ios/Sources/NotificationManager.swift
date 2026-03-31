import Foundation
import UserNotifications
import UIKit

@MainActor
@Observable
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var deviceToken: String?

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    private override init() {
        super.init()
    }

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            if granted {
                registerForRemoteNotifications()
            }
        } catch {
            print("[7Go] 通知許可エラー: \(error.localizedDescription)")
        }
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - APNs Registration

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegisterForRemoteNotifications(deviceToken token: Data) {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = tokenString
        print("[7Go] APNs device token: \(tokenString)")
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("[7Go] APNs登録失敗: \(error.localizedDescription)")
    }

    // MARK: - Handle Incoming Notification

    func handleIncomingSignal(from senderName: String) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        WatchConnectivityManager.shared.sendSignal(senderName: senderName)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        let senderName = content.userInfo["senderName"] as? String
            ?? extractSenderName(from: content)

        await MainActor.run {
            handleIncomingSignal(from: senderName)
        }

        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let senderName = content.userInfo["senderName"] as? String
            ?? extractSenderName(from: content)

        await MainActor.run {
            handleIncomingSignal(from: senderName)
        }
    }

    // MARK: - Sender Name Extraction

    nonisolated private func extractSenderName(from content: UNNotificationContent) -> String {
        let title = content.title
        for separator in ["—", "-", ":"] {
            let parts = title.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }
            let prefix = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard prefix == "7go" else { continue }
            let name = parts[1...].joined(separator: separator)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }

        let body = content.body
        if let range = body.range(of: " が") {
            let candidate = String(body[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { return candidate }
        }

        return "不明"
    }
}
