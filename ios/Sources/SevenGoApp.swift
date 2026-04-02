import SwiftUI

@main
struct SevenGoApp: App {
    @State private var session = UserSession()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isLoggedIn {
                    HomeView()
                } else if session.needsNickname {
                    NicknameSetupView()
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
                }
            }
        }
    }
}
