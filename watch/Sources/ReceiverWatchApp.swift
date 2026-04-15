import SwiftUI
import UserNotifications
import WatchKit

@main
struct SevenGo4WatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(WatchUserSession.shared)
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
        WatchUserSession.shared.activate()
        Task {
            await SignalStore.shared.refreshNotificationStatus()
        }
        requestNotificationPermission()
    }

    func applicationDidBecomeActive() {
        Task {
            await SignalStore.shared.refreshNotificationStatus()
            await WatchPushRegistration.shared.registerIfPossible(
                sessionToken: WatchUserSession.shared.currentUser?.sessionToken
            )
        }
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        Task { @MainActor in
            WatchPushRegistration.shared.updateDeviceToken(deviceToken)
        }
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        print("Watch APNs registration failed: \(error.localizedDescription)")
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, error in
            if let error {
                print("通知許可エラー: \(error.localizedDescription)")
            }

            Task {
                await SignalStore.shared.refreshNotificationStatus()
                await MainActor.run {
                    WKExtension.shared().registerForRemoteNotifications()
                }
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
        let emoji = NotificationPayload.emoji(from: notification)
        let notificationID = notification.request.identifier

        await MainActor.run {
            SignalStore.shared.recordSignal(
                from: senderName,
                emoji: emoji,
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
        let emoji = NotificationPayload.emoji(from: response.notification)
        let notificationID = response.notification.request.identifier

        await MainActor.run {
            SignalStore.shared.recordSignal(
                from: senderName,
                emoji: emoji,
                notificationID: notificationID
            )
        }
    }
}
