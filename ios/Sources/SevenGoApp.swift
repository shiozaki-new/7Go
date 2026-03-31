import SwiftUI
import UserNotifications

@main
struct SevenGoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegateAdaptor.self) var appDelegate
    @State private var session = UserSession()

    var body: some Scene {
        WindowGroup {
            Group {
                if !session.hasCompletedOnboarding {
                    OnboardingView()
                } else if session.isLoggedIn {
                    HomeView()
                } else {
                    LoginView()
                }
            }
            .environment(session)
            .task {
                await session.restoreSession()
                WatchConnectivityManager.shared.activate()
                await NotificationManager.shared.refreshStatus()
            }
        }
    }
}

// MARK: - App Delegate

final class AppDelegateAdaptor: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
}
