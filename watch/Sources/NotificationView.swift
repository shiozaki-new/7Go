import SwiftUI
import UserNotifications
import WatchKit

// MARK: - Notification Controller

final class NotificationController: WKUserNotificationHostingController<NotificationView> {
    var senderName: String = ""

    override var body: NotificationView {
        NotificationView(senderName: senderName)
    }

    override func didReceive(_ notification: UNNotification) {
        senderName = NotificationPayload.senderName(from: notification)

        Task { @MainActor in
            SignalStore.shared.recordSignal(
                from: senderName,
                notificationID: notification.request.identifier
            )
        }
    }
}

// MARK: - Notification View

struct NotificationView: View {
    let senderName: String

    var body: some View {
        VStack(spacing: 12) {
            Text("7Go")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.tint)

            Image(systemName: "hand.tap.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, options: .nonRepeating)

            Text(senderName)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("からシグナルが届きました")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    NotificationView(senderName: "太郎")
}
