import SwiftUI

@main
struct SevenGoApp: App {
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
                await session.restoreSession()
            }
        }
    }
}
