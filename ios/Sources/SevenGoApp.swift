import SwiftUI
import UIKit
import UserNotifications

@main
struct SevenGo4App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = UserSession()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isLoggedIn {
                    HomeView()
                } else {
                    LoginView()
                }
            }
            .environment(session)
            .task {
                PhoneSessionSync.shared.activate()
                await session.restoreSession()
                if let user = session.currentUser {
                    PhoneSessionSync.shared.sendSession(user: user)
                    await PushRegistrationManager.shared.registerIfPossible(sessionToken: user.sessionToken)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationAuthorization(application)
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushRegistrationManager.shared.updateDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func requestNotificationAuthorization(_ application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
                return
            }
            guard granted else { return }
            Task { @MainActor in
                application.registerForRemoteNotifications()
            }
        }
    }
}

@MainActor
final class PushRegistrationManager {
    static let shared = PushRegistrationManager()

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
            try await APIClient.shared.registerDevice(
                pushToken: pushToken,
                deviceKind: "iphone",
                pushTopic: pushTopic,
                token: sessionToken
            )
            lastRegistrationKey = registrationKey
        } catch {
            print("Push registration sync failed: \(error.localizedDescription)")
        }
    }

    func clearSession() {
        activeSessionToken = nil
        lastRegistrationKey = nil
    }
}
