import SwiftUI
import UserNotifications
import WatchKit

@main
struct SevenGoWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(SignalStore.shared)
        }

        WKNotificationScene(controller: NotificationController.self,
                            category: "SIGNAL_RECEIVED")
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        WatchConnectivityManager.shared.activate()
        Task {
            await SignalStore.shared.refreshNotificationStatus()
        }
        requestNotificationPermission()
    }

    func applicationDidBecomeActive() {
        Task {
            await SignalStore.shared.refreshNotificationStatus()
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, error in
            if let error {
                print("[7Go] 通知許可エラー: \(error.localizedDescription)")
            }

            Task {
                await SignalStore.shared.refreshNotificationStatus()
            }
        }
    }
}

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let senderName = NotificationPayload.senderName(from: notification)
        let notificationID = notification.request.identifier

        await MainActor.run {
            SignalStore.shared.recordSignal(
                from: senderName,
                notificationID: notificationID
            )
        }

        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let senderName = NotificationPayload.senderName(from: response.notification)
        let notificationID = response.notification.request.identifier

        await MainActor.run {
            SignalStore.shared.recordSignal(
                from: senderName,
                notificationID: notificationID
            )
        }
    }
}
